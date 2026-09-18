#!/bin/bash
# Regenerează AppIcon.appiconset din Resources/AppIcon.svg.
# Rulat manual, la fiecare schimbare a sursei vectoriale — build_app.sh doar
# consumă PNG-urile, nu le reconstruiește (un build n-are de ce să rescrie
# fișiere urmărite în git).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/macOS/Farul/Resources/AppIcon.svg"
OUT="$ROOT/macOS/Farul/Resources/Assets.xcassets/AppIcon.appiconset"

echo "→ Generez pictograma din $(basename "$SRC")…"
swift "$ROOT/scripts/make-appicon.swift" "$SRC" "$OUT"

# .icns-ul se pastreaza, nu se arunca: build_app.sh il copiaza in bundle,
# iar iconutil refuza un set incomplet — deci generarea lui aici e si
# verificarea ca setul chiar e valid, nu doar zece PNG-uri pe disc.
ICNS="$ROOT/macOS/Farul/Resources/AppIcon.icns"
TMP="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$TMP"
cp "$OUT"/icon_*.png "$TMP/"
iconutil -c icns "$TMP" -o "$ICNS"
rm -rf "$(dirname "$TMP")"
echo "  AppIcon.icns ($(du -h "$ICNS" | cut -f1))"
