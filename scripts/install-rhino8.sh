#!/usr/bin/env bash
#
#  install-rhino8.sh — installe Rhino 8 sous Wine sur Ubuntu / Linux Mint.
#
#  Vous fournissez l'installeur officiel telecharge depuis rhino3d.com.
#  Ce script fait le reste, verifie chaque etape, et s'arrete en expliquant
#  quoi faire si quelque chose ne va pas.
#
#  Usage :
#    ./install-rhino8.sh                       cherche l'installeur tout seul
#    ./install-rhino8.sh /chemin/rhino_8.exe   ou vous lui indiquez
#    ./install-rhino8.sh --help
#
#  Options :
#    --prefix CHEMIN   espace Wine a utiliser (defaut : ~/.local/share/wineprefixes/rhino8)
#    --no-nvidia       ne pas configurer le renvoi de rendu vers une carte NVIDIA
#    -y, --yes         ne pas demander de confirmation
#
#  Relancer le script est sans danger : les etapes deja faites sont detectees.
#
#  Licence MIT. Rhinoceros est une marque de Robert McNeel & Associates ;
#  ce script est independant. Une licence Rhino valide est requise.
#
set -Eeuo pipefail

DEFAULT_PREFIX="$HOME/.local/share/wineprefixes/rhino8"
LOG="${TMPDIR:-/tmp}/rhino8-install-$(date +%Y%m%d-%H%M%S).log"
LAUNCHER="$HOME/.local/bin/rhino8.sh"
DESKTOP_FILE="$HOME/.local/share/applications/rhino8-wine.desktop"
INSTALLER=""; ASSUME_YES=0; SKIP_NVIDIA=0; PREFIX_SET=0
TOTAL_STEPS=11

# ------------------------------------------------------------------ affichage
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  CB=$(tput bold); CR=$(tput setaf 1); CG=$(tput setaf 2)
  CY=$(tput setaf 3); CC=$(tput setaf 6); CN=$(tput sgr0)
else CB=""; CR=""; CG=""; CY=""; CC=""; CN=""; fi

STEP=0
step() { STEP=$((STEP+1)); printf '\n%s[%d/%d]%s %s%s%s\n' "$CC" "$STEP" "$TOTAL_STEPS" "$CN" "$CB" "$1" "$CN"; }
info() { printf '      %s\n' "$1"; }
ok()   { printf '      %s✓%s %s\n' "$CG" "$CN" "$1"; }
warn() { printf '      %s!%s %s\n' "$CY" "$CN" "$1"; }
skip() { printf '      %s·%s %s\n' "$CY" "$CN" "$1"; }

die() {
  printf '\n%s%sInstallation arrêtée.%s\n\n' "$CB" "$CR" "$CN" >&2
  printf '  %s\n\n' "$1" >&2
  [ $# -gt 1 ] && printf '  %sQue faire :%s %s\n\n' "$CB" "$CN" "$2" >&2
  printf '  Journal détaillé : %s\n\n' "$LOG" >&2
  exit 1
}

on_err() {
  local line="$1" caller="$2" cmd="$3"
  [ "${caller:-0}" -gt 0 ] 2>/dev/null && line="$caller"
  die "Une commande a échoué de façon inattendue (ligne $line) : $cmd" \
      "Joignez le journal ci-dessous si vous demandez de l'aide."
}
trap 'on_err "$LINENO" "${BASH_LINENO[0]:-0}" "$BASH_COMMAND"' ERR

run() { printf '\n$ %s\n' "$*" >>"$LOG"; "$@" >>"$LOG" 2>&1; }

# ---------------------------------------------- garde-fou anti-blocage Edge
# MicrosoftEdgeUpdate.exe, installe avec WebView2, ne se termine jamais et
# bloque winetricks et wineserver -w indefiniment. On le tue periodiquement.
# La sortie du sous-shell DOIT etre redirigee, sinon une substitution de
# commande attendrait un EOF qui ne viendrait jamais.
EDGE_PID=""
edge_start() {
  [ -n "$EDGE_PID" ] && return 0
  ( while sleep 20; do pkill -u "$(id -u)" -f 'MicrosoftEdgeUpdat[e]' >/dev/null 2>&1 || true; done ) \
    >/dev/null 2>&1 &
  EDGE_PID=$!
}
edge_stop() {
  [ -n "$EDGE_PID" ] || return 0
  pkill -P "$EDGE_PID" >/dev/null 2>&1 || true
  kill "$EDGE_PID" >/dev/null 2>&1 || true
  EDGE_PID=""
}
trap 'edge_stop' EXIT INT TERM HUP

# wineserver -w est muet et sans limite de temps : on le borne.
wine_wait() {
  pkill -u "$(id -u)" -f 'MicrosoftEdgeUpdat[e]' >/dev/null 2>&1 || true
  if ! timeout 240 wineserver -w >>"$LOG" 2>&1; then
    warn "Des processus Windows sont restés bloqués ; on les arrête."
    wineserver -k >>"$LOG" 2>&1 || true
    sleep 2
  fi
}

# ------------------------------------------------------------------ arguments
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      # affiche l'en-tete de commentaires, et s'arrete a la premiere ligne de code
      awk 'NR>2 { if ($0 !~ /^#/) exit; sub(/^# ?/,""); print }' "$0"
      exit 0 ;;
    -y|--yes)  ASSUME_YES=1 ;;
    --no-nvidia) SKIP_NVIDIA=1 ;;
    --prefix)
      [ $# -ge 2 ] || die "L'option --prefix attend un chemin." "Exemple : $0 --prefix ~/rhino8"
      PREFIX="$2"; PREFIX_SET=1; shift ;;
    -*) die "Option inconnue : $1" "Lancez « $0 --help » pour la liste des options." ;;
    *)  INSTALLER="$1" ;;
  esac
  shift
done

# On n'herite JAMAIS d'un WINEPREFIX de l'environnement : le script modifie
# le prefixe en profondeur, et l'utilisateur ne s'attend pas a ce qu'on touche
# a un prefixe existant destine a autre chose.
if [ "$PREFIX_SET" -eq 0 ]; then
  if [ -n "${WINEPREFIX:-}" ] && [ "$WINEPREFIX" != "$DEFAULT_PREFIX" ]; then
    warn "La variable WINEPREFIX de votre environnement est ignorée :"
    warn "  $WINEPREFIX"
    warn "Pour l'utiliser malgré tout : $0 --prefix \"$WINEPREFIX\""
  fi
  PREFIX="$DEFAULT_PREFIX"
fi

export WINEPREFIX="$PREFIX"
export WINEDEBUG=-all
: >"$LOG"

printf '%s%sInstallation de Rhino 8 sous Wine%s\n' "$CB" "$CC" "$CN"
printf 'Journal : %s\n' "$LOG"

# ============================================================ 1. le systeme
step "Vérification du système"

[ "$(id -u)" -ne 0 ] || die "N'exécutez pas ce script en tant que root." \
  "Relancez-le avec votre compte habituel ; le mot de passe sera demandé au moment voulu."
command -v apt-get >/dev/null || die "Ce script cible Ubuntu, Linux Mint et dérivées." \
  "Sur Fedora ou Arch, installez wine-staging avec votre gestionnaire de paquets puis suivez le guide manuel."
for t in wget curl find; do
  command -v "$t" >/dev/null || die "L'outil « $t » est absent." "Installez-le : sudo apt install $t"
done

# shellcheck disable=SC1091
. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
[ -n "$CODENAME" ] || die "Impossible de déterminer la version d'Ubuntu de base." \
  "Suivez le guide manuel : votre distribution n'est pas reconnue."
ok "Système : ${PRETTY_NAME:-inconnu} (base « $CODENAME »)"

if ! curl -fsS --connect-timeout 10 --max-time 30 -o /dev/null \
     "https://dl.winehq.org/wine-builds/ubuntu/dists/$CODENAME/" 2>>"$LOG"; then
  if ! curl -fsS --connect-timeout 10 --max-time 20 -o /dev/null https://dl.winehq.org/ 2>>"$LOG"; then
    die "Impossible de joindre dl.winehq.org." \
        "Vérifiez votre connexion internet (ou votre portail d'accès / proxy), puis relancez le script."
  fi
  die "WineHQ ne publie pas de paquets pour « $CODENAME »." \
      "Votre version est sans doute trop récente. Vérifiez la liste sur dl.winehq.org/wine-builds/ubuntu/dists/"
fi
ok "Dépôt WineHQ disponible pour « $CODENAME »"

[ "${XDG_SESSION_TYPE:-}" = "wayland" ] && \
  warn "Session Wayland : non testée. Rhino passera par XWayland."

FREE_GB=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc '0-9')
[ "${FREE_GB:-0}" -ge 12 ] || die "Espace disque insuffisant : ${FREE_GB} Go libres, 12 Go nécessaires." \
  "Libérez de la place puis relancez le script."
ok "Espace disque : ${FREE_GB} Go libres"

RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
[ "${RAM_GB:-0}" -ge 7 ] || warn "Seulement ${RAM_GB} Go de RAM ; 8 Go est le minimum réaliste."

# ============================================================ 2. l'installeur
step "Recherche de l'installeur Rhino"

if [ -z "$INSTALLER" ]; then
  for d in "$HOME/Téléchargements" "$HOME/Downloads" "$HOME/Bureau" "$HOME/Desktop" "$HOME"; do
    [ -d "$d" ] || continue
    F=$(find "$d" -maxdepth 1 -iname 'rhino_*8*.exe' -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    [ -n "$F" ] && { INSTALLER="$F"; break; }
  done
fi
[ -n "$INSTALLER" ] && [ -f "$INSTALLER" ] || die \
  "Installeur Rhino introuvable." \
  "Téléchargez Rhino 8 pour Windows sur rhino3d.com (compte McNeel requis) et laissez le fichier dans votre dossier Téléchargements, puis relancez ce script."
SIZE_MB=$(( $(stat -c %s "$INSTALLER") / 1024 / 1024 ))
[ "$SIZE_MB" -ge 300 ] || die "« $(basename "$INSTALLER") » ne fait que ${SIZE_MB} Mo." \
  "L'installeur officiel pèse environ 600 Mo : le téléchargement est incomplet. Recommencez-le."
ok "Installeur : $(basename "$INSTALLER") (${SIZE_MB} Mo)"

# ------------------------------------------------- prefixe deja occupe ?
PREFIX_FOREIGN=0
if [ -f "$PREFIX/system.reg" ] && [ ! -f "$PREFIX/.rhino8-install-ok" ]; then
  if [ -d "$PREFIX/drive_c/Program Files" ]; then
    OTHERS=$(find "$PREFIX/drive_c/Program Files" -maxdepth 1 -mindepth 1 -type d \
             ! -iname 'Rhino*' ! -iname 'Common Files' ! -iname 'Internet Explorer' \
             ! -iname 'Windows*' ! -iname 'dotnet' -printf '%f, ' 2>/dev/null || true)
    [ -n "$OTHERS" ] && PREFIX_FOREIGN=1
  fi
fi

# ============================================================ consentement
NEED_SUDO=0
wine --version 2>/dev/null | grep -q '^wine-1[1-9]' || NEED_SUDO=1

if [ "$ASSUME_YES" -eq 0 ]; then
  echo
  echo "Ce script va :"
  [ "$NEED_SUDO" -eq 1 ] && \
  echo "  · activer l'architecture 32 bits et ajouter le dépôt WineHQ (mot de passe demandé)" && \
  echo "  · installer wine-staging"
  echo "  · installer des composants Windows dans :"
  echo "        $PREFIX"
  echo "  · installer Rhino 8 dans ce même dossier"
  echo "  · créer deux fichiers : $LAUNCHER"
  echo "                          $DESKTOP_FILE"
  echo "  · associer les fichiers .3dm à Rhino"
  echo
  echo "  Durée totale : environ 1 h 30, dont beaucoup d'attente sans intervention."
  echo
  if [ "$PREFIX_FOREIGN" -eq 1 ]; then
    printf '%s%s  ATTENTION%s : le dossier %s contient déjà d'"'"'autres logiciels\n' "$CB" "$CY" "$CN" "$PREFIX"
    printf '  Windows (%s). Ils seront affectés : la version de Windows simulée\n' "${OTHERS%, }"
    printf '  sera forcée, et .NET puis WebView2 y seront ajoutés.\n'
    printf '  Pour les laisser tranquilles, relancez avec : --prefix ~/rhino8\n\n'
  fi
  read -r -p "Continuer ? [o/N] " a || a=""
  case "$a" in [oOyY]*) : ;; *) echo "Abandon."; exit 0 ;; esac
fi

if [ "$NEED_SUDO" -eq 1 ]; then
  sudo -v || die "Droits administrateur refusés." "Relancez le script et saisissez votre mot de passe."
fi

# ============================================================ 3. Wine
step "Installation de Wine"

if [ "$NEED_SUDO" -eq 0 ]; then
  skip "wine-staging déjà présent"
else
  info "Réparation d'éventuelles installations interrompues…"
  sudo dpkg --configure -a >>"$LOG" 2>&1 || true
  sudo apt-get -f install -y >>"$LOG" 2>&1 || true

  info "Activation de l'architecture 32 bits…"
  run sudo dpkg --add-architecture i386

  info "Ajout du dépôt WineHQ…"
  run sudo mkdir -pm755 /etc/apt/keyrings
  SRC="/etc/apt/sources.list.d/winehq-$CODENAME.sources"
  run sudo wget -NP /etc/apt/sources.list.d/ \
      "https://dl.winehq.org/wine-builds/ubuntu/dists/$CODENAME/winehq-$CODENAME.sources"

  # Le nom du fichier de cle est impose par le champ Signed-By, et differe
  # selon la version d'apt (.key jusqu'a apt 2.x, .asc a partir d'apt 3.x).
  KEYPATH=$(awk -F': *' '/^Signed-By:/{print $2; exit}' "$SRC" 2>/dev/null || true)
  case "$KEYPATH" in
    /etc/apt/keyrings/*.key|/etc/apt/keyrings/*.asc|/etc/apt/keyrings/*.gpg) : ;;
    *) KEYPATH=/etc/apt/keyrings/winehq-archive.key ;;
  esac
  info "Clé de signature : $KEYPATH"
  run sudo wget -O "$KEYPATH" https://dl.winehq.org/wine-builds/winehq.key

  info "Téléchargement et installation (5 à 15 minutes)…"
  run sudo apt-get update || die "La mise à jour de la liste des paquets a échoué." \
    "Vérifiez votre connexion internet, puis relancez le script."

  # --no-remove : refuse d'installer si apt devait desinstaller des paquets
  # existants (PlayOnLinux, wine de la distribution...) sans prevenir.
  if ! run sudo apt-get install -y --install-recommends --no-remove winehq-staging; then
    warn "L'installation exigerait de supprimer des paquets déjà présents."
    info "Paquets concernés :"
    sudo apt-get install -s --install-recommends winehq-staging 2>/dev/null \
      | awk '/^Remv/{printf "        %s\n", $2}' | head -20 || true
    die "Installation interrompue pour ne rien supprimer sans votre accord." \
        "Si ces paquets ne vous servent plus : sudo apt install --install-recommends winehq-staging — et confirmez vous-même la suppression."
  fi

  hash -r
  wine --version 2>/dev/null | grep -q '^wine-1[1-9]' || die \
    "Wine est installé, mais ce n'est pas la bonne version qui répond." \
    "Un ancien Wine a priorité. Essayez : sudo apt remove wine wine64 wine32 libwine — puis relancez le script."
fi
ok "$(wine --version) — $(command -v wine)"

# ============================================================ 4. winetricks
step "Installation de winetricks"

WT="$HOME/.local/bin/winetricks"
if [ -x "$WT" ] && "$WT" --version 2>/dev/null | grep -qE '^20(2[5-9]|[3-9])'; then
  skip "winetricks déjà à jour"
else
  mkdir -p "$HOME/.local/bin"
  run wget -O "$WT" https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
  chmod +x "$WT"
fi
case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
ok "winetricks $("$WT" --version 2>/dev/null | cut -d- -f1)"

# ============================================================ 5. le prefixe
step "Création de l'espace Windows"

if [ -f "$PREFIX/system.reg" ]; then
  skip "espace déjà présent : $PREFIX"
else
  mkdir -p "$(dirname "$PREFIX")"
  WINEARCH=win64 WINEDLLOVERRIDES="mscoree=d;mshtml=d" run wineboot --init
  wine_wait
fi
grep -qa '#arch=win64' "$PREFIX/system.reg" || die \
  "Cet espace Wine est en 32 bits, or Rhino exige du 64 bits." \
  "Relancez avec un dossier neuf : $0 --prefix ~/rhino8"
ok "Espace 64 bits : $PREFIX"

edge_start   # actif jusqu'a la fin du script

# ============================================================ 6. composants
step "Installation des composants Windows (30 à 45 minutes)"

DOTNET_MARK="$PREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/mscorlib.dll"
if [ -f "$DOTNET_MARK" ]; then
  skip ".NET Framework 4.8 déjà installé"
else
  info "Des fenêtres d'installation Microsoft vont apparaître et se fermer"
  info "toutes seules : n'y touchez pas. Vous pouvez faire autre chose."
  run "$WT" -q corefonts d3dcompiler_47 vcrun2022 dotnet48 || true
  wine_wait
  [ -f "$DOTNET_MARK" ] || die \
    ".NET Framework 4.8 ne s'est pas installé." \
    "Relancez simplement le script : winetricks reprend où il s'est arrêté."
fi
ok "corefonts, d3dcompiler_47, vcrun2022, .NET Framework 4.8"

# ============================================================ 7. Windows 10
step "Remise en mode Windows 10 (étape critique)"

info "winetricks laisse l'espace en Windows 7 sans le restaurer ;"
info "sans cette correction, Rhino échouerait plus loin sans message."
run wine winecfg /v win10
wine_wait
VER=$(wine winecfg /v 2>>"$LOG" | tr -d '\r\n ' || true)
[ "$VER" = "win10" ] || die "L'espace Wine est resté en « ${VER:-inconnu} » au lieu de win10." \
  "Ouvrez un terminal et lancez : WINEPREFIX='$PREFIX' wine winecfg /v win10"
ok "Mode Windows 10 confirmé"

# ============================================================ 8. WebView2
step "Installation du composant navigateur (5 à 15 minutes)"

webview2_ok() {
  find "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application" \
       -type f -iname 'msedgewebview2.exe' -size +10M -print -quit 2>/dev/null | grep -q .
}
if webview2_ok; then
  skip "WebView2 déjà installé"
else
  info "Sans lui, la fenêtre de licence de Rhino resterait blanche."
  info "Là encore, des fenêtres peuvent apparaître : n'y touchez pas."
  run "$WT" -q webview2 || true
  wine_wait
  webview2_ok || die "WebView2 ne s'est pas installé correctement." \
    "Relancez le script ; si l'échec persiste, consultez le journal."
fi
# webview2 peut rebasculer la version globale de Windows : on revérifie.
VER=$(wine winecfg /v 2>>"$LOG" | tr -d '\r\n ' || true)
if [ "$VER" != "win10" ]; then
  run wine winecfg /v win10; wine_wait
  VER=$(wine winecfg /v 2>>"$LOG" | tr -d '\r\n ' || true)
  [ "$VER" = "win10" ] || die "Impossible de maintenir le mode Windows 10 (« $VER »)." \
    "Lancez : WINEPREFIX='$PREFIX' wine winecfg /v win10"
fi
ok "WebView2 installé, mode Windows 10 maintenu"

# ============================================================ 9. Rhino
step "Installation de Rhino (10 à 20 minutes)"

RHINO_EXE="$PREFIX/drive_c/Program Files/Rhino 8/System/Rhino.exe"
STAMP="$PREFIX/.rhino8-install-ok"

if [ -f "$STAMP" ] && [ -f "$RHINO_EXE" ]; then
  skip "Rhino déjà installé"
else
  [ -f "$RHINO_EXE" ] && warn "Installation précédente incomplète : on la reprend."
  info "L'installeur télécharge plusieurs centaines de Mo. Restez connecté."
  run wine "$INSTALLER" -passive -norestart || true
  wine_wait

  if [ ! -f "$RHINO_EXE" ]; then
    warn "L'installeur officiel n'a pas abouti — passage en installation manuelle."
    PC="$PREFIX/drive_c/ProgramData/Package Cache"
    [ -d "$PC" ] || die "L'installeur n'a rien déposé dans son cache." \
      "Vérifiez votre connexion internet et relancez le script."

    # On prend le plus GROS fichier correspondant : sans le filtre redist/,
    # find peut renvoyer une copie du moteur d'installation (~600 Ko) au lieu
    # du vrai redistribuable (~58 Mo).
    biggest() { find "$PC" -type f "$@" -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-; }
    DESKTOP_RT=$(biggest -path '*/redist/*' -iname 'windowsdesktop-runtime*win-x64.exe')
    ASPNET_RT=$(biggest  -path '*/redist/*' -iname 'aspnetcore*x64.exe')
    RHIEXEC=$(biggest -iname 'rhiexec.msi')
    RHINO_MSI=$(biggest -iname 'rhino.msi')

    for v in DESKTOP_RT RHINO_MSI; do
      [ -n "${!v}" ] || die "Fichier manquant dans le cache d'installation." \
        "L'installeur n'a pas pu tout télécharger. Vérifiez votre connexion et relancez le script."
    done
    [ "$(stat -c %s "$DESKTOP_RT")" -gt 20000000 ] || die \
      "Le runtime .NET trouvé est trop petit pour être le bon fichier." \
      "Supprimez « $PC » et relancez le script pour retélécharger."

    info "Installation des runtimes .NET…"
    run wine "$DESKTOP_RT" /quiet /norestart || true
    [ -n "$ASPNET_RT" ] && { run wine "$ASPNET_RT" /quiet /norestart || true; }
    info "Installation de Rhino…"
    [ -n "$RHIEXEC" ] && { run wine msiexec /i "$RHIEXEC" /qn || true; }
    run wine msiexec /i "$RHINO_MSI" /qn '/l*v' 'C:\rhino_msi.log' || true
    wine_wait
  fi

  [ -f "$RHINO_EXE" ] || die "Rhino ne s'est pas installé." \
    "La cause la plus fréquente est un espace resté en Windows 7. Vérifiez avec : WINEPREFIX='$PREFIX' wine winecfg /v"
  : >"$STAMP"
fi
ok "Rhino installé"

# ============================================================ 10. raccourci
step "Création du raccourci"

# Les variables PRIME n'ont de sens que sur un portable Optimus, ou le rendu
# doit etre renvoye vers la carte NVIDIA. Sur toute autre machine, inutile.
NVIDIA_BLOCK=""
if [ "$SKIP_NVIDIA" -eq 0 ] && command -v glxinfo >/dev/null 2>&1; then
  R1=$(glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL renderer/{print $2}' || true)
  R2=$(__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
       glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL renderer/{print $2}' || true)
  if [ -n "$R1" ] && [ -n "$R2" ] && [ "$R1" != "$R2" ]; then
    NVIDIA_BLOCK=$'export __NV_PRIME_RENDER_OFFLOAD=1\nexport __GLX_VENDOR_LIBRARY_NAME=nvidia\nexport __GL_SYNC_TO_VBLANK=0\nexport vblank_mode=0'
    ok "Carte dédiée détectée : $R2"
  fi
fi

for f in "$LAUNCHER" "$DESKTOP_FILE"; do
  [ -f "$f" ] && cp -f "$f" "$f.sauvegarde" 2>/dev/null && info "Ancien fichier sauvegardé : $(basename "$f").sauvegarde"
done
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

# Heredoc CITE : rien n'est interprete ici ; les valeurs sont injectees
# ensuite, ce qui evite tout probleme d'echappement.
cat > "$LAUNCHER" <<'LAUNCHER_EOF'
#!/usr/bin/env bash
set -u
export WINEPREFIX="@@PREFIX@@"
export WINEDEBUG=-all
@@NVIDIA@@
LOGF="$HOME/.local/share/rhino8-wine.log"
# Rhino n'accepte pas les chemins Unix : conversion obligatoire.
args=()
for f in "$@"; do
  if [ -e "$f" ]; then args+=("$(winepath -w "$f" 2>/dev/null || echo "$f")")
  else args+=("$f"); fi
done
{ echo; echo "--- $(date) ---"; } >>"$LOGF"
wine "C:\\Program Files\\Rhino 8\\System\\Rhino.exe" ${args[@]+"${args[@]}"} >>"$LOGF" 2>&1
rc=$?
if [ $rc -ne 0 ] && [ $rc -ne 1 ]; then
  msg="Rhino s'est arrêté (code $rc). Détails : $LOGF"
  command -v notify-send >/dev/null && notify-send "Rhino 8" "$msg" || echo "$msg" >&2
fi
exit $rc
LAUNCHER_EOF

python3 - "$LAUNCHER" "$PREFIX" "$NVIDIA_BLOCK" <<'PYEOF'
import sys
p, prefix, nvidia = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
s = s.replace("@@PREFIX@@", prefix).replace("@@NVIDIA@@", nvidia)
open(p, "w", encoding="utf-8").write(s)
PYEOF
chmod +x "$LAUNCHER"
bash -n "$LAUNCHER" || die "Le raccourci généré est invalide." "Signalez ce problème avec le journal."

cat > "$DESKTOP_FILE" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=Rhinoceros 8
Comment=Rhino 8 (Wine)
Exec=$LAUNCHER %f
Terminal=false
Categories=Graphics;3DGraphics;
MimeType=application/x-wine-extension-3dm;
StartupWMClass=rhino.exe
DESKTOP_EOF
update-desktop-database "$HOME/.local/share/applications" >>"$LOG" 2>&1 || true
xdg-mime default rhino8-wine.desktop application/x-wine-extension-3dm >>"$LOG" 2>&1 || true
ok "Raccourci « Rhinoceros 8 » ajouté au menu"

# ============================================================ 11. correctif
step "Correctif d'affichage (facultatif)"

FIXSRC="$(dirname "$(readlink -f "$0")")/redraw_fix.py"
if [ -f "$FIXSRC" ]; then
  cp "$FIXSRC" "$PREFIX/drive_c/redraw_fix.py"
  ok "Script copié dans C:\\redraw_fix.py"
  info "Si un viewport reste figé après une sélection, activez-le dans Rhino :"
  info "  Options > General > « Run these commands every time Rhino starts »"
  info "  puis saisissez :  _-RunPythonScript C:/redraw_fix.py"
else
  skip "redraw_fix.py absent (facultatif)"
fi

# ============================================================ fin
edge_stop
cat <<EOF

$CB${CG}Installation terminée.$CN

  Lancez « Rhinoceros 8 » depuis votre menu d'applications.
  Le premier démarrage prend environ une minute.
  Une fenêtre demandera votre adresse e-mail pour activer la licence.

  Des avertissements « libEGL » dans le journal sont normaux.

  Journal de cette installation : $LOG
  Journal des lancements :        $HOME/.local/share/rhino8-wine.log

EOF
