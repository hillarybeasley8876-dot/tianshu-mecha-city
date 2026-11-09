extends Node
## Capture scene (camera-aim): `main.tscn` plus a row of target dummies, so the lock-on and missile-box
## states can be photographed before the enemies unit exists. Not a game entry point — `main.tscn`
## stays that. Run it with:
##   tools/godot.sh shot --scene res://player/camera/demo/camera_demo.tscn --out camera-aim --times=...
## `--lock` on the command line hard-locks the centre dummy after the world is built.

const TARGET := preload("res://player/camera/demo/demo_target.gd")

## [position, size, tint, priority, declared_height] in front of the sandbox PlayerSpawn (0, 1, 60),
## which faces -Z. The last one is the 60 m stand-in for CONTRACTS §5 large-target framing: 143 m
## out and 25° right of spawn, clear of the street dummies so the capture reads as one giant.
const SPOTS: Array[Array] = [
	[Vector3(0.0, 9.0, -80.0), Vector3(10.0, 18.0, 10.0), Color(0.55, 0.25, 0.3), 1.0, 0.0],
	[Vector3(70.0, 12.0, -150.0), Vector3(14.0, 24.0, 14.0), Color(0.5, 0.3, 0.22), 1.0, 0.0],
	[Vector3(-90.0, 10.0, -190.0), Vector3(12.0, 20.0, 12.0), Color(0.45, 0.28, 0.35), 1.0, 0.0],
	[Vector3(150.0, 60.0, -220.0), Vector3(20.0, 40.0, 20.0), Color(0.6, 0.35, 0.25), 2.0, 0.0],
	[Vector3(60.0, 30.0, -70.0), Vector3(26.0, 60.0, 26.0), Color(0.42, 0.3, 0.5), 2.0, 60.0],
]
const TITAN := 4


func _ready() -> void:
	var main := load("res://main.tscn") as PackedScene
	if main == null:
		push_error("camera_demo: cannot load main.tscn")
		return
	add_child(main.instantiate())
	_spawn_targets()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--look="):
			_aim_view(arg)
	if "--lock" in args:
		_lock_when_ready()
	if "--lock-log" in args:
		_lock_log()
	if "--wall" in args:
		_spawn_wall()


## `--lock-log` prints the aim state ten times a second, so a capture run can be correlated with what
## the lock was actually doing at each `--times` entry. Worth having: `tools/godot.sh shot` times
## `--pulse` on its own absolute clock but `--times` relative to world-ready, so the two are offset by
## the world build and a pulse can easily land before the first frame.
func _lock_log() -> void:
	while Game.player == null or Game.player.call(&"aim") == null:
		await get_tree().physics_frame
	var aim := Game.player.call(&"aim") as Node
	while is_instance_valid(aim):
		await get_tree().create_timer(0.1).timeout
		var st := aim.call(&"hud_state") as Dictionary
		print("LOCKLOG t=%.2f hard=%s (%.0f m) soft=%s (%.0f m)" % [
				float(Time.get_ticks_msec()) / 1000.0, _name_of(st.get(&"hard_target")),
				float(st.get(&"hard_distance", -1.0)), _name_of(st.get(&"soft_target")),
				float(st.get(&"soft_distance", -1.0))])


func _name_of(t: Variant) -> String:
	return "null" if t == null else String((t as Node).get_parent().name)


## `--wall` drops a 60 m block right behind the player so the spring arm has to pull the camera in
## against it: the no-clipping shot the brief asks for.
func _spawn_wall() -> void:
	var world: Node = Game.world if Game.world != null else self
	var body := StaticBody3D.new()
	body.name = "BackWall"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 80.0, 8.0)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	body.add_child(mesh)
	body.position = Vector3(0.0, 30.0, 78.0)
	world.add_child(body)


## `--look=yaw,pitch` points the rig once the world exists, so the capture tool can photograph the
## cockpit looking up or sideways without a mouse.
func _aim_view(arg: String) -> void:
	while Game.camera_rig == null:
		await get_tree().physics_frame
	await get_tree().create_timer(1.0).timeout
	var parts := arg.trim_prefix("--look=").split(",")
	if parts.size() != 2:
		push_warning("camera_demo: --look wants yaw,pitch (got %s)" % arg)
		return
	if is_instance_valid(Game.camera_rig):
		Game.camera_rig.call(&"set_look", float(parts[0]), float(parts[1]))


func _spawn_targets() -> void:
	var world: Node = Game.world if Game.world != null else self
	for i in SPOTS.size():
		var body := TARGET.new() as StaticBody3D
		body.name = "Target%d" % i
		body.position = SPOTS[i][0] as Vector3
		body.set(&"size", SPOTS[i][1] as Vector3)
		body.set(&"tint", SPOTS[i][2] as Color)
		body.set(&"declared_height", float(SPOTS[i][4]))
		world.add_child(body)
		(body.get_node(^"Mark") as Targetable).priority = float(SPOTS[i][3])


func _lock_when_ready() -> void:
	while Game.player == null or Game.player.call(&"aim") == null:
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout
	var aim := Game.player.call(&"aim") as Node
	var args := OS.get_cmdline_user_args()
	if "--lock-titan" in args:
		# CONTRACTS §5: the 60 m stand-in 200 m out — the large-target framing shot.
		aim.call(&"lock_to", _mark(TITAN))
		return
	if "--lock-high" in args:
		# The tall dummy 300 m out and 30 m up: the clearest shot of the camera framing hero + target.
		aim.call(&"lock_to", _mark(3))
		return
	aim.call(&"toggle_lock")
	if "--lock-switch" in args:
		await get_tree().create_timer(0.4).timeout
		aim.call(&"switch_target", 1.0)


func _mark(index: int) -> Targetable:
	var body := (Game.world if Game.world != null else self).get_node_or_null(NodePath("Target%d" % index))
	return body.get_node(^"Mark") as Targetable if body != null else null
