extends "res://player/mech/tests/death_test_base.gd"
## The r7b half of the death suite (mech-move): everything that happens AT and AFTER the revive, split
## out of `test_death.gd` to keep both files under the 400-line rule. `test_death.gd` extends this and
## adds the LIVE baseline, the DEAD sweep and the dying-inside-a-state rows.
##
## What is here:
##   * REVIVE   -- the latch (r16 B8 / r7b item 3): the verbs held across the death page are ignored,
##                 every OTHER verb acts on the first live tick;
##   * CARRY    -- a death changes no loadout number (r7b item 2);
##   * OD       -- dying inside an Overdrive closes it through its own path (r7b item 1);
##   * SHOVED   -- a corpse pushed into the air revives airborne and can hop (r7b item 7);
##   * ASSAULT  -- a death in the flight assault jet ends the boost on the bus (r7b item 6);
##   * ONCE     -- `player_died` fires once even when a driver writes hp itself (r7b item 8).


## A row's opening: on the flat, camera level, weapons freshly loaded, skills freshly reset and the
## swap long finished.
func _fresh_row(at: Vector3 = Vector3(0.0, GROUND_Y, 60.0)) -> void:
	await _reset(at)
	_cam().set(&"pitch", 0.0)
	await _step(50)
	await _reset_weapons()
	await _reset_skills()


# --- the revive ------------------------------------------------------------------------------------

## Exactly `_restore_player` (flow 5129b4c), with the verbs the review names held all the way through:
## a trigger (charging the rifle), a guard (which would eat a normal hit) and Space (the RETRY key,
## which is also `jump`). The kill is `_kill_holding()`, so nothing is released first and the hit is
## unblockable -- the phase really kills now (r7b item 4).
func _phase_revive() -> void:
	await _fresh_row()
	_mouse(&"fire", true)
	_key(&"guard", true)
	_key(&"jump", true)
	await _step(30)
	var d0 := died
	var hp0 := _p.hp
	await _kill_holding()
	_ok(not _p.is_alive() and _dead(), "REVIVE the killing blow lands with the guard up",
			"hp %.0f -> %.0f" % [hp0, _p.hp])
	_ok(died - d0 == 1, "REVIVE the death is announced exactly once", "player_died +%d" % (died - d0))
	_ok(Input.is_action_pressed(&"fire") and Input.is_action_pressed(&"guard")
			and Input.is_action_pressed(&"jump"),
			"REVIVE the three verbs are still down at the revive",
			"fire=%s guard=%s jump=%s" % [Input.is_action_pressed(&"fire"),
			Input.is_action_pressed(&"guard"), Input.is_action_pressed(&"jump")])
	_key(&"anchor", true)  # a skill press made while dead (r16 B3)
	await _step(10)
	_key(&"anchor", false)
	await _step(10)
	# Sampled BEFORE the revive: `_revive()` runs four ticks, and a stale release edge left in
	# `WeaponSystem._fire_held` fires the charged shot on the FIRST of them (mutation M9).
	var before := _zero()
	var from := _p.global_position
	await _revive()
	await _step(60)  # fire, guard and Space are STILL held here
	_ok(_p.is_alive() and not _dead(), "REVIVE the mech is back", "hp=%.0f" % _p.hp)
	_ok(_silent(before), "REVIVE a trigger held across the revive does not act (r16 B8)",
			_moved(before))
	_ok(not _guarding(), "REVIVE a guard held across the revive does not come back up")
	_ok(_flat_moved(from) < 0.5 and _p.is_on_floor(),
			"REVIVE Space held across the revive does not hop or take off",
			"%.2f m, floor=%s, %s" % [_flat_moved(from), _p.is_on_floor(), _p.move_state()])
	_ok(_alive_pose(), "REVIVE the death clip is released", _clip())
	_ok(_loadout_quiet(), "REVIVE nothing is left running after the revive", _quiet_loadout())
	_mouse(&"fire", false)
	_key(&"guard", false)
	_key(&"jump", false)
	await _step(20)
	await _revive_fresh_verbs()
	await _revive_w_held()
	await _revive_rmb_held()
	await _revive_charge_released_on_page()


## W held from before the killing blow, through the death page and through the revive: the mech must
## not walk until the key is let go (r16 B8 -- the conflict-map row, which overrides the r7 review's
## "W held through RETRY walks normally"), and a re-press walks again.
func _revive_w_held() -> void:
	await _fresh_row()
	_key(&"move_forward", true)
	await _step(90)
	var speed := _speed()
	await _kill_holding()
	await _revive()
	var from := _p.global_position
	await _step(90)
	var crept := _flat_moved(from)
	_ok(crept < 0.5, "REVIVE W held across the revive does not walk",
			"%.1f m/s -> %.2f m" % [speed, crept])
	_key(&"move_forward", false)
	await _step(20)
	from = _p.global_position
	_key(&"move_forward", true)
	await _step(90)
	var walked := _flat_moved(from)
	_key(&"move_forward", false)
	await _step(10)
	_ok(walked > 3.0, "REVIVE W walks again after it is released and re-pressed",
			"%.1f m" % walked)


## The other half of the latch: a press made AFTER the release acts at once (the RETRY key is not
## eaten for good, and neither is anything else).
func _revive_fresh_verbs() -> void:
	var before := _zero()
	_key(&"jump", true)
	await _step(24)
	_key(&"jump", false)
	await _step(30)
	_ok(int(tally["jumped"]) > int(before["jumped"]),
			"REVIVE a fresh jump press hops again (the RETRY key is not eaten for good)",
			_moved(before))
	before = _zero()
	_mouse(&"fire", true)
	await _step(12)
	_mouse(&"fire", false)
	await _step(30)
	_ok(int(tally["weapon_fired"]) > int(before["weapon_fired"]),
			"REVIVE a fresh trigger press fires again", _moved(before))
	# The hop above leaves the mech in the air and then in a landing recovery; the W row is about the
	# latch, not about either, so it starts from a settled floor.
	for i in 400:
		if _p.is_on_floor() and not String(_p.move_state()).begins_with("land"):
			break
		await get_tree().physics_frame
	await _step(10)
	var from := _p.global_position
	_key(&"move_forward", true)
	await _step(90)
	var walked := _flat_moved(from)
	_key(&"move_forward", false)
	await _step(10)
	_ok(walked > 3.0, "REVIVE a fresh W press walks again",
			"%.1f m, state=%s" % [walked, _p.move_state()])


## r7b item 3, the lead's gate: with RMB (`aim`) held across the revive, a FRESH press of any other
## verb acts at once. Only the held verb is muted -- the old latch kept all five components off until
## every held action had been released, which left fire, melee, guard, skills and lock-on dead.
func _revive_rmb_held() -> void:
	await _fresh_row()
	_mouse(&"aim", true)
	await _step(20)
	await _kill_holding()
	await _revive()
	await _step(30)
	# The latch mutes the ACTION, so the held button has to be read off the device.
	_ok(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT), "REVIVE RMB is still held")
	var ws := _weapons()
	var ctx := ws.get(&"ctx") as Object if ws != null else null
	_ok(ctx == null or not bool(ctx.get(&"ads")),
			"REVIVE a held RMB does not put the mech back into ADS", _quiet_loadout())
	var before := _zero()
	_key(&"melee", true)
	await _step(TAP_TICKS)
	_key(&"melee", false)
	await _step(20)
	_ok(int(tally["melee_swing"]) > int(before["melee_swing"]),
			"REVIVE a fresh F press swings while RMB is still held", _moved(before))
	before = _zero()
	_mouse(&"fire", true)
	await _step(12)
	_mouse(&"fire", false)
	await _step(30)
	_ok(int(tally["weapon_fired"]) > int(before["weapon_fired"]),
			"REVIVE a fresh trigger press fires while RMB is still held", _moved(before))
	_key(&"guard", true)
	await _step(20)
	var guarding := _guarding()
	_key(&"guard", false)
	await _step(10)
	_ok(guarding, "REVIVE a fresh Q press guards while RMB is still held")
	_mouse(&"aim", false)
	await _step(20)


## r7b item 4: a rifle charge held at the killing blow and RELEASED on the death page. The release
## edge is still in `WeaponSystem._fire_held` when the components come back, so without the gate
## dropping the charge the first live tick would fire the charged shot the player never took.
func _revive_charge_released_on_page() -> void:
	await _fresh_row()
	_mouse(&"fire", true)
	await _step(40)  # well into the charge
	var ws := _weapons()
	var rifle := ws.get(&"rifle") as Object if ws != null else null
	var charging := rifle != null and bool(rifle.call(&"is_firing"))
	await _kill_holding()
	var before := _zero()
	_mouse(&"fire", false)
	await _step(30)
	_ok(charging and _silent(before), "REVIVE a charge released on the death page fires nothing",
			"charging=%s %s" % [charging, _moved(before)])
	await _revive()
	await _step(30)
	_ok(_loadout_quiet(), "REVIVE the rifle is not left in a charge stance", _quiet_loadout())
	before = _zero()
	_mouse(&"fire", true)
	await _step(12)
	_mouse(&"fire", false)
	await _step(30)
	_ok(int(tally["weapon_fired"]) > int(before["weapon_fired"]),
			"REVIVE the trigger works again after the dropped charge", _moved(before))


# --- carry-over (r7b item 2) ------------------------------------------------------------------------

## The lead ruled carry-over in and refilling out: a death must not hand the player a magazine, a
## belt, a cooled gatling, a fresh missile cooldown or a weapon they were not holding. The scenario
## spends all of those first, dies for a quarter of a second and reads them back.
func _phase_carry() -> void:
	await _fresh_row()
	var ws := _weapons()
	var sk := _skills()
	if ws == null or sk == null:
		_ok(false, "CARRY the weapon and skill systems are instanced")
		return
	var rifle := ws.get(&"rifle") as Object
	var gat := ws.get(&"gatling") as Object
	var hail := ws.get(&"hailstorm") as Object
	for i in 3:
		_mouse(&"fire", true)
		await _step(12)
		_mouse(&"fire", false)
		await _step(40)
	_key(&"missiles", true)
	await _step(100)
	_key(&"missiles", false)
	await _step(30)
	_key(&"burst", true)
	await _step(TAP_TICKS)
	_key(&"burst", false)
	await _step(90)
	_mouse(&"weapon_next", true)
	await _step(2)
	_mouse(&"weapon_next", false)
	await _step(60)
	_mouse(&"fire", true)
	await _step(150)
	_mouse(&"fire", false)
	await _step(4)
	var slot := sk.call(&"slot", &"burst") as Object
	var before := _carry_line(rifle, gat, slot, ws)
	var cd0 := float(hail.get(&"cooldown"))
	var heat0 := float(gat.get(&"heat"))
	await _kill()
	await _revive()
	var after := _carry_line(rifle, gat, slot, ws)
	_ok(before == after, "CARRY a short death changes no ammo, charge or weapon",
			"%s | %s" % [before, after])
	_ok(cd0 > 1.0 and float(hail.get(&"cooldown")) > 1.0,
			"CARRY the missile cooldown is not zeroed by the death",
			"%.2f -> %.2f" % [cd0, float(hail.get(&"cooldown"))])
	_ok(heat0 > 0.0 and float(gat.get(&"heat")) > 0.0, "CARRY the gatling heat is not zeroed",
			"%.1f -> %.1f" % [heat0, float(gat.get(&"heat"))])


## Only the numbers a death may not touch: the rifle's cell, the gatling's belt, the burst's charges
## and the selected weapon. Heat and cooldowns run down on their own clocks, so they are read apart.
func _carry_line(rifle: Object, gat: Object, slot: Object, ws: Node) -> String:
	return "rifle=%d gatling=%d burst=%d weapon=%s" % [int(rifle.get(&"ammo")), int(gat.get(&"ammo")),
			int(slot.get(&"charges")), ws.call(&"current_weapon")]


# --- the Overdrive (r7b item 1) ---------------------------------------------------------------------

## Dying 1.25 s into an Overdrive has to close the window through the skill's OWN path: the meter
## drops to 0, `overdrive_changed(false)` fires exactly once (audio stops its loop on it) and a V
## press after the revive cannot buy a second one. `SkillSystem.reset()` -- what the gate used to call
## -- zeroed `_od_active` behind `end_overdrive()`'s back and left all of that standing. Since skills
## r5 `on_player_died()` owns the whole skills teardown, so the gate only calls that (mech-move r9).
func _phase_overdrive_death() -> void:
	await _fresh_row()
	_p.add_overdrive(100.0)
	await _step(4)
	_key(&"overdrive", true)
	await _step(OD_HOLD)
	_key(&"overdrive", false)
	await _step(10)
	var lit := bool(_p.hud_state()["overdrive_active"])
	_ok(lit and od_on > 0, "OD the V gesture opens the Overdrive", _od_state())
	await _step(150)  # 1.25 s into the window
	var off0 := od_off
	await _kill_holding()
	_ok(od_off - off0 == 1, "OD the death closes the window with exactly one overdrive_changed(false)",
			"+%d" % (od_off - off0))
	_ok(not bool(_p.hud_state()["overdrive_active"]) and _p.overdrive == 0.0,
			"OD the meter reads 0 and the mech is out of Overdrive", _od_state())
	var before := _zero()
	_key(&"overdrive", true)  # the Lance: a second press inside a live window
	await _step(OD_HOLD)
	_key(&"overdrive", false)
	await _step(20)
	_ok(_silent(before) and _dead_pose(), "OD V while dead fires no Lance", _moved(before))
	await _revive()
	before = _zero()
	_key(&"overdrive", true)
	await _step(OD_HOLD)
	_key(&"overdrive", false)
	await _step(30)
	_ok(_silent(before) and not bool(_p.hud_state()["overdrive_active"]),
			"OD V after the revive does not hand out a free Overdrive",
			"%s %s" % [_od_state(), _moved(before)])


# --- a corpse shoved into the air (r7b item 7) ------------------------------------------------------

## `flow/hive_collapse.gd` `_shove_hero` throws the mech clear of the blast, so the corpse can land
## before flow's respawn runs. `apply_impulse` had already put the state machine in S.AIR, where a
## jump press only buffers and the hop waits for a state the mech never reaches: the revive now reads
## the state off the floor contact it actually has.
func _phase_shoved_corpse() -> void:
	await _fresh_row()
	await _kill()
	_p.apply_impulse(Vector3(0.0, 42.0, 0.0))
	for i in 600:
		if _p.is_on_floor():
			break
		await get_tree().physics_frame
	await _step(20)
	await _revive()
	await _step(10)
	var before := _zero()
	_key(&"jump", true)
	await _step(24)
	_key(&"jump", false)
	await _step(20)
	_ok(int(tally["jumped"]) > int(before["jumped"]),
			"SHOVED a shoved corpse revives on the ground and Space hops again",
			"floor=%s state=%s %s" % [_p.is_on_floor(), _p.move_state(), _moved(before)])
	await _shoved_space_held()


## The same shove, revived in the AIR with Space still held: the held key must not light the
## thrusters (r16 B8), which is only visible off the floor -- on the ground a held jump does nothing
## either way.
func _shoved_space_held() -> void:
	await _fresh_row()
	_key(&"jump", true)
	await _step(20)
	await _kill_holding()
	_p.apply_impulse(Vector3(0.0, 60.0, 0.0))
	await _step(20)
	await _revive()
	var y0 := _p.global_position.y
	var en0 := _p.energy
	await _step(40)
	var rose := _p.global_position.y - y0
	_key(&"jump", false)
	await _step(10)
	_ok(rose < 0.0 and _p.energy >= en0 - 0.01,
			"SHOVED Space held across an airborne revive does not ascend",
			"y %+.1f m, en %.0f -> %.0f" % [rose, en0, _p.energy])


# --- the flight assault jet (r7b item 6) ------------------------------------------------------------

## The `assault` toggle in flight (SPEC §3) is not the S.ASSAULT state, so closing the gate through
## `_set_state` alone left the camera's assault FOV and arm wide for the rest of the run.
func _phase_assault_death() -> void:
	await _fresh_row()
	await _enter_flight()
	await _step(30)
	_key(&"assault", true)
	await _step(TAP_TICKS)
	_key(&"assault", false)
	await _step(20)
	var jetting := _p.locomotion().assault_on and _p.is_flying()
	var was := "flying=%s assault=%s" % [_p.is_flying(), _p.locomotion().assault_on]
	var ended0 := assault_ended
	await _kill_holding()
	_ok(jetting, "ASSAULT the flight jet is on before the killing blow", was)
	_ok(assault_ended - ended0 == 1, "ASSAULT the death ends the flight jet on the bus exactly once",
			"+%d" % (assault_ended - ended0))
	_ok(not _p.locomotion().assault_on, "ASSAULT the toggle is off after the latch")


# --- one death, one announcement (r7b item 8) -------------------------------------------------------

## flow's debug `die` command (and `test_boss_city`) write hp to 0 and emit `player_died` themselves;
## `MechDamage.sync()` used to say it again on the next tick, so every listener ran twice.
func _phase_died_once() -> void:
	await _fresh_row()
	var d0 := died
	_p.set(&"hp", 0.0)
	Events.player_died.emit()
	await _step(10)
	_ok(died - d0 == 1, "ONCE an external hp write and its own announcement still fire once",
			"player_died +%d" % (died - d0))
	_ok(_dead(), "ONCE the gate is closed by the external write", "dead=%s" % _dead())
	await _revive()
	await _step(10)
	d0 = died
	await _kill_holding()  # `_revive` left a 1 s mercy window, so the hit has to clear it
	_ok(died - d0 == 1, "ONCE the next real death is announced again", "player_died +%d" % (died - d0))
