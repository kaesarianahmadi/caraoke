#!/bin/bash
# Paired rapid capture for wireless CarPlay display-delay measurement.
# Alternates CarPlay window + iPhone USB shots with wall-clock timestamps (epoch s, ms precision).
# Usage: sync_probe.sh <out_dir> <iterations> [interval_s]
OUT="${1:?usage: sync_probe.sh <out_dir> <iterations> [interval_s]}"
N="${2:?iterations required}"
IV="${3:-0.4}"
mkdir -p "$OUT"
CSV="$OUT/timestamps.csv"
echo "kind,file,t_epoch" > "$CSV"
for i in $(seq 1 "$N"); do
  T=$(python3 -c 'import time; print(f"{time.time():.3f}")')
  tools/carplay_shot.sh "$OUT/cp_$(printf %03d $i).png" >/dev/null 2>&1
  T2=$(python3 -c 'import time; print(f"{time.time():.3f}")')
  echo "cp,cp_$(printf %03d $i).png,$T" >> "$CSV"
  python3 .zcode/skills/caraoke-phone-tester/tester.py shot --out "$OUT/ph_$(printf %03d $i).png" >/dev/null 2>&1
  T3=$(python3 -c 'import time; print(f"{time.time():.3f}")')
  echo "ph,ph_$(printf %03d $i).png,$T3" >> "$CSV"
  echo "[$i/$N] cp@$T ph@$T3"
  sleep "$IV"
done
echo "DONE $OUT"
