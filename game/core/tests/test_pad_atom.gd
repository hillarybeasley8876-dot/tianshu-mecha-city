extends Node
## Core test: the pad-only combat atom (ACCEPTANCE §2) — every SPEC §3 pad verb, played through the
## REAL res://main.tscn with RAW joypad events only, i.e. through PadInput and the InputMap.
##   tools/godot.sh test res://core/tests/test_pad_atom.gd -- --sandbox --god --no-enemies --timeout=300
##
## The sequence lives in res://core/tests/pad_atom.json and is shared with the windowed drive
## (`tools/godot.sh drive --timeline=res://core/tests/pad_atom.json`), so the film and the test can
## never drift apart. Step kinds: `pad` (raw button/axis), `dpad` (the left thumb leaves the stick, and
## the gap is measured), `chord` (RB held around a face button), `sample` (the test reads state here;
## a drive ignores it), `end`.
##
## Targets are placed IN FRONT of the hero rather than left to the spawner's ring: the acceptance run
## failed its R3 lock because "0 lockable targets in range" — the pack had spawned outside the view.

const MAIN := "res://main.tscn"
const SEQUENCE := "res://core/tests/pad_atom.json"
const SPAWNER := "res://enemies/spawner.tscn"
## Where the targets go, in the hero's own frame: forward, and spread either side. Far enough that the
## hero's opening run closes on them instead of through them, and tough enough (Mantis, 1,800 HP) to
## still be alive at the lock beat 14 s in — the first attempt placed 46 m Rippers and the hero killed
## them before R3.
const RANGE := 260.0
const SPREAD := 30.0
## Where the survivors are moved just before the lock beat.
const REFRONT := 90.0
## Half-spread of the arc, in degrees: inside the lock box's +-12 deg yaw.
const REFRONT_SPREAD_DEG := 6.0
## Thumb travel ONTO the D-pad, one 120 Hz frame. The return is not padded: the stick is restored at
## the instant the thumb lands back on it.
const TRAVEL := 1.0 / 120.0

var _seen: Dictionary = {}
var _checks: int = 0
var _fails: int = 0
var _samples: Dictionary = {}
var _spawner: Node
var _stick: Vector2 = Vector2.ZERO
var _stick_off_since: float = -1.0
var _stick_off_max: float = 0.0
var _measuring: bool = false
var _t0: float = 0.0


func _ready() -> void:
	add_child.call_deferred((load(MAIN) as PackedScene).instantiate())
	var waited := 0
	while (not Game.world_built() or Game.player == null) and waited < 60000:
		await get_tree().physics_frame
		waited += 1
	if Game.player == null:
		print("PAD ATOM FAIL: no player after %d frames" % waited)
		get_tree().quit(1)
		return
	await _wait(1.0)
	_connect_events()
	_spawner = (load(SPAWNER) as PackedScene).instantiate()
	add_child(_spawner)
	_place_targets()
	await _wait(1.2)
	_t0 = Feel.real_now()
	_measuring = true
	await _run(load_sequence())
	_measuring = false
	_report()


func load_sequence() -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SEQUENCE))
	if not data is Array:
		push_error("pad atom: %s is not a JSON array" % SEQUENCE)
		return []
	return data as Array


func _connect_events() -> void:
	Events.weapon_fired.connect(func(w: StringName, _m: Vector3, _d: Vector3) -> void: _mark("fired:" + w))
	Events.weapon_switched.connect(func(w: StringName) -> void: _mark("switched:" + w))
	Events.melee_swing.connect(func(m: StringName, _s: int) -> void: _mark("melee:" + m))
	Events.skill_used.connect(func(s: StringName) -> void: _mark("skill:" + s))
	Events.boost_started.connect(func(k: StringName) -> void: _mark("boost:" + k))
	Events.jumped.connect(func() -> void: _mark("jumped"))
	Events.lock_changed.connect(func(t: Node3D) -> void: _mark("lock:" + ("on" if t != null else "off")))
	Events.missiles_locked.connect(func(n: int) -> void:
			if n > 0:
				_mark("missile_locks"))
	Events.overdrive_changed.connect(func(on: bool) -> void: _mark("overdrive:" + str(on)))
	Events.camera_mode_changed.connect(func(fp: bool) -> void:
			_mark("camera:" + ("first" if fp else "third")))


## Targets in the hero's own frame, so "in view" does not depend on where the sandbox put the hero.
func _place_targets() -> void:
	var hero := Game.player as Node3D
	var fwd := -hero.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := hero.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var placed := 0
	for i in 4:
		var at := hero.global_position + fwd * (RANGE + float(i) * 12.0) + right * (float(i - 2) * SPREAD)
		if _spawner.spawn(&"mantis", Transform3D(Basis(), at)) != null:
			placed += 1
	print("PADATOM placed %d targets in front of the hero at %.0f m" % [placed, RANGE])


## The hero turns during the opening beats (strafe, assault, dash), so by the lock beat the pack can be
## 60-80 degrees off the camera and NOTHING is lockable. Move the survivors back in front of the CAMERA
## (not the body) just before R3, which is what "targets in front of the hero" has to mean for a lock.
func _refront_targets() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		push_error("pad atom: no camera to re-front the targets against")
		return
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var hero := Game.player as Node3D
	var i := 0
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var n3 := e as Node3D
		if n3 == null or (n3.has_method(&"is_alive") and not n3.call(&"is_alive")):
			continue
		# An ARC at one range, not a line: targets strung out along the same bearing occlude each
		# other, and the line-of-sight ray then leaves only the nearest one lockable.
		var a := deg_to_rad(REFRONT_SPREAD_DEG * (float(i) - 1.5))
		n3.global_position = hero.global_position + (fwd * cos(a) + right * sin(a)) * REFRONT
		# Put the LOCK POINT at the camera's height, so the pitch is ~0 and inside the box's +-8 deg.
		var tg := _targetable_of(n3)
		if tg != null:
			n3.global_position.y += cam.global_position.y - tg.global_position.y
		if n3 is CharacterBody3D:
			(n3 as CharacterBody3D).velocity = Vector3.ZERO
		i += 1
	print("PADATOM re-fronted %d target(s) on a %.0f m arc in front of the camera" % [i, REFRONT])


## Applies the shared sequence on the real clock. Absolute `t` in the file, so a drive and this test
## see the same beat.
func _run(steps: Array) -> void:
	for step: Dictionary in steps:
		if bool(step.get("end", false)):
			return
		var due := float(step["t"])
		while Feel.real_now() - _t0 < due:
			await get_tree().physics_frame
		if step.has("pad"):
			_pad(step["pad"] as Dictionary)
		elif step.has("dpad"):
			await _dpad(String(step["dpad"]), float(step.get("hold", 0.08)))
		elif step.has("chord"):
			await _chord(String(step["chord"]), float(step.get("hold", 0.08)))
		elif step.has("sample"):
			_sample(String(step["sample"]))
		elif bool(step.get("place_targets", false)):
			_refront_targets()
		elif bool(step.get("fill_od", false)):
			# The ignition needs a full OD ring; the atom proves the CHORD, not the grind. A drive has
			# no way to fill it, so its overdrive beat may stay dark — the test is the gate.
			if Game.player.has_method(&"add_overdrive"):
				Game.player.call(&"add_overdrive", 100.0)
				print("PADATOM filled the OD ring to %s" % Game.player.get(&"overdrive"))
			else:
				push_warning("pad atom: PlayerMech has no add_overdrive(); the ignition beat cannot fire")


func _pad(spec: Dictionary) -> void:
	if spec.has("button"):
		_btn(_button(String(spec["button"])), bool(spec.get("down", true)))
	elif spec.has("axis"):
		var a: Array = spec["axis"]
		var value := float(a[1])
		match String(a[0]):
			"lx": _stick.x = value
			"ly": _stick.y = value
		_axis(_axis_of(String(a[0])), value)


## The left thumb has to move to the D-pad, so the stick goes to rest for the press and the gap is
## measured: ACCEPTANCE §2 allows 0.3 s, and the 0.4 s reload hold used to break it.
func _dpad(name: String, hold: float) -> void:
	var keep := _stick
	_stick = Vector2.ZERO
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	var off := Feel.real_now()
	await _wait(TRAVEL)
	var b := _button("dpad_" + name)
	_btn(b, true)
	# A D-pad-up HOLD is the reload, so watch for it while the thumb is off the stick: at SPEC §3's
	# 0.25 s it fires inside a 0.27 s hold, at the old 0.4 s it never does and the tap wins instead.
	var watch := name == "up" and hold > 0.2
	var until := Feel.real_now() + hold
	while Feel.real_now() < until:
		if watch and Input.is_action_pressed(&"reload"):
			_samples["reload"] = true
		await get_tree().process_frame
	_btn(b, false)
	_axis(JOY_AXIS_LEFT_X, keep.x)
	_axis(JOY_AXIS_LEFT_Y, keep.y)
	_stick = keep
	var gap := Feel.real_now() - off
	if _measuring:
		_stick_off_max = maxf(_stick_off_max, gap)
		print("PADATOM dpad %s hold=%.3f gap=%.3f" % [name, hold, gap])


## RB is a pure shift layer: it goes down, the face button is pressed under it, and the button keeps its
## shifted action until it is released (the latch).
func _chord(name: String, hold: float) -> void:
	_btn(JOY_BUTTON_RIGHT_SHOULDER, true)
	await _wait(0.03)
	_btn(_button(name), true)
	await _wait(hold)
	_btn(_button(name), false)
	_btn(JOY_BUTTON_RIGHT_SHOULDER, false)


func _sample(what: String) -> void:
	match what:
		"ads": _samples["ads"] = bool(_rig_state().get(&"ads", false))
		"guarding": _samples["guarding"] = _guarding()
		"locked":
			var aim: Object = Game.player.call(&"aim") if Game.player.has_method(&"aim") else null
			var in_view := 0
			var hard: Object = null
			if aim != null and aim.has_method(&"targets_in_view"):
				in_view = (aim.call(&"targets_in_view", 12, 450.0) as Array).size()
			if aim != null and aim.has_method(&"hard_target"):
				hard = aim.call(&"hard_target")
			print("PADATOM lock probe: %d target(s) in view, hard_target=%s" % [in_view, hard])
			_samples["locked"] = int(_seen.get("lock:on", 0)) > 0
		"lock_switched": _samples["lock_switched"] = int(_seen.get("lock:on", 0)) > 1


func _button(name: String) -> JoyButton:
	return {
		"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
		"lb": JOY_BUTTON_LEFT_SHOULDER, "rb": JOY_BUTTON_RIGHT_SHOULDER,
		"l3": JOY_BUTTON_LEFT_STICK, "r3": JOY_BUTTON_RIGHT_STICK,
		"dpad_up": JOY_BUTTON_DPAD_UP, "dpad_down": JOY_BUTTON_DPAD_DOWN,
		"dpad_left": JOY_BUTTON_DPAD_LEFT, "dpad_right": JOY_BUTTON_DPAD_RIGHT,
	}[name] as JoyButton


func _axis_of(name: String) -> JoyAxis:
	return {
		"lx": JOY_AXIS_LEFT_X, "ly": JOY_AXIS_LEFT_Y, "rx": JOY_AXIS_RIGHT_X, "ry": JOY_AXIS_RIGHT_Y,
		"lt": JOY_AXIS_TRIGGER_LEFT, "rt": JOY_AXIS_TRIGGER_RIGHT,
	}[name] as JoyAxis


func _btn(b: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _axis(a: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## Feel.real_now() is a _process clock (Feel advances it in _process), so polling it on physics
## frames can overshoot by a whole frame every call. Poll it on process frames.
func _wait(seconds: float) -> void:
	var t := Feel.real_now()
	var guard := 0
	while Feel.real_now() - t < seconds and guard < 100000:
		await get_tree().process_frame
		guard += 1


func _mark(key: String) -> void:
	_seen[key] = int(_seen.get(key, 0)) + 1


func _count_prefix(p: String) -> int:
	var n := 0
	for k: String in _seen:
		if k.begins_with(p):
			n += int(_seen[k])
	return n


func _rig_state() -> Dictionary:
	var rig: Object = Game.camera_rig
	if rig != null and rig.has_method(&"hud_state"):
		return rig.call(&"hud_state")
	return {}


## The enemy's lock point, if it has one.
func _targetable_of(enemy: Node3D) -> Node3D:
	for c in enemy.get_children():
		if c is Targetable:
			return c as Node3D
	return null


func _guarding() -> bool:
	for c in Game.player.get_children():
		if c.has_method(&"is_guarding"):
			return bool(c.call(&"is_guarding"))
	return false


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print(("PASS " if cond else "FAIL ") + label)


## One check per SPEC §3 pad row, judged by the gameplay signal it must produce.
func _report() -> void:
	var span := Feel.real_now() - _t0
	print("PADATOM ran %.1f s real; signals seen: %s" % [span, str(_seen)])
	_ok(_seen.has("fired:beam_rifle"), "RT fires the rifle")
	_ok(int(_seen.get("fired:beam_rifle", 0)) >= 2, "RT hold fires a charged shot too (%d)"
			% int(_seen.get("fired:beam_rifle", 0)))
	_ok(bool(_samples.get("ads", false)), "LT is ADS")
	_ok(_seen.has("jumped"), "A jumps")
	_ok(_seen.has("boost:quick"), "B tap dashes")
	_ok(_seen.has("boost:slide"), "B hold is the sustained boost")
	_ok(_seen.has("boost:assault"), "L3 toggles the assault boost")
	_ok(_count_prefix("melee:") >= 3, "X x3 is a melee string (%d swings)" % _count_prefix("melee:"))
	_ok(bool(_samples.get("guarding", false)), "LB held guards")
	_ok(bool(_samples.get("locked", false)), "R3 hard-locks a target in front of the hero")
	_ok(bool(_samples.get("lock_switched", false)), "D-pad right switches the lock (camera-aim r8's consumer)")
	_ok(_seen.has("missile_locks") or _seen.has("fired:hailstorm"), "RB+RT paints and fires the missiles")
	_ok(_seen.has("skill:anchor"), "Y fires the Skyhook anchor")
	_ok(_seen.has("skill:rift_step"), "RB+B is Rift Step")
	_ok(_seen.has("skill:ward"), "RB+Y hold raises the Corona Ward")
	_ok(_seen.has("skill:fins"), "RB+Y tap sends the Corona Fins")
	_ok(_seen.has("skill:burst"), "RB+X is Shockcore Burst")
	_ok(_seen.has("skill:well"), "RB+A is Undertow Well")
	_ok(_count_prefix("switched:") >= 2, "D-pad up tap swaps the primary and back (%d)"
			% _count_prefix("switched:"))
	_ok(_seen.has("overdrive:true") or _seen.has("skill:overdrive"), "L3+R3 ignites Zenith Overdrive")
	_ok(_seen.has("camera:first") and _seen.has("camera:third"), "D-pad down toggles 1st/3rd person")
	_ok(bool(_samples.get("reload", false)), "D-pad up held 0.27 s reloads (SPEC §3 threshold 0.25 s)")
	_ok(_stick_off_max <= 0.30, "the left thumb never leaves the stick for more than 0.30 s (longest %.3f s, D-pad only)"
			% _stick_off_max)
	print("PADATOM %s: %d checks, %d failed, longest left-stick release %.3f s"
			% ["FAIL" if _fails > 0 else "PASS", _checks, _fails, _stick_off_max])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(1 if _fails > 0 else 0)
