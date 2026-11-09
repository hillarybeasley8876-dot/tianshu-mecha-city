extends "res://player/mech/tests/mech_test_base.gd"
## mech-move flight-entry suite (lead r6). SPEC §3: a double tap of `jump` toggles free 3D flight.
## Every check here goes through the REAL input path — `Input.parse_input_event` with the physical key
## events a keyboard sends, held for the same 3 rendered frames the autoplay's `tap` uses — because
## the toggle is an edge the state machine has to see exactly once per press.
##
## The bug this pins: `double_jump` used to be honoured in `MechAir.air()` only, so a double tap
## pressed while boosting, dashing, landing or inside the ground knee-dip was answered with a plain
## jump and the flight toggle was thrown away.

const KEY: Dictionary = {&"jump": KEY_SPACE, &"boost": KEY_SHIFT, &"assault": KEY_ALT,
		&"descend": KEY_CTRL}
## `tools/autoplay.gd`'s `tap` holds an action for 3 rendered frames = 6 physics ticks at 120 Hz.
const TAP_TICKS := 6
## 0.22 s between the two presses: the gap `trailer/tl_s06_flight.json` uses.
const TRAILER_GAP := 20
## SPEC §4 knee-dip is 4 frames (67 ms = 8 ticks), so a 58 ms tap-tap lands inside it.
const KNEE_GAP := 1
## The toggle must fire within 0.1 s (12 ticks) of the second press.
const DEADLINE := 12


func _run() -> void:
	await _setup()
	await _test_ground_tap_tap()
	await _test_ground_fast_tap_tap()
	await _test_falling_tap_tap()
	await _test_hovering_tap_tap()
	await _test_boost_slide_tap_tap()
	await _test_assault_tap_tap()
	await _test_dash_tap_tap()
	await _test_single_tap_still_jumps()
	await _test_hold_still_hovers()
	await _test_double_tap_exits_flight()
	await _test_outage_blocks_flight()
	await _test_en_empty_exits_flight()
	_report("mech-move flight input")


# --- the real input path -------------------------------------------------------------------------

## One key event exactly as the OS delivers it: a physical keycode the InputMap already binds
## (core/input_setup.gd), fed through `Input.parse_input_event` instead of `Input.action_press`.
func _key(action: StringName, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY[action] as Key
	ev.pressed = pressed
	Input.parse_input_event(ev)


## A keyboard tap: press, hold `hold` physics ticks, release.
func _key_tap(action: StringName, hold: int = TAP_TICKS) -> void:
	_key(action, true)
	await _step(hold)
	_key(action, false)


## Presses jump, holds it `hold` ticks, releases, waits `gap` ticks and presses again. Returns the
## physics ticks from the SECOND press until `is_flying()` equals `want`, or -1 when it never got
## there. `want = false` is the SPEC §3 exit toggle.
func _tap_tap(hold: int, gap: int, want: bool = true) -> int:
	await _key_tap(&"jump", hold)
	await _step(gap)
	_key(&"jump", true)
	var ticks := 0
	while ticks < 30 and _p.is_flying() != want:
		await get_tree().physics_frame
		ticks += 1
	_key(&"jump", false)
	return ticks if _p.is_flying() == want else -1


func _flew(ticks: int, label: String, detail: String = "") -> void:
	_ok(ticks >= 0 and ticks <= DEADLINE, label,
			"%s%s" % [detail, "" if ticks < 0 else "%d ticks" % ticks])


## Flat ground, camera level, nothing held: the plain tap-tap of `trailer/tl_s06_flight.json`.
func _test_ground_tap_tap() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_flew(await _tap_tap(TAP_TICKS, TRAILER_GAP), "tap-tap on the ground enters flight (0.22 s gap)")


## A fast human double tap (50 ms) lands inside the SPEC §4 knee-dip, which used to swallow it.
func _test_ground_fast_tap_tap() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_flew(await _tap_tap(TAP_TICKS, KNEE_GAP), "a 58 ms tap-tap inside the knee-dip still flies")


func _test_falling_tap_tap() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_p.debug_teleport([0.0, 150.0, 60.0], 0.0)
	await _step(30)
	_ok(_p.move_state() == &"fall", "the mech is falling before the taps", String(_p.move_state()))
	_flew(await _tap_tap(TAP_TICKS, TRAILER_GAP), "a double tap while falling enters flight")


## The first press is HELD, so the mech is hovering (SPEC §4 ascend) when the second press arrives.
func _test_hovering_tap_tap() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_key(&"jump", true)
	await _step(20)
	var state := _p.move_state()
	_key(&"jump", false)
	await _step(6)
	_key(&"jump", true)
	var ticks := 0
	while ticks < 30 and not _p.is_flying():
		await get_tree().physics_frame
		ticks += 1
	_key(&"jump", false)
	_ok(state == &"hover", "holding jump hovers before the second tap", String(state))
	_flew(ticks if _p.is_flying() else -1, "a double tap while hovering enters flight")


## The trailer's own shape: boost held, then tap-tap. `MechBoost.slide` answered both presses with a
## plain hop, so holding boost made the flight toggle unreachable.
func _test_boost_slide_tap_tap() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_key(&"boost", true)
	await _until_state(&"slide", 90)
	await _step(10)
	var sliding := _p.move_state() == &"slide"
	_flew(await _tap_tap(TAP_TICKS, TRAILER_GAP), "a double tap during a boost slide enters flight",
			"sliding=%s " % sliding)
	_key(&"boost", false)
	await _step(10)


## The assault boost is a toggle (SPEC §3), so the taps land in the air after the first hop.
func _test_assault_tap_tap() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	await _key_tap(&"assault")
	await _until_state(&"assault", 90)
	await _step(10)
	_flew(await _tap_tap(TAP_TICKS, TRAILER_GAP), "a double tap during an assault boost enters flight")
	_p.call(&"debug_teleport", [0.0, GROUND_Y, 60.0], 0.0)
	await _step(10)


## A dash ignores jump while its i-frames run (the dodge is committed), so the pair below starts
## inside them: the first press is dropped and the second, past the 12 i-frame ticks but still inside
## the 30 tick jet, must be read as the flight toggle.
func _test_dash_tap_tap() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	await _key_tap(&"boost", 2)
	await _until_prefix("dash", 30)
	var dashing := _dashing()
	_flew(await _tap_tap(TAP_TICKS, 8), "a double tap during a dash enters flight",
			"dashing=%s " % dashing)


func _test_single_tap_still_jumps() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	var y0 := _p.global_position.y
	await _key_tap(&"jump")
	await _step(20)
	_ok(_p.global_position.y > y0 + 2.0 and not _p.is_flying(),
			"a single tap still jumps and does not fly",
			"dy=%.1f flying=%s" % [_p.global_position.y - y0, _p.is_flying()])
	await _reset(Vector3(0.0, GROUND_Y, 60.0))


func _test_hold_still_hovers() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_key(&"jump", true)
	await _until_state(&"hover", 90)
	await _step(20)
	var state := _p.move_state()
	_key(&"jump", false)
	_ok(state == &"hover" and not _p.is_flying(), "holding jump hovers and does not fly", String(state))
	await _step(20)


## SPEC §3: the same double tap toggles flight back off.
func _test_double_tap_exits_flight() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	await _enter_flight()
	await _step(50)  # let the double-tap window lapse, or the next press would toggle straight back on
	_ok(_p.is_flying(), "flight is on before the exit tap-tap", String(_p.move_state()))
	var ticks := await _tap_tap(TAP_TICKS, TRAILER_GAP, false)
	_ok(ticks >= 0 and ticks <= DEADLINE, "a double tap in flight leaves flight",
			"%s %d ticks" % [_p.move_state(), ticks])
	await _reset(Vector3(0.0, GROUND_Y, 60.0))


## SPEC §4 Outage: no thrusters, so the toggle must not light the jet on an empty gauge.
func _test_outage_blocks_flight() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_p.drain_energy(_p.energy_max, true)
	await _step(4)
	var outage := _p.hud_state()["outage"] as bool
	var ticks := await _tap_tap(TAP_TICKS, TRAILER_GAP)
	_ok(outage and ticks < 0, "an Outage blocks the flight toggle",
			"outage=%s flying=%s" % [outage, _p.is_flying()])
	await _reset(Vector3(0.0, GROUND_Y, 60.0))


## SPEC §3/§4: at EN 0 flight ends by itself and the mech leaves into the unpowered glide.
func _test_en_empty_exits_flight() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_p.debug_teleport([0.0, 150.0, 60.0], 0.0)
	await _step(20)
	await _enter_flight()
	await _step(10)
	_ok(_p.is_flying(), "flight is on before the gauge runs out", String(_p.move_state()))
	_p.energy = 1.0
	await _step(20)
	_ok(not _p.is_flying() and _p.move_state() == &"glide",
			"an empty gauge drops the mech out of flight into a glide", String(_p.move_state()))
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
