#!/bin/bash
# r10 before/after measurement: put the PRE-r10 prop meshes back on disk, run whatever is passed as
# "$@", then restore the r10 meshes. The tree is shared, so the swap is guarded by a trap and the
# new meshes are copied aside first; an interrupted run still restores them on EXIT.
#   tools/citykit/props_swap.sh before  <command...>
#   tools/citykit/props_swap.sh after   <command...>
set -u
ROOT="$HOME/m/mecha-city"
MESHES="$ROOT/game/world/props/meshes"
KEEP="$ROOT/tmp/city-kit/r10/new_meshes"

restore() {
  if [ -d "$KEEP" ]; then
    rm -rf "$MESHES"
    cp -R "$KEEP" "$MESHES"
  fi
}

case "${1:-}" in
  save)
    rm -rf "$KEEP"
    cp -R "$MESHES" "$KEEP"
    echo "saved $(ls "$KEEP" | wc -l | tr -d ' ') files to $KEEP" ;;
  before)
    shift
    trap restore EXIT INT TERM
    git -C "$ROOT" checkout HEAD -- game/world/props/meshes || exit 1
    echo "--- PRE-r10 meshes in place"
    "$@"
    code=$?
    exit $code ;;
  after)
    shift
    restore
    echo "--- r10 meshes in place"
    "$@" ;;
  *)
    echo "usage: props_swap.sh save|before|after <command...>"; exit 2 ;;
esac
