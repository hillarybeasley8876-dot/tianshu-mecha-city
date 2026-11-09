class_name WeaponsIntegration
extends Node3D
## Integration range (tests/demo only, review r1 MUST-FIX 5): boots `main.tscn` verbatim — the real
## PlayerMech with its model, AimSystem and camera rig, the feel director and the core sandbox — so
## the weapons run the same code path they will in the game.
##
## The only thing added is a dummy target field: the sandbox has no `Targetable`s, so the Hailstorm
## has nothing to paint. Everything else (player, camera, world, feel) is the shipping scene.
##
##   tools/godot.sh drive --scene=res://combat/weapons/tests/integration.tscn \
##     --timeline=res://combat/weapons/tests/timeline_integration.json --sandbox --shots=...

const MAIN := "res://main.tscn"
const SPAWN := Vector3(0.0, 6.0, 60.0)

var _debug_t: float = 0.0


func _ready() -> void:
	FxBridge.reset()
	var main := (load(MAIN) as PackedScene).instantiate()
	if main == null:
		push_error("WeaponsIntegration: cannot load %s" % MAIN)
		return
	main.name = "Main"
	add_child(main)
	if Game.has_flag("debug"):
		Events.weapon_fired.connect(_on_weapon_fired)
	_place_targets.call_deferred()


func _on_weapon_fired(id: StringName, muzzle: Vector3, dir: Vector3) -> void:
	print("INT fired %s muzzle %v dir %v (yaw %.1f pitch %.1f)" % [id, muzzle, dir,
			rad_to_deg(atan2(-dir.x, -dir.z)), rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))])


## Dummy field: a 120 m rifle wall, the 12-target missile grid at 200 m and a 300 m wall.
func _place_targets() -> void:
	var world := Game.world
	if world == null:
		push_error("WeaponsIntegration: no Game.world to place targets in")
		return
	for i in 3:
		_dummy(world, Vector3(float(i - 1) * 18.0, 12.0, -60.0), 14.0)
	for row in 3:
		for col in 4:
			_dummy(world, Vector3((float(col) - 1.5) * 9.0, 10.0 + float(row) * 8.0, -140.0), 7.0)
	for i in 3:
		_dummy(world, Vector3(float(i - 1) * 30.0, 14.0, -240.0), 20.0)


func _dummy(parent: Node, at: Vector3, size: float) -> void:
	var t := DummyTarget.new()
	t.size = size
	parent.add_child(t)
	t.global_position = at


## With `--debug`: where the crosshair actually points, so a capture that misses can be diagnosed
## without guessing (aim point, direction from the muzzle, distance).
func _process(_delta: float) -> void:
	if not Game.has_flag("debug"):
		return
	_debug_t += get_process_delta_time()
	var p := Game.player
	if p == null or _debug_t < 0.5:
		return
	_debug_t = 0.0
	var aim: Node = p.call(&"aim") if p.has_method(&"aim") else null
	if aim == null:
		return
	var point: Vector3 = aim.call(&"aim_point")
	var muzzle := p.global_position + Vector3.UP * 11.5
	print("INT aim %v  dist %.1f  yaw %.1f pitch %.1f" % [point, muzzle.distance_to(point),
			rad_to_deg(atan2(-(point - muzzle).x, -(point - muzzle).z)),
			rad_to_deg(asin(clampf((point - muzzle).normalized().y, -1.0, 1.0)))])
