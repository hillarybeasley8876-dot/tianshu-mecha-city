class_name Hero3Surfaces
extends RefCounted
## The RENDERED floor under a point, as a query (hero-v3 r9 item 1).
##
## This is `ArtSurfaces` (city-art, `world/art/settle/surface_query.gd`) with ONE difference, and the
## difference is the whole reason it exists: `PhysicsServer3D.body_create()` returns a DYNAMIC body in
## Godot 4.7.2 + Jolt, and `ArtSurfaces` never sets a mode, so every support it indexes falls at
## 9.8 m/s^2 from the tick it is created. Measured (`tests/probe_surface_mode.gd`): a support whose
## top face starts at y = 0 is at y = -4.94 one second later. That makes the settle pass and
## `tools/float_audit.gd` measure a world that is sinking under them, so this gate cannot use it.
##
## Everything else is the same method the brief asks for: `Mesh.create_trimesh_shape()` per mesh, one
## static body per kind, and a `direct_space_state.intersect_ray` straight down. Request filed in
## `status/hero-v3.md`; when city-art sets the mode this file goes away and the probe calls
## `ArtSurfaces` again.

## How far below a query point a surface still counts.
const DROP := 400.0
const ROOF: StringName = &"roof"
const GROUND: StringName = &"ground"
const LAYER := 1 << 22

var _world: World3D = null
var _bodies: Dictionary = {}
var _shapes: Array[ConcavePolygonShape3D] = []
var _shape_of: Dictionary = {}
var _query: PhysicsRayQueryParameters3D = null
var _supports: int = 0
var built_ms: int = 0


func size() -> int:
	return _supports


func setup(world: World3D) -> bool:
	dispose()
	_world = world
	if _world == null:
		push_error("Hero3Surfaces: no World3D - the float gate has no surface to read")
		return false
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN)
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_query.collision_mask = LAYER
	return true


## Index every visible `MeshInstance3D` under `root` as a support of `kind`. In the city the caller
## walks `Tiles` and the kit's near batches instead, exactly as `ArtSurfaces.build` does.
func add_tree(root: Node, kind: StringName = GROUND) -> int:
	var t0 := Time.get_ticks_msec()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible or mi.visibility_range_begin > 0.0:
			continue
		add(mi.mesh, mi.global_transform, kind)
	built_ms = Time.get_ticks_msec() - t0
	return _supports


func add(mesh: Mesh, xf: Transform3D, kind: StringName = GROUND) -> void:
	if mesh == null:
		return
	if not _shape_of.has(mesh):
		var shape := mesh.create_trimesh_shape()
		if shape == null:
			push_warning("Hero3Surfaces: a support mesh has no triangles; it holds nothing up")
			return
		_shape_of[mesh] = shape
		_shapes.append(shape)
	if not _bodies.has(kind):
		var body := PhysicsServer3D.body_create()
		# THE LINE `ArtSurfaces` is missing. Without it every support is a falling rigid body.
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body, _world.space)
		PhysicsServer3D.body_set_collision_layer(body, LAYER)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		_bodies[kind] = body
	PhysicsServer3D.body_add_shape(_bodies[kind],
			(_shape_of[mesh] as ConcavePolygonShape3D).get_rid(), xf)
	_supports += 1


## The highest support straight down from `from`, as `{y, normal, kind}` — `{}` when nothing is there.
func top_below(from: Vector3) -> Dictionary:
	if _world == null:
		return {}
	_query.from = from
	_query.to = from + Vector3.DOWN * DROP
	var hit := _world.direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		return {}
	return {"y": (hit["position"] as Vector3).y, "normal": hit["normal"] as Vector3}


func dispose() -> void:
	for kind in _bodies:
		PhysicsServer3D.free_rid(_bodies[kind])
	_bodies.clear()
	_shapes.clear()
	_shape_of.clear()
	_supports = 0
