#!/bin/bash
# Capturi reale ale panoului Farul (RO/EN/ES × întunecat/luminos), prin
# `Farul --snapshot` din binarul SwiftPM (fără bundle: nu atinge setările
# aplicației instalate, fără automatizare de interfață). Ieșire: evidence/screens/.
#   scripts/capture-screens.sh [lățime înălțime]
set -uo pipefail
EXT=/Volumes/CristiGordas/TESTE/GDC_PROJECTS/Farul
BIN="$EXT/builds/scratch/release/Farul"; S="$EXT/evidence/screens"
W="${1:-1040}"; H="${2:-640}"
mkdir -p "$S" "$EXT/builds/probe/logs"
for lang in ro en es; do for theme in dark light; do
  FARUL_SKIP_APPMOVER=1 FARUL_LOG_DIR="$EXT/builds/probe/logs" perl -e 'alarm 90; exec @ARGV' \
    "$BIN" --snapshot "$S/dashboard-$lang-$theme.png" "$lang" "$theme" "$W" "$H"
done; done
