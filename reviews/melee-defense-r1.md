# melee-defense — review r1 (lead) — FAIL (mechanics excellent; look + cinematics + integration open)

Verified myself: check 29 files clean; test_melee 82/0; test_defense 67/0; showcase movie + 10 stills reviewed.
Frame data, cancels, lunge, charge, catch field, perfect window, anti-mash, guard break: all correct.
Contract decisions (CONTRACTS §5 updated): cinematic shots use the **duel frame** (origin = player/target
midpoint, −Z player→target, +Y up, +X right; `look` in the same frame); camera-aim resolves collisions and
restores the arm. `lunge_to` may be re-issued each tick with the REMAINING time.

## MUST-FIX
1. **Core Rend cinematics**: author the 2–3 shots per enemy class in the duel frame (e.g. side wide
   `(40, 10, 0)` → low hero shot `(-10, 4, 18)` looking at the target's core → impact close `(18, 8, -12)`), and add
   a test: for every shot of every class, both actors' AABB centres project inside the frustum (with ≥ 8 %
   margin) and the camera is outside every collider/AABB. The current exec captures are black frames.
2. **Crescent wave**: a real crescent — curved arc mesh (24 m chord, ~4 m thick at the centre tapering to
   points), hot white leading edge → cyan glow → fading tail (additive, HDR emission so it blooms), slight
   vertical distortion, ground scouring sparks + dust where it passes, `spark_beam` bursts on hits.
   No flat slabs.
3. **Swing readability**: trail ribbon sampled from blade root→tip every physics tick, visible for 0.18 s,
   width = full blade length, additive white→cyan with HDR so it blooms; on hit: `VfxLibrary.spawn(&"spark_beam"
   …)` at the contact point (find it by group `&"vfx_library"`), FEEL row, and the LOCAL hit-stop visibly
   freezing both actors (`Feel.local_hit_stop`). Capture frames exactly at hit moments (trigger screenshots
   from your hit callback in the range scene, not on a timer).
4. **Perfect parry ring**: vertical, in front of the shield, facing the attacker, white-gold, 0→18 m in 0.1 s,
   plus the 40-spark burst; the block hex panel aligned to the shield arm. Not a halo above the head.
5. **Range scene look**: add the ART.md environment (WorldEnvironment glow on, AgX, dusk-ish sun) so bloom and
   colours are judged as in game (the current grey/dark scene hides the saber).
6. **Real integration**: in `main.tscn --sandbox` with the real PlayerMech + camera rig + feel + enemies
   (`--enemies=mantis:2,ripper:6`): full string on rippers, a lunge from 70 m, a perfect parry of a real Mantis
   combo → Return Cut, a Ram Kick from a real assault boost, a catch of real Spitter acid → release, a Core Rend
   on a staggered Mantis. Telemetry/Events prove each; 8 captures `captures/melee_int_*.jpg` + movie.

## SHOULD
- Saber blade: slight taper + hilt glow; idle hum flicker.
