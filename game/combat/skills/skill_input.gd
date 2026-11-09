class_name SkillInput
extends RefCounted
## Input routing for the SkillSystem: one place that turns the registered actions (CONTRACTS §3) into
## activations, including the two gestures that still need timing — the Corona Fins tap / 0.35 s hold
## split and the Zenith Overdrive's 0.25 s ignition hold.
##
## Every press-edge skill (Rift Step, Skyhook Anchor, Shockcore Burst, Undertow Well and the Lance)
## goes through ONE shared 6 f buffer on the REAL clock (SPEC §3 "input buffer 6 f for combos /
## cancels"): the press fires on the edge, and a press `can_act()` refuses waits in the buffer and
## fires on the first tick the mech may act. There is no chord arbitration left — since 37e66d6 Rift
## Step is C / RB+B and the L3+R3 Overdrive chord lives in `core/pad_input.gd`.
##
## It holds only the gesture state; every decision about whether a skill may actually fire stays in
## SkillSystem (cooldowns, charges, EN) and in the skills themselves.

const BUFFER := 6.0 / 60.0   ## SPEC §3, real clock: 6 frames at the dossier's 60 fps

var system: SkillSystem = null

var _player: Node = null
var _buffer: Dictionary[StringName, float] = {}   ## action -> seconds of buffer left
var _lance_pending: bool = false   ## a Lance press held through the 0.45 s ignition (LOCKED)
var _fins_held: float = -1.0
var _fins_warded: bool = false
var _melee_held: float = 0.0
var _od_held: float = 0.0
var _dead: bool = false


func _init(system_: SkillSystem) -> void:
	system = system_


func setup(player: Node) -> void:
	_player = player


func tick(delta: float) -> void:
	if _player == null or system == null:
		return
	if not alive():
		_on_dead()
		return
	_dead = false
	_edges()
	_tick_buffer(delta)
	_try_lance()
	_fins(delta)
	_plunge(delta)
	_overdrive(delta)


## CONTRACTS §5 / mech-move r7: `PlayerMech.is_alive()` is the single death predicate. While it is
## false NO skill input changes skill state, EN, cooldowns or events, and a press made in that window
## is dropped rather than carried into the first live tick.
func alive() -> bool:
	if _player == null or not _player.has_method(&"is_alive"):
		return true
	return bool(_player.call(&"is_alive"))


func _on_dead() -> void:
	if _dead:
		return
	_dead = true
	_buffer.clear()
	_lance_pending = false
	_fins_held = -1.0
	_fins_warded = false
	_melee_held = 0.0
	_od_held = 0.0
	system.on_player_died()


# --- the shared press buffer -----------------------------------------------------------------------

## Fires on the press edge, exactly like the burst and the well always did. `can_act()` refusing is
## not a refusal: the press goes into the buffer and fires on the first tick the mech may act.
func _edges() -> void:
	if Input.is_action_just_pressed(&"rift_step"):
		_press(&"rift_step")
	if Input.is_action_just_pressed(&"anchor"):
		_press(&"anchor")
	if Input.is_action_just_pressed(&"burst"):
		_press(&"burst")
	if Input.is_action_just_pressed(&"well"):
		_press(&"well")
	if Input.is_action_just_pressed(&"overdrive"):
		_overdrive_edge()


func _press(action: StringName) -> void:
	_buffer[action] = BUFFER
	_flush(action)


func _tick_buffer(delta: float) -> void:
	for action: StringName in _buffer.keys():
		var left: float = _buffer[action] - delta
		if left <= 0.0:
			_buffer.erase(action)
			continue
		_buffer[action] = left
		_flush(action)


func _flush(action: StringName) -> void:
	if not _buffer.has(action) or not system.can_act():
		return
	_buffer.erase(action)
	_fire(action)


func _fire(action: StringName) -> void:
	match action:
		&"rift_step":
			system.try_rift_step()
		&"anchor":
			_anchor()
		&"burst":
			system.try_burst()
		&"well":
			system.try_well()


## The anchor action is a toggle: a second press lets go of the line.
func _anchor() -> void:
	if system.anchor.is_attached():
		system.anchor.detach(true)
	else:
		system.try_anchor()


# --- the two gestures that still need timing -------------------------------------------------------

## Tap sends the fins, a 0.35 s hold raises the Corona Ward. Holding while the ward is still cooling
## falls back to the tap on release, so the gesture never silently eats the press.
func _fins(delta: float) -> void:
	if Input.is_action_just_pressed(&"fins"):
		_fins_held = 0.0
		_fins_warded = false
		return
	if _fins_held < 0.0:
		return
	if Input.is_action_pressed(&"fins"):
		_fins_held += delta
		if not _fins_warded and _fins_held >= system.tuning.ward_hold:
			_fins_warded = system.try_ward()
		return
	var tapped := not _fins_warded and _fins_held < system.tuning.ward_hold
	_fins_held = -1.0
	_fins_warded = false
	if tapped and system.can_act():
		system.try_fins()


## SPEC §3: melee held in the air is the Plunge Breaker. The height gate is checked before the charge
## accumulates, so a hold too close to the ground stays available to the melee unit's charged slash.
func _plunge(delta: float) -> void:
	if system.plunge.is_diving():
		_melee_held = 0.0
		return
	if not Input.is_action_pressed(&"melee"):
		_melee_held = 0.0
		return
	if not system.plunge.height_ok():
		return
	_melee_held += delta
	if _melee_held >= system.tuning.plunge_hold:
		_melee_held = 0.0
		system.try_plunge()


## A press while the Overdrive runs (or during its 0.45 s ignition) is the LANCE: SPEC §3 gives it
## "V hold 0.25 s / V", so the press edge fires it and the hold is only the ignition. Otherwise the
## press starts the 0.25 s ignition hold.
func _overdrive_edge() -> void:
	if system.is_overdrive_active() or system.zenith.is_igniting():
		_od_held = -1.0   # this hold is a Lance press; it must never become an ignition
		_lance_pending = true
		return
	_od_held = 0.0


## The ignition hold. It latches (`_od_held = -1`) until release, so one 1 s hold ignites and never
## also fires the Lance (audit #8). On the pad `overdrive` stays pressed for as long as L3+R3 are
## held, so it hit pads too.
func _overdrive(delta: float) -> void:
	if not Input.is_action_pressed(&"overdrive"):
		_od_held = 0.0
		return
	if _od_held < 0.0:
		return   # latched: this hold already decided, and it is still down
	_od_held += delta
	if _od_held < system.tuning.od_hold:
		return
	_od_held = -1.0
	system.try_overdrive()


## A Lance press during the ignition is LOCKED and held: it fires on the tick the ignition ends.
func _try_lance() -> void:
	if not _lance_pending or not system.zenith.can_fire_lance():
		return
	_lance_pending = false
	system.zenith.begin_lance()


## How many seconds of buffer a pending press has left (0 = nothing pending). Tests read it.
func buffer_left(action: StringName) -> float:
	return float(_buffer.get(action, 0.0))


func lance_pending() -> bool:
	return _lance_pending


func reset() -> void:
	_buffer.clear()
	_lance_pending = false
	_fins_held = -1.0
	_fins_warded = false
	_melee_held = 0.0
	_od_held = 0.0
