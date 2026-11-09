# flow r5b — lead brief: the hive collapse must film, and the r5 remainder

## Why
r5 pass 1 (items 1–6) and items 7–9 are committed. The round was stopped mid-work on 11-05 at 11:40,
when the user ordered all parallel work stopped. Your uncommitted work was saved by the lead as a
patch: `tmp/lead/wip/flow/tracked.patch` (48 lines; `flow_assault_targets.gd`, `flow_debug_view.gd`)
plus `tmp/lead/wip/flow/untracked/game/flow/tests/e2e_city_drive.json`. The tree is at HEAD for
`game/flow`.

The trailer's showcase reel (r3) has since filmed a hive kill in the real, un-stubbed flow. **The
collapse cinematic parks the camera inside geometry** about 1 s after the core dies. The rest of the
collapse is a dark interior, with the burning spire seen through a gap and then an unrelated bridge.
The pods and the core film cleanly. See the "Known issues" in `status/trailer.md` and the m6 segment
on the showcase sheet `captures/trailer/sheets/TIANSHU_showcase_segments.jpg`. The collapse is the
reward beat of the demo's main objective, so it must read.

## House rules (the user's machine)
- You are the ONLY worker. `tools/godot.sh shot|run|drive|movie|perf` refuse without the lead's
  `MC_WINDOW_OK`. Verify headless (`test`, `check`).
- Put every windowed run you need (the E2E drives, a collapse capture) under **"Captures needed"** in
  your status file, with exact commands. The lead runs them when the user OKs the screen.
- Never use git stash. Commit with explicit paths.

## Do
1. **Re-apply or drop the WIP.** Read `tmp/lead/wip/flow/tracked.patch` (`git apply` checks clean
   against HEAD). If it is still needed, finish it and commit; if not, say why and drop it.
2. **The collapse camera** (`flow/hive_collapse.gd`, the duel frame).
   - Find why the shot lands inside geometry. The ~110 m wide shot from the hero → spire frame is
     probably placed without a clearance check against the city.
   - Make the camera placement robust: sample candidate bearings and heights around the spire, ray-
     and sphere-check each candidate against the world, and pick a clear one that frames the spire
     and the hero. Never place it inside a collider.
   - **Headless gate:** a test that runs the collapse at all three hives (A2, A5, A6; city-layout r8
     moved A2 and A6, so use the current sites). The chosen camera position is outside every collider
     (a point-in-solid query), the spire base and top are both inside the frustum with a clear ray
     from the camera, for every frame of the 2 s shot.
   - The windowed proof (a movie of each collapse) goes under Captures needed.
3. **`die` announces twice** (mech-move r7b, Request 18). Your FlowDebug `die` writes hp = 0 and emits
   `player_died` itself, and `MechDamage.sync()` now emits on the next tick as well. Drop flow's own
   emit, since mech-move's latch covers it. Gate: one `player_died` per `die`, in a headless test.
4. **Re-run your suites headless** and record the numbers in an r5b section:
   - `test_flow -- --sandbox --flow --spawn=0,1,60`;
   - `test_flow_idle`;
   - `test_boss`;
   - `test_boss_city`;
   - `tools/godot.sh check`.

## Gates
- The new collapse-camera test fails on HEAD and passes after; it covers all three hives.
- The `die` test reads one emission.
- All flow and boss suites pass; `check` is clean; no file over 600 lines.
- `status/flow.md` gets an r5b section and a "Captures needed" list.
