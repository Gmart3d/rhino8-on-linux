# Install Rhino 8 on Linux

Eleven steps to follow in order. You need to understand none of the code: copy each block, paste it, and the guide tells you what you should see next.

**About 1 h 30 · 12 GB of disk space · Ubuntu 24.04+ or Mint 22+ · a McNeel account**

> **Before you start.** Rhino is paid software: you need an account on rhino3d.com and a license, or the free 90-day evaluation. This method is unofficial and unsupported by McNeel — it works, but some features stay unavailable, notably final rendering on the graphics card.

---

## 1. Open the Terminal

*1 minute*

Almost everything is done by pasting commands into the Terminal. Open it with **Ctrl + Alt + T**, or search for “Terminal” in your applications menu. For each step, copy the whole block, paste it and press Enter.

> **What you should see** — A dark window with a line of text waiting for you. That is normal.

## 2. Prepare the system and install Wine

*10 to 15 minutes*

Wine is the program that runs Windows software on Linux. The version shipped by your distribution is too old for Rhino, so we install the official one. You will be asked for your password — that is normal, and it stays invisible while you type it.

```bash
sudo dpkg --add-architecture i386
. /etc/os-release && CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
sudo wget -NP /etc/apt/sources.list.d/ "https://dl.winehq.org/wine-builds/ubuntu/dists/$CODENAME/winehq-$CODENAME.sources"
sudo apt update
sudo apt install -y --install-recommends winehq-staging
wine --version
```

> **What you should see** — The last line must show a number starting with **11**, followed by “Staging”. If it shows 9.0, something went wrong: do not continue.

## 3. Install the winetricks helper

*1 minute*

winetricks automatically installs the Windows components Rhino needs. We take the newest version — the one in the repositories is two years out of date.

```bash
mkdir -p "$HOME/.local/bin"
wget -O "$HOME/.local/bin/winetricks" https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x "$HOME/.local/bin/winetricks"
hash -r && winetricks --version
```

> **What you should see** — A recent date appears, something like `20260125`. A 2024 date means the old version is answering.

## 4. Create Rhino's Windows space

*2 minutes*

Wine creates a fake Windows disk inside a folder — a “prefix”. Rhino will live there, isolated from the rest. Keep that folder for Rhino alone, do not install anything else in it.

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
export WINEARCH=win64
WINEDLLOVERRIDES="mscoree=d;mshtml=d" wineboot --init
```

> **What you should see** — Lines scroll past, then you get the prompt back. A folder has been created. **Keep this Terminal open** until the end of the guide.

## 5. Install the Windows components

*30 to 45 minutes*

This is the longest step, and it runs on its own. Microsoft installer windows will appear and vanish by themselves: **do not touch them**. Go do something else.

```bash
winetricks -q corefonts d3dcompiler_47 vcrun2022 dotnet48
```

> **What you should see** — You get the prompt back after a good half hour. If the Terminal looks frozen for more than ten minutes with nothing happening, see “If you get stuck” at the bottom of this page.

## 6. Switch back to Windows 10 — do not skip this

*10 seconds*

The previous step quietly switched Rhino's space to **Windows 7**. If you do not fix that, the Rhino install will fail later **without showing any error at all** — this is the trap that costs people the most time.

```bash
wine winecfg /v win10
wine reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild
```

> **What you should see** — The last line must show **19045**. That is the Windows 10 build number; 7601 would mean Windows 7. If you see 7601, run the first command again.

## 7. Install the browser component

*5 to 10 minutes*

Rhino shows its licensing window through a Microsoft browser component. Without it, that window stays **blank** and you cannot activate your license. Install it **before** Rhino, not after.

```bash
winetricks -q webview2
wine reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild
```

> **What you should see** — You get the prompt back, and the last line still shows **19045**.

## 8. Download Rhino

*10 minutes*

Go to **rhino3d.com**, sign in with your McNeel account and download the Windows version of Rhino 8. The file is about 600 MB. A free 90-day evaluation is offered if you do not have a license yet.



Stay connected to the internet for what follows: this file is really a downloader, and it will fetch several hundred more megabytes during the install.

> **What you should see** — A file named `rhino_en-us_8….exe` in your Downloads folder.

## 9. Install Rhino

*15 minutes*

We run the official installer. It works on its own; let it finish without clicking elsewhere.

```bash
wine ~/Téléchargements/rhino_en-us_8*.exe -passive -norestart
# si vos dossiers sont en anglais, remplacez Téléchargements par Downloads
ls "$WINEPREFIX/drive_c/Program Files/Rhino 8/System/Rhino.exe"
```

> **What you should see** — The last command must print a path ending in `Rhino.exe`. If it says “No such file”, the install failed: see “If you get stuck”.

## 10. Create the launcher

*2 minutes*

These commands create a small startup program and add it to your menu, so you never need the Terminal again.

```bash
cat > "$HOME/.local/bin/rhino8.sh" <<'FIN'
#!/usr/bin/env bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/rhino8"
export WINEDEBUG=-all
args=()
for f in "$@"; do
  if [ -e "$f" ]; then args+=("$(winepath -w "$f")"); else args+=("$f"); fi
done
exec wine "C:\\Program Files\\Rhino 8\\System\\Rhino.exe" ${args[@]+"${args[@]}"}
FIN
chmod +x "$HOME/.local/bin/rhino8.sh"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/rhino8.desktop" <<FIN
[Desktop Entry]
Type=Application
Name=Rhinoceros 8
Exec=$HOME/.local/bin/rhino8.sh %f
Terminal=false
Categories=Graphics;3DGraphics;
FIN
update-desktop-database "$HOME/.local/share/applications"
```

> **What you should see** — Nothing is printed, which is a good sign. **Rhinoceros 8** now appears in your applications menu.

## 11. First launch and licensing

*5 minutes*

Launch Rhino from your menu. The first start is slow — allow a minute. A window will ask for your e-mail address to activate the license, and your browser will open for validation.



Warning messages sometimes scroll by in the Terminal, especially about `libEGL`. **They are normal** and indicate no problem.

> **What you should see** — Rhino's main window opens with its four views. If the licensing window looks half-drawn, resize it and it fills in.

---

## If you get stuck

**The Terminal seems frozen during step 5 or 7.**

A Microsoft component is stuck in the background. Open a *second* Terminal and paste: `pkill -f MicrosoftEdgeUpdate`. The first one resumes immediately.

**`wine --version` shows 9.0 instead of 11.**

Your distribution's older Wine is still answering. Check that step 2 finished without errors, especially the `apt install` line.

**The Rhino install finishes but Rhino is nowhere.**

In almost every case, step 6 was skipped or did not take. Do it again, check the answer really is `win10`, then run step 9 again.

**The licensing window stays blank.**

The browser component from step 7 is missing or failed. Close Rhino and run that step again.

**A view stays frozen and selection does not show.**

This is a known Wine defect with no simple fix today. Immediate workaround: rotate the view slightly with the mouse and the display updates. A proper fix exists but requires advanced skills — it is covered in the technical write-up.

---

Tested on Linux Mint 22.3 and Ubuntu 26.04, with Rhino 8.34 and Wine 11 staging, on two machines with NVIDIA cards. AMD and Intel setups were not tried.
