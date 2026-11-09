#!/bin/bash
# MECHA CITY Godot wrapper. All runs queue on machine-wide slots (tools/slots.py).
#   tools/godot.sh import                      import changed assets (serialized project-wide)
#   tools/godot.sh check [--only=res://a/,res://b/]
#                                              import, then load every script/scene/shader; exit 1 on errors
#   tools/godot.sh test <res://path/test.gd> [-- args]
#                                              headless SceneTree test script (physics/logic), 120 Hz fixed
#   tools/godot.sh shot --scene res://x.tscn --out <name> [--shots <spec>] [--warm N] [--size WxH]
#                                              windowed capture -> <ROOT>/captures/<name>_<shot>.jpg
#   tools/godot.sh run <res://scene.tscn> [seconds]  windowed smoke run, prints errors + fps, quits
#   tools/godot.sh drive --timeline=res://x.json [--shots=1,4] [--log=/abs.csv] [--frametimes] [game options]
#                                              scripted input play-through (windowed), telemetry print
#   tools/godot.sh movie --movie=/abs/out.avi --timeline=res://x.json [--movie-size=WxH] [...]
#                                              same, recorded at 60 fps (--movie-size = the .avi size)
#   tools/godot.sh perf --skip-menu [--spawn=x,y,z,yaw] [--warm=240]   draw calls/objects per subsystem
#   tools/godot.sh play                       launch the game normally (no slot, for humans)
#   tools/godot.sh export                     release export -> build/TIANSHU.app (under the import slot)
#   tools/godot.sh package --out=<dir>        the post-export step on its own: the files that ship
#                                              NEXT TO the .app (README, THIRD_PARTY_LICENSES)
# Every subcommand takes --timeout=<s>: the slot timeout for that run (pool default when omitted, so a
# long drive is `--timeout=1500`). `test` hands it to the test host as well and gives the slot <s>+60 s,
# so the host's own "TEST TIMEOUT" report prints before the slot kills the process. GODOT=<path>
# overrides the engine binary.
set -u
# The checkout this script lives in, so a git worktree (the trailer renders from one) drives its own
# project rather than the main tree.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$ROOT/game"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
# Every windowed run lands as a small unfocused corner window, never fullscreen (core/game.gd _tool_window).
export MC_TOOL_WINDOW=1
SLOTS="$ROOT/tools/slots.py"
TEST_MARGIN=60      # the test host must reach its own deadline first, so the slot outlives it
mkdir -p "$ROOT/captures" "$ROOT/tmp" "$ROOT/jobs/.slots"

do_import() {
  local req; req=$(date +%s)
  python3 "$SLOTS" import 1 ${SLOT_TIMEOUT[@]+"${SLOT_TIMEOUT[@]}"} -- \
    "$ROOT/tools/godot_import.sh" "$req" >"$ROOT/tmp/last_import.log" 2>&1
  local code=$?
  grep -E "ERROR|SCRIPT ERROR|Failed" "$ROOT/tmp/last_import.log" | grep -v "^\s*at:" | head -40
  return $code
}

# Dev runs render at high and never read/write the player's settings file (core/settings.gd skips
# user://settings.cfg when --quality is given), unless the caller passes its own --quality=.
QUALITY="--quality=high"
for a in "$@"; do case "$a" in --quality=*) QUALITY="$a";; esac; done

cmd="${1:-}"; shift || true
# --timeout=<s> is the caller's, for every subcommand: pull it out of the args (Godot never sees it).
TIMEOUT=""
ARGS=()
for a in "$@"; do
  case "$a" in --timeout=*) TIMEOUT="${a#--timeout=}" ;; *) ARGS+=("$a") ;; esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}
SLOT_TIMEOUT=()
[ -n "$TIMEOUT" ] && SLOT_TIMEOUT=(--timeout "$TIMEOUT")

# The user works on this Mac: a windowed Godot run brings its window to the front and Stage Manager swaps
# the user's own windows away. Windowed runs therefore need the lead's explicit go-ahead (MC_WINDOW_OK=1,
# set only when the user has OK'd a time window); everything else must use the headless test host.
case "$cmd" in
  shot|run|drive|movie|perf)
    if [ "${MC_WINDOW_OK:-}" != "1" ]; then
      echo "refused: '$cmd' opens a window on the user's screen. Use a headless test (tools/godot.sh test),"
      echo "or list the capture under 'Captures needed' in your status file; the lead batches them."
      exit 3
    fi ;;
esac
case "$cmd" in
  import)
    do_import ;;
  check)
    do_import
    python3 "$SLOTS" light 5 ${SLOT_TIMEOUT[@]+"${SLOT_TIMEOUT[@]}"} -- "$GODOT" --headless --path "$PROJ" -s res://tools/check_all.gd -- "$@" ;;
  test)
    script="$1"; shift || true
    [ "${1:-}" = "--" ] && shift
    do_import >/dev/null
    file="$PROJ/${script#res://}"
    # The host's own deadline is --timeout=<s> (default 300): the slot gets that plus a margin.
    host_timeout=300
    [ -n "$TIMEOUT" ] && host_timeout="$TIMEOUT"
    SLOT_TIMEOUT=(--timeout $(( host_timeout + TEST_MARGIN )))
    host_args=(--test="$script")
    [ -n "$TIMEOUT" ] && host_args+=("--timeout=$TIMEOUT")
    if grep -q "^extends SceneTree" "$file" 2>/dev/null; then
      # legacy SceneTree tests: run directly (they must not reference autoloads/class_names at compile time)
      python3 "$SLOTS" light 5 ${SLOT_TIMEOUT[@]+"${SLOT_TIMEOUT[@]}"} -- "$GODOT" --headless --fixed-fps 120 --path "$PROJ" -s "$script" -- "$@" "$QUALITY"
    else
      python3 "$SLOTS" light 5 ${SLOT_TIMEOUT[@]+"${SLOT_TIMEOUT[@]}"} -- "$GODOT" --headless --fixed-fps 120 --path "$PROJ" \
        -s res://tools/test_host.gd -- "${host_args[@]}" "$@" "$QUALITY"
    fi ;;
  shot)
    do_import >/dev/null
    python3 "$SLOTS" heavy 3 --name shot ${SLOT_TIMEOUT[@]+"${SLOT_TIMEOUT[@]}"} -- "$GODOT" --path "$PROJ" --windowed --resolution 1600x900 \
      -s res://tools/capture.gd -- --outdir="$ROOT/captures" "$@" "$QUALITY" ;;
  run)
    scene="$1"; secs="${2:-20}"; shift 2 || true
    # Everything after <scene> <seconds> is a game option and is passed through (city-kit r10).
    do_import >/dev/null
    python3 "$SLOTS" heavy 3 --name run ${SLOT_TIMEOUT[@]+"${SLOT_TIMEOUT[@]}"} -- "$GODOT" --path "$PROJ" --windowed --resolution 1600x900 \
      -s res://tools/smoke_run.gd -- --scene "$scene" --seconds "$secs" "$@" "$QUALITY" ;;
  drive)
    for a in "$@"; do case "$a" in --frametimes) set -- "$@" "--load=load:$(sysctl -n vm.loadavg | awk '{print $2"/"$3"/"$4}')";; esac; done
    do_import >/dev/null
    python3 "$SLOTS" heavy 3 --name drive ${SLOT_TIMEOUT[@]+"${SLOT_TIMEOUT[@]}"} -- "$GODOT" --path "$PROJ" --windowed --resolution 1600x900 \
      -s res://tools/autoplay.gd -- --outdir="$ROOT/captures" "$@" "$QUALITY" ;;
  movie)
    out=""; size=""; rest=()
    for a in "$@"; do case "$a" in
      --movie=*) out="${a#--movie=}" ;;
      --movie-size=*) size="${a#--movie-size=}" ;;
      *) rest+=("$a") ;;
    esac; done
    [ -z "$out" ] && { echo "movie: --movie=/abs/path.avi required"; exit 2; }
    do_import >/dev/null
    # --movie-size=WxH: the Movie Maker fixes the .avi size from display/window/size/window_*_override
    # when the writer starts; --resolution and a later DisplayServer.window_set_size() are both ignored,
    # and project.godot is lead-owned. res://override.cfg is applied at startup, so it is written for this
    # run only and removed on exit. Without --movie-size the run uses the project's own override.
    over="$PROJ/override.cfg"
    if [ -n "$size" ]; then
      case "$size" in
        [0-9]*x[0-9]*) : ;;
        *) echo "movie: --movie-size wants WxH, got '$size'"; exit 2 ;;
      esac
      [ -e "$over" ] && { echo "movie: $over already exists — another capture is running"; exit 2; }
      trap 'rm -f "$over"' EXIT INT TERM
      printf '[display]\n\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' \
        "${size%x*}" "${size#*x}" > "$over"
    fi
    [ ${#SLOT_TIMEOUT[@]} -eq 0 ] && SLOT_TIMEOUT=(--timeout 1800)
    python3 "$SLOTS" heavy 3 --name movie ${SLOT_TIMEOUT[@]+"${SLOT_TIMEOUT[@]}"} -- "$GODOT" --path "$PROJ" --windowed --resolution 1600x900 --write-movie "$out" --fixed-fps 60 \
      -s res://tools/autoplay.gd -- --outdir="$ROOT/captures" "${rest[@]}" "$QUALITY"
    code=$?
    [ -n "$size" ] && rm -f "$over"
    exit $code ;;
  perf)
    do_import >/dev/null
    python3 "$SLOTS" heavy 3 --name perf ${SLOT_TIMEOUT[@]+"${SLOT_TIMEOUT[@]}"} -- "$GODOT" --path "$PROJ" --windowed --resolution 1600x900 \
      -s res://tools/perf_probe.gd -- "$@" "$QUALITY" ;;
  play)
    exec "$GODOT" --path "$PROJ" ;;
  export)
    mkdir -p "$ROOT/build"
    # The shipped app trusts the settle bake without re-checking it (world/art/settle/cache.gd), so a
    # stale bake must never reach the pack.
    if ! "$0" test res://world/art/tests/test_settle_cache.gd >"$ROOT/tmp/last_export_settle.log" 2>&1; then
      echo "export refused: the settle bake is stale -- SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600"
      grep -E "FAIL|stale" "$ROOT/tmp/last_export_settle.log" | head -5
      exit 1
    fi
    # An absolute home path anywhere under game/ means some part of the city silently vanishes on any
    # other machine (city-art r12 §3). Cheap, and it is the whole point of shipping the app.
    if ! "$0" test res://world/art/tests/test_no_abs_paths.gd >"$ROOT/tmp/last_export_paths.log" 2>&1; then
      echo "export refused: an absolute home path under game/ -- see below"
      grep -E "^FAIL" "$ROOT/tmp/last_export_paths.log" | head -10
      exit 1
    fi
    # Output goes to the log only: a pipe that closes early (head) would SIGPIPE Godot mid-savepack.
    [ ${#SLOT_TIMEOUT[@]} -eq 0 ] && SLOT_TIMEOUT=(--timeout 3600)
    python3 "$SLOTS" import 1 ${SLOT_TIMEOUT[@]+"${SLOT_TIMEOUT[@]}"} -- "$GODOT" --headless --path "$PROJ" \
      --export-release "macOS" "$ROOT/build/TIANSHU.app" >"$ROOT/tmp/last_export.log" 2>&1
    code=$?
    grep -E "ERROR|SCRIPT ERROR|Failed" "$ROOT/tmp/last_export.log" | grep -v "^\s*at:" | head -40
    du -sh "$ROOT/build/TIANSHU.app" 2>/dev/null
    [ $code -eq 0 ] && "$0" package --out="$ROOT/build"
    exit $code ;;
  package)
    # Everything that ships BESIDE the .app. Runs on its own too, so the contents can be checked
    # without holding the machine's one import slot for a full export.
    out=""
    for a in "$@"; do case "$a" in --out=*) out="${a#--out=}" ;; esac; done
    [ -z "$out" ] && { echo "package: --out=<dir> required"; exit 2; }
    mkdir -p "$out"
    [ -f "$ROOT/README.md" ] || { echo "package: no README.md at the repo root"; exit 1; }
    cp "$ROOT/README.md" "$out/README.md" || exit 1
    echo "package: $out/README.md"
    # The engine, third-party and font notices, from the same composer the in-game LICENCES page reads
    # (hud r6: ui/licenses/write_third_party.gd). Beside the .app, never inside it (that breaks the
    # ad-hoc signature).
    rm -f "$out/THIRD_PARTY_LICENSES.txt"
    "$0" test res://ui/licenses/write_third_party.gd -- --out="$out/THIRD_PARTY_LICENSES.txt" \
      >"$ROOT/tmp/last_package_licences.log" 2>&1
    [ -s "$out/THIRD_PARTY_LICENSES.txt" ] || { echo "package: the licence writer failed -- tmp/last_package_licences.log"; exit 1; }
    echo "package: $out/THIRD_PARTY_LICENSES.txt"
    ls -la "$out" | grep -E "README|LICENSES" || true
    exit 0 ;;
  *)
    sed -n '2,24p' "$0"; exit 2 ;;
esac
