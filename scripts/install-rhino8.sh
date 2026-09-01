#!/usr/bin/env bash
#
#  install-rhino8.sh — installs Rhino 8 under Wine on Ubuntu / Linux Mint.
#
#  You supply the official installer downloaded from rhino3d.com.
#  This script does the rest: it verifies every step and stops with a plain
#  explanation if anything is wrong.
#
#  Usage:
#    ./install-rhino8.sh                       finds the installer on its own
#    ./install-rhino8.sh /path/to/rhino_8.exe  or you point it at one
#    ./install-rhino8.sh --help
#
#  Options:
#    --prefix PATH   Wine prefix to use (default: ~/.local/share/wineprefixes/rhino8)
#    --no-nvidia     do not configure render offload to an NVIDIA card
#    -y, --yes       do not ask for confirmation
#
#  Re-running this script is safe: completed steps are detected and skipped.
#
#  MIT licence. Rhinoceros is a trademark of Robert McNeel & Associates;
#  this script is independent. A valid Rhino licence is required.
#
set -Eeuo pipefail

DEFAULT_PREFIX="$HOME/.local/share/wineprefixes/rhino8"
LOG="${TMPDIR:-/tmp}/rhino8-install-$(date +%Y%m%d-%H%M%S).log"
LAUNCHER="$HOME/.local/bin/rhino8.sh"
DESKTOP_FILE="$HOME/.local/share/applications/rhino8-wine.desktop"
INSTALLER=""; ASSUME_YES=0; SKIP_NVIDIA=0; PREFIX_SET=0
TOTAL_STEPS=11

# ------------------------------------------------------------------- output
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
  printf '\n%s%sInstallation stopped.%s\n\n' "$CB" "$CR" "$CN" >&2
  printf '  %s\n\n' "$1" >&2
  [ $# -gt 1 ] && printf '  %sWhat to do:%s %s\n\n' "$CB" "$CN" "$2" >&2
  printf '  Full log: %s\n\n' "$LOG" >&2
  exit 1
}

on_err() {
  local line="$1" caller="$2" cmd="$3"
  [ "${caller:-0}" -gt 0 ] 2>/dev/null && line="$caller"
  die "A command failed unexpectedly (line $line): $cmd" \
      "Joignez le journal ci-dessous si vous demandez de l'aide."
}
trap 'on_err "$LINENO" "${BASH_LINENO[0]:-0}" "$BASH_COMMAND"' ERR

run() { printf '\n$ %s\n' "$*" >>"$LOG"; "$@" >>"$LOG" 2>&1; }

# ---------------------------------------------- MicrosoftEdgeUpdate guard
# Installed alongside WebView2, MicrosoftEdgeUpdate.exe never exits and blocks
# "wineserver -w" forever. We kill it BEFORE each wait. Never periodically:
# it is required DURING the WebView2 install (it is what downloads and installs
# the component), and killing it mid-way makes that install fail with status 1.
kill_edge_update() { pkill -u "$(id -u)" -f 'MicrosoftEdgeUpdat[e]' >/dev/null 2>&1 || true; }

# wineserver -w is silent and unbounded: we put a limit on it.
wine_wait() {
  kill_edge_update
  if ! timeout 240 wineserver -w >>"$LOG" 2>&1; then
    warn "Some Windows processes are stuck; stopping them."
    wineserver -k >>"$LOG" 2>&1 || true
    sleep 2
  fi
}

# "wine winecfg /v" prints NOTHING (verified on Wine 11.16), so we read the
# registry instead — the only reliable source. CurrentBuild is 19045 on
# Windows 10 and 7601 on Windows 7. Do not trust CurrentVersion: it reads 6.3
# in both cases, exactly as real Windows 10 does.
prefix_build() {
  timeout 120 wine reg query "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
    /v CurrentBuild 2>>"$LOG" | tr -d '\r' | awk '/CurrentBuild/{print $NF}'
}
is_win10() { [ "$(prefix_build)" = "19045" ]; }

# ----------------------------------------------------------------- arguments
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      # print the comment header, stopping at the first line of code
      awk 'NR>2 { if ($0 !~ /^#/) exit; sub(/^# ?/,""); print }' "$0"
      exit 0 ;;
    -y|--yes)  ASSUME_YES=1 ;;
    --no-nvidia) SKIP_NVIDIA=1 ;;
    --prefix)
      [ $# -ge 2 ] || die "The --prefix option needs a path." "Exemple : $0 --prefix ~/rhino8"
      PREFIX="$2"; PREFIX_SET=1; shift ;;
    -*) die "Unknown option: $1" "Run \"$0 --help\" for the list of options." ;;
    *)  INSTALLER="$1" ;;
  esac
  shift
done

# We NEVER inherit a WINEPREFIX from the environment: this script modifies the
# prefix deeply, and nobody expects an existing prefix meant for something else
# to be touched.
if [ "$PREFIX_SET" -eq 0 ]; then
  if [ -n "${WINEPREFIX:-}" ] && [ "$WINEPREFIX" != "$DEFAULT_PREFIX" ]; then
    warn "The WINEPREFIX variable in your environment is being ignored:"
    warn "  $WINEPREFIX"
    warn "To use it anyway: $0 --prefix \"$WINEPREFIX\""
  fi
  PREFIX="$DEFAULT_PREFIX"
fi

export WINEPREFIX="$PREFIX"
export WINEDEBUG=-all
: >"$LOG"

printf '%s%sInstalling Rhino 8 under Wine%s\n' "$CB" "$CC" "$CN"
printf 'Log: %s\n' "$LOG"

# ============================================================ 1. the system
step "Checking your system"

[ "$(id -u)" -ne 0 ] || die "Do not run this script as root." \
  "Run it as your normal user; your password will be asked for when needed."
command -v apt-get >/dev/null || die "This script targets Ubuntu, Linux Mint and derivatives." \
  "On Fedora or Arch, install wine-staging with your package manager and follow the manual guide."
for t in wget curl find; do
  command -v "$t" >/dev/null || die "The tool \"$t\" is missing." "Install it: sudo apt install $t"
done

# shellcheck disable=SC1091
. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
[ -n "$CODENAME" ] || die "Cannot determine the underlying Ubuntu release." \
  "Follow the manual guide: your distribution was not recognised."
ok "System: ${PRETTY_NAME:-unknown} (base \"$CODENAME\")"

if ! curl -fsS --connect-timeout 10 --max-time 30 -o /dev/null \
     "https://dl.winehq.org/wine-builds/ubuntu/dists/$CODENAME/" 2>>"$LOG"; then
  if ! curl -fsS --connect-timeout 10 --max-time 20 -o /dev/null https://dl.winehq.org/ 2>>"$LOG"; then
    die "Cannot reach dl.winehq.org." \
        "Check your internet connection (captive portal, proxy), then run the script again."
  fi
  die "WineHQ ne publie pas de paquets pour « $CODENAME »." \
      "Your release is probably too recent. Check the list at dl.winehq.org/wine-builds/ubuntu/dists/"
fi
ok "WineHQ repository available for \"$CODENAME\""

[ "${XDG_SESSION_TYPE:-}" = "wayland" ] && \
  warn "Wayland session: untested. Rhino will go through XWayland."

FREE_GB=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc '0-9')
[ "${FREE_GB:-0}" -ge 12 ] || die "Not enough disk space: ${FREE_GB} GB free, 12 GB needed." \
  "Free up some space, then run the script again."
ok "Disk space: ${FREE_GB} GB free"

RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
[ "${RAM_GB:-0}" -ge 7 ] || warn "Only ${RAM_GB} GB of RAM; 8 GB is the realistic minimum."

# ============================================================ 2. the installer
step "Looking for the Rhino installer"

if [ -z "$INSTALLER" ]; then
  for d in "$HOME/Téléchargements" "$HOME/Downloads" "$HOME/Bureau" "$HOME/Desktop" "$HOME"; do
    [ -d "$d" ] || continue
    F=$(find "$d" -maxdepth 1 -iname 'rhino_*8*.exe' -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    [ -n "$F" ] && { INSTALLER="$F"; break; }
  done
fi
[ -n "$INSTALLER" ] && [ -f "$INSTALLER" ] || die \
  "Rhino installer not found." \
  "Download Rhino 8 for Windows from rhino3d.com (McNeel account required), leave the file in your Downloads folder, then run this script again."
SIZE_MB=$(( $(stat -c %s "$INSTALLER") / 1024 / 1024 ))
[ "$SIZE_MB" -ge 300 ] || die "« $(basename "$INSTALLER") » ne fait que ${SIZE_MB} Mo." \
  "The official installer is about 600 MB, so this download is incomplete. Download it again."
ok "Installer: $(basename "$INSTALLER") (${SIZE_MB} MB)"

# ------------------------------------------------- prefix already in use?
PREFIX_FOREIGN=0
if [ -f "$PREFIX/system.reg" ] && [ ! -f "$PREFIX/.rhino8-install-ok" ]; then
  if [ -d "$PREFIX/drive_c/Program Files" ]; then
    OTHERS=$(find "$PREFIX/drive_c/Program Files" -maxdepth 1 -mindepth 1 -type d \
             ! -iname 'Rhino*' ! -iname 'Common Files' ! -iname 'Internet Explorer' \
             ! -iname 'Windows*' ! -iname 'dotnet' -printf '%f, ' 2>/dev/null || true)
    [ -n "$OTHERS" ] && PREFIX_FOREIGN=1
  fi
fi

# ============================================================ consent
NEED_SUDO=0
wine --version 2>/dev/null | grep -q '^wine-1[1-9]' || NEED_SUDO=1

if [ "$ASSUME_YES" -eq 0 ]; then
  echo
  echo "This script will:"
  [ "$NEED_SUDO" -eq 1 ] && \
  echo "  · enable the 32-bit architecture and add the WineHQ repository (asks for your password)" && \
  echo "  · installer wine-staging"
  echo "  · install Windows components into:"
  echo "        $PREFIX"
  echo "  · install Rhino 8 into that same folder"
  echo "  · create two files:   $LAUNCHER"
  echo "                          $DESKTOP_FILE"
  echo "  · associate .3dm files with Rhino"
  echo
  echo "  Total time: about 1 h 30, most of it waiting with nothing to do."
  echo
  if [ "$PREFIX_FOREIGN" -eq 1 ]; then
    printf '%s%s  WARNING%s: %s already holds other Windows software\n' "$CB" "$CY" "$CN" "$PREFIX"
    printf '  (%s). It will be affected: the simulated Windows version will be\n' "${OTHERS%, }"
    printf '  forced, and .NET then WebView2 will be added to it.\n'
    printf '  To leave it alone, run again with: --prefix ~/rhino8\n\n'
  fi
  read -r -p "Continue? [y/N] " a || a=""
  case "$a" in [yYoO]*) : ;; *) echo "Aborted."; exit 0 ;; esac
fi

if [ "$NEED_SUDO" -eq 1 ]; then
  sudo -v || die "Administrator rights refused." "Run the script again and enter your password."
fi

# ============================================================ 3. Wine
step "Installing Wine"

if [ "$NEED_SUDO" -eq 0 ]; then
  skip "wine-staging already present"
else
  info "Repairing any interrupted package installs…"
  sudo dpkg --configure -a >>"$LOG" 2>&1 || true
  sudo apt-get -f install -y >>"$LOG" 2>&1 || true

  info "Enabling the 32-bit architecture…"
  run sudo dpkg --add-architecture i386

  info "Adding the WineHQ repository…"
  run sudo mkdir -pm755 /etc/apt/keyrings
  SRC="/etc/apt/sources.list.d/winehq-$CODENAME.sources"
  run sudo wget -NP /etc/apt/sources.list.d/ \
      "https://dl.winehq.org/wine-builds/ubuntu/dists/$CODENAME/winehq-$CODENAME.sources"

  # The keyring filename is dictated by the Signed-By field, and differs with
  # the apt version (.key up to apt 2.x, .asc from apt 3.x on).
  KEYPATH=$(awk -F': *' '/^Signed-By:/{print $2; exit}' "$SRC" 2>/dev/null || true)
  case "$KEYPATH" in
    /etc/apt/keyrings/*.key|/etc/apt/keyrings/*.asc|/etc/apt/keyrings/*.gpg) : ;;
    *) KEYPATH=/etc/apt/keyrings/winehq-archive.key ;;
  esac
  info "Signing key: $KEYPATH"
  run sudo wget -O "$KEYPATH" https://dl.winehq.org/wine-builds/winehq.key

  info "Downloading and installing (5 to 15 minutes)…"
  run sudo apt-get update || die "Updating the package list failed." \
    "Check your internet connection, then run the script again."

  # --no-remove: refuse to install if apt would silently uninstall existing
  # packages (PlayOnLinux, the distribution's own wine, and so on).
  if ! run sudo apt-get install -y --install-recommends --no-remove winehq-staging; then
    warn "Installing would require removing packages you already have."
    info "Packages affected:"
    sudo apt-get install -s --install-recommends winehq-staging 2>/dev/null \
      | awk '/^Remv/{printf "        %s\n", $2}' | head -20 || true
    die "Stopped so that nothing is removed without your agreement." \
        "If you no longer need them: sudo apt install --install-recommends winehq-staging — and confirm the removal yourself."
  fi

  hash -r
  wine --version 2>/dev/null | grep -q '^wine-1[1-9]' || die \
    "Wine is installed, but the wrong version is answering." \
    "An older Wine takes precedence. Try: sudo apt remove wine wine64 wine32 libwine — then run the script again."
fi
ok "$(wine --version) — $(command -v wine)"

# ============================================================ 4. winetricks
step "Installing winetricks"

WT="$HOME/.local/bin/winetricks"
if [ -x "$WT" ] && "$WT" --version 2>/dev/null | grep -qE '^20(2[5-9]|[3-9])'; then
  skip "winetricks already up to date"
else
  mkdir -p "$HOME/.local/bin"
  run wget -O "$WT" https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
  chmod +x "$WT"
fi
case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
ok "winetricks $("$WT" --version 2>/dev/null | cut -d- -f1)"

# ============================================================ 5. the prefix
step "Creating the Windows space"

if [ -f "$PREFIX/system.reg" ]; then
  skip "space already present: $PREFIX"
else
  mkdir -p "$(dirname "$PREFIX")"
  WINEARCH=win64 WINEDLLOVERRIDES="mscoree=d;mshtml=d" run wineboot --init
  wine_wait
fi
grep -qa '#arch=win64' "$PREFIX/system.reg" || die \
  "This Wine space is 32-bit, and Rhino needs 64-bit." \
  "Run again with a fresh folder: $0 --prefix ~/rhino8"
ok "64-bit space: $PREFIX"

# ============================================================ 6. components
step "Installing the Windows components (30 to 45 minutes)"

DOTNET_MARK="$PREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/mscorlib.dll"
if [ -f "$DOTNET_MARK" ]; then
  skip ".NET Framework 4.8 already installed"
else
  info "Microsoft installer windows will appear and close by themselves:"
  info "leave them alone. You can go and do something else."
  run "$WT" -q corefonts d3dcompiler_47 vcrun2022 dotnet48 || true
  wine_wait
  [ -f "$DOTNET_MARK" ] || die \
    ".NET Framework 4.8 did not install." \
    "Just run the script again: winetricks resumes where it stopped."
fi
ok "corefonts, d3dcompiler_47, vcrun2022, .NET Framework 4.8"

# ============================================================ 7. Windows 10
step "Switching back to Windows 10 (critical step)"

info "winetricks laisse l'espace en Windows 7 sans le restaurer ;"
info "without this fix, Rhino would fail later with no message at all."
run wine winecfg /v win10
wine_wait
BUILD=$(prefix_build)
[ "$BUILD" = "19045" ] || die "The Wine space reports Windows build \"${BUILD:-unknown}\" instead of 19045 (Windows 10)." \
  "Open a terminal and run: WINEPREFIX='$PREFIX' wine winecfg /v win10"
ok "Windows 10 mode confirmed (build $BUILD)"

# ============================================================ 8. WebView2
step "Installing the browser component (5 to 15 minutes)"

webview2_ok() {
  find "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application" \
       -type f -iname 'msedgewebview2.exe' -size +1M -print -quit 2>/dev/null | grep -q .
}
if webview2_ok; then
  skip "WebView2 already installed"
else
  info "Without it, Rhino's licensing window would stay blank."
  info "Here too, windows may appear: leave them alone."
  run "$WT" -q webview2 || true
  wine_wait
  webview2_ok || die "WebView2 did not install correctly." \
    "Run the script again: this step often succeeds on a second attempt. If it keeps failing, empty ~/.cache/winetricks/webview2 and retry."
fi
# webview2 can switch the global Windows version back: re-check.
if ! is_win10; then
  warn "WebView2 changed the Windows version; setting it back."
  run wine winecfg /v win10; wine_wait
  is_win10 || die "Cannot keep the prefix in Windows 10 mode (build \"$(prefix_build)\")." \
    "Run: WINEPREFIX='$PREFIX' wine winecfg /v win10"
fi
ok "WebView2 installed, Windows 10 mode preserved"

# ============================================================ 9. Rhino
step "Installing Rhino (10 to 20 minutes)"

RHINO_EXE="$PREFIX/drive_c/Program Files/Rhino 8/System/Rhino.exe"
STAMP="$PREFIX/.rhino8-install-ok"

if [ -f "$STAMP" ] && [ -f "$RHINO_EXE" ]; then
  skip "Rhino already installed"
else
  [ -f "$RHINO_EXE" ] && warn "Previous installation was incomplete; resuming it."
  info "The installer downloads several hundred MB. Stay connected."
  run wine "$INSTALLER" -passive -norestart || true
  wine_wait

  if [ ! -f "$RHINO_EXE" ]; then
    warn "The official installer did not complete — falling back to manual installation."
    PC="$PREFIX/drive_c/ProgramData/Package Cache"
    [ -d "$PC" ] || die "The installer left nothing in its cache." \
      "Check your internet connection and run the script again."

    # Take the BIGGEST matching file: without the redist/ filter, find can
    # return a cached copy of the installer engine (~600 KB) instead of the
    # real redistributable (~58 MB).
    biggest() { find "$PC" -type f "$@" -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-; }
    DESKTOP_RT=$(biggest -path '*/redist/*' -iname 'windowsdesktop-runtime*win-x64.exe')
    ASPNET_RT=$(biggest  -path '*/redist/*' -iname 'aspnetcore*x64.exe')
    RHIEXEC=$(biggest -iname 'rhiexec.msi')
    RHINO_MSI=$(biggest -iname 'rhino.msi')

    for v in DESKTOP_RT RHINO_MSI; do
      [ -n "${!v}" ] || die "A file is missing from the installation cache." \
        "The installer could not download everything. Check your connection and run the script again."
    done
    [ "$(stat -c %s "$DESKTOP_RT")" -gt 20000000 ] || die \
      "The .NET runtime found is too small to be the right file." \
      "Delete \"$PC\" and run the script again to download it afresh."

    info "Installing the .NET runtimes…"
    run wine "$DESKTOP_RT" /quiet /norestart || true
    [ -n "$ASPNET_RT" ] && { run wine "$ASPNET_RT" /quiet /norestart || true; }
    info "Installing Rhino…"
    [ -n "$RHIEXEC" ] && { run wine msiexec /i "$RHIEXEC" /qn || true; }
    run wine msiexec /i "$RHINO_MSI" /qn '/l*v' 'C:\rhino_msi.log' || true
    wine_wait
  fi

  [ -f "$RHINO_EXE" ] || die "Rhino did not install." \
    "The usual cause is a prefix left on Windows 7. Check with: WINEPREFIX='$PREFIX' wine reg query 'HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion' /v CurrentBuild — it must read 19045."
  : >"$STAMP"
fi
ok "Rhino installed"

# ============================================================ 10. launcher
step "Creating the launcher"

# The PRIME variables only make sense on an Optimus laptop, where rendering
# must be offloaded to the NVIDIA card. Useless on any other machine.
NVIDIA_BLOCK=""
if [ "$SKIP_NVIDIA" -eq 0 ] && command -v glxinfo >/dev/null 2>&1; then
  R1=$(glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL renderer/{print $2}' || true)
  R2=$(__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
       glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL renderer/{print $2}' || true)
  if [ -n "$R1" ] && [ -n "$R2" ] && [ "$R1" != "$R2" ]; then
    NVIDIA_BLOCK=$'export __NV_PRIME_RENDER_OFFLOAD=1\nexport __GLX_VENDOR_LIBRARY_NAME=nvidia\nexport __GL_SYNC_TO_VBLANK=0\nexport vblank_mode=0'
    ok "Discrete GPU detected: $R2"
  fi
fi

for f in "$LAUNCHER" "$DESKTOP_FILE"; do
  [ -f "$f" ] && cp -f "$f" "$f.backup" 2>/dev/null && info "Previous file saved as $(basename "$f").backup"
done
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

# QUOTED heredoc: nothing is expanded here. The values are substituted
# afterwards, which avoids every escaping pitfall.
cat > "$LAUNCHER" <<'LAUNCHER_EOF'
#!/usr/bin/env bash
set -u
export WINEPREFIX="@@PREFIX@@"
export WINEDEBUG=-all
@@NVIDIA@@
LOGF="$HOME/.local/share/rhino8-wine.log"
# Rhino does not accept Unix paths: conversion is required.
args=()
for f in "$@"; do
  if [ -e "$f" ]; then args+=("$(winepath -w "$f" 2>/dev/null || echo "$f")")
  else args+=("$f"); fi
done
{ echo; echo "--- $(date) ---"; } >>"$LOGF"
wine "C:\\Program Files\\Rhino 8\\System\\Rhino.exe" ${args[@]+"${args[@]}"} >>"$LOGF" 2>&1
rc=$?
if [ $rc -ne 0 ] && [ $rc -ne 1 ]; then
  msg="Rhino exited with code $rc. Details: $LOGF"
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
bash -n "$LAUNCHER" || die "The generated launcher is not valid." "Please report this along with the log."

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
ok "\"Rhinoceros 8\" added to your applications menu"

# ============================================================ 11. display fix
step "Display fix (optional)"

SCRIPTDIR="$(dirname "$(readlink -f "$0")")"

# cleanup.sh removes the orphaned processes Rhino leaves behind on every exit.
if [ -f "$SCRIPTDIR/cleanup.sh" ]; then
  install -Dm755 "$SCRIPTDIR/cleanup.sh" "$HOME/.local/bin/rhino8-cleanup.sh"
  ok "Cleanup helper installed: rhino8-cleanup.sh"
  info "Run it if launches start behaving erratically."
fi

FIXSRC="$SCRIPTDIR/redraw_fix.py"
if [ -f "$FIXSRC" ]; then
  cp "$FIXSRC" "$PREFIX/drive_c/redraw_fix.py"
  ok "Script copied to C:\\redraw_fix.py"
  info "If a viewport stays frozen after a selection, enable it inside Rhino:"
  info "  Options > General > « Run these commands every time Rhino starts »"
  info "  then enter:  _-RunPythonScript C:/redraw_fix.py"
else
  skip "redraw_fix.py not found (optional)"
fi

# ============================================================ done
kill_edge_update
cat <<EOF

$CB${CG}Installation complete.$CN

  Launch "Rhinoceros 8" from your applications menu.
  The first start takes about a minute.
  A window will ask for your e-mail address to activate the licence.

  "libEGL" warnings in the log are normal.

  Log of this installation: $LOG
  Log of Rhino launches:    $HOME/.local/share/rhino8-wine.log

EOF
