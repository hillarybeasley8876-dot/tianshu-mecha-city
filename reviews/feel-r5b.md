# feel r5b — lead brief: finish r5 (the saved WIP, the enemy_base edit, the boss kill), plus skate sparks

## Why
r5 items 0, 1 and 2 are committed: the five rows (dcda081, 7d2655d, 408a14e), a swarm kill freezing
the victim instead of the world (aeb8234), and the afterimages (6e3b17f). Then the user stopped all
parallel work on 11-05 at 11:40.

The lead saved your uncommitted work as a patch: `tmp/lead/wip/feel/tracked.patch` (343 lines;
`feel_gallery.gd`, `gallery_timeline.json`, `stand_in_player.gd`, `test_clocks.gd`) plus the untracked
`tmp/lead/wip/feel/untracked/game/fx/tests/swarm_feel.{gd,tscn}`, `swarm_timeline.json`. The tree is at
HEAD for `game/fx`. enemies r11 has since landed (a6269a7…cfbb36f), so your `enemy_base.gd` edit is now
unblocked.

## House rules (the user's machine)
- You are the ONLY worker.
- `tools/godot.sh shot|run|drive|movie|perf` refuse without the lead's `MC_WINDOW_OK`. Verify headless.
- List the exact commands for the swarm movie and the gallery stills under **"Captures needed"**.
- Never use git stash. Commit with explicit paths.

## Do
1. **The WIP.** Re-apply `tracked.patch` (`git apply` checks clean) and the untracked files. Finish
   r5 item 3 (the gallery still clock drift) and commit, or drop what is no longer needed and say why.
2. **The victim-local stop on `enemy_base.gd`.** This is your narrow exception: `_die`, the dead
   branch and `_tick_wreck`. Check it against enemies r11's committed file. Put any line move in your
   status.
3. **The boss kill.** If `game/enemies/boss/brood_titan.gd` still plays `kill_large` at the boss death,
   switch that one line to `boss_kill`. That line is granted. Then confirm with `test_boss` that the
   boss death fires `boss_kill` once.
4. **Skate sparks and dust** (hero-v3 r9 request). On the 42 m/s boost skate and on the slide, emit
   feet-contact sparks and a dust trail from the foot-plant points (`Hero3Model` exposes the sole and
   foot positions; read hero-v3's status for the API). Budget them like the existing VFX pools, and
   turn them off in the air.
5. **Gate everything headless:**
   - `test_feel` (row count), `test_clocks`, the swarm test, `test_feel_rows`, `test_boss`;
   - a new test for item 4: the emitters fire while skating on the ground, stop in the air, and stay
     within budget;
   - `check --only=res://fx/` is clean.

## Gates
All of the above pass. New tests fail on HEAD where that applies. `status/feel.md` gets an r5b section
with the numbers and Captures needed.
