#!/bin/bash
# Probă reală somn/trezire (cere acțiunea ta: adormi Mac-ul). Pornește o copie
# izolată, îți cere să-l adormi ≥ 30 s, apoi arată ce a scris aplicația.
#   scripts/probe-sleep.sh <Farul.app>
APP="${1:?calea spre Farul.app (copie de test)}"
LOGS="${FARUL_WORK:?definește FARUL_WORK}"/evidence/sleep-probe; rm -rf "$LOGS"; mkdir -p "$LOGS"
FARUL_SKIP_APPMOVER=1 FARUL_LOG_DIR="$LOGS" "$APP/Contents/MacOS/Farul" & PID=$!
sleep 4; echo "Farul rulează (PID $PID). Adoarme acum Mac-ul (Meniu Apple → Repaus), așteaptă ≥ 30 s, trezește-l."
read -r -p "Apasă Enter după trezire și după ce vezi din nou desktopul… "
sleep 4; grep -E 'Somn|Trezire' "$LOGS/Farul.log" || echo "NU există linii Somn/Trezire în log"
ps -o %cpu,rss -p $PID; kill $PID
