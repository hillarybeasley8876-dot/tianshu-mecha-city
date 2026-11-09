#!/bin/bash
# city-build: why is an arena socket off the navmesh? Prints the floor under every socket and the
# off-mesh distance per agent class.
#   tools/city/nav_probe.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/tools/godot.sh" test res://world/city/tools/nav_probe.gd --timeout=900 -- "$@"
