class_name MechInput
extends RefCounted
## One physics tick of intent, read from the contract actions (core/input_setup.gd). Edge flags are
## derived by polling (not `is_action_just_pressed`), because at 120 Hz several physics ticks share one
## rendered frame and a scripted `Input.action_press` must be seen exactly once.
## Timing is REAL time (CONTRACTS §3): `poll` gets the raw physics delta and divides the time scale out
## itself, so a double tap is as easy to hit in witch time as it is at normal speed.
##
## The revive latch (r16 B8): whatever is held when the death gate re-opens reads as RELEASED until it
## is actually let go. Without it the key that pressed RETRY would act — `ui_accept` includes Space and
## the pad's A, which are also `jump`. `swallow()` arms it and `PlayerMech` arms the same latch on the
## components, which poll `Input` themselves and cannot be edited from here.

## Every action the mech and its components read. The menu, the camera and the debug keys are
## deliberately not in it: they are not the mech's.
const ACTIONS: PackedStringArray = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"jump", &"descend", &"boost", &"assault",
	&"fire", &"aim", &"reload", &"weapon_next", &"weapon_prev", &"missiles",
	&"melee", &"guard", &"anchor", &"rift_step", &"fins", &"burst", &"well", &"overdrive",
	&"lock_on", &"lock_prev", &"lock_next",
]
## The subset THIS class polls, so the latch can be applied per action here.
const OWN: PackedStringArray = [&"move_forward", &"move_back", &"move_left", &"move_right",
		&"jump", &"descend", &"boost", &"assault"]
## The subset the components poll. `PlayerMech` keeps their `_physics_process` off until every one of
## these that was held at the revive has been released.
const COMPONENT: PackedStringArray = [
	&"fire", &"aim", &"reload", &"weapon_next", &"weapon_prev", &"missiles",
	&"melee", &"guard", &"anchor", &"rift_step", &"fins", &"burst", &"well", &"overdrive",
	&"lock_on", &"lock_prev", &"lock_next",
]

var move: Vector2 = Vector2.ZERO   ## x = right, y = forward, length <= 1
var jump_held: bool = false
var jump_pressed: bool = false     ## rising edge this tick
var jump_released: bool = false
var boost_held: bool = false
var boost_pressed: bool = false
var boost_released: bool = false
var assault_held: bool = false     ## SPEC §3: the assault boost is its own toggle (Left Alt / L3)
var assault_pressed: bool = false
var descend_held: bool = false
var double_jump: bool = false      ## this press is the second one inside `double_tap_window`

## Tuning choice: how close two jump presses must be to count as the flight toggle.
var double_tap_window: float = 0.30
## How long a press latched during a hit-stop stays buffered before it is dropped.
var buffer_window: float = 0.30

var _prev_jump: bool = false
var _prev_boost: bool = false
var _prev_assault: bool = false
var _last_jump_press: float = -100.0
var _t: float = 0.0
## Edges that arrived while the mech was frozen (a local hit-stop, CONTRACTS §4). Juice §2.2: an
## input pressed during a stop is buffered, not eaten, so it fires on the first tick that can act.
var _pend_jump: bool = false
var _pend_boost: bool = false
var _pend_assault: bool = false
var _pend_double: bool = false
var _pend_t: float = -100.0
## Actions held when the death gate re-opened; each reads as released until it is let go (r16 B8).
var _swallow: Dictionary = {}


static func held_actions() -> PackedStringArray:
	return _held_of(ACTIONS)


static func held_component_actions() -> PackedStringArray:
	return _held_of(COMPONENT)


static func _held_of(list: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for a in list:
		if InputMap.has_action(a) and Input.is_action_pressed(a):
			out.append(String(a))
	return out


func poll(delta: float) -> void:
	var rd := Feel.real_delta(delta)
	_t += rd
	move = _move_vector()
	if move.length() > 1.0:
		move = move.normalized()
	descend_held = _held(&"descend")

	var jump := _held(&"jump")
	jump_pressed = jump and not _prev_jump
	jump_released = not jump and _prev_jump
	jump_held = jump
	double_jump = false
	if jump_pressed:
		# The press is only ever seen at a tick boundary, so the true gap is up to one tick shorter than
		# the measured one: allowing that tick keeps the window honest at 36 ticks/s (time scale 0.3).
		double_jump = _t - _last_jump_press - rd <= double_tap_window
		_last_jump_press = _t
	_prev_jump = jump

	var boost := _held(&"boost")
	boost_pressed = boost and not _prev_boost
	boost_released = not boost and _prev_boost
	boost_held = boost
	_prev_boost = boost

	var assault := _held(&"assault")
	assault_pressed = assault and not _prev_assault
	assault_held = assault
	_prev_assault = assault


## An action held since before the revive reads as released, and drops out of the latch the moment it
## is really let go. Everything else is a plain `Input.is_action_pressed`.
func _held(action: StringName) -> bool:
	var down := Input.is_action_pressed(action)
	if _swallow.is_empty():
		return down
	var key := String(action)
	if not down:
		_swallow.erase(key)
		return false
	return not _swallow.has(key)


## `Input.get_vector` cannot be asked per action, so while the latch is armed the stick is rebuilt
## from the four direction actions (a swallowed one contributes nothing).
func _move_vector() -> Vector2:
	if _swallow.is_empty():
		return Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	var v := Vector2.ZERO
	if _held(&"move_right"):
		v.x += 1.0
	if _held(&"move_left"):
		v.x -= 1.0
	if _held(&"move_forward"):
		v.y += 1.0
	if _held(&"move_back"):
		v.y -= 1.0
	return v


## Arm the latch with whatever is held right now, and adopt it as the previous state so nothing
## produces an edge on the next poll.
func swallow(held: PackedStringArray) -> void:
	_swallow.clear()
	for a in held:
		if a in OWN:
			_swallow[String(a)] = true
	_prev_jump = Input.is_action_pressed(&"jump")
	_prev_boost = Input.is_action_pressed(&"boost")
	_prev_assault = Input.is_action_pressed(&"assault")
	_last_jump_press = -100.0


## Called on a tick the mech is frozen: keep this tick's rising edges for later and hide them from
## the states, which are not running now and must not see a press they cannot act on.
func latch_edges() -> void:
	if jump_pressed or boost_pressed or assault_pressed:
		_pend_t = _t
	_pend_jump = _pend_jump or jump_pressed
	_pend_boost = _pend_boost or boost_pressed
	_pend_assault = _pend_assault or assault_pressed
	_pend_double = _pend_double or double_jump
	jump_pressed = false
	boost_pressed = false
	assault_pressed = false
	double_jump = false


## Called on the first tick whose state can act on them (a combat lock keeps the press buffered):
## fold the edges back in so that state reads them now. A press older than `buffer_window` is dropped.
func release_edges() -> void:
	if _t - _pend_t > buffer_window:
		_pend_jump = false
		_pend_boost = false
		_pend_assault = false
		_pend_double = false
	if not (_pend_jump or _pend_boost or _pend_assault):
		return
	jump_pressed = jump_pressed or _pend_jump
	boost_pressed = boost_pressed or _pend_boost
	assault_pressed = assault_pressed or _pend_assault
	double_jump = double_jump or _pend_double
	_pend_jump = false
	_pend_boost = false
	_pend_assault = false
	_pend_double = false


## Test/tool hook: forget the last jump press so a fresh double tap is required.
func reset_taps() -> void:
	_last_jump_press = -100.0
	_prev_jump = Input.is_action_pressed(&"jump")
	_prev_boost = Input.is_action_pressed(&"boost")
	_prev_assault = Input.is_action_pressed(&"assault")
	_swallow.clear()
	_pend_jump = false
	_pend_boost = false
	_pend_assault = false
	_pend_double = false
