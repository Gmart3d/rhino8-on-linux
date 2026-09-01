# Contournement du bug de rafraichissement de Wine.
#  1) redessin force a chaque changement de selection
#  2) redessin force au survol pendant une selection de sous-objets
#     (Ctrl+Shift), pour rendre visible la preselection
import Rhino
import scriptcontext as sc
import System
import System.Windows.Forms as WinForms

# ---------- 1) changements de selection ----------

def _force_redraw(sender, e):
    doc = Rhino.RhinoDoc.ActiveDoc
    if doc is None:
        return
    for view in doc.Views:
        view.Redraw()
    doc.Views.Redraw()

try:
    Rhino.RhinoDoc.SelectObjects -= _force_redraw
    Rhino.RhinoDoc.DeselectObjects -= _force_redraw
    Rhino.RhinoDoc.DeselectAllObjects -= _force_redraw
except Exception:
    pass

Rhino.RhinoDoc.SelectObjects += _force_redraw
Rhino.RhinoDoc.DeselectObjects += _force_redraw
Rhino.RhinoDoc.DeselectAllObjects += _force_redraw

# ---------- 2) preselection au survol ----------

CTRL = WinForms.Keys.Control
SHIFT = WinForms.Keys.Shift

class _PreselectRedraw(Rhino.UI.MouseCallback):
    """Force le repaint du viewport survole pendant Ctrl+Shift.

    Limite a environ 30 images par seconde pour ne pas saturer le rendu,
    et uniquement quand les deux modificateurs sont enfonces : la
    navigation normale n'est donc pas ralentie.
    """
    def __init__(self):
        self._last = 0

    def _modifiers_held(self):
        mods = WinForms.Control.ModifierKeys
        return (mods & CTRL) == CTRL and (mods & SHIFT) == SHIFT

    def OnMouseMove(self, e):
        # survol en Ctrl+Shift : preselection de sous-objets
        if not self._modifiers_held():
            return
        now = System.Environment.TickCount
        if now - self._last < 33:      # ~30 Hz max
            return
        self._last = now
        if e.View is not None:
            e.View.Redraw()

    def OnMouseDown(self, e):
        if e.View is not None:
            e.View.Redraw()

    def OnMouseUp(self, e):
        doc = Rhino.RhinoDoc.ActiveDoc
        if doc is not None:
            for view in doc.Views:
                view.Redraw()
        # Le gumball est repositionne par Rhino APRES ce redessin : on en
        # programme un second, differe, sinon le widget reste invisible
        # jusqu'au prochain mouvement de camera.
        _schedule_late_redraw()

# ---------- redessin differe (repositionnement du gumball) ----------

def _late_redraw(sender, e):
    _timer.Stop()
    doc = Rhino.RhinoDoc.ActiveDoc
    if doc is None:
        return
    for view in doc.Views:
        view.Redraw()

_timer = sc.sticky.get("wine_late_timer")
if _timer is None:
    _timer = WinForms.Timer()
    _timer.Interval = 150
    _timer.Tick += _late_redraw
    sc.sticky["wine_late_timer"] = _timer

def _schedule_late_redraw():
    _timer.Stop()
    _timer.Start()

# on garde l'objet en vie entre deux executions du script
old = sc.sticky.get("wine_preselect_cb")
if old is not None:
    try:
        old.Enabled = False
    except Exception:
        pass

cb = _PreselectRedraw()
cb.Enabled = True
sc.sticky["wine_preselect_cb"] = cb

print("redraw_fix actif : selection, preselection Ctrl+Shift, gumball")
