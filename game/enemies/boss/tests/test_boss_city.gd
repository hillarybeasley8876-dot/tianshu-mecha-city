extends Node
## The boss fight on the REAL map (boss unit, lead review r2 item 4): the director finds the Crown
## from the city's own `spire` landmark, the fight starts when the player is put on the deck, and a
## death puts the player back up there with the boss restored to its phase — the phase checkpoint
## working in the city, not only in `--boss-test`.
##
##   tools/godot.sh test res://enemies/boss/tests/test_boss_city.gd
##
## Headless, but it loads the whole city, so it is slower than test_boss.gd.

const CITY := "res://world/city.tscn"


## The stand-in hero plus the three calls the checkpoint makes on a real PlayerMech, so the city
## test exercises the same path the mech does.
class CheckpointPlayer extends DummyPlayer:
	var hp: float = 10000.0
	var hp_max: float = 10000.0

	func heal(amount: float) -> void:
		hp = minf(hp_max, hp + amount)

	func add_energy(_amount: float) -> void:
		pass

	func invulnerable_for(_seconds: float) -> void:
		pass

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ResourceLoader.exists(CITY):
		_fail("city", "no city scene at " + CITY)
		_finish()
		return
	var city := (load(CITY) as PackedScene).instantiate()
	city.name = "World"
	add_child(city)
	Game.world = city as Node3D
	var waited := 0.0
	while not Game.world_built() and waited < 60.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("city.built", Game.world_built(), "the city never reported world_built")

	var player := CheckpointPlayer.new()
	player.name = "CityPlayer"
	add_child(player)
	Game.register_player(player)
	player.global_position = Vector3(0.0, BossTuning.DECK_Y + 20.0, -40.0)

	# Before the fight, a player below the deck is just flying (the carrier drop passes 400 m):
	# the Crown's return catapult must stay idle until the fight arms it.
	var flyer := BossArena.new()
	flyer.build_geometry = false
	add_child(flyer)
	flyer.global_position = Vector3(0.0, BossTuning.DECK_Y, -120.0)
	var probe_at := player.global_position
	player.global_position = Vector3(300.0, 40.0, 300.0)
	await _step(BossTuning.CATAPULT_DELAY + 1.0)
	_check("catapult.idle_before_fight", not flyer.armed and player.global_position.distance_to(
			Vector3(300.0, 40.0, 300.0)) < 1.0, "an unarmed arena moved the player to %s"
			% player.global_position)
	# Out of the groups now: the director must find the city's own Crown, not this probe.
	flyer.remove_from_group(&"boss_arena")
	flyer.remove_from_group(&"landmark")
	flyer.queue_free()
	await get_tree().process_frame
	player.global_position = probe_at

	var director := BossDirector.new()
	director.name = "BossDirector"
	add_child(director)
	var left := 12.0
	while left > 0.0 and not director.fight_started:
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()
	_check("fight.started", director.fight_started,
			"the director never started the fight with the player on the Crown")
	var arena := director.arena
	_check("arena.found", arena != null, "no Crown arena was attached to the city")
	if arena == null:
		_finish()
		return
	_check("arena.armed", arena.armed, "the fight started but the Crown's return catapult is not armed")
	var centre := arena.global_position
	print("CITYTEST crown at %.0f,%.0f,%.0f (%.0f m from the layout centre), build_geometry=%s"
			% [centre.x, centre.y, centre.z, centre.distance_to(BossTuning.CROWN_CENTRE),
			str(arena.build_geometry)])
	for i in 6:
		var t := arena.ring_point(float(i) / 6.0, 0.8, 0.0)
		print("CITYTEST deck probe t=%.2f -> %.0f,%.0f,%.0f (floor %.0f)"
				% [float(i) / 6.0, t.x, t.y, t.z, arena.floor_y_at(t)])
	# Where the fight actually puts things: the titan's climb target (0.62 / 0.80) and the rim it
	# comes over (0.62 / 0.92), plus the player's respawn ring.
	for r: float in [0.55, 0.72, 0.8, 0.92]:
		var p := arena.ring_point(0.62, r, 0.0)
		print("CITYTEST radius %.2f at the titan's bearing -> y %.0f (floor %.0f)"
				% [r, p.y, arena.floor_y_at(p)])
	_check("arena.at_crown", centre.distance_to(BossTuning.CROWN_CENTRE) < 40.0,
			"the arena is %.0f m from where the layout puts B1_crown"
			% centre.distance_to(BossTuning.CROWN_CENTRE))
	_check("arena.deck", arena.build_geometry != BossArena.world_has_crown(get_tree()),
			"the arena's build_geometry is %s while world_has_crown is %s"
			% [str(arena.build_geometry), str(BossArena.world_has_crown(get_tree()))])
	_check("arena.rim", arena.segments.size() > 0 and arena.segments.size() >= BossTuning.RIM_SEGMENTS,
			"the Crown has %d rim segments" % arena.segments.size())

	# The intro climb runs before the titan is a target; wait it out, then check the fight is live.
	var titan := director.titan
	_check("titan.spawned", titan != null, "the director spawned no titan")
	if titan == null:
		_finish()
		return
	await _step(BossTuning.INTRO_CINEMATIC + 1.0)
	print("CITYTEST titan at %.0f,%.0f,%.0f" % [titan.global_position.x, titan.global_position.y,
			titan.global_position.z])
	_check("titan.alive", titan.is_alive(), "the titan died during its own intro")
	_check("titan.on_deck", absf(titan.global_position.y - centre.y) < 60.0,
			"the titan is at y %.0f, the deck is at %.0f" % [titan.global_position.y, centre.y])

	# SPEC §7.1 checkpoint, in the city. Two halves, and they must not overlap (r5 brief item 4):
	# the death leaves the hero exactly where it fell, and the RESTORE is flow's RETRY, through the
	# `restore_for_phase` hook `FlowProgress.respawn` calls.
	titan.hp = titan.hp_max * 0.28
	titan.phase = 2
	# Adds on the deck before the death: the restore has to take them with it, or they block the next
	# summon ("summon skipped, N adds are already up") and hit the player the moment the fight resumes.
	titan.demand(&"titan_summon")
	await _step(2.0)
	var adds_before := titan.spawner().alive_count() if titan.spawner() != null else 0
	print("CITYTEST adds before the restore: %d" % adds_before)
	var died_at := player.global_position
	player.hp = 0.0
	Events.player_died.emit()
	await _step(0.5)
	_check("death.no_move", player.global_position.distance_to(died_at) < 0.01,
			"the boss moved the dead hero %.1f m" % player.global_position.distance_to(died_at))
	_check("death.no_heal", player.hp <= 0.0,
			"the boss healed the dead hero to %.0f HP" % player.hp)
	_check("death.no_restore", titan.phase == 2 and not is_equal_approx(titan.hp,
			BossTuning.phase_start_hp(2)),
			"the boss restored itself at death time (phase %d, %.0f HP)" % [titan.phase, titan.hp])

	if not director.has_method(&"restore_for_phase"):
		_fail("checkpoint.hook",
				"BossDirector has no restore_for_phase hook for FlowProgress.respawn to call")
		_finish()
		return
	director.restore_for_phase(2)
	await _step(0.5)
	_check("checkpoint.phase", titan.phase == 2, "the boss came back in phase %d" % titan.phase)
	_check("checkpoint.hp", is_equal_approx(titan.hp, BossTuning.phase_start_hp(2)),
			"the boss came back at %.0f HP" % titan.hp)
	_check("checkpoint.rim", arena.broken_segments.size() > 0,
			"phase 2 came back on a mended rim (%d broken)" % arena.broken_segments.size())
	var adds_after := titan.spawner().alive_count() if titan.spawner() != null else 0
	_check("checkpoint.adds", adds_after == 0,
			"%d adds survived the checkpoint restore" % adds_after)
	_check("checkpoint.titan_on_deck",
			absf(titan.global_position.y - arena.floor_y_at(titan.global_position)) < 20.0,
			"the titan came back at y %.0f, the deck under it is %.0f"
			% [titan.global_position.y, arena.floor_y_at(titan.global_position)])
	# The player is flow's business, but the hook must leave it where it was: flow's own respawn moves
	# it to the probed fighting-floor point afterwards.
	_check("checkpoint.hero_untouched", player.global_position.distance_to(died_at) < 0.01,
			"the restore moved the hero %.1f m" % player.global_position.distance_to(died_at))
	_finish()


func _step(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()


func _check(id: String, ok: bool, detail: String) -> void:
	_checks += 1
	if ok:
		return
	_failures.append("%s: %s" % [id, detail])


func _fail(id: String, detail: String) -> void:
	_check(id, false, detail)


func _finish() -> void:
	print("BOSS CITY TEST %d checks, %d failed" % [_checks, _failures.size()])
	for line in _failures:
		print("BOSS CITY TEST FAIL ", line)
	print("PASS" if _failures.is_empty() else "FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)
