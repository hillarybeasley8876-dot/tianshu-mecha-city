extends RefCounted
## Registers every input action at startup (keyboard/mouse + gamepad) so units never edit
## project.godot. Action names are a core contract (CONTRACTS.md §Input); bindings may change.
##
## Semantics (implemented by the owning units; numbers in docs/SPEC.md):
##   boost        tap = dash (quick boost, i-frames); hold = boost slide (ground) / glide (air) — sustained.
##   assault      toggle assault boost (KB Left Alt / pad L3); a dash or a 0.25 s skid brake exits.
##   jump         tap = jump, hold = hover/ascend, double-tap in the air = toggle flight mode.
##   descend      flight: go down.        aim       hold = ADS zoom (and guided missiles after release)
##   fire         tap = shot, hold = charged shot (rifle); gatling: hold to fire, press on the vent mark.
##   melee        tap combo; hold = charged slash; locked 24–80 m = lunge; air hold = plunge breaker;
##                staggered target in reach = execution.
##   guard        tap = perfect-parry window, hold = block, hold ≥0.3 s = catch field.
##   missiles     hold = paint up to 12 locks, release = salvo.     anchor   grapple (skyhook)
##   rift_step    blink (with direction).   fins   tap = send drones, hold = drone barrier (ward)
##   burst        360° shockcore.           well   gravity well (undertow)
##   overdrive    hold 0.25 s = overdrive (OD 100 %); press again = lance finale. (pad: L3+R3)
## Input TIMING (tap/hold thresholds, double-taps, buffers, chords) must use real time:
## `Feel.real_delta(delta)` or `Feel.real_now()` — never raw scaled delta (CONTRACTS §3 clocks).

const KEYS: Dictionary = {
	&"move_forward": [KEY_W],
	&"move_back": [KEY_S],
	&"move_left": [KEY_A],
	&"move_right": [KEY_D],
	&"jump": [KEY_SPACE],
	&"descend": [KEY_CTRL],
	&"boost": [KEY_SHIFT],
	&"assault": [KEY_ALT],
	&"melee": [KEY_F],
	&"guard": [KEY_Q],
	&"missiles": [KEY_1],
	&"anchor": [KEY_E],
	&"rift_step": [KEY_C],
	&"fins": [KEY_Z],
	&"burst": [KEY_X],
	&"well": [KEY_G],
	&"reload": [KEY_R],
	&"overdrive": [KEY_V],
	&"camera_toggle": [KEY_B],
	&"lock_on": [KEY_TAB],
	&"pause": [KEY_ESCAPE],
	&"toggle_fullscreen": [KEY_F11],
	&"debug_toggle": [KEY_F3],
}
const MOUSE: Dictionary = {
	&"fire": [MOUSE_BUTTON_LEFT],
	&"aim": [MOUSE_BUTTON_RIGHT],
	&"lock_on": [MOUSE_BUTTON_MIDDLE],
	&"missiles": [MOUSE_BUTTON_XBUTTON1],
	&"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN],
	&"weapon_prev": [MOUSE_BUTTON_WHEEL_UP],
}
## Gamepad BUTTONS and the fire trigger are translated by the PadInput autoload (core/pad_input.gd: shift
## layer + chords). These actions only come from PadInput (or tools) and need to exist in the InputMap.
const PAD_ONLY: Array[StringName] = [&"lock_prev", &"lock_next"]
## action: [axis, direction]
const AXES: Dictionary = {
	&"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	&"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	&"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	&"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	&"aim": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}
## descend on the pad = B held during flight (the mech-move unit maps boost→descend while flying).


## Idempotent: does nothing when the actions already exist (e.g. a tool script registered them).
static func register_actions() -> void:
	if InputMap.has_action(&"move_forward"):
		return
	for action: StringName in KEYS:
		for key: int in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			_add(action, ev)
	for action: StringName in MOUSE:
		for button: int in MOUSE[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button as MouseButton
			_add(action, ev)
	for action: StringName in PAD_ONLY:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
	for action: StringName in AXES:
		var ev := InputEventJoypadMotion.new()
		ev.axis = AXES[action][0] as JoyAxis
		ev.axis_value = AXES[action][1]
		_add(action, ev)


static func _add(action: StringName, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	InputMap.action_add_event(action, ev)
