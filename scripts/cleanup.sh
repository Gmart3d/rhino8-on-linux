#!/usr/bin/env bash
# Kills leftover Rhino/Wine processes. Rhino's WPF shutdown path leaves
# orphans behind on every exit; they accumulate and make later launches
# erratic. The [brackets] stop pkill from matching its own command line.
set -u
pkill -9 -f 'Rhin[o]\.exe'      2>/dev/null
pkill -9 -f 'RmaErrorReportin[g]' 2>/dev/null
pkill -9 -f 'wineserve[r]'      2>/dev/null
sleep 1
pgrep -af 'wine|Rhino' || echo "Clean."
