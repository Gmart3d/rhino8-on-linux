# Rhino 8 on Linux, through Wine

Rhino 8.34 installs and runs under Wine 11 staging, well enough for real modelling
work — a 1.3 GB production file was used for testing. This repository holds the
install procedure, the traps that cost us hours, measurements, and an honest list
of what still does not work.

Everything here was verified command by command on two machines. Where the two
machines disagree, both answers are documented rather than averaged.

## Quick start — the automated installer

**1.** Download Rhino 8 for Windows from [rhino3d.com](https://www.rhino3d.com/download/)
(a McNeel account is required; a free 90-day evaluation is offered). Leave the
`.exe` in your Downloads folder — the script finds it on its own.

**2.** Get this repository and run the installer:

```bash
git clone https://github.com/Gmart3d/rhino8-on-linux.git
cd rhino8-on-linux/scripts
./install-rhino8.sh
```

It shows what it is about to do, asks for confirmation, then works through eleven
steps — verifying each one and stopping with a plain explanation if anything is
wrong. Re-running it is safe: completed steps are detected and skipped.

Clone the repository rather than downloading the single file: the script looks for
`redraw_fix.py` next to itself for the optional display fix. On its own it still
works, it just skips that last step.

**Allow about 1 h 30**, most of it waiting with nothing to do, and keep a stable
internet connection throughout — the official Rhino executable is a downloader.
Microsoft installer windows will appear and close by themselves during steps 6
and 8; leave them alone.

### Options

| | |
|---|---|
| `--prefix PATH` | install into another Wine prefix (default `~/.local/share/wineprefixes/rhino8`) |
| `--no-nvidia` | skip the NVIDIA Optimus render offload, if detection gets it wrong |
| `-y`, `--yes` | no confirmation prompt — useful for automation, but the prompt is what tells you which files will be written |
| `--help` | full option list |

Trying it on a machine that already runs Rhino? Use `--prefix ~/rhino8-test` to
leave your working prefix alone. Note that it still replaces your menu entry and
the `.3dm` file association — back those up first.


## Documentation

| | |
|---|---|
| **[`scripts/install-rhino8.sh`](scripts/install-rhino8.sh)** | Automated installer. You download Rhino from rhino3d.com, it does the rest — verifying every step and stopping with a plain explanation if anything is wrong. Safe to re-run. |
| **[Install guide](docs/install-guide.md)** | Eleven steps, written for someone who does not use the command line. About 1 h 30. |
| **[Technical notes](docs/technical-notes.md)** | The full procedure with verification commands, 22 traps, measurements, limits and open questions. |
| Français | [Guide d'installation](docs/install-guide.fr.md) · [Notes techniques](docs/technical-notes.fr.md) |

## Tested configurations

| | Machine A | Machine B |
|---|---|---|
| System | Ubuntu 26.04 “Resolute” | Linux Mint 22.3 (noble base) |
| Session | GNOME / XWayland | X11 / Cinnamon |
| GPU | NVIDIA GTX 1080 · driver 580.173.02 | Intel HD 630 + GTX 1060 (Optimus) |
| CPU / RAM | Threadripper 1900X · 98 GB | i7-7700HQ · 31 GB |
| Wine | 11.15 staging | 11.16 staging |
| Rhino | 8.34.26223.11001 | 8.34.26223.11001 |

Both machines use the proprietary NVIDIA driver. **AMD and Intel-only setups have
not been tested**, and neither has native Wayland.

## The one trap that matters most

`winetricks dotnet48` leaves the Wine prefix on **Windows 7** and never restores it.
Rhino's installer then fails **with no error message at all**. Before installing
Rhino, always run:

```bash
wine winecfg /v win10
wine reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild
```

The second command must print **19045**, the Windows 10 build number. 7601 would
mean Windows 7. Do not use `wine winecfg /v` to check — verified at runtime on
Wine 11.16, it prints nothing at all, and reads as a failure on a step that
actually succeeded. `CurrentVersion` is no help either: it reads 6.3 in both
cases, exactly as real Windows 10 does.

The automated installer handles all of this for you.

## What does not work

- Cycles rendering is **CPU-only** — no CUDA, no OptiX under Wine.
- Viewport antialiasing is unavailable: Wine's EGL path exposes no multisample formats.
- The Package Manager UI crashes Rhino. The `Yak.exe` command line works fully.
- Rhino leaves orphaned processes on exit — see [`scripts/cleanup.sh`](scripts/cleanup.sh).
- Offline installation is impossible: the official executable is a downloader.

## Viewport refresh

On both machines a viewport can keep showing a stale image after a mouse selection,
until the camera moves. The two machines needed **different remedies**, documented in
the technical notes. Measurements on machine B established that this is a **race
condition**, not a permanent defect: across 80 refreshes the failure rate moves from
44 % to 0 % depending on whether a wait is inserted before the copy to screen.

An experimental Wine patch addressing this is in [`patches/`](patches/) — see its
[notes](patches/README.md). It is not required for a working install.

## Contents

```
docs/       install guide and technical notes, English and French
scripts/    launcher, menu entry, cleanup, Rhino redraw workaround
patches/    experimental Wine patch for the viewport refresh race
```

## Contributing

Corrections and reports from other configurations are very welcome — especially
AMD, Intel-only, native Wayland, other distributions, and other Rhino versions.
Please open an issue with your system, your GPU driver, your Wine version, and
what you observed.

## Licence

Documentation CC BY-SA 4.0, scripts and patches MIT. See [LICENSE](LICENSE).
Rhinoceros is a trademark of Robert McNeel & Associates; this project is
independent and unaffiliated. A valid Rhino license is required.
