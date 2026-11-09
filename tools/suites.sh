#!/bin/bash
# MECHA CITY suite runner (tooling): runs every game/**/tests/test_*.gd through tools/godot.sh test
# and prints one row per run.
#   tools/suites.sh                 run everything in tools/suites.txt
#   tools/suites.sh --only=a,b      just those rows
#   tools/suites.sh --list          print the list and the coverage check, run nothing
#   tools/suites.sh --jobs=N        parallel runs (default 1: a perf gate measured next to another
#                                   suite reads the load, e.g. enemies_ai's 6 ms physics budget)
# Row: name | res://path | flags. A tracked test_*.gd with no row FAILS the coverage check, because an
# unrun suite is an unverified one. The last line of a full run is the lead's verdict:
#   SUITES <n> rows, <g> green, <k> known, <r> red
# and the exit code is 0 only when r = 0 and nothing is unlisted.
# Columns: name, exit, checks, script_err, other_err (engine ERRORs and push_error, minus the
# exit-time leak lines Godot prints while tearing down) and a verdict; a red listed in
# game/tools/known_issues.txt with the SAME number of failed checks prints KNOWN-ERROR <tag> instead.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$ROOT/tools/suites.txt"
OUT="$ROOT/tmp/suites"
only=""; jobs=1; list_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only=*) only="${1#--only=}" ;;
    --jobs=*) jobs="${1#--jobs=}" ;;
    --list) list_only=1 ;;
    *) echo "suites: unknown option $1"; exit 2 ;;
  esac
  shift
done
mkdir -p "$OUT"

# Every tracked test script must have at least one row.
missing=0
while read -r path; do
  grep -qF "|res://${path#game/}|" "$LIST" || { echo "UNLISTED $path"; missing=1; }
done < <(git -C "$ROOT" ls-files 'game/**/tests/test_*.gd')
[ "$list_only" = 1 ] && { [ "$missing" = 0 ] && echo "coverage: every tracked test has a row"; exit "$missing"; }

run_one() {
  local name="$1" path="$2" flags="$3"
  local log="$OUT/$name.log"
  # shellcheck disable=SC2086
  ( cd "$ROOT" && tools/godot.sh test "$path" -- $flags ) >"$log" 2>&1
  local code=$?
  local checks script_err other_err
  checks=$(grep -oE "(TEST|[A-Z][A-Z ]*TEST)[^|]*[0-9]+ checks?, [0-9]+ (failures?|failed)" "$log" | tail -1)
  # Any "<n> checks, <n> failed" summary line (PADATOM, AI, BOSS, SPAWNER …), then a bare PASS/FAIL.
  [ -z "$checks" ] && checks=$(grep -E "[0-9]+ checks?, [0-9]+ (failures?|failed)" "$log" | tail -1)
  [ -z "$checks" ] && checks=$(grep -E "PASS|FAIL" "$log" | tail -1)
  script_err=$(grep -c "SCRIPT ERROR" "$log")
  # Engine ERRORs, minus Godot's exit-time teardown lines and the host's own "TEST ERRORS n" report.
  other_err=$(grep "ERROR" "$log" | grep -v "SCRIPT ERROR" | grep -v "^TEST " \
    | grep -vcE "ObjectDB instances leaked at exit|RID allocations of type|resources still in use at exit|still in use at exit")
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$code" "${checks:-<no checks line>}" "$script_err" "$other_err" \
    > "$OUT/$name.row"
}
export -f run_one
export ROOT OUT

rows=()
while IFS='|' read -r name path flags; do
  case "$name" in ''|'#'*) continue ;; esac
  [ -n "$only" ] && { case ",$only," in *",$name,"*) ;; *) continue ;; esac; }
  rows+=("$name|$path|$flags")
done < "$LIST"

pids=()
for row in "${rows[@]}"; do
  # bash 3.2 has no `wait -n`: throttle on the number of live background jobs.
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$jobs" ]; do sleep 1; done
  IFS='|' read -r name path flags <<< "$row"
  run_one "$name" "$path" "$flags" &
  pids+=("$!")
done
wait

red=0
known_reds=0
printf 'name\texit\tchecks\tscript_err\tother_err\tverdict\n'
for row in "${rows[@]}"; do
  name="${row%%|*}"
  [ -f "$OUT/$name.row" ] || { printf '%s\tNO ROW\n' "$name"; red=$((red + 1)); continue; }
  IFS=$'\t' read -r rname code checks se oe < "$OUT/$name.row"
  verdict="ok"
  if [ "$code" != 0 ]; then
    # A suite listed as `red|...` in game/tools/known_issues.txt is expected red; a DIFFERENT number of
    # failed checks than the one recorded there is a new failure and stays red.
    path=$(echo "$row" | cut -d'|' -f2)
    krow=$(awk -F'|' -v s="$path" '$1=="red" && $2==s {print; exit}' "$ROOT/game/tools/known_issues.txt")
    if [ -n "$krow" ]; then
      want=$(echo "$krow" | cut -d'|' -f3)
      tag=$(echo "$krow" | cut -d'|' -f4)
      got=$(grep -oE '[0-9]+ fail(ed|ures?)' "$OUT/$name.log" | tail -1 | grep -oE '^[0-9]+')
      # a suite whose summary carries no count: the number of its own FAIL lines
      [ -z "$got" ] && got=$(grep -c '^FAIL ' "$OUT/$name.log")
      if [ "${got:-x}" = "$want" ]; then
        verdict="KNOWN-ERROR $tag (expected $want failed)"
        known_reds=$((known_reds + 1))
      else
        verdict="RED (known list says $want failed, this run had ${got:-?})"
        red=$((red + 1))
      fi
    else
      verdict="RED"
      red=$((red + 1))
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rname" "$code" "$checks" "$se" "$oe" "$verdict"
done
echo "---"
# The lead's one line: `tools/suites.sh` with no arguments ends here, and exits 0 only when nothing is red.
[ "$missing" != 0 ] && echo "suites: $missing tracked test(s) have no row"
echo "SUITES ${#rows[@]} rows, $(( ${#rows[@]} - red - known_reds )) green, $known_reds known, $red red"
[ "$red" -eq 0 ] && [ "$missing" -eq 0 ]
