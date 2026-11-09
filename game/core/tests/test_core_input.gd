extends Node
## Core test: PadInput shift layer / chords / latching and the Feel clocks.
##   tools/godot.sh test res://core/tests/test_core_input.gd

var _fails: int = 0
var _checks: int = 0


## Runs after Feel every frame (default priority) and records the biggest real_delta it was handed.
class Probe extends Node:
	var max_real_dt: float = 0.0
	func _process(delta: float) -> void:
		max_real_dt = maxf(max_real_dt, Feel.real_delta(delta))


func _ready() -> void:
	await _pad_tests()
	await _pad_rows()
	await _reload_hold()
	await _clock_tests()
	print("CORE INPUT TEST %d checks, %d failures" % [_checks, _fails])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("PASS " if ok else "FAIL ") + what)


func _btn(index: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _pad_tests() -> void:
	_btn(JOY_BUTTON_A, true)
	_check(Input.is_action_pressed(&"jump"), "A = jump")
	_btn(JOY_BUTTON_A, false)
	_check(not Input.is_action_pressed(&"jump"), "A released")
	_btn(JOY_BUTTON_RIGHT_SHOULDER, true)
	_btn(JOY_BUTTON_X, true)
	_check(Input.is_action_pressed(&"burst") and not Input.is_action_pressed(&"melee"), "RB+X = burst, not melee")
	_btn(JOY_BUTTON_RIGHT_SHOULDER, false)
	_check(Input.is_action_pressed(&"burst"), "burst stays latched after RB release")
	_btn(JOY_BUTTON_X, false)
	_check(not Input.is_action_pressed(&"burst"), "burst released with X")
	_btn(JOY_BUTTON_RIGHT_SHOULDER, true)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_check(Input.is_action_pressed(&"missiles") and not Input.is_action_pressed(&"fire"), "RB+RT = missiles")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_btn(JOY_BUTTON_RIGHT_SHOULDER, false)
	_check(not Input.is_action_pressed(&"missiles"), "missiles released with RT")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_check(Input.is_action_pressed(&"fire"), "RT alone = fire")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_btn(JOY_BUTTON_LEFT_STICK, true)
	await _frames(12)
	_check(Input.is_action_pressed(&"assault"), "L3 alone = assault after the chord window")
	_btn(JOY_BUTTON_LEFT_STICK, false)
	_check(not Input.is_action_pressed(&"assault"), "assault released")
	_btn(JOY_BUTTON_LEFT_STICK, true)
	_btn(JOY_BUTTON_RIGHT_STICK, true)
	await _frames(12)
	_check(Input.is_action_pressed(&"overdrive"), "L3+R3 = overdrive")
	_check(not Input.is_action_pressed(&"assault") and not Input.is_action_pressed(&"lock_on"),
			"chord does not also fire assault / lock_on")
	_btn(JOY_BUTTON_RIGHT_STICK, false)
	await _frames(12)
	_check(not Input.is_action_pressed(&"overdrive") and not Input.is_action_pressed(&"assault"),
			"releasing one stick ends overdrive; the other does not commit later")
	_btn(JOY_BUTTON_LEFT_STICK, false)
	_btn(JOY_BUTTON_DPAD_UP, true)
	_btn(JOY_BUTTON_DPAD_UP, false)
	_check(Input.is_action_pressed(&"weapon_next"), "D-pad up tap = weapon_next (held for a few ticks)")
	await get_tree().create_timer(0.1, true, false, true).timeout
	_check(not Input.is_action_pressed(&"weapon_next"), "weapon_next auto-released")


## One check per SPEC §3 pad row that _pad_tests does not already cover. Every one of these was
## routed correctly but unguarded (finding input-pad-bindings-untested), so a refactor could drop a
## verb silently.
func _pad_rows() -> void:
	_btn(JOY_BUTTON_B, true)
	_check(Input.is_action_pressed(&"boost"), "B = boost")
	_btn(JOY_BUTTON_B, false)
	_btn(JOY_BUTTON_X, true)
	_check(Input.is_action_pressed(&"melee"), "X = melee")
	_btn(JOY_BUTTON_X, false)
	_btn(JOY_BUTTON_Y, true)
	_check(Input.is_action_pressed(&"anchor"), "Y = Skyhook anchor")
	_btn(JOY_BUTTON_Y, false)
	_btn(JOY_BUTTON_LEFT_SHOULDER, true)
	_check(Input.is_action_pressed(&"guard"), "LB = guard")
	_btn(JOY_BUTTON_LEFT_SHOULDER, false)
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	_check(Input.is_action_pressed(&"aim"), "LT = aim / ADS")
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_check(not Input.is_action_pressed(&"aim"), "LT released")
	# Sticks stay in the InputMap (PadInput does not translate them).
	_axis(JOY_AXIS_LEFT_X, -1.0)
	_check(Input.is_action_pressed(&"move_left"), "left stick X = move_left")
	_axis(JOY_AXIS_LEFT_Y, 1.0)
	_check(Input.is_action_pressed(&"move_back"), "left stick Y = move_back")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	_check(Input.is_action_pressed(&"look_right"), "right stick X = look_right")
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	_check(Input.is_action_pressed(&"look_up"), "right stick Y = look_up")
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	# R3 on its own commits lock_on once the chord window has passed.
	_btn(JOY_BUTTON_RIGHT_STICK, true)
	await _frames(12)
	_check(Input.is_action_pressed(&"lock_on"), "R3 alone = lock_on after the chord window")
	_check(not Input.is_action_pressed(&"overdrive"), "... and does not become overdrive")
	_btn(JOY_BUTTON_RIGHT_STICK, false)
	_check(not Input.is_action_pressed(&"lock_on"), "lock_on released with R3")
	# The shift layer, with the latch: a face button pressed under RB keeps its shifted action until
	# that button is released, whatever RB does meanwhile.
	for b: JoyButton in [JOY_BUTTON_Y, JOY_BUTTON_B, JOY_BUTTON_A]:
		var want: StringName = {JOY_BUTTON_Y: &"fins", JOY_BUTTON_B: &"rift_step", JOY_BUTTON_A: &"well"}[b]
		_btn(JOY_BUTTON_RIGHT_SHOULDER, true)
		_btn(b, true)
		_check(Input.is_action_pressed(want), "RB+%s = %s" % [_name(b), want])
		_btn(JOY_BUTTON_RIGHT_SHOULDER, false)
		_check(Input.is_action_pressed(want), "%s stays latched after RB is released" % want)
		_btn(b, false)
		_check(not Input.is_action_pressed(want), "%s released with its own button" % want)
	# D-pad left/right switch the lock (camera-aim r8 owns the consumer; this guards the action).
	_btn(JOY_BUTTON_DPAD_LEFT, true)
	_check(Input.is_action_pressed(&"lock_prev"), "D-pad left = lock_prev")
	_btn(JOY_BUTTON_DPAD_LEFT, false)
	_check(not Input.is_action_pressed(&"lock_prev"), "lock_prev released")
	_btn(JOY_BUTTON_DPAD_RIGHT, true)
	_check(Input.is_action_pressed(&"lock_next"), "D-pad right = lock_next")
	_btn(JOY_BUTTON_DPAD_RIGHT, false)
	_check(not Input.is_action_pressed(&"lock_next"), "lock_next released")
	# Camera toggle has two pad rows in SPEC §3: D-pad down and View.
	_btn(JOY_BUTTON_DPAD_DOWN, true)
	_check(Input.is_action_pressed(&"camera_toggle"), "D-pad down = camera_toggle")
	_btn(JOY_BUTTON_DPAD_DOWN, false)
	_btn(JOY_BUTTON_BACK, true)
	_check(Input.is_action_pressed(&"camera_toggle"), "View = camera_toggle")
	_btn(JOY_BUTTON_BACK, false)
	_btn(JOY_BUTTON_START, true)
	_check(Input.is_action_pressed(&"pause"), "Menu = pause")
	_btn(JOY_BUTTON_START, false)
	_check(not Input.is_action_pressed(&"pause"), "pause released")


func _name(b: JoyButton) -> String:
	return {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y"}.get(b, str(b))


## SPEC §3's 0.25 s tap/hold threshold: a reload must not fire at 0.20 s, must have fired by 0.27 s,
## and must not ALSO produce the tap's weapon_next on release.
func _reload_hold() -> void:
	await _settle()
	_btn(JOY_BUTTON_DPAD_UP, true)
	await _hold(0.20)
	_check(not Input.is_action_pressed(&"reload"), "D-pad up held 0.20 s has not reloaded yet")
	await _hold(0.07)
	_check(Input.is_action_pressed(&"reload"), "D-pad up reloaded by 0.27 s (SPEC §3 threshold 0.25 s)")
	_btn(JOY_BUTTON_DPAD_UP, false)
	var next := await _sampled(&"weapon_next", 6)
	_check(not next, "a reload hold does not also fire weapon_next on release")
	_check(not Input.is_action_pressed(&"reload"), "reload released with the D-pad")


## Real seconds, not frames: PadInput times the hold on Feel.real_now().
func _hold(seconds: float) -> void:
	var t := Feel.real_now()
	while Feel.real_now() - t < seconds:
		await get_tree().process_frame


## Was `action` pressed at any point over the next `frames` frames? (The D-pad tap holds an action for
## 3 physics ticks, so a single sample can miss it.)
func _sampled(action: StringName, frames: int) -> bool:
	var seen := false
	for i in frames:
		seen = seen or Input.is_action_pressed(action)
		await get_tree().process_frame
	return seen


func _settle() -> void:
	await get_tree().create_timer(0.15, true, false, true).timeout


func _clock_tests() -> void:
	Feel.slow_mo(0.3, 1.0, 0.0, 0.0, true)
	await _frames(6)
	_check(absf(Engine.time_scale - 0.3) < 0.02, "witch slow-mo sets time_scale 0.3 (got %.3f)" % Engine.time_scale)
	_check(absf(Feel.player_time_comp() * Engine.time_scale - 1.0) < 0.01, "player runs at full speed in witch time")
	_check(absf(Feel.real_delta(Engine.time_scale / 120.0) - 1.0 / 120.0) < 1e-5, "real_delta undoes the scale")
	Feel.hit_stop(0.2, 0.05)
	await _frames(3)
	_check(absf(Feel.player_time_comp() - 1.0) < 0.01,
			"a global hit-stop freezes the player even in witch time (comp %.2f)" % Feel.player_time_comp())
	await get_tree().create_timer(1.3, true, false, true).timeout
	_check(absf(Engine.time_scale - 1.0) < 0.01, "slow-mo ends on real time")
	_check(not Feel.is_witch_time(), "witch time cleared")
	_check(not Feel.hit_stop(0.0), "a zero-length hit-stop is refused")
	_check(Feel.hit_stop(0.05), "... and does not use up the rate-limit budget")
	var probe := Probe.new()
	add_child(probe)
	await get_tree().create_timer(0.3, true, false, true).timeout
	probe.max_real_dt = 0.0
	Feel.hit_stop(0.1, 0.05)
	await get_tree().create_timer(0.4, true, false, true).timeout
	_check(probe.max_real_dt < 0.1, "_process real_delta stays one frame across a hit-stop (max %.3f s)"
			% probe.max_real_dt)
	probe.queue_free()
