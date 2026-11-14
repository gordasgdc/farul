#!/bin/bash
# Verificări automate Farul: redactare, rotație log, export, verificator de
# update, dezinstalare pe home izolat, logger defect. Ieșirea merge sub
# Totul generat merge în FARUL_WORK (folder extern de lucru): nimic pe discul intern.
#   scripts/test.sh [pkg_valid] [versiune] [pkg_nesemnat]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="${FARUL_WORK:?definește FARUL_WORK (folder de lucru pentru build/teste)}"
[ -d "$EXT" ] && [ -w "$EXT" ] || { echo "FARUL_WORK indisponibil sau nescriibil"; exit 3; }
OUT="$EXT/builds/tests"; mkdir -p "$OUT/logs" "$OUT/clang" "$OUT/tmp"
SRC="$ROOT/macOS/Farul/Sources/Farul"
export CLANG_MODULE_CACHE_PATH="$OUT/clang" TMPDIR="$OUT/tmp/"
swiftc -O -o "$OUT/farul-checks" -framework AppKit \
  "$ROOT/macOS/Farul/Tests/FarulChecks/main.swift" \
  "$SRC/DiagnosticLog.swift" "$SRC/Diagnostics.swift" "$SRC/UpdateVerifier.swift" \
  "$SRC/SelfUninstaller.swift" "$SRC/SelfUpdater.swift" "$SRC/AppMover.swift" "$SRC/Localization.swift"
rm -rf "$OUT/logs"; mkdir -p "$OUT/logs"
export FARUL_LOG_DIR="$OUT/logs" FARUL_LOG_MAX_BYTES=20000
[ $# -ge 2 ] && export FARUL_TEST_PKG="$1" FARUL_TEST_PKG_VERSION="$2"
[ $# -ge 3 ] && export FARUL_TEST_PKG_UNSIGNED="$3"
STATUS=0
"$OUT/farul-checks" | tee "$OUT/last-run.txt" || STATUS=$?
# Logger defect: calea de log nu poate fi creată; procesul trebuie să termine normal.
BROKEN=$(FARUL_LOG_DIR=/dev/null/inexistent "$OUT/farul-checks" --log-broken-child 2>&1 || true)
if echo "$BROKEN" | grep -q child-done; then echo "PASS  logger defect nu blochează operația"; else echo "FAIL  logger defect: $BROKEN"; STATUS=1; fi
exit $STATUS
