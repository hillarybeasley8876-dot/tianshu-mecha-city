# flow — numeric-robustness audit (lead, 2026-11-02) — 5 verified findings

A 36-agent audit read every non-test script twice (non-finite math; clocks + integrators) and a skeptic
tried to refute each finding; these survived. Fix them all (the proposed fixes were checked by the
skeptic — where it corrected one, the correction is what is written under *fix*). Add a regression check
for each high one in your suite, keep every suite green, run one scripted fight with `--nan-watch`, commit,
and report per finding: fixed (how) / not reproducible (evidence).

Clock contract reminder (CONTRACTS §3): Feel.real_delta/real_now for input, camera, UI/post and rate
limits; Feel.player_delta for player timers/anims; plain delta for world VFX; NEVER the wall clock
(movie capture renders a frame in ~70 ms of wall time). Feel now divides _process deltas by the
frame's own scale, so Feel.real_delta(delta) is correct in _process too.

## 1. [high] game/flow/drop_in.gd:57 (clock)
**What**: The 30 s FALL_TIMEOUT starts counting at boot, because `_process` is enabled automatically and `_started` defaults to 0.0. `begin()` never resets `_done`, so idling on the title screen for 30 s pre-finishes the drop and the flow then hangs in DROP_IN.

**Trigger**: Normal launch (no --skip-menu/--sandbox). menu_root shows the TITLE page without pausing the tree, so DropIn._process runs. Once Feel.real_now() > 30 s it calls _finish(false): plays land_light at Vector3.ZERO, calls rig.end_cinematic() on the title shot and sets _done = true. Pressing START then runs begin(), but _process and _on_landed both return on _done and `finished` never emits. Result: no tutorial, no start checkpoint, and _on_all_spires_down (which needs DISTRICT) never opens the boss gate. --spawn runs never call begin(), so they get the same spurious land_light + end_cinematic at t = 30 s. Feel.real_now() also advances while paused, so a >30 s pause during the fall times out mid-air.

**Fix**: As proposed, plus: 1) set_process(false) in _ready. 2) In begin(), reset _done = false and _fall_t = 0.0. 3) Accumulate `_fall_t += Feel.real_delta(delta)` in _physics_process, enabled only between begin() and _finish(). 4) Guard Events.landed.connect with is_connected.

**Skeptic's check**: drop_in.gd defines _process, so Godot enables it at ready. With _started = 0.0 and _done = false (drop_in.gd:27-28) it measures Feel.real_now() from boot, and the TITLE page never pauses the tree (menu_root.gd:101). After 30 s on the title, `_finish(false)` sets _done = true (:71). begin() (:31-51) never clears it, so _process and _on_landed return early and `finished` never fires. GameFlow stays in DROP_IN, arena_cleared is ignored (game_flow.gd:189-191), and the boss gate never opens. Feel.real_now() also keeps running during pause, so a long pause mid-fall times the drop out early.

## 2. [high] game/flow/drop_in.gd:80 (other)
**What**: _finish() calls rig.end_cinematic(), but that only restores arm/look (camera_rig.gd:382) and never deactivates CameraCinematic. The 40 s drop cinematic keeps the camera for about 30 s after landing.

**Trigger**: Every drop-in. A 400 m fall at fall_gravity 25.5 m/s² with a 50 m/s terminal speed lands after ~9 s. _cine.active stays true until CINEMATIC_LEN = 40 s. Meanwhile camera_rig._physics_process keeps calling _cine.advance() and returns before _update_look(), so look input is ignored while the tutorial's first hint asks the player to LOOK.

**Fix**: As proposed: call rig.request_cinematic([], 0.0), then end_cinematic(), then release_fov(0.2). The explicit restore calls are needed because request() sets active = false before calling _finish(), so _finish skips its own restore. Cleaner: a camera-aim stop_cinematic() that calls _cine._finish(). The title shot (100000 s) leaks the same way when --spawn is used without --skip-menu (game_flow.gd:168-171).

**Skeptic's check**: end_cinematic (camera_rig.gd:382) only restores the arm, snaps the camera and re-enables look. CameraCinematic.active (camera_cinematic.gd:16) stays true until _finish (:207) runs when _left reaches 0. Until then camera_rig._physics_process calls _cine.advance and returns before _update_look (camera_rig.gd:211-223), for the full CINEMATIC_LEN of 40 s. The drop lands well before that, so look input stays dead for roughly 30 s while the tutorial's LOOK prompt (tutorial_director.gd:20) is up.

## 3. [medium] game/flow/encounter_director.gd:251 (nonfinite)
**What**: _spawn_pack places a roaming pack at the player's own altitude, 160-380 m away, with no clamp to the ±700 m map. Off-map, EnemySpawner._grounded finds no navmesh within 60 m and its downward ray (at+200 to at-400) hits nothing, so it returns the raw airborne point: ground monsters spawn in mid-air outside the city.

**Trigger**: Player within about 300 m of an edge, which is two-thirds of the map; the H0 drop point at Godot (-560, 2, 600) is 100-140 m from two edges. BEHIND_BIAS puts 75% of packs behind the player, e.g. the ripper pack at 170-300 m, which lands at |x| or |z| > 700. The terrain tiles stop at ±700 and the skyline ring has no collision. Rippers, mantises and spitters then fall forever (velocity capped near 60 m/s, so y runs away). While the player stands on reachable ground, their nav agents can still report the target reachable, because the path starts from the nearest navmesh point, so the spawner's leash may never relocate them. They keep counting against max_alive (12) and the 40-enemy budget, which trims later waves and pins music intensity at contact.

**Fix**: 1) Clamp the centre's x and z to ±(bounds.half − GROUP_SPREAD − margin), about ±650. 2) Then `at = FlowSpawner.ground_snap(self, at, player.global_position.y)`, as `_start_wave` does. 3) If the snap misses, or the clamp moved the point a lot, fall back to `spawner.place_around(player.global_position, bearing / TAU, type)`, which returns a path-checked navmesh point. 4) Keep `director.enabled` false until the drop has landed (or until DISTRICT), so packs do not spawn on the title screen.

**Skeptic's check**: `_spawn_pack` (encounter_director.gd:246-256) puts the pack centre at the player's altitude, 170-380 m out. There is no clamp and no ground_snap (`_start_wave` does one at :159). EnemySpawner._grounded (spawner.gd:161-173) only snaps to navmesh within 60 m, and its ray hits nothing past ±700: the 700-900 m skirt is a render-only kit.slab, and terrain.py:221-245 only adds a wall/curtain at the edge, with no floor beyond it; skyline.glb is a single render node. From PlayerSpawn (-560, 2, 600), yaw 54.2°, the 'behind' bearing of ~36°±46° puts most ripper packs at z > 700. Ground types then fall forever at ≤ 60 m/s (enemy_base.gd:294-306). While idle they patrol to the nearest navmesh point (brain.gd:121-126), so agent.is_target_reachable() stays true and `_leash` (spawner.gd:49-67) never moves them. They keep filling max_alive, the 40-enemy budget, and CONTACT music intensity. The director also ticks during TITLE, so the first pack can fall off-map at t = 40 s, before START.

## 4. [low] game/flow/game_flow.gd:313 (clock)
**What**: The run clock shown on the victory page is ticked with the scaled physics delta.

**Trigger**: Every global hit-stop (0.05x) and every slow-mo or witch time (0.3-0.5x) under-counts it. A kill_large loses ~0.3 s and a perfect dodge ~0.25 s, so a full run reports tens of seconds less than was actually played.

**Fix**: Tick with Feel.real_delta(delta) in game_flow._physics_process, and also make the page show that value: have _write_time rebuild the victory rows, and drop menu_root's own scaled time accumulation.

**Skeptic's check**: game_flow.gd:313 ticks FlowProgress._run_time with the scaled physics delta, so global hit-stops, slow-mo and witch time all under-count it. The victory page does not even show this value, though. menu_root connects game_won first (main.gd adds the HUD before the flow), and its _on_won (menu_root.gd:343-345) builds the rows from its own stats["time"], which is also accumulated from scaled _process delta (:330). victory_director._write_time writes the flow's time only after the page is built.

## 5. [low] game/flow/hive_collapse.gd:32 (clock)
**What**: The blast chain and the 30 s smoke lifetime are timed against Feel.real_now(), which keeps advancing while the tree is paused (Feel is PROCESS_MODE_ALWAYS). This node is pausable, so pause time leaks into its timers.

**Trigger**: Pausing during the 0.7 s chain: on resume both remaining blasts, with their kill_large feel events, fire in the same frame. Pausing for 30 s or more during the wreck: the smoke column is released the frame play resumes.

**Fix**: As proposed: accumulate `_t += Feel.real_delta(delta)` in _physics_process, enabled via set_physics_process(true) in run().

**Skeptic's check**: hive_collapse.gd:41 and :49 time the blast chain, topple, swap and the 30 s smoke from Feel.real_now(). That clock keeps advancing in pause, because Feel is PROCESS_MODE_ALWAYS (feel.gd:48, 149-152), while this node inherits pausable mode from GameFlow and stops. Pausing during the 0.9 s chain fires the remaining kill_large blasts, the topple snap and the swap all in the first frame after resume. A pause that runs past the 31.3 s wreck window releases the smoke column the moment play resumes.

## Lead decision for the drop-in cinematic finding
camera-aim fixes `end_cinematic()` to end the cinematic completely (CONTRACTS §5) — keep calling it; do not
work around it with `request_cinematic([], 0.0)`.
