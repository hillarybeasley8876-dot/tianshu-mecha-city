extends Node3D
## AI demo scene (enemies unit): the sandbox, a stand-in hero and the full 19-monster mix, with an
## orbiting camera. Used for the movie:
##   tools/godot.sh movie --movie=<abs>/enemies_ai.avi --scene=res://enemies/tests/ai_demo.tscn \
##       --timeline=res://enemies/tests/ai_demo_timeline.json
## It is the same fight `tests/test_ai.gd` asserts on, so the movie shows the tested behaviour.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const MIX: Array[Array] = [
	[EnemyTypes.RIPPER, 12], [EnemyTypes.MANTIS, 2], [EnemyTypes.SPITTER, 2],
	[EnemyTypes.HARRIER, 2], [EnemyTypes.JUGGERNAUT, 1],
]
const CAM_DISTANCE := 105.0
const CAM_HEIGHT := 46.0
const CAM_SPEED := 0.10   ## radians per second

var _camera: Camera3D
var _angle: float = 0.6


func _ready() -> void:
	add_child((load(SANDBOX) as PackedScene).instantiate())
	var hero := DummyPlayer.new()
	hero.name = "DummyPlayer"
	hero.position = Vector3(0.0, 1.0, 0.0)
	add_child(hero)
	Game.register_player(hero)
	_camera = Camera3D.new()
	_camera.name = "DemoCamera"
	_camera.fov = 60.0
	_camera.far = 4000.0
	add_child(_camera)
	_place_camera()
	_spawn.call_deferred()


func _process(delta: float) -> void:
	_angle += CAM_SPEED * delta
	_place_camera()


func _place_camera() -> void:
	_camera.position = Vector3(cos(_angle) * CAM_DISTANCE, CAM_HEIGHT, sin(_angle) * CAM_DISTANCE)
	_camera.look_at(Vector3(0.0, 12.0, 0.0), Vector3.UP)


func _spawn() -> void:
	while not Game.world_built():
		await get_tree().physics_frame
	var spawner := EnemySpawner.new()
	spawner.name = "Spawner"
	spawner.auto_spawn = false
	add_child(spawner)
	var centre := Vector3(0.0, 1.0, 0.0)
	for row: Array in MIX:
		var type: StringName = row[0]
		var count: int = row[1]
		for i in count:
			var at := spawner.place_around(centre, float(i) / float(count))
			spawner.spawn(type, EnemySpawner.face_towards(at, centre))
