class_name MeleeIntegration
extends Node3D
## Real integration (review r1 MUST-FIX 6): boots `main.tscn` verbatim — the shipping PlayerMech with
## its hero model, AimSystem, camera rig and the melee/defence components already instanced, the feel
## director, the HUD and the core sandbox — and drives the six things the review asked to see against
## the enemies unit's real monsters:
##
##   1. the L1→L2→L3 string on rippers           4. a Ram Kick out of a real assault boost
##   2. a 70 m lunge onto a mantis               5. catching real spitter acid and throwing it back
##   3. a perfect parry of a mantis → Return Cut  6. a Core Rend on a staggered mantis
##
## Every beat prints an `INT` line carrying the Events/telemetry that proves it and takes a still from
## inside the beat, so the capture lands on the moment rather than on a timer. The scripted hooks into
## the game live in `MeleeIntegrationRig`; this file is the beat list.
##
##   tools/godot.sh drive --scene=res://combat/melee/tests/integration.tscn --sandbox \
##     --enemies=mantis:2,ripper:6 --timeline=res://combat/melee/tests/timeline_integration.json
##   tools/godot.sh movie --movie=$PWD/captures/melee_int.avi --scene=... (same options)

const MAIN := "res://main.tscn"
const SPAWN_Y := 3.0            ## the mech's capsule centre on the sandbox floor
const START := Vector3(0.0, SPAWN_Y, -100.0)   ## the open runway, not the sandbox spawn at z = 60

var rig := MeleeIntegrationRig.new()

## Monsters whose stability pool is held full for the length of a beat. A ripper's pool breaks after
## a handful of saber hits, and a STAGGERED monster is executable — mid-string it would steal a press
## for a Core Rend, which is correct game behaviour but not what the string beat is measuring.
var _steady: Array[Node3D] = []

var _player: Node3D = null
var _melee: MeleeSystem = null
var _defense: DefenseSystem = null
var _hits: Array[StringName] = []
var _parries: int = 0


func _ready() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	if main == null:
		push_error("MeleeIntegration: cannot load %s" % MAIN)
		return
	main.name = "Main"
	add_child(main)
	Events.hit_landed.connect(_on_hit)
	Events.parry_success.connect(func(_h: HitInfo, _s: Node) -> void: _parries += 1)
	_run.call_deferred()


func _run() -> void:
	await _bind()
	if rig.player == null or _melee == null or _defense == null:
		print("INT ABORT player=%s melee=%s defense=%s" % [rig.player, _melee, _defense])
		return
	await _beat_string()
	await _beat_lunge()
	await _beat_ram_kick()
	await _beat_catch()
	await _beat_parry_return()
	await _beat_core_rend()
	print("INT done shots=%d failed=%d" % [rig.shots, rig.failed])
	for line in rig.results:
		print("INT ", line)


## Wait for the world, then grab the shipping player and its two combat components.
func _bind() -> void:
	for _i in 1200:
		_player = Game.player as Node3D
		if _player != null and Game.world_built():
			break
		await get_tree().physics_frame
	for child in _player.get_children():
		if child is MeleeSystem:
			_melee = child as MeleeSystem
		elif child is DefenseSystem:
			_defense = child as DefenseSystem
	rig.setup(self, _player, get_tree().root.find_child("EnemySpawner", true, false))
	rig.teleport(START)


func _on_hit(hit: HitInfo, _actor: Node) -> void:
	if hit != null and hit.source == rig.player:
		_hits.append(hit.weapon)


func _physics_process(_delta: float) -> void:
	for enemy in _steady:
		if not is_instance_valid(enemy):
			continue
		var status: Variant = enemy.get(&"status")
		if status is StatusComponent:
			## reset() and not just `stability = max`: one heavy hit can empty the pool outright, and
			## the stagger it starts outlives the rest of the beat.
			(status as StatusComponent).reset()


# --- beats ---------------------------------------------------------------------------------------

## 1. The full L1→L2→L3 ground string on rippers: three taps, three different moves, hits on at least
## two weapons. Three rippers abreast — one dies to L1+L2 (760 damage), so a single target would
## leave L3 swinging at a corpse.
func _beat_string() -> void:
	await rig.clear_field()
	rig.teleport(START)
	await rig.settle()
	var target := rig.spawn(&"ripper", Vector3(0.0, 0.0, -123.0))
	_steady = [target, rig.spawn(&"ripper", Vector3(-7.0, 0.0, -121.0)),
			rig.spawn(&"ripper", Vector3(7.0, 0.0, -121.0))]
	await rig.face_and_lock(target)
	_hits.clear()
	var seen: Array[StringName] = []
	for _i in 3:
		## Tap inside the cancel window (which sits in RECOVERY for every ground move, §4.3) instead of
		## on a stopwatch: a hit-stop holds the move clock, so a fixed wait drifts out of the window.
		await rig.wait_phase(_melee, [MeleeSystem.Phase.RECOVERY, MeleeSystem.Phase.IDLE])
		await rig.tap(&"melee", 4)
		seen.append(_melee.move)
	_steady.clear()
	await rig.shot("string")
	var chain := seen == [MeleeTable.L1, MeleeTable.L2, MeleeTable.L3]
	rig.report("string", chain and rig.distinct(_hits) >= 2,
			"ground_chain=%s moves=%s hits=%s" % [str(chain), str(seen), str(_hits)])


## 2. A 70 m lunge onto a hard-locked mantis. Retried once — a 110 m/s dash across the sandbox is
## stopped short by any prop in the way (`MechAir.lunge` bails on `is_on_wall`), so the bar is
## "crossed at least half the gap under power"; the continuous homing is pinned by
## `lunge.keeps_homing_through_active` in the unit suite. Two misses is a real failure.
func _beat_lunge() -> void:
	var detail := ""
	var ok := false
	for _attempt in 2:
		detail = await _lunge_once()
		ok = detail.begins_with("ok ")
		if ok:
			break
	rig.report("lunge", ok, detail)


func _lunge_once() -> String:
	await rig.clear_field()
	rig.teleport(START)
	await rig.settle()
	var target := rig.spawn(&"mantis", Vector3(0.0, 0.0, -170.0))
	await rig.face_and_lock(target)
	await rig.wait(0.3)
	var dist := rig.flat_gap(target)
	_melee.reset()
	## Re-assert the lock right before the press: the aim system drops it the moment the target
	## leaves the camera cone, and the rig is still settling after the turn.
	await rig.face_and_lock(target)
	var en_before: float = rig.player.get(&"energy")
	await rig.tap(&"melee", 4)
	var started := _melee.move
	await rig.wait(0.25)
	await rig.shot("lunge_mid")
	## Run the move out rather than sampling on a fixed clock.
	for _i in 240:
		if _melee.move == &"":
			break
		await get_tree().physics_frame
	var closed := rig.flat_gap(target)
	await rig.shot("lunge_end")
	var text := "start=%.0fm move=%s end=%.0fm en=%.0f->%.0f lock=%s" % [dist, started, closed,
			en_before, float(rig.player.get(&"energy")), str(rig.aim_target() != null)]
	var ok := started == MeleeTable.LUNGE and closed < dist * 0.5
	return ("ok " if ok else "") + text


## 3. A Ram Kick out of a REAL assault boost (SPEC §4): `assault` is its own toggle — it has to be
## tapped on its own, because a dash cancels it — and the press then has to come out as `ram_kick`
## while `move_state()` says assault.
func _beat_ram_kick() -> void:
	await rig.clear_field()
	rig.teleport(START)
	var target := rig.spawn(&"ripper", Vector3(0.0, 0.0, -128.0))
	await rig.face_and_lock(target)
	## Roll first, then toggle: a standing mech drops the jet on the next touchdown.
	Input.action_press(&"move_forward")
	await rig.wait(0.25)
	## The toggle is an edge the locomotion can swallow, so it is retried until `move_state()` reports
	## assault rather than assumed to have taken.
	var state := StringName(rig.player.call(&"move_state"))
	for _attempt in 6:
		await rig.tap(&"assault", 4)
		for _i in 60:
			state = rig.player.call(&"move_state")
			if state == &"assault":
				break
			await get_tree().physics_frame
		if state == &"assault":
			break
	_melee.reset()
	_hits.clear()
	await rig.tap(&"melee", 4)
	var started := _melee.move
	await rig.wait(0.3)
	Input.action_release(&"move_forward")
	await rig.tap(&"assault", 4)
	await rig.shot("ram_kick")
	rig.report("ram_kick", started == MeleeTable.RAM_KICK,
			"move_state=%s move=%s hits=%s en=%.0f" % [state, started, str(_hits),
			float(rig.player.get(&"energy"))])


## 4. Catch real spitter acid and throw it back: hold the guard past 0.3 s, wait for a round to be
## caught, then let go and watch `catch_count` fall to zero with the rounds outbound.
##
## The round is the enemies unit's shipped `EnemyProjectile`, produced by the spitter's own
## `spawn_attack` — but after a 4 s grace period this script pulls the trigger, because the spitter's
## brain is free to spend a whole window walking out to its 150–300 m stand-off band (SPEC §7) and
## never lob at all. Retried once.
func _beat_catch() -> void:
	var detail := ""
	var ok := false
	for _attempt in 2:
		detail = await _catch_once()
		ok = detail.begins_with("ok ")
		if ok:
			break
	rig.report("catch", ok, detail)


func _catch_once() -> String:
	await rig.clear_field()
	rig.teleport(START)
	## 80 m: inside the acid lob's 60–320 m band, so the arc is aimed at the mech rather than short.
	var target := rig.spawn(&"spitter", Vector3(0.0, 0.0, -180.0))
	await rig.face_and_lock(target)
	_defense.reset()
	await rig.wait(1.0)
	Input.action_press(&"guard")
	var caught := 0
	var lobs := 0
	for i in 1800:
		caught = _defense.catch_count()
		if caught > 0:
			break
		## Every second: top the gauge up (the open catch field costs 140 EN/s), stand 80 m off and
		## pull the trigger. The AI stays ON — `spawn_attack` aims at `perception.target`, which is
		## empty with the brain disabled, so a frozen spitter lobs at its own feet.
		if i % 120 == 0:
			rig.refill()
			rig.stand_in_front(target, 80.0)
			await rig.face_and_lock(target)
			lobs += 1
			_spit(target)
		await get_tree().physics_frame
	await rig.shot("catch_hold")
	Input.action_release(&"guard")
	await rig.wait(0.25)
	var after := _defense.catch_count()
	await rig.shot("catch_release")
	var text := "caught=%d after_release=%d state=%s lobs=%d gap=%.0f" % [caught, after,
			_defense.hud_state()["state"], lobs, rig.flat_gap(target)]
	return ("ok " if caught > 0 and after == 0 else "") + text


## Fires the spitter's acid lob through the enemy's own public API (`EnemyBase.spawn_attack`), so the
## round the Mirror Guard catches is the shipped projectile, not a stand-in.
func _spit(spitter: Node3D) -> bool:
	if spitter == null or not is_instance_valid(spitter) or not spitter.has_method(&"spawn_attack"):
		return false
	for attack in spitter.call(&"attacks"):
		if StringName(attack.get(&"id")) == &"spitter_acid_lob":
			return bool(spitter.call(&"spawn_attack", attack))
	return false


## 5. A perfect parry of a real mantis combo, then the Return Cut inside the 0.8 s window. Retried
## once: a parry is a 167 ms window against an AI that picks its own attack times, so one pass can
## easily see the hit land during the block instead.
func _beat_parry_return() -> void:
	var detail := ""
	var ok := false
	for _attempt in 2:
		detail = await _parry_once()
		ok = detail.begins_with("ok ")
		if ok:
			break
	rig.report("parry_return", ok, detail)


func _parry_once() -> String:
	await rig.clear_field()
	rig.teleport(START)
	var target := rig.spawn(&"mantis", Vector3(0.0, 0.0, -113.0))
	await rig.face_and_lock(target)
	_defense.reset()
	_parries = 0
	var move := &""
	var tick := 0
	## Guard on a 0.62 s cycle: outside the 0.5 s anti-mash rule, so every press gets the full 167 ms
	## window, and long enough that the 18-frame minimum guard has expired between taps.
	while tick < 3600:
		if tick % 74 == 0:
			await rig.tap(&"guard", 30)
		if _parries > 0:
			await rig.tap(&"melee", 4)
			move = _melee.move
			break
		await get_tree().physics_frame
		tick += 1
	await rig.shot("parry_return")
	var text := "parries=%d move=%s window=%.2f blocked=%.0f state=%s gap=%.0f" % [_parries, move,
			float(_melee.hud_state()["return_window"]), float(_defense.blocked_damage),
			_defense.hud_state()["state"], rig.flat_gap(target)]
	var ok := _parries > 0 and move == MeleeTable.RETURN_CUT
	return ("ok " if ok else "") + text


## 6. A Core Rend on a staggered mantis. The gate is 14 m AND ±60° of the VICTIM's own facing
## (CONTRACTS §6), so the beat stands the mech in front of the mantis rather than hoping it turned,
## and presses inside the 0.8 s stagger.
func _beat_core_rend() -> void:
	await rig.clear_field()
	rig.teleport(START)
	var target := rig.spawn(&"mantis", Vector3(0.0, 0.0, -114.0))
	await rig.wait(0.8)
	rig.stand_in_front(target, 10.0)
	await rig.face_and_lock(target)
	rig.stagger(target)
	var available := bool(_melee.hud_state()["execution_available"])
	_melee.reset()
	await rig.tap(&"melee", 4)
	var executing := bool(_melee.hud_state()["executing"])
	var camera: Node = Game.camera_rig
	var cut := camera != null and bool(camera.call(&"is_cinematic"))
	await rig.wait(0.25)
	await rig.shot("core_rend_a")
	await rig.wait(0.3)
	await rig.shot("core_rend_b")
	rig.report("core_rend", available and executing and cut,
			"available=%s executing=%s cinematic=%s gap=%.0f" % [available, executing, cut,
			rig.flat_gap(target)])
