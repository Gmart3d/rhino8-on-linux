#!/usr/bin/env bash
# TEMPLATE FOR MANUAL INSTALLATION ONLY.
# install-rhino8.sh does NOT use this file: it generates its own version,
# with Unix-path conversion, NVIDIA Optimus detection and launch logging.
# Use this only if you followed the manual guide in docs/.
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
