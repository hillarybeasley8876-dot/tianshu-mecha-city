class_name SkylineWalker
extends Node3D
## The Brood Titan walking the skyline before the fight (boss unit). SPEC §8.3 / MAP §2: a colossal
## monster is visible on the horizon from minute one, outside the ±700 m playable square and inside
## the ±900 m skyline ring, and it answers every fallen Hive Spire with a roar and a change of course
## toward the player.
##
## Non-interactive: no hurtboxes, no AI, no collision. It is 90 m of silhouette and one sound.

signal roared()

const MODEL := "res://enemies/models/titan_skyline/titan_skyline_model.tscn"
## The walk cycle is 2.33 s long for a 90 m body; at 14 m/s the stride would slide, so the playback
## is scaled by the model's own `set_locomotion` speed argument (MonsterModel handles it).
const ROAR_TURN_TIME := 1.5

var speed: float = BossTuning.WALKER_SPEED
var radius: float = BossTuning.WALKER_RADIUS

var _model: Node3D = null
var _angle: float = 0.0
var _roar_left: float = 0.0
var _facing: float = 0.0
var _center: Vector3 = Vector3.ZERO


## Places the walker on the ring and starts it walking. `centre` is the map origin (the Spire).
static func spawn(parent: Node, centre: Vector3, start_t: float = 0.0) -> SkylineWalker:
	if parent == null or not is_instance_valid(parent):
		push_error("SkylineWalker: no parent to spawn the skyline titan into")
		return null
	var walker := SkylineWalker.new()
	walker.name = "SkylineWalker"
	walker._center = centre
	walker._angle = TAU * fposmod(start_t, 1.0)
	parent.add_child(walker)
	return walker


func _ready() -> void:
	add_to_group(&"skyline_walker")
	_model = _load_model()
	if _model != null:
		add_child(_model)
	position = _ring_point()
	_facing = _angle + PI * 0.5


func _load_model() -> Node3D:
	if not ResourceLoader.exists(MODEL):
		push_error("SkylineWalker: no skyline titan model at " + MODEL)
		return null
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_error("SkylineWalker: cannot load " + MODEL)
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		push_error("SkylineWalker: " + MODEL + " is not a Node3D scene")
		return null
	node.name = "Model"
	return node


func _physics_process(delta: float) -> void:
	if _roar_left > 0.0:
		_roar_left -= delta
		_face_player(delta)
		_set_locomotion(&"idle", 0.0)
		return
	# Walking the ring: the bearing advances at the speed the arc length demands.
	_angle += (speed / maxf(radius, 1.0)) * delta
	position = _ring_point()
	var tangent := _angle + PI * 0.5
	_facing = _turn_toward(_facing, tangent, BossTuning.WALKER_TURN * delta)
	rotation.y = _facing
	_set_locomotion(&"walk", speed)


## The roar the flow unit asks for when a spire dies (FlowProgress calls `roar()` on `&"boss"`, so the
## director forwards it here). The walker stops, turns toward the player and roars for
## WALKER_ROAR_STOP seconds; `boss_roar` carries the shake and the 1.5 km audible sound.
func roar() -> void:
	if _roar_left > 0.0:
		return
	_roar_left = BossTuning.WALKER_ROAR_STOP
	if _model != null and _model.has_method(&"play_action"):
		_model.call(&"play_action", &"roar")
	Feel.play(&"boss_roar", global_position, 1.0)
	Audio.play(&"titan_roar", global_position)
	roared.emit()


## SPEC §8.3: "each destroyed spire makes it roar and change course toward the player". Turning to
## face the player is the change of course the player can see from the street.
func _face_player(delta: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	var to := player.global_position - global_position
	if Vector2(to.x, to.z).length_squared() < 1.0:
		return
	_facing = _turn_toward(_facing, atan2(-to.x, -to.z), BossTuning.WALKER_TURN * 2.0 * delta)
	rotation.y = _facing


func _ring_point() -> Vector3:
	return _center + Vector3(cos(_angle) * radius, BossTuning.WALKER_Y, sin(_angle) * radius)


func _turn_toward(current: float, want: float, step: float) -> float:
	return current + clampf(wrapf(want - current, -PI, PI), -step, step)


func _set_locomotion(state: StringName, spd: float) -> void:
	if _model != null and _model.has_method(&"set_locomotion"):
		_model.call(&"set_locomotion", state, spd)


## Called by the director when the boss fight starts: the beast on the horizon and the beast on the
## crown are the same animal, so the walker leaves.
func despawn() -> void:
	if _model != null and _model.has_method(&"play_action"):
		_model.call(&"play_action", &"roar")
	queue_free()
