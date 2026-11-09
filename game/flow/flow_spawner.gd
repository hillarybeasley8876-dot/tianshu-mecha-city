class_name FlowSpawner
extends RefCounted
## Finds the live `EnemySpawner` (enemies unit) for the flow unit: the encounter director and the hive
## spires both place monsters through it and nothing else. Returns null — never an error — when
## enemies are stubbed out (`--stub=enemies`) or not instanced yet, so the demo still runs alone.

## How far down `ground_snap` looks for a floor, and how far above it the monster is placed.
const SNAP_RANGE := 400.0
const SNAP_LIFT := 2.0

static var _cached: Node3D = null


static func get_spawner(from: Node) -> Node3D:
	if is_instance_valid(_cached):
		return _cached
	if from == null or not from.is_inside_tree():
		return null
	var tree := from.get_tree()
	var grouped := tree.get_first_node_in_group(&"enemy_spawner")
	if grouped is Node3D:
		_cached = grouped as Node3D
		return _cached
	for node in tree.root.get_children():
		var found := _scan(node)
		if found != null:
			_cached = found
			return _cached
	return null


static func _scan(node: Node) -> Node3D:
	if node is EnemySpawner:
		return node as Node3D
	for child in node.get_children():
		var found := _scan(child)
		if found != null:
			return found
	return null


## Places `count` monsters of `type` on a ring of `radius` around `centre`, spread evenly and faced
## inward. Returns the ones that were actually spawned (a missing scene or a null spawner yields an
## empty array and one warning, never a crash).
static func spawn_ring(spawner: Node3D, type: StringName, centre: Vector3, count: int,
		radius: float, seed_t: float = 0.0) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if spawner == null or count <= 0:
		return out
	for i in count:
		var t := seed_t + float(i) / float(maxi(count, 1))
		var at := centre + Vector3(cos(TAU * t), 0.0, sin(TAU * t)) * radius
		var xform: Transform3D = spawner.call(&"face_towards", at, centre)
		var enemy := spawner.call(&"spawn", type, xform) as Node3D
		if enemy != null:
			out.append(enemy)
	return out


## Drops `at` onto the first solid surface below it on `Layers.WORLD`, or `Vector3.INF` when there is
## none (off the edge of the map, or no world at all). Only works from a physics frame — that is where
## the callers are.
static func snap_to_ground(from: Node3D, at: Vector3) -> Vector3:
	if from == null or not from.is_inside_tree():
		return Vector3.INF
	var space := from.get_world_3d().direct_space_state
	if space == null:
		return Vector3.INF
	var params := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * SNAP_RANGE)
	params.collision_mask = Layers.WORLD
	var hit := space.intersect_ray(params) as Dictionary
	if hit.is_empty():
		return Vector3.INF
	return (hit["position"] as Vector3) + Vector3.UP * SNAP_LIFT


## `snap_to_ground` with a height to fall back to when there is no floor under the point. The generated
## spawn sockets start at the top of an arena's trigger volume, and a pack that materialises 100 m in
## the air is a bug the player sees.
static func ground_snap(from: Node3D, at: Vector3, fallback_y: float) -> Vector3:
	var snapped := snap_to_ground(from, at)
	if snapped != Vector3.INF:
		return snapped
	return Vector3(at.x, fallback_y, at.z)
