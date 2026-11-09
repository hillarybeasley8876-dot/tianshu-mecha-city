extends "res://player/mech/tests/death_probe_base.gd"
## mech-move r7 death probe: the acceptance re-check of "a dead mech is dead" on the live tree.
##
## Drives the district checkpoint of `main.tscn` and, for four deaths, presses REAL device events
## (InputEventKey / InputEventMouseButton through `Input.parse_input_event`, so the menu's own `_input`
## sees them first) while the MECH DESTROYED page is up. Each verb is probed on its own and the model
## pose is read after each one, so the log says which input breaks the held `death` clip.
##
## Deaths: standing still, W already held, at the apex of a hop, and in flight about +40 m.

func _run() -> void:
	var ok := await _until(func() -> bool: return Game.world_built() and Game.player != null, 400.0, "world")
	flow = get_tree().root.get_node_or_null(^"Main/GameFlow")
	if not ok or flow == null:
		_log("FATAL no world / no GameFlow")
		await _end()
		return
	for a: StringName in [&"ui_up", &"ui_down", &"ui_accept", &"move_forward", &"fire"]:
		var evs: PackedStringArray = []
		for e in InputMap.action_get_events(a):
			evs.append(e.as_text())
		_log("INPUTMAP %s = [%s]" % [a, ", ".join(evs)])
	if not await _until(func() -> bool: return _state() == &"tutorial", 240.0, "tutorial"):
		await _end()
		return
	Game.player.call(&"invulnerable_for", GOD_T)
	await _secs(1.0)
	(flow.get(&"director") as FlowEncounterDirector).force_clear(&"A1")
	if not await _until(func() -> bool: return _state() == &"district", 30.0, "district"):
		await _end()
		return
	await _secs(2.0)
	var c := flow.call(&"checkpoint") as FlowCheckpoint
	_log("checkpoint %s; hero at %s" % [String(c.id) if c != null else "NONE", _v(Game.player.global_position)])
	await _cycle_idle_death()
	Game.player.call(&"invulnerable_for", GOD_T)
	await _secs(2.0)
	await _cycle_held_w_death()
	Game.player.call(&"invulnerable_for", GOD_T)
	await _secs(2.0)
	await _cycle_hop_death()
	Game.player.call(&"invulnerable_for", GOD_T)
	await _secs(2.0)
	await _cycle_flight_death()
	await _end()


## Death 1: die standing still, then try each verb on its own while the page is up.
func _cycle_idle_death() -> void:
	var p := Game.player
	_pose("alive_before")
	await _kill("idle")
	await _secs(1.2)
	_check("page_up", _state() == &"game_over"
			and (_menus() == null or _page() == HudMenuRoot.Page.GAME_OVER),
			"flow=%s page=%d menus=%s" % [_state(), _page(), str(_menus() != null)])
	_pose("dead_t1.2")
	await _shot("d1_dead_page")
	await _closeup("d1_dead_closeup")
	# W, a real key event, 1.0 s. The page's own footer says "W / S or LS select".
	var at0 := p.global_position
	var cur0 := _cursor()
	var st0 := steps
	var states: Dictionary = {}
	_key(KEY_W, true)
	for i in int(TICK * 1.0):
		await get_tree().physics_frame
		states[String(p.call(&"move_state"))] = true
	_key(KEY_W, false)
	await _secs(0.5)
	var walked := _flat(p.global_position - at0)
	_log("WHILE DEAD W 1.0 s (real key): moved %.1f m (%s -> %s), states seen %s, footsteps %d, menu cursor %d -> %d, hp=%.0f alive=%s dead=%s" % [
			walked, _v(at0), _v(p.global_position), str(states.keys()), steps - st0, cur0, _cursor(),
			float(p.get(&"hp")), str(p.call(&"is_alive")), str(_dead_of(p))])
	_check("dead_no_walk", walked < 0.5 and steps - st0 == 0,
			"W 1.0 s while dead moved %.1f m, footsteps %d" % [walked, steps - st0])
	_pose("dead_after_W")
	await _shot("d2_walked_page")
	await _closeup("d2_walked_closeup")
	# LMB, a real mouse event, 0.15 s.
	var f0 := fired
	_lmb(true)
	await _secs(0.15)
	_lmb(false)
	await _secs(0.6)
	_log("WHILE DEAD LMB tap (real mouse): %d shots, hp=%.0f alive=%s dead=%s" % [fired - f0,
			float(p.get(&"hp")), str(p.call(&"is_alive")), str(_dead_of(p))])
	_check("dead_no_fire", fired - f0 == 0, "LMB tap while dead -> %d weapon_fired" % (fired - f0))
	_pose("dead_after_LMB_0.6s")
	await _secs(1.0)
	_pose("dead_after_LMB_1.6s")
	await _closeup("d3_fired_closeup")
	# F (melee), Shift (boost tap = dash).
	var s0 := swings
	await _tap_key(KEY_F, 0.08)
	await _secs(0.6)
	_log("WHILE DEAD F tap: melee_swing x%d" % (swings - s0))
	_check("dead_no_melee", swings - s0 == 0, "F tap while dead -> %d melee_swing" % (swings - s0))
	_pose("dead_after_F")
	var b0 := boosts
	var at1 := p.global_position
	await _tap_key(KEY_SHIFT, 0.08)
	await _secs(0.6)
	_log("WHILE DEAD Shift tap: boost_started x%d, moved %.1f m" % [boosts - b0, _flat(p.global_position - at1)])
	_check("dead_no_boost", boosts - b0 == 0, "Shift tap while dead -> %d boost_started" % (boosts - b0))
	_pose("dead_after_Shift")
	await _closeup("d4_after_verbs_closeup")
	await _retry("idle")
	_check("revived", bool(p.call(&"is_alive")) and not _dead_of(p)
			and (_menus() == null or _page() == HudMenuRoot.Page.NONE),
			"hp=%.0f dead=%s page=%d flow=%s" % [float(p.get(&"hp")), str(_dead_of(p)), _page(), _state()])
	await _secs(1.5)
	# Controls after the respawn (real events).
	var at2 := p.global_position
	await _tap_key(KEY_W, 1.5)
	var moved := _flat(p.global_position - at2)
	var f1 := fired
	for i in 3:
		_lmb(true)
		await _secs(0.12)
		_lmb(false)
		await _secs(0.4)
	_check("controls_after_retry", moved > 3.0 and fired - f1 > 0, "W 1.5 s -> %.1f m, LMB x3 -> %d shots" % [
			moved, fired - f1])
	_pose("alive_after_retry")


## Death 2: the player is holding W when the mech dies, and keeps holding it while the page comes up.
func _cycle_held_w_death() -> void:
	var p := Game.player
	_key(KEY_W, true)
	await _secs(0.6)
	_log("HELD W before death: state=%s speed=%.1f" % [str(p.call(&"move_state")),
			_flat(p.get(&"velocity") as Vector3)])
	await _kill("held_w")
	var at0 := p.global_position
	await _secs(1.2)
	var moved := _flat(p.global_position - at0)
	_log("HELD W THROUGH DEATH: %.1f m in the 1.2 s after death, state=%s, page=%d flow=%s hp=%.0f dead=%s" % [
			moved, str(p.call(&"move_state")), _page(), _state(), float(p.get(&"hp")), str(_dead_of(p))])
	_check("held_w_corpse_still", moved < 0.5, "%.1f m after death with W held" % moved)
	_pose("held_w_dead_t1.2")
	await _shot("d5_heldw_page")
	await _closeup("d5_heldw_closeup")
	_key(KEY_W, false)
	await _secs(0.5)
	await _retry("held_w")


## Death 3: killed at the apex of a hop. It must land still posed, not stand up on the `land_*` clip.
func _cycle_hop_death() -> void:
	var p := Game.player
	var y0 := p.global_position.y
	await _tap_key(KEY_SPACE, 0.10)
	var apex := y0
	for i in int(TICK * 1.0):
		await get_tree().physics_frame
		apex = maxf(apex, p.global_position.y)
		if p.global_position.y < apex - 0.3:
			break
	_log("HOP apex %.1f m above the deck (y %.1f -> %.1f), state=%s" % [apex - y0, y0, apex,
			str(p.call(&"move_state"))])
	await _kill("hop")
	await _until(func() -> bool: return p.is_on_floor(), 8.0, "hop touchdown")
	await _secs(1.0)
	var line := _pose("hop_dead_landed")
	_check("hop_death_still_posed", line.contains("clip=death") and line.contains("weight=1.00"),
			line)
	await _closeup("d6_hop_dead_closeup")
	await _secs(0.5)
	await _retry("hop")


## Death 4: killed in free flight about +40 m up. Same check on the way down.
func _cycle_flight_death() -> void:
	var p := Game.player
	await _tap_key(KEY_SPACE, 0.08)
	await _secs(0.12)  # SPEC §3: the second tap must land inside the 0.30 s window (0.08 + 0.12 s)
	await _tap_key(KEY_SPACE, 0.08)
	var flew := await _until(func() -> bool: return bool(p.call(&"is_flying")), 3.0, "flight")
	_check("flight_entered", flew, "flying=%s" % str(p.call(&"is_flying")))
	var y0 := p.global_position.y
	_key(KEY_SPACE, true)
	await _until(func() -> bool: return p.global_position.y - y0 > 40.0, 12.0, "climb +40 m")
	_key(KEY_SPACE, false)
	_log("FLIGHT before death: flying=%s y %.1f -> %.1f state=%s" % [str(p.call(&"is_flying")), y0,
			p.global_position.y, str(p.call(&"move_state"))])
	await _kill("flight")
	_check("flight_death_exits_flight", not bool(p.call(&"is_flying")),
			"flying=%s after the killing blow" % str(p.call(&"is_flying")))
	await _until(func() -> bool: return p.is_on_floor(), 20.0, "flight touchdown")
	await _secs(1.0)
	var line := _pose("flight_dead_landed")
	_check("flight_death_still_posed", line.contains("clip=death") and line.contains("weight=1.00"),
			line)
	await _closeup("d7_flight_dead_closeup")
	await _secs(0.5)
	await _retry("flight")
	await _secs(1.0)
	await _closeup("d8_standing_after_retry")


func _end() -> void:
	_log("SUMMARY: %d checks failed" % fails.size())
	for f in fails:
		print("VDEAD FAILED ", f)
	await _frames(30)
	if get_tree().has_method(&"_finish"):
		get_tree().call(&"_finish")
	else:
		get_tree().quit(0 if fails.is_empty() else 1)
