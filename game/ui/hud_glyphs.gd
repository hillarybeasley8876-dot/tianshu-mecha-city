class_name HudGlyphs
extends RefCounted
## Key / button glyphs for the HUD (brief §8): every prompt and hotbar slot shows the binding for the
## device the player last touched, so a pad player never sees "LMB". Bindings are SPEC §3; the action
## names are the contract in `core/input_setup.gd`, and on the pad the chords come from the `PadInput`
## autoload (`core/pad_input.gd`) — RB is a pure shift layer, so four verbs read as "RB + face button".

const ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right", "look_up", "look_down", "look_left",
	"look_right", "fire", "aim", "jump", "descend", "boost", "assault", "melee", "guard", "missiles",
	"anchor", "rift_step", "fins", "burst", "well", "reload", "weapon_next", "weapon_prev",
	"overdrive", "lock_on", "lock_prev", "lock_next", "camera_toggle", "pause",
]

## Pad glyphs, SPEC §3. RB is the shift layer: RB+RT / RB+X / RB+Y / RB+B / RB+A.
const PAD: Dictionary = {
	&"fire": "RT", &"aim": "LT", &"jump": "A", &"descend": "B", &"boost": "B", &"assault": "L3",
	&"melee": "X", &"guard": "LB", &"missiles": "RB+RT", &"anchor": "Y", &"rift_step": "RB+B",
	&"fins": "RB+Y", &"burst": "RB+X", &"well": "RB+A", &"reload": "D↑", &"weapon_next": "D↑",
	&"weapon_prev": "D↑", &"overdrive": "L3+R3", &"lock_on": "R3", &"lock_prev": "D←",
	&"lock_next": "D→", &"camera_toggle": "D↓", &"pause": "MENU",
	&"move_forward": "LS", &"move_back": "LS", &"move_left": "LS", &"move_right": "LS",
	&"look_up": "RS", &"look_down": "RS", &"look_left": "RS", &"look_right": "RS",
}

## Keyboard + mouse, SPEC §3.
const KEYBOARD: Dictionary = {
	&"fire": "LMB", &"aim": "RMB", &"jump": "SPACE", &"descend": "CTRL", &"boost": "SHIFT",
	&"assault": "L ALT", &"melee": "F", &"guard": "Q", &"missiles": "1", &"anchor": "E",
	&"rift_step": "C", &"fins": "Z", &"burst": "X", &"well": "G", &"reload": "R",
	&"weapon_next": "WHEEL", &"weapon_prev": "WHEEL", &"overdrive": "V", &"lock_on": "TAB",
	&"camera_toggle": "B", &"pause": "ESC",
	&"move_forward": "W", &"move_back": "S", &"move_left": "A", &"move_right": "D",
	&"look_up": "MOUSE", &"look_down": "MOUSE", &"look_left": "MOUSE", &"look_right": "MOUSE",
}

## Pad buttons the shift layer is not part of, watched for the device switch.
const PAD_BUTTONS: Array[int] = [
	JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
	JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT,
	JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_START, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK,
]
const PAD_AXES: Array[int] = [
	JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y,
	JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT,
]
## Actions whose only binding is a pad stick/button, so they cannot prove keyboard use.
const STICK_ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right", "look_up", "look_down", "look_left",
	"look_right", "assault", "lock_prev", "lock_next",
]

var pad_active: bool = false


## Watches both devices: any pad button, trigger or stick movement flips the HUD to pad glyphs, and a
## key or mouse movement flips it back.
func poll() -> bool:
	if _pad_moved():
		pad_active = true
	elif _key_or_mouse_moved():
		pad_active = false
	return pad_active


func _pad_moved() -> bool:
	for device in Input.get_connected_joypads():
		for b in PAD_BUTTONS:
			if Input.is_joy_button_pressed(device, b):
				return true
		for axis in PAD_AXES:
			if absf(Input.get_joy_axis(device, axis)) > 0.35:
				return true
	return false


func _key_or_mouse_moved() -> bool:
	if Input.get_last_mouse_velocity().length_squared() > 4.0:
		return true
	for action: String in ACTIONS:
		if action in STICK_ACTIONS or not InputMap.has_action(action):
			continue
		if Input.is_action_pressed(action):
			return true
	return false


## The glyph to print for `action` on the device the player is currently using. `lock_prev` and
## `lock_next` are `PAD_ONLY` (`core/input_setup.gd`): they have no keyboard binding at all, so a
## keyboard glyph for them would name a key that does nothing (camera-aim r8). They fall back to the
## pad button they really are.
func glyph(action: StringName) -> String:
	var table := PAD if pad_active else KEYBOARD
	if table.has(action):
		return String(table[action])
	return String(PAD.get(action, String(action).to_upper()))
