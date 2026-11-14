#!/bin/bash
# Probă locală a actualizării asistate, fără instalare și fără a atinge
# /Applications: serverește candidatul pe 127.0.0.1 și rulează `Farul
# --update-dry-run` din copii de test ale aplicației (versiune simulată).
# Scenarii: valid, deja la zi, pachet modificat, pachet nesemnat, fără sha256.
#   scripts/probe-update.sh <candidate-dir>
set -uo pipefail
CAND="${1:?candidate dir}"; VERSION=$(basename "$CAND" | sed 's/candidate-//')
EXT="${FARUL_WORK:?definește FARUL_WORK (folder de lucru pentru build/teste)}"
W="$EXT/builds/probe"; rm -rf "$W"; mkdir -p "$W/logs"
PKG="$CAND/Farul-$VERSION.pkg"; SHA=$(awk '{print $1}' "$CAND/SHA256SUMS")
PORT=8777; FAIL=0

mkapp() { # <nume> <versiune simulată>
  ditto "$CAND/Farul.app" "$W/$1.app"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $2" "$W/$1.app/Contents/Info.plist"
  codesign --force -s - "$W/$1.app" 2>/dev/null
}
manifest() { # <dir> <sha|-> <versiune>
  python3 - "$1" "$2" "$3" "$PORT" <<'PY'
import json,sys
d,sha,ver,port=sys.argv[1:5]
m={"version":ver,"app_version":ver,"download_url":{"mac":f"http://127.0.0.1:{port}/Farul-{ver}.pkg"},"mandatory":False}
if sha!="-": m["sha256"]={"mac":sha}
json.dump(m,open(d+"/update.json","w"))
PY
}
serve() { ( cd "$1" && exec python3 -m http.server $PORT --bind 127.0.0.1 >"$W/logs/http.log" 2>&1 ) & SRV=$!; sleep 1; }
stop() { kill $SRV 2>/dev/null; wait $SRV 2>/dev/null; }
run() { # <titlu> <app> <așteptat: ok|refuz|zi> <dir>
  serve "$4"
  OUT=$(FARUL_UPDATE_URL="http://127.0.0.1:$PORT/update.json" FARUL_SKIP_APPMOVER=1 FARUL_LOG_DIR="$W/logs" "$W/$2.app/Contents/MacOS/Farul" --update-dry-run 2>&1); RC=$?
  stop
  case "$3" in
    ok) [ $RC -eq 0 ] && echo "$OUT" | grep -q ACCEPTAT;;
    zi) [ $RC -eq 0 ] && echo "$OUT" | grep -q "la zi";;
    refuz) [ $RC -eq 2 ] && echo "$OUT" | grep -q REFUZAT;;
  esac && echo "PASS  $1 → $OUT" || { echo "FAIL  $1 (rc=$RC) → $OUT"; FAIL=1; }
}

mkapp old 0.1.1; mkapp same "$VERSION"
# 1) valid
mkdir "$W/s1"; cp "$PKG" "$W/s1/"; manifest "$W/s1" "$SHA" "$VERSION"
run "actualizare validă (0.1.1 → $VERSION)" old ok "$W/s1"
# 2) deja la zi
run "deja la zi ($VERSION instalat)" same zi "$W/s1"
# 3) pachet modificat
mkdir "$W/s3"; cp "$PKG" "$W/s3/"; printf '\0' >> "$W/s3/Farul-$VERSION.pkg"; manifest "$W/s3" "$SHA" "$VERSION"
run "pachet modificat după publicare" old refuz "$W/s3"
# 4) pachet nesemnat (cu sha corect pentru el)
UN="$EXT/builds/tests/unsigned/Farul-unsigned.pkg"
if [ -f "$UN" ]; then mkdir "$W/s4"; cp "$UN" "$W/s4/Farul-$VERSION.pkg"; manifest "$W/s4" "$(shasum -a 256 "$UN" | awk '{print $1}')" "$VERSION"
  run "pachet nesemnat" old refuz "$W/s4"; fi
# 5) manifest fără sha256
mkdir "$W/s5"; cp "$PKG" "$W/s5/"; manifest "$W/s5" "-" "$VERSION"
run "manifest fără sumă de control" old refuz "$W/s5"
# 6) manifest anunță altă versiune decât conține pachetul
mkdir "$W/s6"; cp "$PKG" "$W/s6/Farul-0.9.0.pkg"; manifest "$W/s6" "$SHA" "0.9.0"
run "manifest minte despre versiune (0.9.0 vs pachet $VERSION)" old refuz "$W/s6"
echo; [ $FAIL -eq 0 ] && echo "TOATE SCENARIILE AU TRECUT" || echo "UNELE SCENARII AU PICAT"; exit $FAIL
