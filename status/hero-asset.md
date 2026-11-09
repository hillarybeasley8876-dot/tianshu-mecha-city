# hero-asset status

## Done (r3 — lead review r2 polish)
- **Cadence (r2 answer 2)**: `HeroLegs.MAX_PELVIS_DROP` 0.60 → **1.00 m**, which raises the lead cap
  from 3.38 m to **4.15 m** (the horizontal leg of the reach triangle on the 8.26 m leg), and the
  ground blend now hands over to the bound above 6 m/s instead of 9 (`BLEND_GROUND` (0, 6, 16),
  `HeroLegs.WALK_FULL`). `native_speed`, the stride, the foot-height floor and the cadence floor all
  read the **mixed** walk/run metrics (`HeroLegs.cycle`, `bound_mix`) so they agree with what the
  blend space is really showing. Result: the walk at SPEC §4's 9 m/s runs at **1.35×** (was 2.46×)
  on a **6.7 m** stride (was 4.3 m), the bound at 16 m/s at 1.35× on 7.3 m. New gate in the suite:
  playback ≤ 2.0×.
- **Joint fillers (r2 answer 3)**: 20 % smaller (`JOINT_SCALE` 0.80), the sphere is now 24×14
  (was 16×10, 288 → 624 tris each) so it stops reading as a faceted ball, and the material is
  **anodised gunmetal** — base (0.19, 0.20, 0.23), metallic 0.45, roughness 0.36 — instead of the
  near-black (0.10) metal 0.92 that only mirrored the sky and went black from the side. A
  procedural **ring/panel-line normal map** (`HeroJoint_nor_gl`, 256×128, 4 latitude grooves ×
  6 longitude seams, generated in `hero_parts._joint_normal_image` so the build stays hermetic) is
  wired onto the sphere UVs (`create_uvsphere(calc_uvs=True)`); it exports next to the GLBs as
  `hero_HeroJoint_nor_gl.jpg`. The balls now show a specular band and machined rings instead of a
  silhouette.
- `hero_gallery.gd`: `--hero-look=<x,y,z>` aims the capture lens at a joint, for the close-ups.
- Kept the local `blender/hero/hero_lib.py:export_glb` copy (r2 answer 4).

## Done (r2 — lead review r1 + robustness audit)
- **Robustness audit (`reviews/hero-asset-audit.md`), all three findings**:
  1. *hit_pause never reached the model* — `hero_model.gd` now takes a creep fraction
     (`hit_pause(seconds, creep = 0.05)`): the game default creeps the tree at 5 % of the player clock
     (the player is the attacker or the parrier at every call site) and does NOT vibrate, while
     `creep = 0.0` holds the pose dead still and shakes the mesh for the capture galleries. The forward
     from `PlayerMech.hit_pause` is mech-move's file — see Requests 1. Regression: the thigh turns
     1.43°/8 frames creeping vs 7.9° free, no vibration; creep 0 freezes and shakes.
  2. *Thruster directions used raw inside the bone frame* (jets 58–143° off, calf jets firing up the
     legs) — `hero_fx.gd` converts `dir` and `up` through the bone's inverse basis before handing them
     to `ParticleProcessMaterial.direction` and to the cone's basis, via one guarded helper that
     reports a missing bone instead of indexing −1. Regression: all six jets and nozzles are now
     0.0° off the authored direction (was 58–143°).
  3. *Glow plates kept the bone rotation* (the chest "core" was a 0.2 m fin sticking out of the chest,
     the visor a slab through the head) — the plate now gets `Transform3D(bone_basis_inv, position)`.
     Regression: both plates keep the mech's axes, 0.0° off.
  Also split the 456-line `hero_rig.gd`: thrusters, nozzles and the glow moved to a new `hero_fx.gd`
  (218 lines), leaving the rig at 314 lines with sockets, weapons, wings and the aim chain.
- **Locomotion, per the art call** (`hero_legs.gd` + `hero_step.gd`):
  - **Speed-matched playback**: `build_hero.py` now measures every locomotion loop on the posed 16 m
    armature and emits `hero_loco.gd` (cycle, native stride, native ground speed, contact fraction,
    lowest ankle height). Measured: idle 15.30 s / 1.68 m / 0.11 m/s, walk 2.33 s / 6.39 m /
    2.74 m/s, run 1.23 s / 7.59 m / 6.15 m/s. An `AnimationNodeTimeScale` ("rate") between the loco
    machine and the action layer is driven with `v / v_native`, so actions keep the game clock.
  - **Stride warping**: two `TwoBoneIK3D` modifiers (L/R Thigh→Calf→Foot, pole markers in front of
    the knees) run after the AnimationTree and before the aim chain. Each foot has a footstep planner
    (`HeroStep`): the clip keeps the rhythm (the ankle's fore/aft offset from its own hip says
    stance vs swing), the stride comes from the real ground speed, and the plant is held at **one
    world point** from touchdown to lift. The swing lands the foot where the body will actually be;
    the animation still supplies the arc height.
  - **Pelvis drop** ≤ 0.60 m keeps the knees bent; the lead a foot may be planted is capped by the
    legs' reach (`max lead 3.38 m`), so the IK is never asked for a target it must drag toward.
  - **Run = thruster-assisted bound**: the run clip is retimed in Blender so ground contact is 30 % of
    the cycle (airborne glide between steps, `BOUND run: contact 27/38 frames -> flight x5.73`), a
    12° forward lean is applied over Waist/Spine01/Spine02 above 12 m/s, and the backpack nozzles
    pulse at every push-off (`HeroRig.set_bound_jet`, separate from the gameplay thruster level).
- **Idle stance** (must-fix 2): the IK plants both feet at 1.3× hip width with the knees over the
  toes, the pelvis keeps a slight crouch, and a 2.5° / 0.22 Hz breathing sway runs on the waist. The
  bow-legged wrestler stance is gone — the raw clip's feet are ~4 m outboard of the hips.
- **Shield at rest** (must-fix 3): the kite shield was mounted upside down (its point, at the prop's
  -Z, was mapped to world +Z), which left its wide end stuck out at hip height. `build_shield` now
  maps +Z to +Z, so it hangs along the left forearm with its long axis vertical, clear of the thigh.
- **Feet on the ground**: the walk/run clips float the ankle ~1 m above the rest height; the IK
  rebases the animation's own arc so the lowest foot sits exactly on the ground plane (1.66 m ankle).
- **Test**: `test_hero_model.gd` **193 checks, 0 failed**, including the three new gates and the four
  audit regressions.
- Weapons integration re-run on the rebuilt model: hailstorm alternates the shoulder rails,
  `DRIVE done t=12.0 errors=0`.
- Scripted fight with the NaN watch: `tools/godot.sh drive --timeline=res://enemies/tests/
  fight_timeline.json --nan-watch` → `DRIVE done t=36.0 errors=0`, no NANWATCH reports (the three
  warnings are the audio unit's missing `enemy_telegraph/stagger/death` ids).

## In progress / next
- Nothing in flight. The open art questions are in Known issues / Requests.

## How to verify (exact commands)
```
tools/blender.sh run blender/hero/build_hero.py                        # rebuild (84 s), prints LOCO/BOUND/JOINTS
tools/godot.sh check --only=res://player/model/hero/                   # 0 errors
tools/godot.sh test res://player/model/hero/tests/test_hero_model.gd   # 195 checks, 0 failed
tools/godot.sh test res://player/model/hero/tests/hero_foot_trace.gd   # writes tmp/hero-asset/r2/*.csv
uv run --with matplotlib python3 tmp/hero-asset/plot_foot_trace.py     # captures/hero_foot_*.png
bash tmp/hero-asset/capture_r3.sh                                      # walk/run strips + knee/elbow close-ups
tools/godot.sh drive --scene=res://combat/weapons/tests/integration.tscn \
  --timeline=res://combat/weapons/tests/timeline_integration.json --sandbox --debug
```

## Evidence (paths, numbers)
- `captures/hero3_walk_strip.jpg`, `captures/hero3_run_strip.jpg` — 8 frames per cycle, side view,
  the mech really driving across the sandbox at 9 / 16 m/s on the new cadence.
- `captures/hero3_knee_strip.jpg`, `captures/hero3_elbow_strip.jpg` — side close-ups of the fillers
  mid-stride: gunmetal with a specular band and the machined ring pattern, not a black ball.
- `captures/hero3_rest_front34.jpg` / `_side` / `_rear34` — the hip fillers at gameplay distance.
- Test gates after the change: walk at 9 m/s **1 % / 0 %** slide of a 6.7 m stride (gate 10 %,
  playback **1.35×**); run at 16 m/s **0 % / 0 %** of 7.3 m (gate 15 %, 1.35×); both under the new
  2.0× cadence gate; knees max 170° / 163° (gate 175°); lowest foot 1.66 m.
- Leg geometry: ground ankle 1.66 m, leg 8.26 m, half hip 1.12 m, **max lead 4.15 m** (was 3.38 m).
- Weapons integration on the rebuilt model: `DRIVE done t=12.0 errors=0`, hailstorm alternating the
  shoulder rails at x −2.81 / +0.65 (3.46 m apart, the pod spacing).

- `captures/hero_foot_walk.png`, `captures/hero_foot_run.png` — foot world travel at 9 and 16 m/s,
  before (raw Tripo clip at 1.0×: both feet move continuously) and after (flat planted stretches).
- `captures/hero_walk_strip.jpg`, `captures/hero_run_strip.jpg` — 8 frames per cycle, side view, with
  the mech really driving across the sandbox (`--hero-drive`).
- `captures/hero_rest2_front.jpg`, `captures/hero_rest2_rear.jpg` — idle stance, long lens.
- `captures/hero_shield_rear34.jpg` — shield hanging vertically on the left forearm.
- Test gates: walk at 9 m/s **0 % / 1 %** slide of a 4.3 m stride (gate 10 %, playback 2.46×);
  run at 16 m/s **0 % / 0 %** of a 6.6 m stride (gate 15 %, playback 1.46×); knees max 171° / 163°
  (gate 175°); lowest foot 1.66 m (ground plane, gate −0.05).
- Leg geometry: ground ankle 1.66 m, leg 8.26 m, half hip 1.12 m, max lead 3.38 m, pelvis bone Pelvis.
- Weapons: `INT fired hailstorm muzzle (2.25, 21.83, 59.02)` / `(−1.86, 21.88, 58.75)` — alternating rails.
- `captures/hero_thrust_rear34.jpg`, `captures/hero_thrust_side.jpg` — all six plumes blowing away
  from the body after the audit fix (the calf jets used to fire up the legs).

## Known issues
1. Between 6 and 9 m/s the ground space crossfades two loops of different length (walk 2.33 s, run
   1.23 s) at one playback rate, so the shorter one laps inside the longer. `HeroLegs` reads the
   *mixed* metrics so the planner and the slide gate agree with what is on screen, and the slide gate
   holds at 9 m/s, but the raw blend is still two cycles beating against each other. A dedicated
   mid-speed clip (or retiming the walk) would be the clean fix.
2. The walk stride is 6.7 m on a 16 m mech — the largest the 4.15 m lead cap allows at the mocap
   cadence. A longer stride would need a still deeper pelvis drop.
3. The joint fillers read as machined ball joints now, but at the elbow the forearm armour is narrow
   enough that the ball still stands proud of the plate. Shrinking further would reopen the gap the
   fillers exist to cover.
4. The stride uses the mech's **measured** ground speed, not the state's speed: a mech walking into a
   wall plays the raw clip instead of skating.
5. Carried over from r1 and unchanged: alignment residual 4.5 cm; aim asymmetry past ±60°;
   `land_heavy` 2.18 s against a 0.38 s landing state; LOD1 mirrors the animated pose only.

## Requests (to the lead / other units)
1. **mech-move**: audit finding 1 is only half fixable from here — `PlayerMech.hit_pause`
   (game/player/mech/player_mech.gd:342) still forwards only to `MechLocomotion`, so no live hit-stop
   reaches `HeroModel.hit_pause`. Please add
   `if _model != null and is_instance_valid(_model) and _model.has_method(&"hit_pause"): _model.call(&"hit_pause", seconds)`
   (the default creep 0.05 is what the game wants; the gallery passes 0.0 explicitly).
   **melee-defense**: `MeleeSystem._advance` has to hold for the same span, or the saber keeps
   sweeping while the arm creeps.
2. Closed by r2 answer 2 (pelvis drop 1.0 m, walk→bound above 6 m/s): the walk is back inside the
   1.35× preferred rate on a 6.7 m stride.
3. Closed by r2 answer 3 (joint fillers: 20 % smaller, anodised gunmetal, ring normal map).
   Open follow-up is Known issue 3 — is the elbow ball standing proud acceptable, or should the
   forearm plate be widened instead?
4. `blender/lib/export.py`: still no access to the glTF animation-size options or a `force_jpeg`
   flag; `blender/hero/hero_lib.py:export_glb` keeps its local copy (r2 answer 4: keep for now).

