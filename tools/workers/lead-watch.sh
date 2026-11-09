#!/bin/bash
# Lead monitor (Monitor tool): one line per M78 job that reaches done/failed/stopped, again after each new round.
# Lives in tools/ (committed), never in the shared tmp/ that workers clean. Errors go to stdout so they are seen.
cd ~/m/mecha-city || { echo "watch: no repo"; exit 1; }
snap() { python3 tools/workers/m78.py status 2>/dev/null | python3 tools/workers/lead-snap.py 2>&1; }
prev="$(snap)"
echo "watch: armed — $(printf '%s\n' "$prev" | grep -c ':done:') jobs done"
while true; do
  cur="$(snap)"
  if [ "$cur" != "$prev" ]; then
    comm -13 <(printf '%s\n' "$prev" | sort) <(printf '%s\n' "$cur" | sort) | sed 's/^/M78 job finished → /'
    prev="$cur"
  fi
  sleep 30
done
