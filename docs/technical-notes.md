# Rhino 8 under Wine — technical notes

A procedure verified command by command on two machines, with the traps that cost hours, the points where the two installs contradict each other, and an honest list of what does not work.

| | Machine A | Machine B |
|---|---|---|
| System | Ubuntu 26.04 “Resolute” | Linux Mint 22.3 (noble base) |
| Session | GNOME / XWayland | X11 / Cinnamon |
| GPU | NVIDIA GTX 1080 · 580.173.02 | Intel HD 630 + GTX 1060 (Optimus) |
| CPU / RAM | Threadripper 1900X · 98 GB | i7-7700HQ · 31 GB |
| Wine | 11.15 staging | 11.16 staging |

---

## Prerequisites

- A distribution based on Ubuntu 24.04 (noble) or newer.
- An X11 or XWayland session. Native Wayland was not tested.
- sudo rights, 12 GB free in `$HOME`, 8 GB RAM minimum (16 GB realistic).
- A stable internet connection throughout the install: the official executable is a downloader.
- `$HOME/.local/bin` present in your `PATH`.

## Procedure

### 1. Find the right APT codename

```bash
. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}"
echo "session: ${XDG_SESSION_TYPE:-inconnue}"
```

The WineHQ repository is indexed by *Ubuntu* codename, not by your derivative's own. On Mint 22.3, `lsb_release -sc` returns “zena” and the WineHQ URL 404s; read `UBUNTU_CODENAME` instead, which is “noble”. Note your display session too: everything here was validated on X11 and XWayland, never on native Wayland.

> **Check** — `curl -o /dev/null -w '%{http_code}\n' https://dl.winehq.org/wine-builds/ubuntu/dists/$CODENAME/` must return 200. A 404 means you used the derivative's codename.

### 2. Check hardware, RAM and disk

```bash
free -h
df -h "$HOME"
lspci -nn | grep -iE 'vga|3d'
```

Measured at the end: 7.0 GB prefix (3.7 GB of it `drive_c/windows`, from .NET Framework 4.8 assemblies; 1.3 GB Rhino; 908 MB WebView2), plus a 636 MB downloaded installer. Rhino uses about 1.2 GB of RAM with nothing but a cube open. What `lspci` prints decides whether the Optimus steps apply to you.

> **Check** — At least 12 GB free in `$HOME` and 8 GB RAM (16 GB realistic). Two graphics controllers listed means Optimus.

### 3. Enable the i386 architecture

```bash
sudo dpkg --add-architecture i386
dpkg --print-foreign-architectures
```

A **blocking** step, missing from our original notes: `wine-staging` hard-depends on `wine-staging-i386` at the same version. Without the 32-bit architecture the install fails on unmet dependencies. Also check that *universe* and *multiverse* are enabled — they are by default on desktop Mint and Ubuntu, not on a minimal install.

> **Check** — The command must list `i386`.

### 4. Add the WineHQ key and repository

```bash
. /etc/os-release && CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
sudo wget -NP /etc/apt/sources.list.d/ "https://dl.winehq.org/wine-builds/ubuntu/dists/$CODENAME/winehq-$CODENAME.sources"
gpg --show-keys --with-fingerprint /etc/apt/keyrings/winehq-archive.key
```

The key filename is not yours to choose: the `.sources` file WineHQ publishes contains `Signed-By: /etc/apt/keyrings/winehq-archive.key`. Keep the key **ASCII-armored** — do *not* run `gpg --dearmor`, whatever most tutorials say. On apt 3.x distributions (Ubuntu 25.10+) the expected name may end in `.asc`: read the `Signed-By` field of the downloaded file and name the key accordingly.

> **Check** — The fingerprint must be `D43F 6401 4536 9C51 D786 DDEA 76F1 A20F F987 672F`, uid “WineHQ packages”. **Verified case on Ubuntu 26.04** (apt 3.x): a `.key` keyring is ignored *silently*, the repository shows as unsigned with `NO_PUBKEY 76F1A20FF987672F`. Name it `.asc` and fix the file: `sudo sed -i 's|winehq-archive\.key|winehq-archive.asc|' /etc/apt/sources.list.d/winehq-*.sources`

### 5. Install winehq-staging, then check which Wine answers

```bash
sudo apt update
sudo apt install --install-recommends winehq-staging
wine --version
readlink -f "$(command -v wine)"
dpkg -S "$(command -v wine)"
```

`--install-recommends` is not decoration: it pulls libgnutls (TLS, hence license activation), libglu1-mesa, GTK, CUPS, Kerberos and the whole libx* set. Without it you get a degraded install. Choose *staging*: the stable branch was capped at 11.0 while staging was at 11.16. Important: your distribution's Wine 9.0 packages may remain installed alongside — hence the check below, the only one that proves the right Wine answers.

> **Check** — `readlink -f` must point at `/opt/wine-staging/bin/wine` and `dpkg -S` must answer `winehq-staging`. There is no `wine64` binary with winehq-staging: never use it in scripts.

### 6. Install a current winetricks

```bash
mkdir -p "$HOME/.local/bin"
wget -O "$HOME/.local/bin/winetricks" https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x "$HOME/.local/bin/winetricks"
hash -r; winetricks --version
```

The repository winetricks is 20240105 — two years behind the one used here. A 2024 winetricks does not know the current URLs, nor the workarounds for Wine bugs 53925 and 58921 that the `webview2` verb applies automatically.

> **Check** — `command -v winetricks` must return the `~/.local/bin` path, not `/usr/bin`.

### 7. Create the 64-bit prefix

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
export WINEARCH=win64
WINEDLLOVERRIDES="mscoree=d;mshtml=d" wineboot --init
grep -am1 '#arch' "$WINEPREFIX/system.reg"
```

Pick a path with **no spaces and no username**: spaces do work, but every copied command then becomes a quoting trap. The `mscoree=d;mshtml=d` overrides stop Wine-Mono from installing — Rhino ships its own .NET 8. Be aware: Wine links the prefix's `Documents`, `Desktop` and `Downloads` to your *real* Linux folders, and the user folder is named after your login.

> **Check** — Expect `#arch=win64`. A 32-bit prefix cannot install `rhino.msi`, which is x64.

### 8. Install the Windows components

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
winetricks -q corefonts d3dcompiler_47 vcrun2022 dotnet48
cat "$WINEPREFIX/winetricks.log"
```

`dotnet48` is **mandatory** and it is the heavy one: Rhino's MSI runs managed custom actions (WiX/DTF) that need a .NET Framework CLR *in addition to* the bundled .NET 8. Without it the install dies with `0x80070643`. Don't be alarmed if the log shows verbs you never typed: `dotnet48` calls `remove_mono`, then `dotnet40`, which switches to Windows XP temporarily.

> **Check** — The log must contain corefonts, d3dcompiler_47, vcrun2022 and dotnet48. `drive_c/windows/mono` must be **absent**.

### 9. Put the prefix back on Windows 10

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
wine winecfg /v win10
wine reg query "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentBuild
```

**The central trap of the whole procedure.** In winetricks, `load_dotnet48()` ends with `w_set_winver win7` *without restoring* — unlike `load_dotnet40()`, which brackets its change. The prefix therefore stays on Windows 7 and the Rhino install later fails silently. `wine winecfg /v` with no argument prints the current version — that is the check; with `win10` it is the fix.

> **Check** — **Verified at runtime:** `wine winecfg /v` with no argument prints *nothing* on Wine 11.16 — do not use it as a check. The only reliable source is the registry: `CurrentBuild` must read **19045** (Windows 10), not 7601 (Windows 7). **Note**: `CurrentVersion` reads 6.3 in both cases — so does real Windows 10.

### 10. Install WebView2 before the Rhino installer

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
winetricks -q webview2
wine reg query "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentBuild
ls "$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/"
```

Our original notes put WebView2 *after* Rhino: that ordering is wrong. The installer log shows it stopping exactly on `Redist_MSWebView2_Standalone` (error `0x80040902`), before the .NET runtimes were even reached. WebView2 also drives the licensing window, which stays blank without it. Expected side effect: winetricks adds a *per-application* override `msedgewebview2.exe = win7` — leave it alone, it does not change the global version.

> **Check** — A version folder exists, and `CurrentBuild` still reads 19045. The `msedgewebview2.exe` binary is about 4.6 MB — do not test for the folder alone, it appears as soon as extraction starts.

### 11. Get the official installer

```bash
ls -lh ~/Téléchargements/rhino_en-us_*.exe 2>/dev/null || ls -lh ~/Downloads/rhino_en-us_*.exe
```

Download only from **rhino3d.com**, with a McNeel account. The file matches `rhino_en-us_<VERSION>.exe`, about 636 MB. Never stated anywhere and yet decisive: this `.exe` is a **downloader**. It fetches vcredist, WebView2, the Desktop Runtime and ASP.NET Core from `files.mcneel.com` while it runs. Offline installation is impossible. Nothing here circumvents licensing.

> **Check** — Size in the 600–700 MB range, and `files.mcneel.com` reachable.

### 12. Run the installer, then read its log

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
wine ~/Téléchargements/rhino_en-us_*.exe -passive -norestart
LOG=$(ls -t "$WINEPREFIX/drive_c/users/$USER/AppData/Local/Temp/Rhino_8_"*.log | head -1); echo "$LOG"
grep -E 'i301:|i319:|i338:|i399:|i007:' "$LOG" | tail -40
```

With steps 9 and 10 done, the installer should complete on its own — that is what happened on the Ubuntu machine. On the Mint machine it failed, but *because* those two steps were missing. Do not conclude anything without reading the log: it is what tells you whether the MSIs were applied.

> **Check** — Success: no `Error 0x…` on a package and `Program Files/Rhino 8/System/Rhino.exe` present — skip to step 14. Failure: a non-zero `i319 … result: 0x…` — go to step 13.

### 13. Fallback: manual install with no hard-coded GUID

```bash
export PC="$WINEPREFIX/drive_c/ProgramData/Package Cache"
find "$PC" -type f \( -iname '*.msi' -o -iname '*.exe' \) -printf '%10s  %P\n' | sort -k2
find_one() { find "$PC" -type f "$@" -print -quit; }
DESKTOP_RT=$(find_one -path '*/redist/*' -iname 'windowsdesktop-runtime*win-x64.exe')
ASPNET_RT=$(find_one -path '*/redist/*' -iname 'aspnetcore*x64.exe')
RHIEXEC_MSI=$(find_one -iname 'rhiexec.msi'); RHINO_MSI=$(find_one -iname 'rhino.msi')
for v in DESKTOP_RT ASPNET_RT RHIEXEC_MSI RHINO_MSI; do f=${!v}; printf "%-12s %12s  %s\n" "$v" "$(stat -c %s "$f")" "$f"; done
wine "$DESKTOP_RT" /quiet /norestart && wine "$ASPNET_RT" /quiet /norestart
wine msiexec /i "$RHIEXEC_MSI" /qn /l*v 'C:\rhiexec.log'
wine msiexec /i "$RHINO_MSI" /qn /l*v 'C:\rhino_msi.log'
```

Two naming conventions coexist in the cache: `{GUID}vVERSION` for the Rhino MSIs, but a **SHA-1 hash** with no braces for the .NET runtimes. So hard-code no identifier — they change with every version. The `-path '*/redist/*'` filter is **essential**: without it `find` returns a 622 KB copy of the installer engine before the real 58 MB redistributable, and the install “succeeds” without installing anything. Always check the sizes before running.

> **Check** — Expected magnitudes: rhino.msi ≈ 550 MB, rhiexec.msi ≈ 1 MB, windowsdesktop ≈ 58 MB, aspnetcore ≈ 10 MB. Afterwards `grep -a 'VersionNT' C:\rhino_msi.log` must show **603**, not 601.

### 14. Verify what actually landed

```bash
wine reg query 'HKLM\Software\McNeel\Rhinoceros\8.0\Install' /v Version
ls -l "$WINEPREFIX/drive_c/Program Files/Rhino 8/System/Rhino.exe"
ls "$WINEPREFIX/drive_c/Program Files/dotnet/shared/"*
```

A checkpoint before touching the launcher. Expected: Rhino 8, Rhino Installer Engine, .NET Framework 4.8, the .NET 8 runtimes (Core, Desktop, ASP.NET), WebView2, and VC++ 2015-2022 and 2013.

> **Check** — The registry returns the build number; `dotnet/shared` holds the three 8.0.x subfolders.

### 15. Optimus: decide whether the PRIME variables help

```bash
glxinfo -B | grep 'OpenGL renderer'
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo -B | grep 'OpenGL renderer'
```

A decisive, instant test that does not require launching Rhino. On the reference machine: `Mesa Intel HD Graphics 630` without the variables, `NVIDIA GeForce GTX 1060` with them. If both lines are **identical**, you are not on Optimus: leave the NVIDIA block off. The variables break nothing elsewhere — libglvnd falls back to Mesa silently — but on a laptop they wake the discrete GPU at every launch.

> **Check** — The two lines must differ for the NVIDIA block to be meaningful.

### 16. Install the launcher script

```bash
# voir le script complet plus bas / see the full script below
chmod +x "$HOME/.local/bin/rhino8.sh"
"$HOME/.local/bin/rhino8.sh"
```

Three differences from our original script, all measurement-driven. The NVIDIA block is **commented out** and isolated. `__VK_LAYER_NV_optimus` was dropped: no effect. And crucially, path conversion via `winepath -w` was added — verified by side-by-side launches: with a Unix path Rhino opens “Untitled”, with the converted path it opens the file.

> **Check** — Rhino starts. With the NVIDIA block on, `nvidia-smi | grep -i rhino` should show real usage (107 MiB measured); about 1 MiB means the process is not drawing on the discrete GPU.

### 17. Menu entry and .3dm association

```bash
desktop-file-validate "$HOME/.local/share/applications/rhino8-wine.desktop"
update-desktop-database "$HOME/.local/share/applications"
xdg-mime default rhino8-wine.desktop application/x-wine-extension-3dm
gtk-launch rhino8-wine
```

Two real defects of our original file are fixed here. With no `MimeType=` line and no explicit association, double-clicking a `.3dm` goes through the shortcut winemenubuilder generates automatically, which only sets `WINEPREFIX`: measured, that Rhino uses just 1 MiB on the NVIDIA card versus 107 MiB through the launcher — **acceleration is lost**. And `%f` passes a Unix path, which Rhino ignores: it only works with the conversion added in step 16.

> **Check** — `desktop-file-validate` must print nothing, and double-clicking a `.3dm` must open that file — check the window title.

### 18. First launch and licensing

```bash
"$HOME/.local/bin/rhino8.sh" 2>&1 | tee /tmp/rhino-first-run.log
```

Cloud Zoo activation goes through WebView2 and your browser: this is where step 10 pays off. **Expected** messages that indicate no problem: `libEGL warning: … driver (null)` and `egl: failed to create dri2 screen` at every launch, and `Failed to unregister class Chrome_WidgetWin_0. Error = 1412` on exit.

> **Check** — Rhino opens its main window and the title bar shows the license state.

### 19. Viewport refresh

```bash
# -> "Two machines, two remedies" / "Deux machines, deux remedes"
```

This is where the two machines **diverge**, and where recipes must not be merged. Read the dedicated section before applying anything.

> **Check** — See the comparison section.

### 20. Shut down cleanly between runs

```bash
pkill -9 -f 'Rhin[o]\.exe'
pkill -9 -f 'wineserve[r]'
pgrep -af 'wine|Rhino'
```

The brackets are not a flourish: `pkill -9 -f "Rhino.exe"` kills the terminal running the command, because that shell's own command line contains the pattern. Also, `wineserver -k` was not enough to stop Rhino in our tests. Closing leaves orphaned processes that accumulate and make later launches erratic.

> **Check** — `pgrep` must return nothing before the next launch.

### 21. Hygiene before you share anything

```bash
grep -rInE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+|/home/[a-z]+' . --include='*.xml' --include='*.sh' --include='*.py'
```

Read this **before** publishing a repository, a backup or a screenshot. Never share the prefix or the *License Manager* folder: under Wine, DPAPI is a stub, and `cloudzoo.json` literally contains the base64 of “Wine Crypt32 ok”. **The auth token is not protected.** Rhino's settings file also holds the account e-mail address and user-specific paths.

> **Check** — The grep must return no e-mail address and no `/home/LOGIN` in anything you publish.

## The two files to create

`~/.local/bin/rhino8.sh`

```bash
#!/usr/bin/env bash
# Launches Rhino 8 under Wine.
set -u
export WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/rhino8}"
export WINEDEBUG=-all

# --- OPTIONAL BLOCK: Intel + NVIDIA Optimus laptop only ---------------
# Uncomment only if step 15 shows two different renderers.
#export __NV_PRIME_RENDER_OFFLOAD=1
#export __GLX_VENDOR_LIBRARY_NAME=nvidia
# Disables vsync: a palliative for the frozen refresh, but it can cause
# visible tearing.
#export __GL_SYNC_TO_VBLANK=0   # NVIDIA driver
#export vblank_mode=0           # Mesa equivalent

# Rhino does not accept Unix paths: conversion is required.
args=()
for f in "$@"; do
  if [ -e "$f" ]; then args+=("$(winepath -w "$f" 2>/dev/null || echo "$f")")
  else args+=("$f"); fi
done
exec wine "C:\Program Files\Rhino 8\System\Rhino.exe" ${args[@]+"${args[@]}"}
```

`~/.local/share/applications/rhino8-wine.desktop`

```ini
[Desktop Entry]
Type=Application
Name=Rhinoceros 8 (Wine)
Exec=/home/VOTRE_LOGIN/.local/bin/rhino8.sh %f
Icon=/home/VOTRE_LOGIN/.local/share/icons/rhino8.ico
Terminal=false
Categories=Graphics;3DGraphics;
MimeType=application/x-wine-extension-3dm;
StartupWMClass=rhino.exe
```

## Two machines, two remedies

The two installs diverge on five points, and merging their recipes would produce contradictory instructions.

| | Ubuntu 26.04 · XWayland · GTX 1080 | Mint 22.3 · X11 · Optimus |
|---|---|---|
| Official bootstrapper | Works in `-passive` mode once .NET Framework 4.8 is present. | Failed with `0x902` — but WebView2 was missing and the prefix was on Windows 7. |
| MSI failure mode | `0x80070643` for lack of .NET Framework 4.8. | `LaunchConditions` with `VersionNT = 601`. |
| Python scripting (RunPythonScript) | **Never starts.** Only the VBScript engine works. | **Works**, and the whole refresh workaround depends on it. |
| Refresh remedy | Drop the viewport to **OpenGL 2.1** (6.3 fps versus 12.6 on a 1.3 GB scene). | Stay on **OpenGL 3.3** and force redraws with a Python script. |
| Grasshopper and plugins | Tested and working: Pufferfish, Parakeet, LunchBox through Yak. | **Not tested.** |

## Traps

| Symptom | Cause | Remedy |
|---|---|---|
| `apt install winehq-staging` fails on unmet dependencies. | The 32-bit architecture is not enabled. | `sudo dpkg --add-architecture i386 && sudo apt update` |
| The WineHQ repository file 404s. | You used the derivative's codename (“zena” on Mint) instead of Ubuntu's. | Read `UBUNTU_CODENAME` from `/etc/os-release`. |
| apt rejects the repository as unsigned. | The key was `gpg --dearmor`ed or saved under another name. | Save the raw `winehq.key` under the exact name in the `Signed-By` field. |
| `wine --version` shows 9.0. | The distribution's Wine won in the PATH. | `readlink -f "$(command -v wine)"` must give `/opt/wine-staging/bin/wine`. |
| **rhino.msi does nothing, with no visible error.** | The prefix stayed on Windows 7: `load_dotnet48()` ends with `w_set_winver win7` and never restores it. | `wine winecfg /v win10` before any MSI. Log signature: `VersionNT = 601`. |
| The MSI log shows `VersionNT = 603` and you assume failure. | In win10 mode Wine reports 603, exactly as real Windows 10 does. | 603 is the **expected** value. Do not look for 1000. |
| The installer stops with a code such as `0x902`. | The bootstrapper failed on WebView2, with the prefix still on Windows 7. | Do steps 9 and 10 *before* running it. |
| The Desktop Runtime “installs” in seconds, with no effect. | `find` returned a cached copy of the installer engine (622 KB) instead of the redistributable (58 MB). | Add `-path '*/redist/*'` and check the size. |
| You look for brace-named folders for the .NET runtimes and find none. | They are named by a SHA-1 hash, with no braces and no version. | Search by filename, never by folder pattern. |
| The winetricks log contains verbs you never asked for. | `dotnet48` calls `remove_mono`, then `dotnet40`, which switches to Windows XP. | Normal. But if you interrupt it, re-check the Windows version. |
| Double-clicking a `.3dm` opens an empty document. | No association, and `%f` passes a Unix path that Rhino ignores. | `MimeType=` + `xdg-mime default` + `winepath -w` conversion. |
| `pkill -9 -f "Rhino.exe"` kills the terminal. | The shell's own command line contains the pattern. | Write `pkill -9 -f 'Rhin[o]\.exe'`. |
| A Rhino settings change vanishes on restart. | Rhino rewrites its XML on exit, overwriting anything edited while it ran. | Edit the XML with Rhino **closed**, or use the UI. |
| The Python startup script stops working. | The engine is IronPython 2.7: f-strings and annotations break it. | Keep the script Python 2 compatible. |
| `Version=win7` shows up in the registry after step 9. | It is a *per-application* override for `msedgewebview2.exe`, added by winetricks. | Leave it. The global version is read with `wine winecfg /v`. |
| winetricks hangs forever after WebView2 is installed. | `MicrosoftEdgeUpdate.exe` never exits and blocks `wineserver -w`. | Kill it before or during the winetricks run. |
| Grasshopper wires are drawn straight instead of curved. | Wine's built-in GDI+. | `winetricks -q gdiplus` — confirmed on the Ubuntu machine. |
| `winetricks` hangs silently for 30 minutes. | `MicrosoftEdgeUpdate.exe`, installed with WebView2, never exits, and `wineserver -w` waits for every process to die. | `pkill -f MicrosoftEdgeUpdate` unblocks it instantly. |
| An automation script hangs when opening a file. | The modal “Missing Fonts” dialog opens when the document references missing fonts. | Tick “Don't show again”, and install the missing fonts. |
| `wine Rhino.exe /runscript="..."` does nothing. | Wine rebuilds the command line wrapping the whole argument in quotes, a form Rhino does not accept. | Go through a `.bat` launched with `wine cmd /c`. |
| `-_RunScript C:\file.rvb` returns a syntax error. | `RunScript` compiles its argument as code; the colon in the path is what breaks. | Use `-_LoadScript` to run a file. |
| `wine winecfg /v` prints nothing and you assume the step failed. | That command does not print the current version on Wine 11.16 — verified at runtime on two prefixes. | Read the registry instead: `CurrentBuild` must be 19045. |
| The Package Manager crashes Rhino instantly. | Silent crash in the embedded WebView2 child processes. | Use the Yak command line instead — fully functional. |

## What does not work

- Cycles rendering is **CPU-only**. Neither CUDA nor OptiX is detected under Wine; the GPU is never used for final rendering.
- Viewport antialiasing is **unavailable**: Wine's EGL path exposes no multisample pixel formats. `_-ViewCaptureToFile` exports are antialiased regardless.
- The refresh workaround **is not a fix**: it forces redraws, at a cost, without addressing the cause.
- The Package Manager crashes Rhino. The Yak command line works perfectly.
- Unclean exit: orphaned processes at every close, and they accumulate.
- Offline installation is **impossible**: the official executable is a downloader.
- Single-purpose prefix: `dotnet48` removes Wine-Mono, breaking other .NET applications sharing it.
- **The license token is not protected**: DPAPI is a stub under Wine. Never publish the prefix.
- This is **not a sandbox**: Rhino has write access to your real Documents, Desktop and Downloads.
- About 8 GB occupied when done, installer included.

## What we do not know

- This write-up rests on **two machines only**, both on the proprietary NVIDIA driver. Nothing was tested on AMD or Intel-only with Rhino.
- **No native Wayland testing**: X11 on one machine, XWayland on the other.
- No other distribution tested. Fedora and Arch have no WineHQ repository; Debian uses different codenames.
- A single Rhino version, 8.34. Another version will change the cache identifiers and possibly the behaviour.
- Licensing: only the Cloud Zoo evaluation was tried. No standalone license, no local Zoo.
- **The cause of the refresh problem is not established.** The remedies here are palliatives whose effect we observed, nothing more.
- The published order was **replayed and validated** on 2026-09-01 on a fresh prefix on the Mint machine: WebView2, then Windows 10, then the official installer, which completed on its own without the manual fallback. This caveat, present in earlier versions of this document, is now lifted.

