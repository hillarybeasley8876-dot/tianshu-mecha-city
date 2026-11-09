extends Node3D
## Spawn probe (enemies unit): does putting a monster into the world move whatever is standing where
## the spawner is? `EnemySpawner.spawn()` used to `add_child` the new monster at the spawner's own
## origin and only then move it, so for one tick it was a solid body under the hero (or under the
## titan, whose AddSpawner is its child) — and the stander inherited the jump to the spawn point as
## platform velocity. Ported from the r15 acceptance probe
## (`game/tmp_accept/spec-coverage/fling_probe.gd`) so the lead can re-run the same 10 trials.
##
##   tools/godot.sh drive --scene=res://enemies/tests/spawn_probe.tscn \
##     --timeline=res://enemies/tests/spawn_probe.json --sandbox --god --quality=low
##
## Every trial must come out under 1 m/s and 0.1 m. At b5d26d4 (before the fix) the two ripper
## trials under the hero read ~16 km/s and ~8 km of travel.

const MAIN := "res://main.tscn"
const SETTLE := 90      ## ticks for the mech to land and stop after a teleport
const WATCH := 60       ## ticks of watch after each spawn
const SPEED_LIMIT := 1.0
const MOVE_LIMIT := 0.1
const TRIALS: Array = [
	["ripper", Vector3(0, 8, 0), Vector3(0, 0, -40)],
	["ripper", Vector3(0, 8, 0), Vector3(0, 0, -40)],
	["ripper", Vector3(200, 8, 200), Vector3(200, 0, 160)],
	["mantis", Vector3(0, 8, 0), Vector3(0, 0, -40)],
	["mantis", Vector3(200, 8, 200), Vector3(200, 0, 160)],
	["spitter", Vector3(0, 8, 0), Vector3(0, 0, -60)],
	["juggernaut", Vector3(0, 8, 0), Vector3(0, 0, -60)],
	["ripper", Vector3(12, 8, 0), Vector3(12, 0, -40)],
	["ripper", Vector3(0, 8, 30), Vector3(0, 0, -10)],
	["ripper", Vector3(200, 8, 200), Vector3(200, 0, 160)],
]

var _player: CharacterBody3D = null
var _spawner: Node = null


func _ready() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	main.name = "Main"
	add_child(main)
	_run.call_deferred()


func _wait(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame


func _run() -> void:
	for _i in 6000:
		_player = Game.player as CharacterBody3D
		if _player != null and Game.world_built():
			break
		await get_tree().physics_frame
	await _wait(120)
	_spawner = get_tree().root.find_child("EnemySpawner", true, false)
	if _spawner == null:
		print("SPAWN PROBE no EnemySpawner in the tree")
		get_tree().set(&"_end_t", 0.0)
		return
	print("SPAWN PROBE spawner_at=%s trials=%d" % [(_spawner as Node3D).global_position,
			TRIALS.size()])
	var worst_speed := 0.0
	var worst_moved := 0.0
	var flung := 0
	for i in TRIALS.size():
		var trial: Array = TRIALS[i]
		var at: Vector3 = trial[1]
		_spawner.call(&"clear")
		await _wait(2)
		_player.call(&"debug_teleport", [at.x, at.y, at.z], 0.0)
		await _wait(SETTLE)
		var p0 := _player.global_position
		var basis := Basis.looking_at((at - trial[2]).normalized() * Vector3(1, 0, 1), Vector3.UP)
		var enemy: Node3D = _spawner.call(&"spawn", StringName(trial[0]),
				Transform3D(basis, trial[2])) as Node3D
		var max_speed := 0.0
		var first_ticks := PackedStringArray()
		for t in WATCH:
			await get_tree().physics_frame
			var v := _player.velocity
			max_speed = maxf(max_speed, v.length())
			if t < 4:
				first_ticks.append("t%d v=(%.0f,%.0f,%.0f) pv=(%.0f,%.0f,%.0f) floor=%s" % [t, v.x, v.y,
						v.z, _player.get_platform_velocity().x, _player.get_platform_velocity().y,
						_player.get_platform_velocity().z, _player.is_on_floor()])
		var moved := _player.global_position.distance_to(p0)
		worst_speed = maxf(worst_speed, max_speed)
		worst_moved = maxf(worst_moved, moved)
		if max_speed > SPEED_LIMIT or moved > MOVE_LIMIT:
			flung += 1
		print("SPAWN trial=%d type=%s player_at=%s spawn_at=%s max_speed=%.3f moved=%.3fm  %s" % [i,
				trial[0], at, trial[2], max_speed, moved, " | ".join(first_ticks)])
		_player.velocity = Vector3.ZERO
		_player.call(&"debug_teleport", [0.0, 8.0, 300.0], 0.0)
		await _wait(30)
	print("SPAWN PROBE done trials=%d flung=%d worst_speed=%.3f m/s worst_moved=%.3f m (limits %.1f / %.1f)"
			% [TRIALS.size(), flung, worst_speed, worst_moved, SPEED_LIMIT, MOVE_LIMIT])
	get_tree().set(&"_end_t", 0.0)
