#!/bin/bash
# Localizare RO/EN/ES: (1) auditul existent `LocalizationAudit` pe binarul
# construit (fiecare cheie în toate limbile), (2) aceiași specificatori %@/%d
# în cele trei limbi (altfel String(format:) crapă), (3) niciun text vizibil
# scris direct în cod, în afara lui L.t(…). Pică (exit 1) la orice problemă.
#   scripts/check-l10n.sh [calea/spre/binarul/Farul]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:-/Volumes/CristiGordas/TESTE/GDC_PROJECTS/Farul/builds/scratch/release/Farul}"
SRC="$ROOT/macOS/Farul/Sources/Farul"
export FARUL_SKIP_APPMOVER=1 FARUL_LOG_DIR="${TMPDIR:-/tmp}/farul-l10n-logs"
echo "→ audit chei"; "$BIN" --l10n-audit
python3 - "$BIN" <<'PY'
import re, subprocess, sys
bin_ = sys.argv[1]
tables = {}
for lang in ("ro", "en", "es"):
    out = subprocess.run([bin_, "--strings", lang], capture_output=True, text=True, check=True).stdout
    tables[lang] = dict(line.split("\t", 1) for line in out.splitlines() if "\t" in line)
bad = 0
spec = re.compile(r"%(?:\d+\$)?[@dlfus]+")
for key in tables["ro"]:
    sets = {l: sorted(spec.findall(tables[l].get(key, ""))) for l in tables}
    if len({tuple(v) for v in sets.values()}) != 1:
        print(f"SPECIFICATORI DIFERIȚI {key}: {sets}"); bad += 1
    for l in tables:
        if not tables[l].get(key, "").strip(): print(f"GOL {l}/{key}"); bad += 1
print(f"→ specificatori: {len(tables['ro'])} chei, {bad} probleme")
sys.exit(1 if bad else 0)
PY
echo "→ texte scrise direct în UI/alerte"
HITS=$(grep -rnE 'Text\("[A-Za-zĂÂÎȘȚăâîșț]|messageText = "|informativeText = "|withTitle: "|setStatus\("|labelWithString: "[A-Za-z]' "$SRC" \
  | grep -vE 'Localization\.swift|L\.t\(|Text\("v\\\(|labelWithString: "Farul \\\(' || true)
if [ -n "$HITS" ]; then echo "$HITS"; echo "FAIL: texte literale în cod"; exit 1; fi
echo "OK: toate textele vizibile trec prin L.t"
