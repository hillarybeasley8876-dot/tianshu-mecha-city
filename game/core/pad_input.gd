extends Node
## PadInput (autoload, core-owned): the ONLY place gamepad buttons become actions, so chords and the
## shift layer have one owner. Sticks stay in the InputMap (core/input_setup.gd); keyboard/mouse too.
##
## Layout (SPEC §3):
##   A jump · B boost · X melee · Y anchor · LB guard · RT fire · LT aim · R3 lock_on · L3 assault
##   L3+R3 (within 4 frames, both held) = overdrive · D-pad ↑ weapon_next (hold = reload) · ↓ camera_toggle
##   ← / → lock_prev / lock_next · View camera_toggle · Menu pause
##   RB = SHIFT layer (no own action): RB+RT missiles (hold paints, release fires) · RB+X burst ·
##   RB+Y fins (hold = ward) · RB+B rift_step · RB+A well
## A face button pressed with RB held keeps its shifted action until that button is released (latched),
## whatever RB does meanwhile; a button pressed before RB keeps its normal action.

const TRIGGER_ON := 0.35
const TRIGGER_OFF := 0.25
const CHORD_WINDOW := 4.0 / 60.0   ## seconds (real time) L3 waits for R3 before committing assault
## SPEC §3's tap/hold threshold. The D-pad sits under the left thumb, so every 1/100 s here is 1/100 s
## the thumb is off the stick: at 0.4 s a manual reload broke ACCEPTANCE §2's "never more than 0.3 s".
const RELOAD_HOLD := 0.25

const NORMAL: Dictionary = {
	JOY_BUTTON_A: &"jump", JOY_BUTTON_B: &"boost", JOY_BUTTON_X: &"melee", JOY_BUTTON_Y: &"anchor",
	JOY_BUTTON_LEFT_SHOULDER: &"guard", JOY_BUTTON_RIGHT_STICK: &"lock_on",
	JOY_BUTTON_DPAD_DOWN: &"camera_toggle", JOY_BUTTON_DPAD_LEFT: &"lock_prev",
	JOY_BUTTON_DPAD_RIGHT: &"lock_next", JOY_BUTTON_BACK: &"camera_toggle", JOY_BUTTON_START: &"pause",
}
const SHIFTED: Dictionary = {
	JOY_BUTTON_A: &"well", JOY_BUTTON_B: &"rift_step", JOY_BUTTON_X: &"burst", JOY_BUTTON_Y: &"fins",
}

var _rb: bool = false
var _latched: Dictionary = {}      ## button -> action currently pressed for it
var _rt_action: StringName = &""   ## fire or missiles while the trigger is down
var _stick_at: Dictionary = {JOY_BUTTON_LEFT_STICK: -1.0, JOY_BUTTON_RIGHT_STICK: -1.0}   ## press time
var _stick_action: Dictionary = {JOY_BUTTON_LEFT_STICK: &"", JOY_BUTTON_RIGHT_STICK: &""}  ## committed
var _dpad_up_at: float = -1.0
var _reload_sent: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_button(event as InputEventJoypadButton)
	elif event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		if m.axis == JOY_AXIS_TRIGGER_RIGHT:
			_trigger(m.axis_value)


func _process(_delta: float) -> void:
	var now := Feel.real_now()
	for b: int in _stick_at:
		if _stick_at[b] >= 0.0 and _stick_action[b] == &"" and now - float(_stick_at[b]) >= CHORD_WINDOW:
			_stick_action[b] = &"assault" if b == JOY_BUTTON_LEFT_STICK else &"lock_on"
			Input.action_press(_stick_action[b])
	if _dpad_up_at >= 0.0 and not _reload_sent and now - _dpad_up_at >= RELOAD_HOLD:
		_reload_sent = true
		Input.action_press(&"reload")


func _button(e: InputEventJoypadButton) -> void:
	var b := e.button_index
	if b == JOY_BUTTON_RIGHT_SHOULDER:
		_rb = e.pressed
	elif b == JOY_BUTTON_LEFT_STICK or b == JOY_BUTTON_RIGHT_STICK:
		_stick(b, e.pressed)
	elif b == JOY_BUTTON_DPAD_UP:
		_dpad_up(e.pressed)
	elif e.pressed:
		var action: StringName = SHIFTED.get(b, &"") if _rb else &""
		if action == &"":
			action = NORMAL.get(b, &"")
		if action != &"" and not _latched.has(b):
			_latched[b] = action
			Input.action_press(action)
	elif _latched.has(b):
		Input.action_release(_latched[b])
		_latched.erase(b)


## L3 / R3: each waits CHORD_WINDOW; pressed together they become one `overdrive` press.
func _stick(b: int, pressed: bool) -> void:
	var other: int = JOY_BUTTON_RIGHT_STICK if b == JOY_BUTTON_LEFT_STICK else JOY_BUTTON_LEFT_STICK
	if pressed:
		_stick_at[b] = Feel.real_now()
		if float(_stick_at[other]) >= 0.0 and _stick_action[other] == &"":
			_stick_action[b] = &"overdrive"
			_stick_action[other] = &"overdrive"
			Input.action_press(&"overdrive")
		return
	_stick_at[b] = -1.0
	var action: StringName = _stick_action[b]
	_stick_action[b] = &""
	if action == &"overdrive":
		_stick_action[other] = &"done" if float(_stick_at[other]) >= 0.0 else &""
		Input.action_release(&"overdrive")
	elif action != &"" and action != &"done":
		Input.action_release(action)


## D-pad up: tap = weapon_next (on release), hold ≥ RELOAD_HOLD = reload.
func _dpad_up(pressed: bool) -> void:
	if pressed:
		_dpad_up_at = Feel.real_now()
		_reload_sent = false
		return
	_dpad_up_at = -1.0
	if _reload_sent:
		Input.action_release(&"reload")
	else:
		_tap(&"weapon_next")


## Press for 3 physics ticks of real time so `_physics_process` readers always see it.
func _tap(action: StringName) -> void:
	Input.action_press(action)
	get_tree().create_timer(3.0 / 120.0, true, false, true).timeout.connect(
			func() -> void: Input.action_release(action))


func _trigger(value: float) -> void:
	if _rt_action == &"" and value >= TRIGGER_ON:
		_rt_action = &"missiles" if _rb else &"fire"
		Input.action_press(_rt_action, clampf(value, 0.0, 1.0))
	elif _rt_action != &"" and value <= TRIGGER_OFF:
		Input.action_release(_rt_action)
		_rt_action = &""
