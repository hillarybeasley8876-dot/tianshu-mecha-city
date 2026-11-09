# Brief: camera-aim — third/first-person camera rig, lock-on, AimSystem

## Goal
A camera that sells scale and speed and never fights the player: over-the-shoulder third person and a
cockpit first person, switchable any time (B / View); precise mouse aim and good gamepad aim on a fast
mech; hard lock with switching; soft-lock magnetism; multi-target query for missiles; execution
mini-cinematics. Screen shake / FOV kicks from `Feel` signals are applied here.

## Read first
`docs/CONTRACTS.md` §3–5 (CameraRig + AimSystem APIs), `docs/SPEC.md` §3, §5, `docs/FEEL.md` (header rules:
trauma², rotational shake, 1st-person scaling), `ref/research/juice-impact.md` §3 (camera numbers),
`ref/research/feel-mech-games.md` (camera sections, cockpit lessons; use SPEC numbers if not written yet),
`game/core/feel.gd`, `game/core/targetable.gd`.

## You own
`game/player/camera/**` (rig scene `camera_rig.tscn`, scripts, cockpit frame mesh/scene, tests),
`game/player/aim/**` (`aim_system.tscn`, scripts, tests).

## Build
1. **CameraRig** (Node3D, registers `Game.camera_rig = self` in `_ready`, follows `Game.player` smoothly
   at 120 Hz without jitter): third person per SPEC §5 (pivot 11 m, distance 26 m, shoulder 5 m, FOV 70,
   ADS 52; spring arm collision on `Layers.MASK_SIGHT` with a 3 m probe so the camera never clips into
   buildings; quick recovery). First person: camera at the model's `cockpit` socket (or 13.5 m), FOV 80
   (ADS 60), cockpit frame (simple canopy struts + dashboard geometry you build, emissive cyan details),
   blend 0.25 s between modes, `Events.camera_mode_changed`.
2. **Look input**: mouse (raw relative, Settings `mouse_sensitivity`, invert), gamepad right stick with
   response curve (exponent 1.6), acceleration after 0.3 s full tilt; pitch −70°..+75°.
3. **Feel hooks**: trauma shake (rotational Perlin, pitch/yaw/roll max 3°/3°/2°, shake = trauma²,
   decay 1.2/s), kick spring channel, FOV punch (`fov_kick_requested`), boost FOV per FEEL rows;
   1st person ×0.6 shake ×0.75 FOV fx. Landing dip on `Events.landed`.
4. **AimSystem** (child component of PlayerMech, `aim_system.tscn`): crosshair ray from the active
   camera centre (1,500 m, `Layers.MASK_PLAYER_ATTACK`) → `aim_point()`; `aim_dir_from(muzzle)`
   corrects parallax; soft lock: nearest valid Targetable within 4° of the crosshair inside 600 m gets
   magnetism (Settings `aim_assist`, slows look speed 35 % over targets on gamepad, mild pull on mouse);
   hard lock (`lock_on`): best target by angle/distance/priority, toggle, switch by mouse flick > 15° or
   stick flick; lost on LOS loss > 1.5 s or death; `Events.lock_changed`; lock-on camera framing keeps
   hero and target in view (third person); `targets_in_view(max, range)` for missiles (screen box 24°×16°
   around the crosshair, LOS-checked, sorted by priority then angle). `hud_state()` keys: aim_point,
   hard_target (Node), soft_target, first_person, ads, lock_range.
5. **Cinematic**: `request_cinematic(shots, duration)` — shots are dicts {offset (in target space),
   look_at (node or point), fov, t}; returns control after `duration`; used by executions.

## Done when
- `tools/godot.sh check --only=res://player/camera/,res://player/aim/` → 0 errors.
- `tools/godot.sh test res://player/aim/tests/test_aim.gd`: in the sandbox with 5 dummy Targetables (you
  may spawn simple StaticBody targets in the test), soft lock picks the one under the crosshair, hard
  lock selects/switches/loses LOS correctly, `targets_in_view` returns ≤ max sorted, `aim_point` hits a
  wall at the right distance.
- `tools/godot.sh test res://player/camera/tests/test_camera.gd`: camera never inside geometry while the
  player runs along a wall and under the deck (probe check every tick); mode toggle round-trips.
- Captures: `captures/camera-aim_*.jpg` — third person idle, running, ADS, lock-on on a far target,
  first person cockpit (looking forward and up), near a wall (no clipping). Use the mech-move player if
  it exists; otherwise a stand-in body in your test scene.
