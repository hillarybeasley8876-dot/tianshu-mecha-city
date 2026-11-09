#!/bin/bash
# city-build: bake the city navmeshes offline (one NavigationMesh per agent class).
#   tools/city/bake_nav.sh [--class=small|medium|large]
# The GDScript lives under res:// (game/world/city/tools/bake_nav.gd) because tools/godot.sh
# only accepts res:// paths; this wrapper is the command the brief names.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/tools/godot.sh" test res://world/city/tools/bake_nav.gd --timeout=2400 -- "$@"
