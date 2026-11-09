extends "res://player/mech/tests/mech_test_base.gd"
## Shared harness for `test_death.gd` (mech-move r7): the REAL input path (`Input.parse_input_event`
## with the physical key and mouse events a device sends, the bindings of `core/input_setup.gd`), the
## event counters the dead-input list checks, a lock-on target so `lock_changed` can fire while the
## mech is alive, the killing blow and the revive exactly as `flow_progress.gd` `_restore_player`
## writes it (flow's commit 5129b4c).
##
## `tools/autoplay.gd`'s `tap` holds an action for 3 rendered frames = 6 physics ticks at 120 Hz.

const TAP_TICKS := 6
## V held this long is the Overdrive gesture (SPEC §4 / core/input_setup.gd).
const OD_HOLD := 45
## Every action the dead-input list presses, with the physical key or mouse button behind it
## (core/input_setup.gd). `1` and MOUSE4 are both `missiles`; Tab and MMB are both `lock_on`.
const KEY: Dictionary = {
	&"move_forward": KEY_W, &"move_back": KEY_S, &"move_left": KEY_A, &"move_right": KEY_D,
	&"jump": KEY_SPACE, &"descend": KEY_CTRL, &"boost": KEY_SHIFT, &"assault": KEY_ALT,
	&"melee": KEY_F, &"guard": KEY_Q, &"missiles": KEY_1, &"anchor": KEY_E, &"rift_step": KEY_C,
	&"fins": KEY_Z, &"burst": KEY_X, &"well": KEY_G, &"reload": KEY_R, &"overdrive": KEY_V,
	&"lock_on": KEY_TAB,
}
const MOUSE: Dictionary = {
	&"fire": MOUSE_BUTTON_LEFT, &"aim": MOUSE_BUTTON_RIGHT, &"lock_on": MOUSE_BUTTON_MIDDLE,
	&"missiles": MOUSE_BUTTON_XBUTTON1, &"weapon_next": MOUSE_BUTTON_WHEEL_DOWN,
	&"weapon_prev": MOUSE_BUTTON_WHEEL_UP,
}
## The signals a corpse must never produce again.
const COUNTS: PackedStringArray = ["jumped", "boost_started", "weapon_fired", "melee_swing",
		"skill_used", "missiles_locked", "weapon_switched", "lock_changed", "overdrive_changed",
		"ultimate_fired", "flight_changed"]

var tally: Dictionary = {}
var died: int = 0
var od_on: int = 0
var od_off: int = 0
var assault_ended: int = 0
var _target: Node3D
var _target2: Node3D


## A lock-on target the aim system can actually acquire: `Targetable` walks up to an actor that
## answers `take_hit`, and `is_valid_target()` needs it alive and visible.
class FakeActor:
	extends Node3D

	var hp: float = 1000.0

	func take_hit(_hit: HitInfo) -> void:
		hp -= 1.0

	func is_alive() -> bool:
		return hp > 0.0

	func get_team() -> int:
		return 1


func _setup() -> void:
	await super()
	for id in COUNTS:
		tally[id] = 0
	Events.jumped.connect(func() -> void: tally["jumped"] += 1)
	Events.boost_started.connect(func(_k: StringName) -> void: tally["boost_started"] += 1)
	Events.weapon_fired.connect(func(_w: StringName, _m: Vector3, _d: Vector3) -> void:
			tally["weapon_fired"] += 1)
	Events.melee_swing.connect(func(_m: StringName, _s: int) -> void: tally["melee_swing"] += 1)
	Events.skill_used.connect(func(_s: StringName) -> void: tally["skill_used"] += 1)
	Events.missiles_locked.connect(func(_c: int) -> void: tally["missiles_locked"] += 1)
	Events.weapon_switched.connect(func(_w: StringName) -> void: tally["weapon_switched"] += 1)
	Events.lock_changed.connect(func(_t: Node3D) -> void: tally["lock_changed"] += 1)
	Events.overdrive_changed.connect(func(_a: bool) -> void: tally["overdrive_changed"] += 1)
	Events.ultimate_fired.connect(func() -> void: tally["ultimate_fired"] += 1)
	Events.flight_changed.connect(func(_f: bool) -> void: tally["flight_changed"] += 1)
	Events.player_died.connect(func() -> void: died += 1)
	Events.overdrive_changed.connect(func(a: bool) -> void:
		if a:
			od_on += 1
		else:
			od_off += 1)
	Events.boost_ended.connect(func(kind: StringName) -> void:
			if kind == &"assault":
				assault_ended += 1)
	_build_target()


func _build_target() -> void:
	_target = _fake_target("FakeTarget", Vector3(0.0, GROUND_Y, -70.0))
	# A second one, so the D-pad lock switch has something to step onto (`switch_target` needs a pool
	# of at least two before it moves the lock at all).
	_target2 = _fake_target("FakeTarget2", Vector3(45.0, GROUND_Y, -70.0))


func _fake_target(n: String, at: Vector3) -> Node3D:
	var a := FakeActor.new()
	a.name = n
	a.position = at
	add_child(a)
	var t := Targetable.new()
	t.name = "LockPoint"
	t.radius = 6.0
	a.add_child(t)
	return a


# --- the real input path --------------------------------------------------------------------------

func _key(action: StringName, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY[action] as Key
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _mouse(action: StringName, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE[action] as MouseButton
	ev.pressed = pressed
	ev.position = get_viewport().get_visible_rect().size * 0.5
	ev.global_position = ev.position
	Input.parse_input_event(ev)


## Presses `action` through whichever device `core/input_setup.gd` binds it to.
func _press(action: StringName, down: bool) -> void:
	if KEY.has(action):
		_key(action, down)
	else:
		_mouse(action, down)


func _tap(action: StringName, hold: int = TAP_TICKS) -> void:
	_press(action, true)
	await _step(hold)
	_press(action, false)


func _hold(action: StringName, ticks: int) -> void:
	_press(action, true)
	await _step(ticks)
	_press(action, false)


func _release_all() -> void:
	for a: StringName in KEY:
		_key(a, false)
	for a: StringName in MOUSE:
		_mouse(a, false)
	await _step(2)


## The pad's D-pad (SPEC §3 "D-pad ← → lock_prev / lock_next"): `core/pad_input.gd` is the only thing
## that turns a joypad button into an action, so the row has to send the real device event.
func _pad(button: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _pad_tap(button: JoyButton) -> void:
	_pad(button, true)
	await _step(TAP_TICKS)
	_pad(button, false)
	await _step(2)


## Test-harness reset: a row must not inherit the previous row's spent magazine or its heat, or the
## second `missiles` row paints into an empty launcher. `reset()` is each component's public hook.
func _reset_weapons() -> void:
	for c in _components():
		if c.has_method(&"current_weapon"):
			c.call(&"reset")
	await _step(2)


## The same for the skills: a row must not inherit a spent charge, a buff window or a running
## Overdrive (its aftermath drains EN, which is a number other rows read). The window is closed
## through its own path FIRST, so the harness never leaves `MechEnergy.overdrive_active` set the way
## `SkillSystem.reset()` alone would.
func _reset_skills() -> void:
	var sk := _skills()
	if sk == null:
		return
	if bool(sk.call(&"is_overdrive_active")):
		sk.call(&"end_overdrive")
	sk.call(&"reset")
	await _step(2)


## The two reads that moved in the r7 split, behind `has_method` so this ONE file can also be run
## against HEAD's pre-split `player_mech.gd` -- the FAIL/PASS pair the review asks for. `_dead()` is
## `MechDamage.dead` since the split and `_dead` before it; `components()` is the CONTRACTS §5 load
## order since the split and the `reset()`-capable children before it.
func _dead() -> bool:
	if _p.has_method(&"damage"):
		return bool((_p.call(&"damage") as Object).get(&"dead"))
	return bool(_p.get(&"_dead"))


func _components() -> Array[Node]:
	if _p.has_method(&"components"):
		return _p.call(&"components")
	var out: Array[Node] = []
	for c in _p.get_children():
		if c.has_method(&"reset") or c.has_method(&"is_guarding") or c.has_method(&"aim_point"):
			out.append(c)
	return out


func _clear_invuln() -> void:
	var host: Object = (_p.call(&"damage") as Object) if _p.has_method(&"damage") else _p
	host.set(&"_invuln_t", 0.0)


# --- death and revive -----------------------------------------------------------------------------

func _kill() -> void:
	_release_all()
	await _kill_holding()


## Kills the mech with every key STILL DOWN and with a hit nothing can eat: `unblockable` short-circuits
## the guard's damage filter (`defense_system.gd` `_damage_filter`), so a guard held at the killing
## blow cannot absorb it, and `_clear_invuln` drops the mercy window a heavy hit would have bought
## (r7b item 4). This is the kill every "held across the death" row uses.
func _kill_holding() -> void:
	_clear_invuln()
	await _step(2)
	var hit := HitInfo.make(_p.hp_max * 1.5, HitInfo.EXPLOSIVE, _enemy, &"test_kill_held")
	hit.unblockable = true
	_p.take_hit(hit)
	await _step(24)  # DEATH_BLEND is 0.08 s: the clip is only at weight 1 after it


## Exactly what `flow_progress.gd` `_restore_player` does at flow's commit 5129b4c: set `hp`, then
## `heal()`, `add_energy()` and `invulnerable_for()`.
func _revive() -> void:
	_p.set(&"velocity", Vector3.ZERO)
	_p.set(&"hp", _p.hp_max)
	_p.heal(_p.hp_max)
	_p.add_energy(_p.energy_max)
	_p.invulnerable_for(1.0)
	await _step(4)


# --- reads ------------------------------------------------------------------------------------------

func _zero() -> Dictionary:
	var out: Dictionary = {}
	for id in COUNTS:
		out[id] = tally[id]
	return out


## Every counter the dead list watches, as "name=before->after" for the ones that moved.
func _moved(before: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in COUNTS:
		if int(tally[id]) != int(before[id]):
			parts.append("%s %d->%d" % [id, int(before[id]), int(tally[id])])
	return "none" if parts.is_empty() else ", ".join(parts)


func _silent(before: Dictionary) -> bool:
	for id in COUNTS:
		if int(tally[id]) != int(before[id]):
			return false
	return true


## The hero model's held clip: `death` at weight 1 is the pose a corpse must keep.
func _clip() -> String:
	var m := _p.model()
	if m == null or not m.has_method(&"current_action"):
		return "no model"
	var clips: Object = m.get(&"clips") as Object
	if clips == null:
		return String(m.call(&"current_action"))
	return "%s/%s w=%.2f" % [String(m.call(&"current_action")), String(clips.call(&"current")),
			float(clips.call(&"weight"))]


func _dead_pose() -> bool:
	var m := _p.model()
	if m == null or not m.has_method(&"current_action"):
		return true  # no hero model in this build: the pose check is the probe's job
	var clips: Object = m.get(&"clips") as Object
	if clips == null:
		return String(m.call(&"current_action")) == &"death"
	return String(clips.call(&"current")) == &"death" and float(clips.call(&"weight")) > 0.99


## The revive must have released the held `death` clip. A build with no hero model cannot answer, so
## the check passes and the probe's POSE table is the record.
func _alive_pose() -> bool:
	var m := _p.model()
	if m == null or not m.has_method(&"current_action"):
		return true
	return String(m.call(&"current_action")) != &"death"


func _guarding() -> bool:
	for c in _components():
		if c.has_method(&"is_guarding"):
			return bool(c.call(&"is_guarding"))
	return false


func _flat_moved(from: Vector3) -> float:
	return Vector2(_p.global_position.x - from.x, _p.global_position.z - from.z).length()


# --- component reads (CONTRACTS §5 load order) ------------------------------------------------------

func _comp(method: StringName) -> Node:
	for c in _components():
		if c.has_method(method):
			return c
	return null


func _weapons() -> Node:
	return _comp(&"current_weapon")


func _skills() -> Node:
	return _comp(&"is_overdrive_active")


func _melee() -> Node:
	return _comp(&"charge_ratio")


## Everything the gate must have stopped, read straight off the components: the lit saber, the rifle's
## charge stance, the gatling's barrel spin, the launcher's paint and ADS. `none` when there is no
## component to ask.
func _quiet_loadout() -> String:
	var parts: PackedStringArray = []
	var ws := _weapons()
	if ws != null:
		var ctx := ws.get(&"ctx") as Object
		var rifle := ws.get(&"rifle") as Object
		var gat := ws.get(&"gatling") as Object
		var hail := ws.get(&"hailstorm") as Object
		parts.append("ads=%s" % _flag(ctx != null and bool(ctx.get(&"ads"))))
		parts.append("charge=%s" % _flag(rifle != null and bool(rifle.call(&"is_firing"))))
		parts.append("spin=%s" % _flag(gat != null and float(gat.call(&"spin")) > 0.0))
		parts.append("paint=%s" % _flag(hail != null and bool(hail.get(&"painting"))))
	var me := _melee()
	if me != null:
		var saber := me.get(&"saber") as Object
		parts.append("saber=%s" % _flag(saber != null and bool(saber.get(&"lit"))))
	return "none" if parts.is_empty() else " ".join(parts)


func _loadout_quiet() -> bool:
	return not _quiet_loadout().contains("=ON")


func _flag(on: bool) -> String:
	return "ON" if on else "off"


## The Overdrive window as the mech and the skill system each see it (r7b item 1).
func _od_state() -> String:
	var sk := _skills()
	var sys := "n/a" if sk == null else str(bool(sk.call(&"is_overdrive_active")))
	return "mech=%s sys=%s meter=%.0f" % [_p.hud_state()["overdrive_active"], sys, _p.overdrive]

