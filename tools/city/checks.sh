#!/bin/bash
# city-build: run the Godot-side city checks C12-C17 headless.
#   tools/city/checks.sh
# The GDScript lives under res:// (game/world/city/tools/checks.gd) because tools/godot.sh only
# accepts res:// paths; this wrapper is the command the brief names.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/tools/godot.sh" test res://world/city/tools/checks.gd --timeout=1800 -- "$@"
