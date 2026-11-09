extends "res://player/mech/tests/death_dead_phase.gd"
## mech-move r7/r7b death suite: the headless pipeline half of "a dead mech is dead". Drives the REAL
## PlayerMech and the five components it instanced (CONTRACTS §5) with real `Input.parse_input_event`
## key, mouse and pad events, exactly as `test_flight_input.gd` does, and no HUD -- so the GAME_OVER
## pause hud r6 is landing cannot mask a single check (r16 Round 2).
##
## Phases (the revive half and the r7b scenarios live in `death_phases.gd`):
##   1. LIVE   -- every verb on the dead-input list works, so a 0 later means something;
##   2. DEAD   -- `take_hit` to 0 hp, then the same verbs do nothing at all;
##   3. STATES -- dying inside a state ends it and leaves the wreck still.
##   4. REVIVE -- exactly what `flow_progress.gd` `_restore_player` does, with the stale cases.

## action, hold ticks, the signal that proves it acted, and which device sends it. `missiles` is
## pressed as BOTH `1` and MOUSE4 and `lock_on` as BOTH Tab and MMB (r16 Round 2), because the dead
## list has to match the live baseline device for device.
const VERBS: Array[Array] = [
	[&"move_forward", 90, "moved", "key"],
	[&"jump", 24, "jumped", "key"],
	[&"boost", TAP_TICKS, "boost_started", "key"],
	[&"assault", TAP_TICKS, "boost_started", "key"],
	[&"fire", 30, "weapon_fired", "mouse"],
	[&"melee", TAP_TICKS, "melee_swing", "key"],
	[&"guard", 30, "guarding", "key"],
	[&"anchor", TAP_TICKS, "skill_used", "key"],
	[&"missiles", 100, "missiles_locked", "key"],
	[&"missiles", 100, "missiles_locked", "mouse"],
	[&"weapon_next", TAP_TICKS, "weapon_switched", "mouse"],
	[&"weapon_prev", TAP_TICKS, "weapon_switched", "mouse"],
	[&"lock_on", TAP_TICKS, "lock_changed", "key"],
	[&"lock_on", TAP_TICKS, "lock_changed", "mouse"],
	[&"overdrive", OD_HOLD, "overdrive_changed", "key"],
]
const TAGS: Array[StringName] = [&"any", &"dash", &"skill", &"melee", &"fire"]


func _run() -> void:
	await _setup()
	await _phase_live()
	await _phase_dead()
	await _phase_death_in_states()
	await _phase_revive()
	await _phase_carry()
	await _phase_overdrive_death()
	await _phase_shoved_corpse()
	await _phase_assault_death()
	await _phase_died_once()
	_report("mech-move death")


func _send(row: Array, down: bool) -> void:
	if String(row[3]) == "key":
		_key(row[0] as StringName, down)
	else:
		_mouse(row[0] as StringName, down)


func _verb_label(row: Array) -> String:
	return "%s (%s)" % [String(row[0]), String(row[3])]


## Did the verb do its job? `moved` and `guarding` are read off the world, the rest off the bus.
func _acted(row: Array, before: Dictionary, from: Vector3) -> bool:
	match String(row[2]):
		"moved": return _flat_moved(from) > 3.0
		"guarding": return _guarding()
		_: return int(tally[row[2]]) > int(before[row[2]])


# --- 1. live ---------------------------------------------------------------------------------------

func _phase_live() -> void:
	for row in VERBS:
		await _reset(Vector3(0.0, GROUND_Y, 60.0))
		_cam().set(&"pitch", 0.0)
		await _step(50)  # the 0.35 s weapon swap must finish, or weapon_prev is refused
		_reset_weapons()  # every row starts with a loaded, cool launcher
		if String(row[0]) == &"overdrive":
			_p.add_overdrive(100.0)  # the gesture needs a full OD gauge (SPEC §4)
			await _step(4)
		var before := _zero()
		var from := _p.global_position
		_send(row, true)
		await _step(int(row[1]))
		var acted := _acted(row, before, from)
		_send(row, false)
		await _step(30)
		# Some verbs act on the RELEASE (the rifle's charged shot, the missile salvo), so the answer
		# is "did it act at any point in the press", not "was it acting on this exact tick".
		acted = acted or _acted(row, before, from)
		_ok(acted, "LIVE %s acts" % _verb_label(row), _moved(before))
	# The air-melee hold is the plunge (skills-catalog §4.2): pressed while FALLING from height, not
	# off a hop -- the Plunge Breaker is an air-to-ground slam and needs the drop.
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	_p.debug_teleport([0.0, 160.0, 60.0], 0.0)
	await _step(30)
	var falling := _p.move_state() == &"fall"
	var before := _zero()
	_key(&"melee", true)
	await _step(60)
	var plunged := int(tally["skill_used"]) > int(before["skill_used"])
	_key(&"melee", false)
	await _step(10)
	_ok(falling and plunged, "LIVE melee held in the air uses the plunge",
			"state=%s %s" % [_p.move_state(), _moved(before)])
	await _live_pad()


## The pad's D-pad lock switch (SPEC §3, r16 B10): `core/pad_input.gd` turns the button into
## `lock_next`, so the row has to send the real joypad event, not an action press.
func _live_pad() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(50)
	var before := _zero()
	_key(&"lock_on", true)
	await _step(TAP_TICKS)
	_key(&"lock_on", false)
	await _step(20)
	var locked := int(tally["lock_changed"]) > int(before["lock_changed"])
	before = _zero()
	await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
	await _step(20)
	var switched := int(tally["lock_changed"]) > int(before["lock_changed"])
	before = _zero()
	await _pad_tap(JOY_BUTTON_DPAD_LEFT)
	await _step(20)
	_ok(locked and switched and int(tally["lock_changed"]) > int(before["lock_changed"]),
			"LIVE the pad's D-pad steps the lock both ways", _moved(before))


func _key_tap_air() -> void:
	_key(&"jump", true)
	await _step(TAP_TICKS)
	_key(&"jump", false)
	await _step(16)


# --- 2. dead ---------------------------------------------------------------------------------------

func _phase_dead() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	_p.add_overdrive(100.0)
	await _kill()
	_ok(not _p.is_alive() and _dead(), "the killing blow closes the gate",
			"hp=%.0f" % _p.hp)
	_ok(_dead_pose(), "the corpse holds the death clip", _clip())
	for row in VERBS:
		var before := _zero()
		var from := _p.global_position
		_send(row, true)
		await _step(int(row[1]))
		var acted := _acted(row, before, from)
		_send(row, false)
		await _step(20)
		# Some verbs act on the RELEASE (the rifle's charged shot, the missile salvo), so the answer
		# is "did it act at any point in the press" -- the same OR the LIVE loop uses (r7b item 4).
		acted = acted or _acted(row, before, from)
		_ok(not acted, "DEAD %s does nothing" % _verb_label(row), _moved(before))
		_ok(_dead_pose(), "DEAD %s leaves the death pose alone" % _verb_label(row), _clip())
	var silent_before := _zero()
	_mouse(&"fire", true)  # real ticks under the cancel checks, so the bus row can actually fail
	for tag in TAGS:
		_ok(not _p.can_cancel(tag), "DEAD can_cancel(%s) is false" % tag)
		await _step(3)
	_mouse(&"fire", false)
	await _step(20)
	_ok(_silent(silent_before), "DEAD nothing reached the bus during the cancel checks",
			_moved(silent_before))
	_ok(not _guarding(), "DEAD the guard is down")
	var components_off := true
	for c in _components():
		if c.is_physics_processing():
			components_off = false
	_ok(components_off, "DEAD every component PlayerMech instanced stopped polling input")
	# A rifle charge held at death and released on the page fires nothing (review item 2).
	var f0 := int(tally["weapon_fired"])
	_mouse(&"fire", true)
	await _step(60)
	_mouse(&"fire", false)
	await _step(30)
	_ok(int(tally["weapon_fired"]) == f0, "DEAD a trigger held then released fires nothing",
			"%d shots" % (int(tally["weapon_fired"]) - f0))
	await _dead_pose_height()
	await _dead_air_melee()
	await _dead_pad()
	await _dead_projectile()
	await _dead_quiet_loadout()


# --- 2b. dying inside a state ----------------------------------------------------------------------

func _phase_death_in_states() -> void:
	await _die_holding(&"move_forward", 90, "with W held")
	await _die_in_state(&"boost", 90, "slide", "in a boost slide")
	await _die_in_state(&"assault", 4, "assault", "in the assault boost")
	await _die_dashing()
	await _die_airborne(false)
	await _die_airborne(true)


## Killed while running: the corpse must not keep the stride.
func _die_holding(action: StringName, ticks: int, label: String) -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	_key(action, true)
	await _step(ticks)
	var speed := _speed()
	await _kill()
	_key(action, false)
	var from := _p.global_position
	await _step(140)
	_ok(_flat_moved(from) < 0.5 and _dead_pose(), "DEAD %s: the corpse stops" % label,
			"v=%.1f m/s -> %.2f m, %s" % [speed, _flat_moved(from), _clip()])


func _die_in_state(action: StringName, ticks: int, want: String, label: String) -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	_press(action, true)
	await _until_state(StringName(want), 120)
	await _step(ticks)
	var state := _p.move_state()
	await _kill()
	_press(action, false)
	var from := _p.global_position
	await _step(140)
	_ok(state == StringName(want) and _flat_moved(from) < 0.5 and _dead_pose(),
			"DEAD %s: the state ends and the corpse stops" % label,
			"state=%s -> %.2f m, %s" % [state, _flat_moved(from), _clip()])


func _die_dashing() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _tap(&"boost", 2)
	await _until_prefix("dash", 30)
	# Past the 12 i-frame ticks but still inside the 30 tick jet: a hit landing inside the i-frames
	# is a PERFECT DODGE (SPEC §4), so killing there would never kill anything.
	await _step(14)
	var dashing := _dashing()
	await _kill()
	var from := _p.global_position
	await _step(140)
	_ok(dashing and _flat_moved(from) < 0.5 and _dead_pose(),
			"DEAD in a dash: the corpse stops",
			"dashing=%s -> %.2f m, %s" % [dashing, _flat_moved(from), _clip()])


## Killed at the apex of a hop, or in free flight. Both must land STILL POSED: the landing used to
## swap the held `death` clip for `land_light` / `land_heavy` and stand the wreck back up.
func _die_airborne(flying: bool) -> void:
	var label := "in flight" if flying else "at a hop apex"
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(4)
	if flying:
		await _enter_flight()
		await _step(30)
	else:
		await _key_tap_air()
	var was_flying := _p.is_flying()
	var y0 := _p.global_position.y
	await _kill()
	var exits := not _p.is_flying()
	for i in 900:
		if _p.is_on_floor():
			break
		await get_tree().physics_frame
	await _step(60)
	_ok(was_flying == flying and exits and _dead_pose() and _p.is_on_floor(),
			"DEAD %s: it lands still posed" % label,
			"flying=%s y=%.1f floor=%s %s" % [was_flying, y0, _p.is_on_floor(), _clip()])
