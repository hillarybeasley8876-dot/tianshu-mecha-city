#!/bin/bash
# city-build: report on the city's navigation (sync time, link attachment, gameplay reachability).
#   tools/city/nav_report.sh
# The GDScript lives under res:// (game/world/city/tools/nav_report.gd) because tools/godot.sh only
# accepts res:// paths; this wrapper is the command the brief names.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$ROOT/tools/godot.sh" test res://world/city/tools/nav_report.gd --timeout=900 -- "$@"
