extends Node
## LOS-loss test (enemies unit, lead r12). Run: tools/godot.sh test res://enemies/tests/test_los_loss.gd
##
## A monster that loses sight of the player must never park blind forever. One of each archetype is
## fought in the sandbox, the player is taken out of its line of sight three different ways, and the
## brain is asked to answer each time: investigate the last known position, re-path toward the
## player, flank, or give up and go back to its arena anchor. Parking on the remembered point is
## the bug this suite exists for (Request 21 — a spitter in the sandbox trench stayed silent for the
## rest of the run), and it is why the gate below is a behaviour and not a position.
##
## The cover is the test's own: a 700 x 200 x 20 m city block dropped into the sandbox's
## NavigationRegion3D and RE-BAKED, so the navmesh paths around it like any other building. It is
## deliberately wider than a monster can walk round inside the window — otherwise "it lost sight"
## would be a fact about the archetype's speed rather than about the AI.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const WALL_CENTRE := Vector3(-100.0, 100.0, -150.0)
const WALL_SIZE := Vector3(700.0, 200.0, 20.0)

const OPEN := Vector3(0.0, 1.0, -60.0)      ## player starts here, clear sight from every slot
const HIDE := Vector3(200.0, 1.0, -240.0)   ## behind the wall: 190 m away, inside every sight range
## On the roof of the sandbox's north-east tower: 200 m up a sheer face, so no ground monster can
## path to it and the tower itself blocks the line of sight. This is the brief's "onto another
## level" — a distance alone is not, because a monster is allowed to chase the position it
## remembers for Perception.LOSE_MEMORY seconds and the sandbox is not long enough to outrun that.
const ROOF := Vector3(80.0, 201.0, -260.0)
const TRENCH := Vector3(185.0, -30.0, 0.0)  ## the sandbox trench floor, 30 m below the deck

## One of each archetype, on ground that is empty in every direction so the opening line of sight is
## a property of the archetype and not of a crate. [type, position]
const PACK: Array[Array] = [
	[EnemyTypes.RIPPER, Vector3(-80.0, 0.0, -100.0)],
	[EnemyTypes.MANTIS, Vector3(-40.0, 0.0, -20.0)],
	[EnemyTypes.SPITTER, Vector3(0.0, 0.0, -110.0)],
	[EnemyTypes.HARRIER, Vector3(40.0, 0.0, -20.0)],
	[EnemyTypes.JUGGERNAUT, Vector3(80.0, 0.0, -100.0)],
]

const WARM_MAX := 10.0      ## seconds every monster gets to notice the player
const WINDOW := 24.0        ## seconds the player stays out of sight
const RETURN_WINDOW := 14.0 ## seconds the player is back in the open

## The numbers the brief asks to be taken from SPEC/AI rather than invented:
##   REACT_MAX — test_ai.STUCK_TIME (6 s): the brief's "never idle for more than 6 s", reused as the
##               deadline for reacting at all.
##   GIVEUP_MAX — EnemySpawner.LEASH_AFTER (8 s, the same tolerance the spawner gives a monster that
##               is out of the fight) plus 6 s to walk back, so a brain that searches and then
##               gives up answers inside it and a brain that circles the remembered point never does.
const REACT_MAX := 6.0
const GIVEUP_MAX := 14.0
const STILL_MAX := 6.0      ## test_ai.STUCK_TIME
const MOVE_EPS := 2.0       ## test_ai.STUCK_DELTA, over SAMPLE_EVERY — the same 4 m/s threshold
const SAMPLE_EVERY := 0.5   ## test_ai samples its stuck check on the same cadence

## Behaviour states this suite looks for. Spelled as literals, not EnemyBrain constants, so the file
## also compiles against the brain it is meant to fail on.
const SEARCHING := &"search"
const RETURNING := &"return"

var _fails: int = 0
var _checks: int = 0
var _spawner: EnemySpawner
var _player: DummyPlayer
var _track: Dictionary = {}      ## EnemyBase -> record
var _elapsed: float = 0.0
var _bake_done: bool = false


func _ready() -> void:
	await _build_world()
	await _scenario(&"cover", HIDE, false)
	await _scenario(&"roof", ROOF, false)
	await _scenario(&"level", TRENCH, false)
	await _scenario(&"cover_leashed", HIDE, true)
	print("LOS TEST %d checks, %d failures" % [_checks, _fails])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)


func _build_world() -> void:
	var packed := load(SANDBOX) as PackedScene
	if packed == null:
		push_error("test_los_loss: cannot load the sandbox")
		get_tree().quit(1)
		return
	var world := packed.instantiate()
	world.name = "World"
	add_child(world)
	Game.world = world
	while not Game.world_built():
		await get_tree().physics_frame
	await _add_cover(world)
	_player = DummyPlayer.new()
	_player.name = "DummyPlayer"
	_player.position = OPEN
	add_child(_player)
	Game.register_player(_player)
	_spawner = EnemySpawner.new()
	_spawner.name = "Spawner"
	_spawner.auto_spawn = false
	_spawner.leash = false   ## the brain owns this suite; the leash gets its own scenario
	add_child(_spawner)
	for i in 30:
		await get_tree().physics_frame


## Drops the cover block into the world's NavigationRegion3D and re-bakes, so the navmesh routes
## around it exactly as it does around the sandbox's own buildings. Without the re-bake a monster
## would path straight into the wall and the unstick would read as "stuck", which is a different bug.
func _add_cover(world: Node) -> void:
	var region := world.get_node_or_null(^"Navigation") as NavigationRegion3D
	if region == null:
		push_error("test_los_loss: the sandbox has no NavigationRegion3D to bake the cover into")
		get_tree().quit(1)
		return
	var body := StaticBody3D.new()
	body.name = "LosWall"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = WALL_CENTRE
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = WALL_SIZE
	shape.shape = box
	body.add_child(shape)
	region.add_child(body)
	_bake_done = false
	region.bake_finished.connect(_on_baked, CONNECT_ONE_SHOT)
	region.bake_navigation_mesh(true)
	# Guarded on WALL time, not on frames: a headless test runs its physics as fast as the CPU
	# allows, so a frame budget can expire long before the bake thread has finished.
	var deadline := Time.get_ticks_msec() + 90000
	while not _bake_done and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	if not _bake_done:
		push_error("test_los_loss: the cover block never finished baking")
		get_tree().quit(1)
		return
	for i in 10:
		await get_tree().physics_frame


func _on_baked() -> void:
	_bake_done = true


## One full pass: spawn the pack in the open, let it acquire the player, take the player away, watch
## what every brain does about it, then put the player back and check the fight resumes.
func _scenario(tag: StringName, hide_at: Vector3, leashed: bool) -> void:
	_spawner.leash = leashed
	_player.global_position = OPEN
	await _spawn_pack()
	var warmed := await _warm(tag)
	if not warmed:
		return
	_player.global_position = hide_at
	var lost := _lost_sight()
	_check("%s: the player really is out of sight from all %d" % [tag, _track.size()],
			lost == _track.size(), "%d still had line of sight" % (_track.size() - lost))
	_elapsed = 0.0
	await _watch(tag)
	_report(tag)
	if leashed:
		_report_leash(tag)
	await _player_returns(tag)


func _spawn_pack() -> void:
	_spawner.clear()
	_track.clear()
	await get_tree().physics_frame
	for row: Array in PACK:
		var e := _spawner.spawn(row[0] as StringName,
				EnemySpawner.face_towards(row[1] as Vector3, OPEN))
		if e == null:
			_fails += 1
			print("FAIL could not spawn %s" % row[0])
			continue
		_track_enemy(e)


func _track_enemy(e: EnemyBase) -> void:
	_track[e] = {
		"name": "%s" % e.enemy_type,
		"anchor": e.global_position,
		"last": e.global_position,
		"telegraphs": 0,
		"saw": false,
		"was_blind": false,
		"first_blind": -1.0,
		"blind_since": -1.0,
		"max_blind": 0.0,
		"still_for": 0.0,
		"max_still": 0.0,
		"reacted": -1.0,
		"resolved": -1.0,
		"jumped": false,
		"refound": false,
	}
	e.telegraph_started.connect(_on_telegraph)


func _on_telegraph(enemy: EnemyBase, _attack: StringName, _kind: StringName) -> void:
	var rec: Dictionary = _track.get(enemy, {})
	if not rec.is_empty():
		rec["telegraphs"] = int(rec["telegraphs"]) + 1


## Every monster has to notice the player before it can lose them; a spawn that never sees anything
## is a broken fixture, not a finding.
func _warm(tag: StringName) -> bool:
	var dt := get_physics_process_delta_time()
	var elapsed := 0.0
	while elapsed < WARM_MAX:
		await get_tree().physics_frame
		elapsed += dt
		var seen := 0
		for e: EnemyBase in _track.keys():
			if is_instance_valid(e) and e.target() != null:
				(_track[e] as Dictionary)["saw"] = true
			if is_instance_valid(e) and bool((_track[e] as Dictionary)["saw"]):
				seen += 1
		if seen == _track.size():
			print("WARM %s: the whole pack has the player at %.1f s" % [tag, elapsed])
			return true
	var late: Array[String] = []
	for e: EnemyBase in _track.keys():
		if is_instance_valid(e) and not bool((_track[e] as Dictionary)["saw"]):
			late.append(String((_track[e] as Dictionary)["name"]))
	_check("%s: every archetype sees the player in the open within %.0f s" % [tag, WARM_MAX],
			late.is_empty(), ", ".join(late))
	return false


func _lost_sight() -> int:
	var lost := 0
	for e: EnemyBase in _track.keys():
		if is_instance_valid(e) and not e.perception.can_see(_player):
			lost += 1
	return lost


## Watches every monster for WINDOW seconds after the player left its sight. `blind` starts when
## perception finally drops the target (Perception.LOSE_MEMORY after the last sighting), so the
## deadlines below are all measured from THAT moment — the 10 s of "it is still sure" are the AI's
## own memory, not a grace period this suite is handing out.
func _watch(tag: StringName) -> void:
	var dt := get_physics_process_delta_time()
	var sample := int(SAMPLE_EVERY / dt)
	for step in int(WINDOW / dt):
		await get_tree().physics_frame
		_elapsed += dt
		if step % sample != 0:
			continue
		for e: EnemyBase in _track.keys():
			if is_instance_valid(e) and e.alive:
				_sample(e, SAMPLE_EVERY, tag)


func _sample(e: EnemyBase, window: float, tag: StringName) -> void:
	var rec: Dictionary = _track[e]
	var blind := e.target() == null
	if blind:
		if float(rec["blind_since"]) < 0.0:
			rec["blind_since"] = _elapsed
		if not bool(rec["was_blind"]):
			rec["was_blind"] = true
			rec["first_blind"] = _elapsed
		rec["max_blind"] = maxf(float(rec["max_blind"]), _elapsed - float(rec["blind_since"]))
	else:
		rec["blind_since"] = -1.0
	# Stillness: it has not moved MOVE_EPS, has not attacked and is not mid-attack. A monster
	# standing still through a windup is doing its job, not idling — test_ai measures "stuck" the
	# same way. A monster parked on a remembered point that still circles never trips this either,
	# which is exactly why the behavioural gates below exist alongside it.
	var telegraphs: int = int(rec["telegraphs"])
	var moved := e.global_position.distance_to(rec["last"])
	if moved > MOVE_EPS or telegraphs != int(rec.get("last_telegraphs", -1)) \
			or e.state() == EnemyBrain.ATTACK:
		rec["still_for"] = 0.0
	else:
		rec["still_for"] = float(rec["still_for"]) + window
		rec["max_still"] = maxf(float(rec["max_still"]), float(rec["still_for"]))
	rec["last_telegraphs"] = telegraphs
	if bool(rec["was_blind"]):
		var state := e.state()
		if float(rec["reacted"]) < 0.0 and blind \
				and (state == SEARCHING or state == RETURNING):
			rec["reacted"] = _elapsed
		if float(rec["resolved"]) < 0.0 \
				and (not blind or state == RETURNING or state == EnemyBrain.IDLE):
			rec["resolved"] = _elapsed
		if not blind:
			rec["refound"] = true
	# A jump of more than 100 m inside one 0.25 s sample is the spawner's leash, not the monster:
	# nothing in this game moves that fast.
	if bool(rec["was_blind"]) and not bool(rec["jumped"]) and moved > 100.0:
		rec["jumped"] = true
	rec["last"] = e.global_position
	if _traced < 260 and fmod(_elapsed, 2.0) < 0.25:
		_traced += 1
		print("LOS %s %.1fs %-11s %-10s blind=%s v=%.0f d_player=%.0f d_anchor=%.0f"
				% [tag, _elapsed, rec["name"], e.state(), blind,
				Vector3(e.velocity.x, 0.0, e.velocity.z).length(),
				e.global_position.distance_to(_player.global_position),
				e.global_position.distance_to(rec["anchor"])])


var _traced: int = 0


func _report(tag: StringName) -> void:
	for e: EnemyBase in _track.keys():
		if not is_instance_valid(e):
			continue
		var rec: Dictionary = _track[e]
		var name := String(rec["name"])
		var blind_at := float(rec["first_blind"])
		if not bool(rec["was_blind"]):
			# Not a failure: the archetype walked or flew to the player and never lost them. The
			# fixture itself is guarded by the line-of-sight check above.
			print("note %s/%s never went blind — it reached the player and held the target"
					% [tag, name])
			continue
		var reacted := float(rec["reacted"])
		_check("%s/%s answers losing the player within %.0f s (search / re-path / go home)"
				% [tag, name, REACT_MAX], reacted >= 0.0 and reacted <= blind_at + REACT_MAX,
				_react_detail(rec))
		var resolved := float(rec["resolved"])
		_check("%s/%s gives up or re-finds the player within %.0f s of going blind"
				% [tag, name, GIVEUP_MAX], resolved >= 0.0 and resolved <= blind_at + GIVEUP_MAX,
				_resolve_detail(rec))
		_check("%s/%s is never still for %.0f s" % [tag, name, STILL_MAX],
				float(rec["max_still"]) < STILL_MAX, "still %.1f s" % float(rec["max_still"]))


func _react_detail(rec: Dictionary) -> String:
	if float(rec["reacted"]) >= 0.0:
		return "reacted at %.1f s (blind from %.1f s)" % [float(rec["reacted"]),
				float(rec["first_blind"])]
	return "never left the remembered point — blind %.1f s of a %.0f s window, state stayed %s" \
			% [float(rec["max_blind"]), WINDOW, "approach/position"]


func _resolve_detail(rec: Dictionary) -> String:
	if float(rec["resolved"]) >= 0.0:
		return "resolved at %.1f s" % float(rec["resolved"])
	return "parked blind: %.1f s of the %.0f s window with no answer" % [float(rec["max_blind"]),
			WINDOW]


## The leashed scenario's own gate: the spawner is the director's voice, and a monster that has been
## alerted, has gone blind and is out of the fight has to be put back into it — otherwise an
## objective that waits for an arena to be cleared stalls forever.
func _report_leash(tag: StringName) -> void:
	for e: EnemyBase in _track.keys():
		if not is_instance_valid(e):
			continue
		var rec: Dictionary = _track[e]
		if not bool(rec["was_blind"]):
			continue   ## it never lost the player; there is nothing to put back
		_check("%s/%s is put back in the fight when it goes blind and far" % [tag, rec["name"]],
				bool(rec["jumped"]) or bool(rec["refound"]),
				"still blind %.0f m from the player" % e.global_position.distance_to(
						_player.global_position))


## The player steps back into the open. Whatever the monsters decided to do, the fight has to come
## back to them — that is the whole point of not letting them park.
func _player_returns(tag: StringName) -> void:
	_player.global_position = OPEN
	var dt := get_physics_process_delta_time()
	var back: Dictionary = {}
	for e: EnemyBase in _track.keys():
		if is_instance_valid(e):
			back[e] = false
	for i in int(RETURN_WINDOW / dt):
		await get_tree().physics_frame
		for e: EnemyBase in back.keys():
			if is_instance_valid(e) and e.alive and e.target() != null:
				back[e] = true
	var late: Array[String] = []
	for e: EnemyBase in back.keys():
		if not bool(back[e]):
			late.append(String((_track[e] as Dictionary)["name"]))
	_check("%s: the whole pack is back on the player within %.0f s of it stepping out"
			% [tag, RETURN_WINDOW], late.is_empty(), ", ".join(late))


func _check(what: String, ok: bool, detail: String) -> void:
	_checks += 1
	if ok:
		print("ok   %s" % what)
	else:
		_fails += 1
		print("FAIL %s — %s" % [what, detail])
