#!/bin/bash
# The --tod A/B for a shot (trailer unit). Same take, same camera, N times of day, so the pick is made
# on frames and not on a hunch. r2b: redone on the city-art r15 sky.
#
#   tools/trailer/tod_ab.sh <label> <timeline.json> <tod, tod, …> [extra godot.sh drive args…]
#
#   tools/trailer/tod_ab.sh cold res://trailer/tl_s01_cold.json 0.0,0.35,0.6 \
#       --trailer-cam=res://trailer/cam_s01_cold.json --skip-menu --no-enemies --god
#
# Writes <ROOT>/captures/trailer/tod/<label>_tod<A>_t<T>.jpg for every (tod, shot time).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/captures/trailer/tod"
SHOTS="${TOD_AB_SHOTS:-1.5,3.8}"

label="${1:?usage: tod_ab.sh <label> <timeline> <tod,tod,…> [args…]}"; shift
timeline="${1:?usage: tod_ab.sh <label> <timeline> <tod,tod,…> [args…]}"; shift
tods="${1:?usage: tod_ab.sh <label> <timeline> <tod,tod,…> [args…]}"; shift
mkdir -p "$OUT"

for tod in ${tods//,/ }; do
  echo "== $label tod=$tod"
  "$ROOT/tools/godot.sh" drive --timeline="$timeline" --scene=res://trailer/shot.tscn \
    --tod="$tod" --shots="$SHOTS" --out="${label}_tod${tod}" --outdir="$OUT" "$@" 2>&1 \
    | grep -E "DRIVE done|CAPTURE|ERROR" | tail -6
done
