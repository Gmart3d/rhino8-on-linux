# Rhino 8 on Linux, through Wine

Rhino 8.34 installs and runs under Wine 11 staging, well enough for real modelling
work — a 1.3 GB production file was used for testing. This repository holds the
install procedure, the traps that cost us hours, measurements, and an honest list
of what still does not work.

Everything here was verified command by command on two machines. Where the two
machines disagree, both answers are documented rather than averaged.

## Start here

| | |
|---|---|
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
wine winecfg /v          # must answer: win10
```

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
