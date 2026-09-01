# Workaround for Wine's viewport refresh bug in Rhino 8.
#   1) force a redraw on every selection change
#   2) force a redraw while hovering during sub-object selection
#      (Ctrl+Shift), so the pre-selection highlight becomes visible
#   3) force a second, delayed redraw so the gumball reappears
#
# Load it from Rhino: Options > General > "Run these commands every time
# Rhino starts", then enter:  _-RunPythonScript C:/redraw_fix.py
#
# Note: Rhino 8's engine here is IronPython 2.7 — keep this Python 2
# compatible (no f-strings, no annotations).
import Rhino
import scriptcontext as sc
import System
import System.Windows.Forms as WinForms

# ---------- 1) selection changes ----------

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

# ---------- 2) hover pre-selection ----------

CTRL = WinForms.Keys.Control
SHIFT = WinForms.Keys.Shift

class _PreselectRedraw(Rhino.UI.MouseCallback):
    """Repaint the hovered viewport while Ctrl+Shift are held.

    Capped at roughly 30 frames per second so rendering is not saturated,
    and only while both modifiers are down, so ordinary navigation is
    never slowed down.
    """
    def __init__(self):
        self._last = 0

    def _modifiers_held(self):
        mods = WinForms.Control.ModifierKeys
        return (mods & CTRL) == CTRL and (mods & SHIFT) == SHIFT

    def OnMouseMove(self, e):
        # Ctrl+Shift hover: sub-object pre-selection
        if not self._modifiers_held():
            return
        now = System.Environment.TickCount
        if now - self._last < 33:      # 30 Hz cap
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
        # Rhino repositions the gumball AFTER this redraw, so schedule a
        # second, delayed one — otherwise the widget stays invisible until
        # the camera next moves.
        _schedule_late_redraw()

# ---------- delayed redraw (gumball repositioning) ----------

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

# keep the callback alive between runs of this script
old = sc.sticky.get("wine_preselect_cb")
if old is not None:
    try:
        old.Enabled = False
    except Exception:
        pass

cb = _PreselectRedraw()
cb.Enabled = True
sc.sticky["wine_preselect_cb"] = cb

print("redraw_fix active: selection, Ctrl+Shift pre-selection, gumball")
