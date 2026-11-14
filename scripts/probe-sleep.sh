#!/bin/bash
# Probă reală somn/trezire, fără interacțiune în script: pornește o copie izolată,
# măsoară consumul înainte, așteaptă somnul și trezirea (tu adormi Mac-ul),
# apoi măsoară din nou și compară. Rezultat: $FARUL_WORK/evidence/sleep-probe/result.txt
#   scripts/probe-sleep.sh <Farul.app>
APP="${1:?calea spre Farul.app (copie de test)}"
D="${FARUL_WORK:?definește FARUL_WORK}"/evidence/sleep-probe; rm -rf "$D"; mkdir -p "$D"
R="$D/result.txt"
cpu() { # medie %CPU și RSS (MB) pe N secunde, o probă/secundă
  local n=$1 s=0 r=0 i v
  for i in $(seq "$n"); do v=$(ps -o %cpu=,rss= -p "$PID"); s=$(echo "$s + ${v% *}" | bc -l); r=${v#* }; sleep 1; done
  printf "%.2f%% CPU medie, %d MB RSS" "$(echo "$s / $n" | bc -l)" "$((r/1024))"
}
FARUL_SKIP_APPMOVER=1 FARUL_LOG_DIR="$D" "$APP/Contents/MacOS/Farul" >/dev/null 2>&1 & PID=$!
echo "PID=$PID start $(date +%T)" > "$R"
sleep 5; echo "înainte de somn: $(cpu 20)" >> "$R"; echo "READY $(date +%T)" >> "$R"
for i in $(seq 900); do grep -q Trezire "$D/Farul.log" 2>/dev/null && break; sleep 1; done
grep -q Trezire "$D/Farul.log" || { echo "FĂRĂ TREZIRE în 15 min" >> "$R"; kill $PID; exit 1; }
sleep 3; echo "după trezire: $(cpu 20)" >> "$R"
echo "linii Somn/Trezire: $(grep -cE 'Somn|Trezire' "$D/Farul.log") (așteptat 2)" >> "$R"
echo "fire: $(ps -M -p $PID | tail -n +2 | wc -l)" >> "$R"
FARUL_SKIP_APPMOVER=1 "$APP/Contents/MacOS/Farul" --dump-metrics 2>/dev/null | head -c 300 >> "$R"; echo >> "$R"
kill $PID; echo "DONE" >> "$R"
