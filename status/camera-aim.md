# camera-aim status

## Done
- **r8 review (this session) — the pad's D-pad ← / → now switches the hard lock.** Details in
  "r8 review — what changed" below.
- **r7 review — three items, all landed.** Details in "r7 review — what changed" below:
  1. **First person no longer films the mech's own chassis** (the trailer's `s05_fp` black frame).
  2. **A real-flow regression test for the camera parking** after the flow's cinematic (the park itself
     does not reproduce in the current tree — measured four ways, see below).
  3. **Flight framing** (lead add-on): the rig keeps a flying mech in frame.

### r8 review — what changed this session

**Re-check first (as asked).** At HEAD `acc1e75` the defect is still live:
`grep -rnw --include='*.gd' --exclude-dir=.godot -e lock_next -e lock_prev game` returns only
`core/input_setup.gd`, `core/pad_input.gd` and `ui/hud_glyphs.gd` — no consumer. Nothing in
`player/aim/` had changed since `b5d26d4`. Confirmed by running the lead's probe on the unmodified
tree before touching anything (see Evidence).

**1. [major] D-pad ← / → never switched the hard lock — FIXED**

- **Consumer added in `AimSystem`** (`player/aim/aim_system.gd`), beside the `lock_on` read, so the
  `test_aim` sandbox reaches it (the verifier's suggestion). `_read_switch_input()` runs after
  `_update_hard` in `_physics_process` and calls the **existing** `switch_target(±1)` — there is no
  second selection anywhere.
  - `Input.is_action_just_pressed(&"lock_next" / &"lock_prev")`. PadInput holds the action for as long
    as the button is down, so the just-pressed edge is the press: a 0.25 s hold switches once and fires
    exactly one `Events.lock_changed` (→ one `lock_on` sound + one `ai_target_locked` voice line,
    `audio/event_router.gd:186`). Measured: `held on 12 tick(s)`, `lock_changed events +1`.
  - **Gated on `hard_target() == null`** — with no lock a press changes nothing and acquires nothing.
  - **Gated on `_cinematic()`** (the rig's `is_cinematic()`), because that is exactly where both flick
    paths are dead: `camera_rig.gd` returns before `_update_look`, and `camera_cinematic.gd:56`
    disables the look channel.
  - `switch_target`'s comment now names both callers and states that KB+M switching stays the mouse
    flick and that the wheel is weapon swap.
- **The keep cone was undoing the switch on the next tick.** `switch_target` has no cone limit on its
  pool, but `_update_hard` drops a lock outside ±30° yaw (`HARD_CONE_YAW_DEG 40 × 0.5 ×
  HARD_KEEP_SCALE 1.5`). Measured on the lead's own probe: the D-pad LEFT pick landed at **−32.05°**
  and was dropped one tick later, so the probe still failed with the consumer in place. Fixed with
  `SWITCH_GRACE = 0.35 s`: after a *deliberate* switch the cone test is suspended while the lock
  framing (9 rad/s) turns the view onto the new target. The cone is about where the player is
  *looking*; it is not a verdict on a target the player just selected. LOS, range and death still drop
  the lock during the grace. **This is the rule the lead said they would pick after this round — it is
  implemented because the gate cannot pass without it, and it is the one behaviour change to the flick
  path as well (a flick to a far-off target now sticks instead of being undone).** See Requests 5.

**2. [minor] `CameraRig.eye_residual()` — the line for CONTRACTS §3 is in Requests 0g below.** No code
change.


### r7 review — what changed this session

**1. First person goes black ~1 s after `camera_toggle` (`tl_s05_fp.json`) — FIXED**

Traced with a new windowed harness (`player/camera/demo/rig_probe.tscn`, wraps `main.tscn`):
- It is **not** the blend's end state, the arm, the near plane, the canopy, the post stack, ScreenFx /
  Feel, the HUD, the enemies or the city: each was ruled out by measurement
  (`--fp-hide`, `--fp-keep`, `--stub=feel,hud,enemies`, `--no-post`, `--fp-nofx`, `--no-enemies`).
- The rig's position and orientation are **identical** at the clean frame and the black frame
  (`tmp/camera-aim/orient.csv`: yaw −180, pitch −6, shake (0,0,0), forward (0,0,1) at t=3.0 and t=4.0).
- The trigger is **`fire`**: the same timeline without `fire` stays clean for the whole 6.4 s
  (luma 0.108 at t=3/4/6); with `fire` it goes black between t=3.0 and t=3.1 every run.
- `--fp-keep=World` (hero + canopy hidden) is clean, `--fp-keep=CameraRig` (world + hero hidden) is
  clean, `--fp-hide=<every canopy mesh>` is still black ⇒ **world + hero** is the pair that blacks out,
  and the canopy is not involved.
- **Cause:** in the cockpit the lens sits 1.2 m in front of the model's `cockpit` socket — inside the
  mech's own head — and `Hero3Aim` solves the weapon onto the aim line, which in first person *starts
  at the lens*. The moment the trigger is held the gatling is swung across the canopy. `muzzle_r`
  measures 6.0 m from the lens at that moment (`PROBEDUMP`), i.e. the weapon is held right in front of
  it. The hero's body is ONE rigid-skinned mesh (`Hero3Body`) plus three weapon nodes
  (`Hero3Saber` / `Hero3Rifle` / `Hero3Shield`, `hero3_rig.gd:16`), which is why a per-node AABB scan
  25 m around the lens found nothing new.
- **Fix — `player/camera/camera_hero_cull.gd` (new, 55 lines):** the hero's `VisualInstance3D`s move to
  one dedicated visual layer (bit 18; free — no `.tscn` in the tree sets `layers`) and the rig clears
  that bit from `_cam.cull_mask` above `first_person_blend() > 0.5`. A cull mask, not `visible = false`,
  because hero-v3 shows and hides its own weapon nodes from its own tick (`set_saber_drawn`, the rifle
  swap) and would undo the flag. Only THIS camera is affected: the trailer's cinematic cameras, the
  canopy HUD's SubViewport, `player/mech/debug_camera.gd` and every shadow keep the default mask.
- **Proof:** `captures/camera-aim_fpfix_t{1,2,3,4,6}_0.jpg` — the same repro, now 0.205 / 0.185 / 0.181
  / **0.238** / 0.181 mean luma (was 0.110 / … / **0.039** / 0.040). `tmp/camera-aim/fpfix.csv`:
  559 first-person ticks, **0 frames under 0.02 luma**.

**The lead's first-person gates, measured** (`demo/timeline_fp_run.json`: `camera_toggle`, walk, boost,
dash, jump, a 3-hit melee combo, ~7 s of gatling fire, guard, flight entry, a second weapon and ADS, in
the city at `--tod=0.6` and at `--tod=0.0`; `demo/rig_probe.tscn --probe-luma=1` logs every tick):

| gate | day (`final_day.csv`) | night (`final_night.csv`) |
|---|---|---|
| 30 s first-person run, frames under 0.02 mean luma | **0** of 3553 ticks (min luma 0.096) | **0** of 3551 (min 0.118) |
| eye vs the model's `cockpit` socket, ≤ 0.2 m | **max 0.180 m, 0 ticks over** | **max 0.180 m, 0 ticks over** |
| ACCEPTANCE §3 cockpit frame coverage | **17.2 %** (limit 18 %) — `test_camera` | same geometry |
| SPEC §5 blend 0.35 s, holds the aim point | **42 ticks** both ways, aim point within **0.024** of the reticle — `test_camera_cockpit` | — |

Contact sheets: `tmp/camera-aim/fp_final_sheet.jpg`, `tmp/camera-aim/fp_final_night_sheet.jpg`
(captures `camera-aim_fp_final_t*.jpg`, `camera-aim_fp_final_night_t*.jpg`).

The eye gate needed one change to pass honestly. The bob filter that damps the gait's step bob out of
the first-person eye (hero-v3 r5 item 8) could carry the camera up to
`EYE_BOB_MAX × (1 − EYE_BOB_KEEP)` = 0.39 m off the socket. `camera_blend.gd` now caps the correction
at `EYE_OFFSET_MAX 0.18 m` and restarts the baseline from the capped value, so travel (a climb, a dive,
a heavy landing) passes through almost whole — which is what it should feel like — while the small step
bob is still damped to a swell. `CameraRig.eye_residual()` records the number **in the tick that places
the camera**: the hero's `Skeleton3D` moves its `BoneAttachment3D` sockets on the idle frame, so any
outside sampler reads the socket a frame late and reports up to 1 m of the model's own landing crouch
as camera error (measured — it is why the first three attempts at this number looked wrong).

- **2. The camera parks after the flow's cinematic — NOT REPRODUCIBLE; regression test shipped**

Measured four ways in the current tree, all with `--skip-menu` and the real flow (no `--stub=flow`),
`--god --tod=0.6`, walking the hero for 8 s and logging the rig every tick
(`tmp/camera-aim/{flow,flow2,drop,movie}.csv`):

| run | flags | result |
|---|---|---|
| `drive` | `--spawn=-200,39.5,-260,180 --no-enemies` | follows: `follow_err` 3.07 m (the spring's own 2v/ω at 16 m/s), hero at 0.751 of the frame height the whole run, `cine` false throughout |
| `drive` | `+ --enemies=ripper:6,mantis:2` | same, `errors=0` |
| `drive` | no `--spawn` (the real 400 m drop-in) | `cine` true during the fall, false from t=6.0, `follow_err` 0.14 m, hero at 0.773 |
| `movie` | the trailer's own capture path (`--write-movie --fixed-fps 60`) | follows, `follow_err` 3.07 m |

So `end_cinematic()` does hand the view back on every path the trailer uses. What I could not do is
prove the trailer's report wrong, so the deliverable is the regression the lead asked for:
**`player/camera/tests/test_camera_flow.gd`** builds the **real** `flow/game_flow.tscn` over the **real**
`camera_rig.tscn` (not `flow/tests/flow_fake_rig.gd`), parks `GameFlow._title()`'s 100 000 s vista on
the rig, lets the flow's own `_enter_tutorial()` call `end_cinematic()`, and gates on the lead's
numbers. **10/10 PASS**; against the pre-audit-#2 `end_cinematic()` (restoring look/arm but never
cancelling the shot list) it fails **6/10** with the rig **102.86 m** off its follow position and the
arm at 0 — i.e. it reproduces the reported symptom exactly.

**3. Flight framing (lead add-on, mech-move request 6) — DONE**

`player/camera/camera_flight.gd` (new, 96 lines): one 0→1 factor, in over 0.30 s and out over 0.45 s,
engaged while `PlayerMech.is_flying()`. It spends that factor on four things:
- **a velocity lead on the follow pivot** of `2/ω` seconds, which cancels the critically damped
  spring's steady-state ramp lag exactly (24 m at 84 m/s on the ω 7 boost spring), so the pivot rides
  ON the mech. That is also what keeps the arm's occlusion probe spanning camera → hero instead of
  camera → where the hero was;
- **a dead-zone pitch follow** (`DEAD 0.12` of the frame's half-height, `PITCH_RATE 70 °/s` at full
  excess): the player's own aim is untouched until the mech is genuinely leaving the frame;
- **a speed-scaled arm**, 44 m at cruise → 52 m at `flight_boost_speed` 84 m/s;
- **a 60 m/s arm push-out** through `CameraArm.set_push_bonus`, because a pillar passed at 84 m/s is
  gone in 0.05 s and the SPEC §5 recovery rate of 10 m/s left the hero small for 4 s.

Gate (`tmp/camera-aim/flight_{sandbox,city}.csv`, the hero's screen bbox and the camera → chest sight
line logged every tick, both runs `errors=0`):

| run | hero height on screen | off-frame ticks | sight line blocked | follow lag |
|---|---|---|---|---|
| `res://player/mech/timelines/flight.json --sandbox` | **min 25.2 %**, max 42.3 % | **0** of 1025 | **0.000 s** | ≤ 3.75 m |
| `demo/timeline_flight_city.json`, the city at `--tod=0.6` | **min 25.3 %**, max 42.8 % | **0** of 875 | **0.000 s** | ≤ 1.64 m |

Contact sheets: `tmp/camera-aim/flight_sandbox_sheet.jpg`, `tmp/camera-aim/flight_city_sheet.jpg`
(captures `camera-aim_flight_{sandbox,city}_t*.jpg`). Before/after against mech-move's own strip
(`captures/mech-move_flight_t4_9.jpg`, `t5_9.jpg`): the hero was small, near the frame edge and behind
pillars; it is now 25–43 % of the frame height and centred-left of the reticle in every frame.

**Ground behaviour is untouched**, pinned by three control checks in the new suite (arm still 42 m,
flight factor 0, the pitch is the player's alone).

**Structure**: the flight channel and the first-person cull are two new sibling modules, and the
pivot/arm/spring-rate geometry moved out of the rig into `camera_follow.gd` — the rig is 418 lines
(was 460), and no file in the unit is over 418.

### For the trailer
- **First person now films.** `--pulse=camera_toggle@1.4` (or `tap camera_toggle` in a timeline) with
  `--stub=flow` and a `--spawn` films the cockpit with the gatling firing; the eye no longer ends up
  inside the mech's own weapon. `captures/camera-aim_fpfix_t4_0.jpg` is the frame the old `s05_fp`
  take went black on.
- **The un-stubbed flow works.** Every gameplay take can drop `--stub=flow`: measured with
  `--skip-menu --spawn=… --enemies=ripper:6,mantis:2` in both `drive` and `movie`, the rig follows the
  hero for the whole run (`tmp/camera-aim/{flow2,movie}.csv`). If a take still parks, it is not
  `end_cinematic()`; send me the exact flags and I will chase it.

- **CameraRig** (`player/camera/camera_rig.tscn`): third person and first-person cockpit, 0.35 s blend
  that keeps the aim point, registers `Game.camera_rig`, critically damped follow spring (10 rad/s walk,
  7 boost, 14 dash), lock-on camera tracking (9 rad/s), `request_cinematic`, `end_cinematic`,
  `occluder_fade`, `set_override_fov`, `hud_state()`.
- **Modules** (all ≤ 410 lines, one job each): `camera_look.gd`, `camera_arm.gd` (probe + occluder
  fade), `camera_shake.gd`, `camera_fov.gd`, `camera_cinematic.gd` (duel frame), `camera_feel.gd`
  (Feel/Events switchboard), `cockpit_frame.gd` + `cockpit_build.gd` + `cockpit_glass.gdshader`.
- **AimSystem** (`player/aim/aim_system.tscn` + `target_query.gd`): crosshair ray from the camera,
  `aim_dir_from` parallax, soft lock (7° mouse / 10° pad, ≤300 m, LOS, lead, pad slowdown), hard lock
  (≤450 m, flick switching, LOS grace, `Events.lock_changed`, `lock_to`), `targets_in_view`, `hud_state()`.

### r2 review — what changed this session (the single MUST-FIX: framing)
1. **Third-person framing rebuilt to the lead's decision (framing wins, SPEC §5)**:
   `ARM_LENGTH 22 → 42 m`, `SHOULDER 8.3 → 12 m`, `ARM_BOOST 24/26/30 → 46/48/52`, new
   **`ARM_ADS 28 m`** blended on the FOV channel's own 0.25 s in / 0.40 s out ramp
   (`camera_fov.ads_blend()` → `CameraRig._arm_target()`, used by the tick, `end_cinematic()` and
   `_snap_to_player()`). Measured through the live camera on the real hero in `main.tscn`
   (`measure_framing.gd`): **height 39.3 %** (want 36–44), **body centre 31.7 %** of the width
   (want 31–37), **crosshair clearance 7.9 %** (want ≥ 6) — the 90 %-of-frame hero of r1 is gone.
   SPEC says "≈ arm 40 m"; 42 m is what centres the band once the body's 13.5 m of depth is projected
   (40 m measures 43.9 %, hard against the top of the band), and the boost offsets keep the review's
   deltas (+4/+6/+10).
2. **Test bands repinned** to the review's numbers (`HEIGHT_BAND 0.36–0.44`, `CENTRE_BAND 0.31–0.37`,
   `ARM_FULL 42`, `ARM_ADS 28`) and three new assertions: ADS arm = 28 m, ADS FOV = 38°, arm returns
   to 42 m after release. The framing test now snaps the rig (`snap_to_player`) instead of waiting out
   a 4 s arm push-out; the mode-toggle round trip waits 600 ticks for the same reason.
3. **Aim test rebuilt around the aim ray**: the camera now sits 12 m right of the mech's centreline, so
   world-axis dummies land 4–8° off the reticle at test range. `_spawn_targets()` places the five
   dummies by angle/distance from the live ray (`_on_axis(yaw, pitch, dist)`), the first-person check
   spawns its own dummy on the cockpit axis (the cockpit is on the centreline, 12 m off the third-person
   ray), and the off-cone check turns 60° instead of 30° (a 30° swing only moves the near dummies ~20°
   because the camera orbits at 42 m).
4. **Re-captured** third_idle / third_run / third_ads / lock_far / wall_noclip and the 6 tour frames.

### Earlier sessions (still standing, verified again this run)
- Cockpit rebuilt: thin gunmetal plates with 1.2–1.5 cm cyan trim, raked console across the bottom
  91–98 % of the frame, fresnel+dust glass capped at alpha 0.08, coverage 17.2 % (limit 18 %).
- Aim ray starts at the arm tip (the camera's un-shaken position) so it passes exactly through the
  reticle; `test_aim` asserts the aim point projects to (0.500, 0.500).
- Duel-frame cinematics (`{offset, look, fov, t}` around the hero↔target midpoint), collision-resolved
  shots, neutralised rig yaw/pitch, `end_cinematic()` restores look input, FOV, arm and basis.
- Occlusion dither (`occluder_fade` + the `camera_dither` group, 1 → 0.3 → 1).
- Real-clock springs (`Feel.real_delta`) so the camera keeps up in witch time (7.7 m lag either way).

### Audit round (reviews/camera-aim-audit.md, 8 findings) — all fixed, all with a regression check
1. **#1 [high] stick look double-converted to real time** (`camera_look.gd:61`): the rig already passes
   `Feel.real_delta(delta)` into `take_delta`, which multiplied by `_real_dt()` again. Deleted
   `_real_dt()`; the stick term now multiplies by the `delta` it is given. Pre-fix a full stick inside a
   0.05 hit-stop turned 120° in 24 ticks, now 60.0° — the same as at 1.0 time scale.
2. **#2 [high] `end_cinematic()` did not end the cinematic** (`camera_rig.gd`): it now calls
   `CameraCinematic.cancel()` (new: clears `active`/shots, never calls back into the rig, so
   `_finish()` → `end_cinematic()` cannot recurse), releases the held FOV and restores arm + look in
   that one call, per the lead's CONTRACTS §5 decision. `set_look_enabled()` now flushes buffered mouse
   motion on re-enable as well as on disable. A 30 s request cut after 4 ticks leaves `is_cinematic()`
   false, FOV 55, arm 42 m and no re-applied shot (pre-fix: still active, FOV 48, arm 0 m).
3. **#3 [medium] execution shots ran on the wrong clock**: `request_cinematic(shots, duration, clock)`
   with `clock := &"real"` (default, unchanged for flow/boss/victory) or `&"player"`
   (`CameraCinematic.player_clock`; the rig feeds `advance()` `Feel.player_delta`). Under a 0.3x slow-mo
   a 0.2 s real-clock shot ends inside 40 ticks and the player-clock one is still running.
4. **#4 [medium] the cockpit view lagged the body**: `_follow()` now blends the rig onto the eye point
   with `smoothstep(0.5, 1.0, fp_t)` after the spring step and feeds the target's velocity forward.
   Worst lag at the 42 m/s skate: 1.75 m → 0.00 m (the canopy is visible from 0.5, so the blend starts
   there — snapping only at 1.0 would jump up to 4 m and re-start the spring from rest).
5. **#5 [medium] yaw whip on a near-vertical hard lock**: the yaw step is scaled by
   `smoothstep(0.15, 0.35, flat / |to|)`; the pitch term is unchanged. A target straight overhead leaves
   the yaw alone and a target crossing the vertical steps ≤ 0.0°/tick (pre-fix: 13.0°/tick, and a 180°
   swing for a target held overhead).
6. **#6 [low] `invert_y` inverted the aim assist**: `_pitch_deg - d.y * invert - assist.y`. With invert on
   the assist now pulls the same way (30.0° vs 30.0°; pre-fix −30.0°).
7. **#7 [low] canopy yaw-lag not reseeded**: on the hidden→visible edge `_yaw` is seeded to the live view
   yaw and `_damage` to 0. Worst error on entering first person: 107.5° → 0.0°.
8. **#8 [low] canopy lag on scaled delta**: `var dt := Feel.real_delta(delta)` for both the lag factor and
   the damage decay. Behind a 240°/s turn in 0.3x slow-mo: 52.8° → 17.2° (the designed 80 ms).

**Structure**: the audit pushed `camera_rig.gd` to 451 lines, so the 1st/3rd cross-fade moved to a new
sibling module `camera_blend.gd` (71 lines: mode state, the aim-preserving offsets, the cockpit eye
point), matching the existing Look/Fov/Arm/Shake/Cinematic split. Rig back to 418.

**Evidence**: every check in `tests/test_camera_audit.gd` was re-run against the pre-fix line
(`tmp/camera-aim/revert.py` reverts one finding at a time) and each one FAILS there — see the numbers
above. Scripted fight `tools/godot.sh drive --timeline=res://enemies/tests/fight_timeline.json
--nan-watch`: `errors=0`, no NANWATCH lines, 3 warnings, all audio ids another unit has not shipped
(`enemy_death`, `enemy_stagger`, `enemy_telegraph`); the player took 10000 → 7465 HP, so hit-stops and
slow-mos ran through the fixed clocks. `captures/camera-aim_t3_0.jpg` (third person) and
`captures/camera-aim_t3_5.jpg` (cockpit) re-checked by eye: framing and canopy unchanged, no clipping.

### r5 review — what changed this session (CONTRACTS §5 "Large-target framing")
1. **New channel `camera_large.gd`** (75 lines, a `Large` node on the rig): one 0→1 factor eased in
   over 0.45 s when the hard-lock target's ACTOR reports `framing_height() >= 30 m` (CONTRACTS §5; the
   boss is 60) and out over 0.70 s when the lock drops. `Targetable.actor()` (core) is how the rig
   reaches the actor; an actor without the method reports 0 and the street shot is untouched.
2. **Three numbers spend that factor**:
   - arm 42 → **64 m** (`_arm_target()`; large wins over the ADS 34 m pull-in),
   - pivot **+14 m** (`_chest_point()`), because a +12° look-up along a 64 m arm drops the camera
     13.3 m below the 12.5 m pivot — i.e. under the street. Faded out by the first-person blend.
   - lock-tracked pitch **+12°**, so the frame lifts from the locked core toward the boss's head and
     the hero sits at the bottom edge. The offset is part of the TRACKED pitch, so a dropped lock never
     jerks the view: tracking simply stops and the player owns the angle.
3. **The +12° is clamped** (`camera_lock.large_pitch_offset`): a core high on a titan would tip the arm
   far enough to bury the camera, so the offset is limited to keep it ≥ 3 m above the hero's feet.
   No feedback loop — the bearing is measured from the lifted pivot, which the offset cannot move.
   Measured: a mid-body core gets the full 11.8°, a crest core at 60 m gets 5.8° and the camera holds
   y 3.1 m instead of −3.2 m.
4. **`camera_arm.set_push_bonus()`**: the SPEC §5 occlusion recovery is 10 m/s, i.e. 2.2 s for the
   22 m a lock-on asks for. The rig adds 38 m/s while the framing factor is non-zero; the wall/deck
   recovery keeps the plain 10 m/s.
5. **New suite `test_camera_large.gd`** (22 checks, 0 failures) with the contract's 60 m stand-in:
   arm 64.0, pitch bearing + 11.8°, camera never in geometry over the whole reframe (min y 6.1),
   the hero fully in frame (y 0.66–0.95) AND the whole titan feet-to-crest (y 0.46–0.80), the crest
   clamp, the ease back to 42 m / 0° / pivot 12.5, and a 16 m control target that changes nothing.
6. **Rig split again**: the lock tracking (audit #5's near-vertical yaw guard + the new pitch clamp)
   moved out of `camera_rig.gd` into `camera_lock.gd` (45 lines), so the rig is 421 lines rather than
   450 after the feature. Dead `_screen_points` helper removed; `_project_point`, `_corners_of`,
   `_project_box` and `_camera_hits_world` moved to `camera_test_base.gd` for the second suite
   (`test_camera.gd` 476 → 414).
7. **Demo**: `demo_target.gd` implements the contract method `framing_height()` (an exported
   `declared_height` is the number it returns — the rig calls the METHOD) and builds a giant as
   legs + torso + head instead of one slab, so the captures read as a titan. `camera_demo.tscn`
   gained a 60 m stand-in 143 m out (`--lock-titan`).

## In progress / next
- Nothing outstanding from the brief, reviews r2–r8, the audit round or the lead's r7 add-on.
- Not done, and deliberately: the first-person view has no arms or weapon in frame (see Known issues).
  If hero-v3 wants a lowered-weapon cockpit pose instead of the cull, that is their call and one module
  of mine to delete.

### r3 review — what changed this session (the single item: ADS arm)
1. **`ARM_ADS` 28 → 34 m** (`camera_rig.gd`), comment updated with the reason. Re-captured
   `captures/camera-aim_third_ads.jpg`: the whole mech now fits (head no longer clipped at the top), it
   occupies the left quarter instead of the left third, and the crosshair/heat ring sit on clear ground.
2. **ADS test band** (`test_camera.gd`): `ARM_ADS := 34.0`, plus two new assertions measured through the
   live camera — hero height inside `ADS_HEIGHT_BAND 0.76–0.83` and crosshair clearance ≥ 6 % (measured
   79.6 % / 13.9 % clear). `test_camera` is now **74 PASS / 0 FAIL**; `test_aim` 27/0; `check` 21 files,
   0 errors.
3. **The lead's "~60 % height" estimate does not hold at FOV 38** — measured screen height at ADS is
   ≈ 2706 / arm_m %, so 34 m → 79.6 %, 38 m → 71 %, **45 m → 60 %**. Height at ADS is dominated by the
   FOV zoom (tan 27.5° / tan 19° = 1.51), not by the arm: reaching 60 % would mean pushing the camera
   *out* to ~45 m, i.e. dropping the "ADS pulls in" rule. Implemented the constant the lead ordered (34 m)
   and pinned the measured band; the trade-off is in Requests below.

## How to verify (exact commands)
```
tools/godot.sh check --only=res://player/camera/,res://player/aim/     # 36 files, 0 errors
tools/godot.sh test res://player/camera/tests/test_camera.gd           # 0 failures
tools/godot.sh test res://player/camera/tests/test_camera_audit.gd      # 0 failures
tools/godot.sh test res://player/camera/tests/test_camera_feel.gd       # 0 failures
tools/godot.sh test res://player/camera/tests/test_camera_large.gd      # 0 failures
tools/godot.sh test res://player/camera/tests/test_camera_cockpit.gd    # 12 PASS (r7 item 1)
tools/godot.sh test res://player/camera/tests/test_camera_flight.gd     # 18 PASS (r7 item 3)
tools/godot.sh test res://player/camera/tests/test_camera_flow.gd -- --sandbox --flow --spawn=0,1,60
                                                                        # 10 PASS (r7 item 2, real flow)
tools/godot.sh test res://player/aim/tests/test_aim.gd                  # 36 PASS / 0 failures (r8:
                                                                        # 8 of them are the D-pad checks)

# r8 item 1 — the lead's acceptance probe (copy it in, run it, delete the copy: every unit's `check`
# compiles all of res://, and game/tmp/ is git-ignored)
mkdir -p game/tmp/acc
cp ~/m/mc-accept/game/tmp_accept/verify-pad-dpad-lock-switch-dead/acc_dpad_switch.gd game/tmp/acc/
tools/godot.sh test res://tmp/acc/acc_dpad_switch.gd -- --sandbox --no-enemies --skip-menu \
  --stub=flow,boss,post --timeout=800        # DPAD-SWITCH PASS: 3 defect checks, 0 failed (run valid)
rm -rf game/tmp/acc

# r8 captures — the before/after pair. NOTE the pulse offset: `tools/godot.sh shot` times `--pulse` on
# its own absolute clock but `--times` relative to world-ready, so `--pulse=…@3.5` fires ~1 s BEFORE
# the `--times=3.0` frame. `--lock-log` prints the live lock ten times a second so the frames can be
# tied to a target; the pair below was picked that way (t3_7 = Target0, t4_1 = Target1).
tools/godot.sh shot --scene=res://player/camera/demo/camera_demo.tscn --sandbox \
  --out=camera-aim_dpad_switch --times=2.5,2.9,3.3,3.7,4.1,4.5 --lock --lock-log --pulse=lock_next@4.85

P=res://player/camera/demo/rig_probe.tscn   # the windowed harness every r7 number comes from
# r7 item 1 — the repro that used to go black, and the 30 s first-person gate (day and night)
tools/godot.sh drive --scene=$P --timeline=res://player/camera/demo/timeline_fp.json \
  --out=camera-aim_fpfix --skip-menu --god --tod=0.6 --stub=flow --spawn=-200,39.5,-260,180 \
  --enemies=ripper:4 --probe-luma=1 --probe-log=$PWD/tmp/camera-aim/fpfix.csv --shots=1.0,2.0,3.0,4.0,6.0
tools/godot.sh drive --scene=$P --timeline=res://player/camera/demo/timeline_fp_run.json \
  --out=camera-aim_fp_gate --skip-menu --god --tod=0.6 --stub=flow --spawn=-200,39.5,-260,180 \
  --enemies=ripper:6,mantis:2 --probe-luma=1 --probe-log=$PWD/tmp/camera-aim/gate_day.csv
# r7 item 2 — the real flow, no stubs (drive and movie)
tools/godot.sh drive --scene=$P --timeline=res://player/camera/demo/timeline_walk.json \
  --out=camera-aim_flow --skip-menu --god --tod=0.6 --spawn=-200,39.5,-260,180 \
  --enemies=ripper:6,mantis:2 --probe-log=$PWD/tmp/camera-aim/flow2.csv
# r7 item 3 — flight, sandbox and city
tools/godot.sh drive --scene=$P --timeline=res://player/mech/timelines/flight.json --sandbox \
  --out=camera-aim_flight_sandbox --probe-log=$PWD/tmp/camera-aim/flight_sandbox.csv \
  --shots=0.9,2.2,3.6,4.9,5.9,7.4,8.8,10.2
tools/godot.sh drive --scene=$P --timeline=res://player/camera/demo/timeline_flight_city.json \
  --out=camera-aim_flight_city --skip-menu --god --tod=0.6 --stub=flow --no-enemies \
  --probe-log=$PWD/tmp/camera-aim/flight_city.csv --shots=0.9,2.2,3.6,4.9,6.0,7.4,8.6
# still standing from earlier rounds
tools/godot.sh test res://player/camera/tests/measure_framing.gd       # live framing numbers in main.tscn
tools/godot.sh test res://combat/melee/tests/test_melee.gd             # 156 checks, 0 failed (cinematics)
tools/godot.sh drive --timeline=res://enemies/tests/fight_timeline.json --nan-watch   # errors=0, no NANWATCH
S=res://player/camera/demo/camera_demo.tscn
tools/godot.sh shot --scene=$S --sandbox --out=camera-aim --times=3.0                        # third_idle
tools/godot.sh shot --scene=$S --sandbox --out=camera-aim --times=5.0 --press=move_forward   # third_run
tools/godot.sh shot --scene=$S --sandbox --out=camera-aim --times=3.0 --press=aim            # third_ads
tools/godot.sh shot --scene=$S --sandbox --out=camera-aim --times=4.0 --lock --lock-high     # lock_far
tools/godot.sh shot --scene=$S --sandbox --out=camera-aim --times=3.5 --pulse=camera_toggle@1.5
tools/godot.sh shot --scene=$S --sandbox --out=camera-aim --times=3.0 --wall                 # wall_noclip
tools/godot.sh shot --scene=$S --sandbox --out=camera-aim_lock_titan --times=4.0 --lock --lock-titan
tools/godot.sh shot --scene=$S --sandbox --out=camera-aim_lock_titan_ads --times=4.5 --press=aim --lock --lock-titan
tools/godot.sh shot --scene=$S --sandbox --out=camera-aim_lock_titan_cockpit --times=4.5 \
  --pulse=camera_toggle@1.5 --lock --lock-titan
tools/godot.sh drive --timeline=res://player/mech/timelines/tour.json --sandbox --out=camera-aim_tour \
  --shots=3.0,6.5,11.5,16.0,24.0,43.0
```

## Evidence (paths, numbers)
**r8 (this session)**
- **Test written first, run on HEAD's code** (`player/aim/tests/test_aim.gd`, 8 new checks, raw
  `InputEventJoypadButton` through `Input.parse_input_event` + `Input.flush_buffered_events`, held 30
  ticks = 0.25 s). Before the fix:
  ```
  FAIL D-pad → switches to the nearest target on the right (t0, wanted t1)
  FAIL a 0.25 s D-pad hold fires exactly one lock_changed (0)
  FAIL D-pad ← fires exactly one lock_changed (0)
  TEST FAILED (3 failures)
  ```
  After the fix: `TEST PASSED (0 failures)`, 36 PASS. The D-pad lines:
  ```
  PASS D-pad → with no hard lock changes nothing and acquires none (0 events)
  PASS hard lock on the centre dummy before the D-pad test (t0)
  PASS D-pad → switches to the nearest target on the right (t1, wanted t1)
  PASS a 0.25 s D-pad hold fires exactly one lock_changed (1)
  PASS D-pad ← switches back to the centre dummy (t0)
  PASS D-pad ← fires exactly one lock_changed (1)
  PASS the lock survives the cinematic framing (t0)
  PASS D-pad → during a cinematic does not switch (t0, 0 events)
  PASS the lock is still the centre dummy after the cinematic (t0)
  ```
- **The lead's acceptance probe**, real `main.tscn`, raw pad events, before → after:
  ```
  before:  DPAD-SWITCH FAIL: 3 defect checks, 3 failed; 0 control failures (run valid)
  mid-fix: DPAD-SWITCH FAIL: 3 defect checks, 1 failed; 0 control failures (run valid)
           (RIGHT passed, LEFT still failed — the keep cone, measured at −32.05°)
  after:   DPAD-SWITCH PASS: 3 defect checks, 0 failed; 0 control failures (run valid)
  ```
  Final run, in full: `lock_next just_pressed seen on 1 physics tick(s), held on 12 tick(s);
  lock_changed events +1`, `acc_centre → acc_right`, then `acc_centre → acc_left`, then
  `Input.action_press(lock_next)` → `acc_right`, and both RS-flick controls still pass.
- **Captures** (`--lock-log` correlation in brackets):
  - `captures/camera-aim_dpad_switch_t3_7.jpg` — **before**: cyan lock diamond on the centre dummy
    (Target0), labelled **140 m**, camera straight down the street. [LOCKLOG t=8.55 `hard=Target0`]
  - `captures/camera-aim_dpad_switch_t4_1.jpg` — **after**, 0.3 s after the D-pad → press: the diamond
    is on the next dummy to the right (Target1), labelled **221 m**, and the camera has swung right to
    follow it. [LOCKLOG t=8.71 `hard=Target1`, first sample after the switch]
  - `captures/camera-aim_dpad_switch_t4_5.jpg` — the same lock settled.
  - Contact sheet `tmp/camera-aim/dpad_final.jpg`.
- **Edge measurements the lead asked for** (scratch probe on the real `main.tscn`, three dummies at
  −18° / 0° / +18°, raw D-pad events). Numbers in Known issues below.
- Test counts at the end of the round: `test_aim` 36 PASS / 0 FAIL, `test_camera` / `_audit` / `_feel`
  / `_large` / `_cockpit` / `_flight` all 0 failures, `test_camera_flow` 10 PASS, `check` 36 files
  0 errors 0 warnings.

**r7 (this session)**
- `captures/camera-aim_fpfix_t{1_0,2_0,3_0,4_0,6_0}.jpg` — the r7 first-person repro, fixed.
  Mean luma 0.205 / 0.185 / 0.181 / **0.238** / 0.181 (the same take before the fix: 0.110 / … /
  **0.039** / 0.040). Contact sheet `tmp/camera-aim/fpfix.jpg`.
- `captures/camera-aim_fp_final_t*.jpg` (day) and `camera-aim_fp_final_night_t*.jpg` (`--tod=0.0`):
  the 30 s first-person run in the city — walk, boost, dash, jump, 3-hit melee combo, ~7 s of gatling
  fire, guard, flight entry, a second weapon, ADS. Contact sheets `tmp/camera-aim/fp_final_sheet.jpg`
  and `tmp/camera-aim/fp_final_night_sheet.jpg`. **0 frames under 0.02 mean luma** and **eye residual
  max 0.180 m** in both (`final_day.csv` 3553 first-person ticks, `final_night.csv` 3551).
- `captures/camera-aim_flight_sandbox_t*.jpg`, `captures/camera-aim_flight_city_t*.jpg` and the
  contact sheets `tmp/camera-aim/flight_{sandbox,city}_sheet.jpg` — the flight gate above.
- `tmp/camera-aim/{flow,flow2,drop,movie}.csv` — the four "does the camera park?" runs.
- `tmp/camera-aim/orient.csv` — the rig's position and orientation are identical on the clean frame and
  the black frame (that is what sent the hunt after the geometry rather than the camera).
- Bisect captures: `camera-aim_nocanopy_*` (whole canopy hidden, still black), `camera-aim_keep_World_*`
  / `camera-aim_keep_CameraRig_*` (each clean), `camera-aim_stub_{feel,hud,enemies}_*` (still black),
  `camera-aim_nopost_*`, `camera-aim_fpnofx_*`, `camera-aim_noen_*`, `camera-aim_fpback_*` (back to
  third person at t=4.2 is clean).
- Test counts: `test_camera_cockpit` 12 PASS, `test_camera_flight` 18 PASS, `test_camera_flow` 10 PASS,
  `test_camera` / `_audit` / `_feel` / `_large` / `test_aim` all 0 failures, `check` 32 files 0 errors.

**Earlier rounds (still standing)**
- `captures/camera-aim_third_idle.jpg`, `_third_run.jpg`, `_third_ads.jpg`, `_lock_far.jpg`,
  `_wall_noclip.jpg`, `_first_forward.jpg`, `_first_up.jpg`, `_first_side.jpg`.
- `captures/camera-aim_tour_t{3_0,6_5,11_5,16_0,24_0,43_0}.jpg` — mech-move tour through this rig.
- `captures/camera-aim_lock_titan_t4_0.jpg` (60 m stand-in at 145 m, third person: hero bottom-left,
  titan feet-to-crest in frame, camera 12 m up), `_lock_titan_ads_t4_5.jpg` (same lock + ADS),
  `_lock_titan_cockpit_t4_5.jpg` (the framing correctly does nothing in the cockpit).
- Numbers: arm 42 m (boost 46/48/52, assault measured), ADS arm 34 m at FOV 38°, pivot 12.5, shoulder 12,
  pitch −6°, FOV 55/38 third and 62/45 first, blend 0.35 s (measured 42 ticks at 120 Hz, the held aim
  point within 0.024 of the reticle through it), framing 39.3 % / 31.7 % / 7.9 %,
  cockpit coverage 17.2 % (limit 18 %), witch-time follow lag 7.7 m vs 7.7 m baseline, drive run errors=0.

## Known issues
- **[r8, measured, NOT changed — the lead picks the rule] `→` at the right end of a row bounces between
  the last two targets.** The wrap fallback in `switch_target` (`aim_system.gd`, `|dx − 360·dir|`)
  ignores the side, so from the rightmost target it picks the *adjacent* one on the left rather than
  the far end. Measured on the real `main.tscn` with three dummies at −18° / 0° / +18°, five raw
  D-pad → presses 0.1 s apart from the centre:
  ```
  press 1: m_centre -> m_right   press 2: m_right -> m_centre
  press 3: m_centre -> m_right   press 4: m_right -> m_centre
  press 5: m_centre -> m_right
  ```
  Every press fires exactly one `lock_changed` (no spurious events) and the lock never drops; it just
  oscillates. This is the pre-existing `switch_target` selection, shared with the flick, and the r8
  brief told me to measure it and not change it.
- **[r8, measured, CHANGED — flagging it] `SWITCH_GRACE 0.35 s`.** The keep cone (±30° yaw) used to
  undo a switch on the very next tick whenever the newly picked target was more than 30° off the view
  — measured at **−32.05°** on the lead's own probe, which is why D-pad LEFT still failed with the
  consumer in place. The cone test is now suspended for 0.35 s after a deliberate switch. Side effect:
  the **flick** path gets the same grace, so a flick onto a far-off target now sticks instead of being
  silently undone. LOS, range and death still drop the lock during the grace; the cone resumes after
  it, so turning away from a switched lock still releases it. If the lead wants a different rule
  (bounding the switch pool to the keep cone instead, say), it is one constant and one `if`.
- **[r8] The `→` / `←` switch does not work in the cockpit for targets far off the view.** The grace
  relies on the lock framing turning the camera, and `camera_lock.gd` is not run in first person
  (SPEC §5: the cockpit view stays free). A cockpit switch to a target more than 30° off is therefore
  dropped when the grace expires. Same as before the change for anything under 30°; it is only the
  >30° case that is now kept for 0.35 s and then released instead of being released immediately.
- **[r8, tooling, not mine] `tools/godot.sh shot` times `--pulse` and `--times` on different clocks.**
  `--pulse` compares against `_t`, which starts when the capture node is created; the `--times` loop
  uses `start = _t` read *after* the world is ready. The two are offset by the world build (~1.1 s
  here), so `--times=3.0,4.5 --pulse=lock_next@3.5` pulses about a second *before* the first frame and
  both frames show the post-switch state. Worked around with `--lock-log` plus a compensated pulse
  time; a fix belongs in `game/tools/capture.gd` (lead's).
- **[r8] `combat/weapons/**` has uncommitted work in the shared tree** that throws
  (`weapon_system.gd:121`, `Invalid assignment … 'ads' … on a base object of type 'Nil'`) and takes
  `ui/hud_data.gd:75 poll` down with it. Some capture runs report `errors=1010` and lose the HUD
  range labels; the r8 captures above were taken on runs that came up clean (`errors=0`). Not this
  unit.
- **The pilot no longer sees their own chassis in first person** (r7 item 1). That is the fix, and it
  is what every first-person game does, but it has two visible costs: the mech casts no shadow of
  itself into the cockpit view, and the arms/rifle are gone from the frame. If hero-v3 would rather
  solve it their side (a lowered-weapon pose in the cockpit, or an IK target that is not the lens), the
  cull is one module to delete — say the word.
- **`--tod` does not appear to be applied in the shared tree right now**: `world/art/time_of_day.gd`
  fails to compile ("Nonexistent function 'build'"), so `--tod=0.0` renders as dusk rather than night in
  every capture above. That is city-art's in-progress work, not this unit; the night contact sheet is
  still a valid "no black frame at low light" check, just not a true night one.
- **The eye residual is measured inside the rig** (`CameraRig.eye_residual()`, recorded in the tick
  that places the camera). An outside sampler cannot do it: the hero's `Skeleton3D` moves its
  `BoneAttachment3D` sockets on the idle frame, so a probe reading the socket from `_process` measures
  up to 1 m of the model's own landing crouch and reports it as camera error. The design bound is
  `EYE_BOB_MAX × (1 − EYE_BOB_KEEP)` = 0.39 m, and the residual is the deliberate gait-bob damping
  (hero-v3 r5 item 8), not lag.
- **ADS while locked on a large target**: the arm keeps the 64 m large framing but the FOV channel still
  zooms to 38°, which crops the hero's feet. Deliberate (ADS is the player's own zoom, and every
  shooter crops the character when aiming), but it is the one state where the "both in frame" promise
  does not hold. Say the word and I will damp the ADS zoom while a large lock is up.
- **city-build's `world/city.gd:85` throws** (`Out of bounds get index '2'` in `to_godot()`) in the
  shared tree right now, so `tools/godot.sh drive --timeline=res://enemies/tests/fight_timeline.json`
  reports `errors=1` and the player falls through an unbuilt city. Uncommitted work in their folder,
  not this unit; the camera captures above run clean (`errors=0`).
- **ADS height is 79.6 %, not the ~60 % the r3 review expected** (see above). At FOV 38 the options are
  arm ≈ 45 m (no pull-in) or FOV ≈ 49 at arm 34 (barely a zoom). 34 m as ordered; the frame reads well.
- **Rest framing drifted with the hero model**: `measure_framing` in `main.tscn` now prints
  **41.8 % height / 30.7 % centre / 7.9 % clear** (r3 verified 39.3 / 31.7 / 7.9). The hero model is now
  16.00 m tall (another unit's rebuild), which pushes the centre 0.3 pp left of the 31–37 % band.
  `SHOULDER 12.0 → 11.6` would recentre it; left alone because the lead accepted the rest framing at r3
  and this is their model's change, not the rig's.
- The placeholder's `cockpit` socket is at 9.9 m, below SPEC's 11.5–13.5 m band; the rig clamps the eye
  to the band floor and offsets it 1.2 m forward. With a socket inside the band both are no-ops.
- In first person the hero's own rifle/blade crosses the lower right of the view
  (`camera-aim_first_forward.jpg`). Hiding near geometry in first person is hero-asset's call.
- The console reads as a plain slab from the pilot's eye: at a 57° rake its lit readouts are ~2 % of
  the frame height. Wants modelled dashboard art rather than more parameters.
- `aim_point()` falls back to 1,500 m per CONTRACTS §5 although the rifle cuts off at 500 m.
- `fx/feel_director.gd`, `fx/vfx/*.gdshader` and `ui/widgets/low_hp.gd` do not compile in the shared
  tree right now (other units, in progress); every run of main.tscn prints those errors.

## Requests (to the lead / other units)
0f. **hero-v3 — the cockpit weapon pose.** `Hero3Aim` solves the rifle/gatling onto the aim line, and in
   first person that line starts at the lens, so the weapon covers the canopy (this was the r7 black
   frame). I fixed it on my side by culling the whole chassis from the first-person camera. If you would
   rather show the arms and the gun in the cockpit — every mech game does — the fix belongs in the aim
   solve (a lowered or offset target while `Events.camera_mode_changed(true)`), and I will retire
   `camera_hero_cull.gd`. Note the chassis is ONE rigid-skinned mesh (`Hero3Body`) plus
   `Hero3Saber`/`Hero3Rifle`/`Hero3Shield`, so there is no per-limb switch to flip today.
0g. **lead — `CameraRig.eye_residual()`: ANSWERED, here is the line to paste into the CameraRig
   paragraph of `docs/CONTRACTS.md` §3.**
   > `func eye_residual() -> float` — read-only telemetry. Metres between the point the first-person
   > camera is actually sitting at and the model's **raw** `cockpit` socket, recorded inside `_follow`
   > in the same tick that places the camera (it cannot be sampled from outside: the hero's
   > `Skeleton3D` moves its `BoneAttachment3D` sockets on the idle frame, so an external probe reads up
   > to 1 m of the model's own landing crouch and reports it as camera error). What it returns:
   > **third person** and **during the 0.35 s first/third blend** — `0.0` (reset every tick at the top
   > of `_follow`; it is only written once `fp_t > 0.99`); **first person, blend complete** — the live
   > residual in metres, non-zero by design, since it is the deliberate gait-bob damping
   > (`EYE_BOB_MAX × (1 − EYE_BOB_KEEP)` = 0.39 m is the bound, hero-v3 r5 item 8), not lag;
   > **during a cinematic** — it holds its last value, because the rig returns before `_follow`;
   > **with no `Game.player`** — `_follow` returns before the reset, so it holds its last value.
   > No case should read differently; say the word if you want one changed.
0d. **boss / enemies**: the rig calls `framing_height() -> float` as a METHOD on the actor behind the
   Targetable (`Targetable.actor()`). Nobody in the tree implements it yet, so the framing is inert
   until the titan does. `>= 30` engages it; the test stand-in returns 60.
0e. **Lead — pivot lift**: CONTRACTS §5 lists arm and pitch only, but +12° on a 64 m arm puts the
   camera 13.3 m BELOW the 12.5 m pivot, i.e. under the street, so the rig also lifts the pivot 14 m
   (faded out in the cockpit). Without it the arm probe just eats the extra length. Want it in the
   contract text, or a different number?
0c. **melee**: pass the execution clock — `rig.request_cinematic(shots, duration, &"player")` in
   `execution_director.gd:202`. Audit #3 is fixed on my side (the parameter and the player-time advance
   exist and are tested), but until that call passes `&"player"` the shots still run on real time and
   will drift ~0.15–0.27 s ahead of an execution that triggers its own slow-mo/hit-stop.
0. **Lead — ADS framing decision (r3)**: implemented `ARM_ADS 34 m` as ordered, but it measures 79.6 % of
   the frame height, not ~60 %. Geometry at FOV 38: height ≈ 2706 / arm_m %. For ~60 % either the arm
   goes to ~45 m (ADS stops pulling in) or ADS FOV opens to ~49 (arm 34). Say which and I will ship it.
0b. **Lead — rest centre_x**: 30.7 % vs the 31–37 % band after the hero grew to 16.00 m; `SHOULDER 11.6`
   recentres it. Want me to?
1. **SPEC §5**: the arm line says "≈ arm 40 m"; the rig ships 42 m because that is what centres the
   36–44 % band with the current 16 m hero (40 m measures 43.9 %). Update SPEC or tell me to trade band
   headroom for the round number. Same for the ADS note in Known issues.
2. **hero-asset / mech-move**: raise the placeholder's `cockpit` socket to 12 m (SPEC §2 band).
3. **city-art**: join occluding buildings to the `camera_dither` group and give them either
   `set_fade(amount)` or a `fade` instance shader parameter; the rig drives 1 → 0.3 while they are in
   the camera's way.
4. **melee**: cinematic shots use the duel frame — `{offset, look, fov, t}` with `look` a point in the
   same frame; `request_cinematic` resolves every shot against collision, and `end_cinematic()` restores
   the arm and look control (call it directly if you stop a cinematic early).
5. **lead — two decisions from r8, both measured, neither blocking.**
   a. **`SWITCH_GRACE` (0.35 s).** The gate could not pass without it: the keep cone dropped a switch
      that landed 32.05° off the view on the very next tick. I implemented "suspend the cone test
      briefly after a *deliberate* switch, so the 9 rad/s lock framing can turn onto the new target",
      because it is the behaviour every action game has and because bounding the switch pool to the
      cone instead would make the verb refuse to work at the angles where it is most needed. It also
      changes the flick path (see Known issues). One constant + one `if` if you want it different.
   b. **The `→` wrap bounce.** Repeated → at the right end of a row alternates between the last two
      targets (five presses measured, `centre → right → centre → right → centre`). The wrap fallback
      picks the nearest target by `|dx − 360·dir|` and so ignores the side. Left as-is per the brief.
      A fix would be to make the wrap go to the *far* end of the row (`min` over signed `dx` on the
      opposite side) rather than to the adjacent one.
6. **lead / tools — `game/tools/capture.gd` clocks.** `--pulse` is compared against `_t` (absolute,
   from capture-node creation) while the `--times` loop uses `start = _t` read after the world is
   ready, so a pulse and a `--times` entry with the same number are ~1 s apart. That is why the r8
   brief's `--times=3.0,4.5 --pulse=lock_next@3.5` photographs the post-switch state twice. Either
   make `_pulses` relative to the same `start`, or document it; every unit that scripts a beat with
   `--pulse` will hit this.
7. **hud** — `ui/hud_glyphs.gd:32` gives `lock_prev`/`lock_next` the keyboard glyphs "MMB"/"WHEEL".
   There is no keyboard binding for either action (they are `PAD_ONLY`, `core/input_setup.gd:56`), and
   the wheel is weapon swap. The r8 captures show the pad glyphs, so this did not surface on screen —
   flagging it because the r8 brief asked me to.
