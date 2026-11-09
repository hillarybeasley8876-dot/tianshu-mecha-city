#!/bin/bash
# The r6 A/B sheet for the takes whose time of day was still open: c_od, s08_boss, c_flight, c_fp.
#   tools/trailer/r6_ab_sheet.sh [out.jpg]
# One row per time of day, one column per take (the first cut-window midpoint of each).
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/tmp/trailer/r6/ab_e.jpg}"
D="$ROOT/tmp/trailer/r6/tod"
rows=()
for tod in 0.0 0.35 0.6; do
  cells=""
  for f in c_od:2_7 s08_boss:3_4 c_flight:2_8 c_fp:3_7; do
    cells="$cells,$D/${f%%:*}_tod${tod}_t${f#*:}_16x9.jpg"
  done
  rows+=("tod $tod=${cells#,}")
done
python3 "$ROOT/tools/trailer/grid.py" -o "$OUT" --cols 4 "${rows[@]}"
