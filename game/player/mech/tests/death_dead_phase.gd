extends "res://player/mech/tests/death_phases.gd"
## The DEAD-phase extras of the death suite (mech-move r7b), split out of `test_death.gd` for the
## 400-line rule: the input rows the r7 review added (the pad's D-pad, a salvo in flight, the loadout
## that was running at the killing blow) and the air-melee / Overdrive hold. `test_death.gd` extends
## this and drives them from `_phase_dead()`.


## The corpse's pose in NUMBERS, so "it stays posed" is a measurement and not a word: the cockpit
## socket's height above the model origin with the held `death` clip at weight 1, against the same
## socket standing. The probe's `_pose` line prints the same two numbers in the windowed run.
func _dead_pose_height() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(60)
	var stand := _cockpit_h()
	if stand < 0.0:
		return  # no hero model in this build: the probe's POSE table is the record
	await _kill()
	await _step(60)
	var slumped := _cockpit_h()
	await _step(240)
	var settled := _cockpit_h()
	_ok(settled > 1.0 and settled < stand * 0.75,
			"DEAD the corpse is a kneeling slump, not a standing mech",
			"cockpit %.1f m at 0.5 s, %.1f m settled, vs %.1f m standing" % [slumped, settled, stand])


## The `cockpit` socket (CONTRACTS §5) in metres above the model origin; -1 when there is no hero.
func _cockpit_h() -> float:
	var m := _p.model()
	if m == null or not m.has_method(&"socket"):
		return -1.0
	var c := m.call(&"socket", &"cockpit") as Node3D
	if c == null:
		return -1.0
	return c.global_position.y - (m as Node3D).global_position.y


## r16 B10: the pad's D-pad lock switch is on the dead list too.
func _dead_pad() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(50)
	_key(&"lock_on", true)
	await _step(TAP_TICKS)
	_key(&"lock_on", false)
	await _step(20)
	await _kill()
	var before := _zero()
	await _pad_tap(JOY_BUTTON_DPAD_RIGHT)
	await _pad_tap(JOY_BUTTON_DPAD_LEFT)
	await _step(20)
	_ok(_silent(before) and _dead_pose(), "DEAD the pad's D-pad does not move the lock",
			_moved(before))


## r7b item 9: a salvo already in the air keeps flying. The missiles are children of the weapon
## system with their own clock, so the gate stops the mech and not the world -- this row is the
## regression guard for that, not a bug.
func _dead_projectile() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	await _step(50)
	var ws := _weapons()
	if ws == null:
		return
	var mm := ws.get(&"missiles") as Object
	_key(&"missiles", true)
	await _step(100)
	_key(&"missiles", false)
	await _step(20)
	var in_air := int(mm.call(&"active_count"))
	var impacts0 := int(mm.get(&"impacts"))
	await _kill()
	for i in 400:
		if int(mm.call(&"active_count")) == 0:
			break
		await get_tree().physics_frame
	await _step(10)
	_ok(in_air > 0 and int(mm.get(&"impacts")) > impacts0,
			"DEAD a salvo fired before the death keeps flying to its target",
			"in air %d, impacts +%d" % [in_air, int(mm.get(&"impacts")) - impacts0])


## r7b item 2: everything that was RUNNING at the killing blow is stopped -- the lit saber, the
## rifle's charge stance, the gatling's spin, the missile paint and ADS -- while the ammo behind them
## carries over (the CARRY phase).
func _dead_quiet_loadout() -> void:
	await _fresh_row()
	_mouse(&"weapon_next", true)
	await _step(2)
	_mouse(&"weapon_next", false)
	await _step(60)
	_mouse(&"aim", true)
	_key(&"melee", true)
	_mouse(&"fire", true)
	_key(&"missiles", true)
	await _step(60)
	var busy := _quiet_loadout()
	await _kill_holding()
	_ok(busy.count("=ON") >= 2, "DEAD the loadout really is running before the killing blow", busy)
	_ok(_loadout_quiet(), "DEAD the gate stops the saber, the charge, the spin, the paint and ADS",
			"%s -> %s" % [busy, _quiet_loadout()])
	_mouse(&"aim", false)
	_key(&"melee", false)
	_mouse(&"fire", false)
	_key(&"missiles", false)
	await _step(20)


## r16 Round 2: a corpse's air-melee hold (the Plunge Breaker) and V (Overdrive) while it falls.
func _dead_air_melee() -> void:
	await _reset(Vector3(0.0, GROUND_Y, 60.0))
	_cam().set(&"pitch", 0.0)
	_p.add_overdrive(100.0)
	_p.debug_teleport([0.0, 160.0, 60.0], 0.0)
	await _step(30)
	await _kill()
	var before := _zero()
	_key(&"melee", true)
	_key(&"overdrive", true)
	await _step(60)
	_key(&"melee", false)
	_key(&"overdrive", false)
	await _step(20)
	_ok(_silent(before) and _dead_pose(),
			"DEAD a melee hold and V in the air do nothing", _moved(before))


