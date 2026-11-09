# hero-v3 r5 — lead brief: put the Tianshu in the game, and give it weight

## Why now
The user played the current build. Their words: "你不觉得高达目前的绑定很有问题吗。好多物件都不对
下落和《人类一败涂地》软绵绵的 没力量感！！！". In English: the old hero's rig is broken, many parts
are wrong, and falling is soft and floppy like Human: Fall Flat, with no power.

That is the OLD white hero (`player/model/hero/`): one 170 k-vertex mesh with every vertex on a single
bone, plus Tripo text-to-motion clips for falling. Your rigid-piece model fixes the first half the
moment it is in the game. This round puts it there and makes it HEAVY.

## r4 verdict
The lead re-ran your gates and its own probes against the final r4 state:
- 11 of 12 hero3 tests pass.
- Release, idle, aim signs and the chain probes are clean.
- dash, slide, lunge and locked no longer step.

Accepted, except for item 9 (pieces), carried below.

## The switch: you do it this time (the lead's "not your job" list from r4)
The owners of these files are idle. Edit them, keep each change small, and run that unit's own tests
after each one.
1. `player/mech/player_mech.gd:17`: point `HERO_MODEL` at `res://player/model/hero3/hero3_model.tscn`.
   Grep everything that reaches the model and confirm it only uses the HeroModel API (CONTRACTS §5).
2. **Aim.** Every physics frame, call `model.set_aim(<the weapon context's aim_point()>, weight)`.
   - The weight goes to 1 while aiming or firing a ranged weapon.
   - It eases back to 0 a short time after the last shot, so the rifle comes down.
   - `combat/weapons/weapon_context.gd` already has the aim point.
3. `stop_action`:
   - at guard end (`combat/defense/defense_system.gd` `_end_guard`);
   - when the gatling's `_spin` reaches 0 (`combat/weapons/gatling.gd`).
4. **Hit reactions and death** in `PlayerMech._apply_damage`:
   - `hit_light` or `hit_heavy` by `tuning.hurt_heavy_damage`;
   - `hit_knockdown` on a big knockback;
   - `death` (held) when hp reaches 0.
   Today the model is never told it was hit.
5. **Perfect parry.** Play `parry` where `defense_system.gd` plays the `parry_perfect` feel (two call
   sites).
6. **Sweep direction.**
   - Add a per-move sweep direction to `combat/melee/melee_table.gd`, generated from
     `test_hero3_reach.gd`'s printout, not typed.
   - `blade_dir` sweeps left to right for those moves, so the hitbox and the blade agree.
   - Re-run the melee unit's suites.
7. **Footsteps.**
   - Connect `Hero3Gait.footstep` to `Events.footstep` and `Feel.play(&"footstep_heavy")` at the
     planted foot.
   - The timer in `mech_contact.footsteps` stays only for a model without the signal (the placeholder).
8. **Cockpit eye.** Low-pass the eye point in `player/camera/camera_blend.gd` `cockpit_point`, so the
   gait's pelvis bob does not shake the first-person view. Damp the bob; keep a little.
9. **Remove the old hero.** Once the game runs on hero3, delete `player/model/hero/`, its tests and
   anything only it used, in its own commit. First grep that nothing else loads it.

## Weight: the part the user is angry about
The lead is retuning the BODY at the same time: fall gravity 25.5 → ~80 m/s², a higher terminal speed,
the landing tiers, and the landing feel rows.
- Do NOT edit `player/mech/mech_tuning.gd`, `docs/SPEC.md` or `fx/events/land_*.tres`.
- Read them after the lead's commit lands: the git log will say "lead: heavy fall".

The model has to sell the same weight:
- **Landing.** Scale the crouch by the impact.
  - `Events.landed(impact_speed)` exists; `set_locomotion` also gets `land_light` / `land_heavy`.
  - A heavy landing:
    - drops the pelvis 2.0–2.5 m within 3 frames (60 fps);
    - folds the knees, with the feet planted through the IK;
    - pitches the torso forward 10–15°;
    - throws the arms down and out, to brace;
    - holds about 6 frames;
    - recovers over about 0.3 s with an ease-out.
  - A light landing dips about 0.8 m.
  - Today `Hero3Air` dips 0.6 / 1.2 m over 0.18 / 0.38 s. That is the soft half of the complaint.
- **Falling.**
  - The air pose must read as a machine bracing, not a body dangling: compact, knees slightly bent,
    arms held.
  - In `fall`, faster than about 15 m/s down, extend the legs toward the ground and spread the arms a
    little.
  - Use the speed `set_locomotion` already receives, or add a vertical-speed input to the API if you
    need one: CONTRACTS §5 is the lead's, so say so in your status.
- **Hit reactions.** These must snap. Peak displacement lands in 2–3 frames, not a slow ease.

## Carried from r4 item 9
Two crossings are visible in normal play: knockdown R_Calf/R_Thigh +0.707 m, and the melee_l1 follow
R_Forearm/R_Hand +0.198 m. Fix them; the gate stays at 5 cm.

## Gates
- All `hero3/tests/` pass, plus every unit suite you touched:
  - melee, defense, weapons, camera, mech-move;
  - `tools/godot.sh test` for each `tests/` folder;
  - `tools/godot.sh check` clean.
- The game boots into the city with 0 script errors from your files.

## Evidence (in the GAME, not the model sandbox)
- A side-view filmstrip of a ~20 m drop and landing in the city: before (commit 8f2bfd1) and after.
- The same for a plain hop.
- A melee combo, aimed fire, guard and perfect parry, dash and slide, filmed from the game camera.
- A 4 s first-person clip while walking (the eye low-pass).
- The before/after sheet goes in `captures/`. The lead will show it to the user.

Commit per step with an explicit path list. Report in `status/hero-v3.md`.
