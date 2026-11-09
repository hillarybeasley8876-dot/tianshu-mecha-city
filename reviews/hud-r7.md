# hud r7 — lead brief (urgent): GAME_OVER pauses the tree in the death frame, and the death breaks

## Why
The lead's captures batch (trailer r4, `status/trailer.md` r4 §5 item 2 and the flow section; sheets
`captures/batch_r4/mech-move_sheet.jpg` and `flow_sheet.jpg`) found the most serious defect left in
the demo. **With the menus live, a death does not play out:**
- **The death slump never plays.** Every `POSE dead_*` line reads `clip=death weight=0.00
  cockpit_h=13.1`: the mech stands upright under the MECH DESTROYED page, and the probe ends
  `SUMMARY: 2 checks failed` (`hop_death_still_posed`, `flight_death_still_posed`). The same run with
  `--stub=hud` passes everything: weight 1.00, slumped.
- **The whole-city E2E stalls at the death beat.** `FLOWDBG die` → `wait_state ["game_over"]` times
  out, and nothing follows: no respawn, no boss, no victory. With the HUD stubbed, it completes.

**The cause** (lead reading, confirm it): `game/ui/menus/menu_root.gd:311-315` `_on_player_died()`
calls `_set_paused(true)` in the SAME frame `player_died` fires. The hero's death clip
(`Hero3Model`, advanced in `_physics_process`, blending in over 0.08 s from weight 0) is frozen at
weight 0. Any flow logic that runs on process frames after the death, including FlowDebug's beat runner
and its own waits, freezes too. The mech-move r7 critic predicted exactly this (`reviews/r16-lead-
decisions.md`, round 2, mech-move r7).

## House rules
- You are the ONLY worker.
- Headless tests first. The user has OK'd the screen for this session, so you MAY run the two windowed
  gates below, prefixed with `MC_WINDOW_OK=1`, one at a time, and nothing else windowed.
- Never use git stash. Commit with explicit paths.

## Do
1. **The fix belongs in the menu.** Keep the game running until the death has played out, then pause.
   - Show the GAME_OVER page at once. Pause the tree only when BOTH:
     - flow is in `game_over` (`Game`/flow state, or a signal);
     - the death has settled: the hero's death clip is at full weight, through the model API if it
       exposes one, or a fixed 1.5 s on the REAL clock (`Feel.real_now` or unscaled time).
   - Inputs: mech-move's death gate already makes the corpse ignore input, so nothing the player
     presses during that 1.5 s may act. Confirm it.
2. **A headless regression test.** Boot `main.tscn` with the HUD live, kill the mech with an
   unblockable hit, and tick through. Assert:
   - flow reaches `game_over`;
   - the death clip weight reaches 1.0 before the pause;
   - the tree is paused afterwards;
   - RETRY (a real key event) respawns at the checkpoint, and the page closes only after.
   The test must FAIL on HEAD's `menu_root.gd`.
3. **The two windowed gates**, from `status/trailer.md` r4:
   - mech-move's `1_death` command (menus live): `SUMMARY: 0 checks failed`, every dead POSE at
     weight 1.00;
   - flow's `3_city` E2E: it passes the death beat and reaches victory (`E2ECAMREPORT` present).

## Gates
- The new test fails on HEAD and passes after.
- `test_hud`, `test_title_tutorial` and the flow suites pass. `tools/suites.sh --only=<hud rows>,flow,mech_death`
  is green.
- Both windowed gates pass, with their log lines in your r7 status section.
