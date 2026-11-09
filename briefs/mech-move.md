# Brief: mech-move — PlayerMech root, locomotion, energy, damage pipeline, placeholder model

## Goal
The player's 16 m mech moves like the best mech games: instant response, highway speeds, heavy landings,
dash with i-frames and perfect dodge, boost slide, assault boost, jump/hover, free flight. It is the root
every combat component plugs into (CONTRACTS §5). Feel target: Armored Core VI speed + Gundam weight.

## Read first
`docs/CONTRACTS.md` (all, esp. §4–5), `docs/SPEC.md` §2–5 and §10, `docs/FEEL.md` (movement rows),
`ref/research/feel-mech-games.md` (movement/camera tuning; if it is not written yet, use SPEC §4 numbers),
`ref/research/skills-catalog.md` §4.1 (EN/OD rules), `game/core/**` (Feel, Events, Game, HitInfo, Layers).

## You own
`game/player/player_mech.tscn`, `game/player/mech/**` (scripts, tuning resource, tests, timelines,
debug camera), `game/player/model/placeholder/**`.

## Build
1. **PlayerMech** (`player/mech/player_mech.gd`, `class_name PlayerMech`, `CharacterBody3D`, group
   `&"player"`, layer `Layers.PLAYER`, mask `Layers.MASK_CHARACTER`): capsule r 3.5 m, h 15 m; floor max
   angle 45°, floor snap 2 m; spawns at `Game.spawn_transform(<world PlayerSpawn marker or origin>)`;
   `Game.register_player(self)` in `_ready`; then instances the model (`player/model/hero/hero_model.tscn`
   if it exists, else your placeholder) and every component scene in CONTRACTS §5 order (skip missing).
   Two Hurtboxes (torso, legs) on `Layers.PLAYER_HURTBOX` and one `Targetable` is NOT needed (player).
2. **Tuning** in `player/mech/mech_tuning.gd` (`Resource`, exported fields) + `mech_tuning.tres` with
   SPEC §4 numbers. No magic numbers in the state code.
3. **States** (one small script per state or one state machine file ≤ 400 lines + helpers): ground
   (idle/walk/run with accel/decel and 540°/s turn), dash (8 directions relative to camera yaw; out-expo
   speed curve; i-frames first 6 f (= 12 physics ticks); chain ≤ 3 then 0.45 s lockout; cancels per
   skills-catalog §4.3 cancel windows are offered through `can_cancel()`), boost slide (hold boost after
   the dash: ground skating with lean + air glide), assault boost (after 1.2 s hold; ≤70°/s turn),
   air (jump with 2–4 f anticipation, hover/ascend while holding jump), flight (double-tap jump in the
   air; 3D flight relative to camera look; descend action; exits at EN 0 into a glide), landing
   (light < 25 m drop; heavy ≥ 25 m: 0.25 s recovery, dash-cancel from 8 f), locked (combat
   `lock_movement`), lunge (`lunge_to`). Movement is camera-relative via `Game.camera_rig.yaw_basis()`.
4. **Energy / OD**: EN rules SPEC §4 (regen delay, Outage); OD 0–100 with the gain rules in
   skills-catalog §4.1 exposed as `add_overdrive(pct)`; emits `Events.energy_depleted`.
5. **Damage pipeline**: `take_hit(hit)`: invulnerable → if the hit came during dash i-frames from an enemy
   attack → perfect dodge (`Feel.play(&"perfect_dodge")`, `Feel.slow_mo(0.3, 0.35, 0.03, 0.15, true)`,
   `Events.perfect_dodge`, +3 % OD) and no damage; else run damage filters in order (first `true` wins);
   else apply to HP (10,000), knockback, `Events.player_damaged`, `Feel.play(&"hurt_light"/&"hurt_heavy")`
   (heavy ≥ 600 dmg), OD gain from damage taken; HP 0 → `Events.player_died` (not with `--god`).
6. **Full PlayerMech API** of CONTRACTS §5 incl. `telemetry()` (keys: state, speed, vx, vy, vz, x, y,
   z, en, od, hp, grounded, flying, boosting, invuln, dash_chain) and `debug_teleport`.
7. **Feel + events**: call `Feel.play` with the FEEL ids at the right moments (dash, boost_start,
   assault_boost, jump, land_light, land_heavy, footstep_heavy) and emit the movement Events.
8. **Placeholder model** (`player/model/placeholder/placeholder_model.tscn`): a 16 m blocky mech from
   primitives (head, chest, waist, arms, legs, backpack, two wing plates, rifle on the right hand, shield
   on the left forearm) in the hero colours (white #E9EDF2, cobalt #1F4FC8, amber #F2A33A, cyan glow
   #4FE6FF), implementing the full HeroModel API with simple procedural motion (leg swing by speed,
   lean into acceleration, hover/flight pose, dash pose, landing crouch, thruster glow by level, wings
   open by `set_wings`). Sockets as named Marker3D.
9. **Debug camera** (`player/mech/debug_camera.gd`): simple follow camera used only if `Game.camera_rig`
   is null (so your captures work before camera-aim lands).

## Done when (run these yourself; paste results in status)
- `tools/godot.sh check --only=res://player/` → 0 errors.
- `tools/godot.sh test res://player/mech/tests/test_locomotion.gd` passes, asserting in the sandbox:
  run speed 28 ± 1 m/s reached in ≤ 0.4 s; dash 18 ± 2 m in 0.30 s, costs 110 EN, i-frames exactly the
  first 12 ticks; 3 chained dashes then lockout; jump apex 7 ± 0.7 m; hover drains 90 ± 5 EN/s; flight
  toggles on double-tap and cruises 50 ± 2 m/s; assault boost after 1.2 s hold reaches 110 ± 3 m/s; EN
  regen starts after 0.45 s; Outage pause 1.6 s; drop from the 40 m deck = heavy landing; the 19° deck
  ramp is climbable at run speed; a hit during i-frames triggers perfect dodge and no damage; a damage
  filter returning true blocks the hit.
- `tools/godot.sh drive --sandbox --timeline=res://player/mech/timelines/tour.json --shots=...` runs a
  45 s tour (run, dash chain, slide, assault boost along the runway, jump + hover onto the deck, flight
  over the sky bridge, heavy landing) with 0 errors; 8 captures in `captures/mech-move_*.jpg`; a 60 fps
  movie `tools/godot.sh movie --movie=/Users/minimax/m/mecha-city/captures/mech-move_tour.avi ...`.
- Status file lists every tuning choice you made beyond SPEC.
