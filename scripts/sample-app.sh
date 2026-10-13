#!/bin/bash
# Läuft neben dem UI-Test im Hintergrund: Alle 25 Sekunden den Prozess der App im Simulator
# zwei Sekunden lang abtasten (macOS sample). Zeigt, woran der Hauptthread arbeitet, falls die
# App nicht mehr antwortet.
#
#   sample-app.sh <ausgabe> <präfix>
OUT="$1"
PREFIX="${2:-app}"
mkdir -p "$OUT"
for round in $(seq 1 14); do
  sleep 25
  pid=$(pgrep -f "/Signalwerk.app/Signalwerk" | head -1)
  if [ -z "$pid" ]; then
    echo "Runde $round: App läuft nicht" >> "$OUT/$PREFIX-sample-index.txt"
    continue
  fi
  echo "Runde $round: pid $pid, $(date -u +%H:%M:%S)" >> "$OUT/$PREFIX-sample-index.txt"
  sample "$pid" 2 -mayDie -file "$OUT/$PREFIX-sample-$round.txt" > /dev/null 2>&1 || true
done
