extends Node
## hero-v3 r9 scratch: is a `PhysicsServer3D.body_create()` body STATIC by default in 4.7.2 + Jolt?
##   tools/godot.sh test res://player/model/hero3/tests/probe_surface_mode.gd
##
## `ArtSurfaces` (city-art) builds its rendered-surface index out of raw server bodies and never sets
## a mode. If those bodies fall, every rendered-floor number the settle pass and `tools/float_audit.gd`
## produce is measured against a surface that is sinking. This prints the answer in one run.

const PROBE_AT := Vector3(0.0, 5.0, 60.0)


func _ready() -> void:
	var world := (load("res://core/sandbox/sandbox.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	for i in 20:
		await get_tree().physics_frame
	var mesh := BoxMesh.new()
	mesh.size = Vector3(100.0, 4.0, 100.0)
	var shape := mesh.create_trimesh_shape()
	var space := world.get_world_3d().space
	var q := PhysicsRayQueryParameters3D.create(PROBE_AT, PROBE_AT + Vector3.DOWN * 60.0)
	q.collision_mask = 1 << 21
	for mode: Array in [[PhysicsServer3D.BODY_MODE_STATIC, "static (explicit)"],
			[-1, "default (never set)"]]:
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_space(body, space)
		PhysicsServer3D.body_set_collision_layer(body, 1 << 21)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		if int(mode[0]) >= 0:
			PhysicsServer3D.body_set_mode(body, int(mode[0]))
		PhysicsServer3D.body_add_shape(body, shape.get_rid(), Transform3D(Basis.IDENTITY,
				Vector3(0.0, -2.0, 60.0)))
		for i in 2:
			await get_tree().physics_frame
		var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
		var first := (hit["position"] as Vector3).y if not hit.is_empty() else NAN
		for i in 120:
			await get_tree().physics_frame
		hit = world.get_world_3d().direct_space_state.intersect_ray(q)
		var later := (hit["position"] as Vector3).y if not hit.is_empty() else NAN
		print("MODE %-22s top face y: %.3f then %.3f after 1 s  -> %s"
				% [mode[1], first, later, "STATIC" if absf(later - first) < 0.001 else "FALLING"])
		PhysicsServer3D.free_rid(body)
	print("PASS")
	get_tree().quit(0)
