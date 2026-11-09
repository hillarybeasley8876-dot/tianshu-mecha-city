#!/bin/bash
# One trailer take: tools/godot.sh movie at the deliverable's 1920x1080.
#
#   tools/trailer/record.sh <out.avi> <timeline.json> [extra godot.sh movie args...]
#
# The capture size comes from `tools/godot.sh movie --movie-size=WxH`, which writes the Movie Maker
# size override (res://override.cfg) for that run only — Godot fixes the .avi size from
# display/window/size/window_*_override when the writer starts and ignores --resolution afterwards.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SIZE="${TRAILER_SIZE:-1920x1080}"

out="${1:?usage: record.sh <out.avi> <timeline.json> [args...]}"; shift
timeline="${1:?usage: record.sh <out.avi> <timeline.json> [args...]}"; shift

mkdir -p "$(dirname "$out")"
"$ROOT/tools/godot.sh" movie --movie="$out" --movie-size="$SIZE" --timeline="$timeline" "$@"
code=$?
[ $code -ne 0 ] && echo "record: FAILED ($code) $out" >&2
exit $code
