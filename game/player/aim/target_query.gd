extends RefCounted
## Target geometry (camera-aim): the scanning half of lock-on, shared by the soft lock, the hard lock and
## the missile lock box so all three agree on validity, range and line of sight. Pure functions on the
## physics space: no state, no signals.

const SOFT_RANGE := 300.0          ## SPEC §5: soft lock acquire range
const SOFT_CONE_MOUSE_DEG := 7.0   ## SPEC §5: auto-acquire cone, mouse
const SOFT_CONE_PAD_DEG := 10.0    ## ... and pad
const HARD_RANGE := 450.0          ## SPEC §5: hard lock toggle range
const HARD_CONE_YAW_DEG := 40.0    ## how far off the crosshair a hard lock may grab
const HARD_CONE_PITCH_DEG := 30.0
const HARD_KEEP_SCALE := 1.5       ## SPEC §5: the lock is kept inside 1.5× the acquire cone
const BOX_YAW_DEG := 24.0          ## SPEC §5 missile paint box (full width)
const BOX_PITCH_DEG := 16.0
const LOS_EPSILON := 1.5           ## m of slack so a target's own collider does not block it


## Yaw/pitch of `point` in the view basis, in degrees (+yaw = right of the crosshair, +pitch = above).
func angles_to(point: Vector3, origin: Vector3, view: Basis) -> Vector2:
	var local := view.inverse() * (point - origin)
	var flat := Vector2(local.x, local.z).length()
	return Vector2(rad_to_deg(atan2(local.x, -local.z)), rad_to_deg(atan2(local.y, maxf(flat, 0.001))))


## Every valid Targetable within `max_range` of `origin`, nearest first. `space` is a
## PhysicsDirectSpaceState3D; pass null to skip the line-of-sight test.
func candidates(space: PhysicsDirectSpaceState3D, origin: Vector3, max_range: float) -> Array[Targetable]:
	var out: Array[Targetable] = []
	var r2 := max_range * max_range
	for node in _group():
		var t := node as Targetable
		if t == null or not t.is_valid_target():
			continue
		if origin.distance_squared_to(t.global_position) > r2:
			continue
		if space != null and not has_line_of_sight(space, origin, t.global_position):
			continue
		out.append(t)
	out.sort_custom(func(a: Targetable, b: Targetable) -> bool:
			return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	return out


## Scenery-only ray (Layers.MASK_SIGHT): true when nothing solid sits between the two points.
func has_line_of_sight(space: PhysicsDirectSpaceState3D, origin: Vector3, point: Vector3) -> bool:
	var to := point - origin
	var dist := to.length()
	if dist < 0.01:
		return true
	var params := PhysicsRayQueryParameters3D.create(origin, point, Layers.MASK_SIGHT)
	params.collide_with_areas = false
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return true
	return float(hit["position"].distance_to(origin)) >= dist - LOS_EPSILON


## Lower is better: angle dominates, distance breaks ties, priority (elites, weak points) wins outright.
func score(t: Targetable, angles: Vector2, origin: Vector3, max_range: float) -> float:
	var angle := angles.length()
	var dist := origin.distance_to(t.global_position)
	return angle + dist / maxf(max_range, 1.0) * 12.0 - t.priority * 8.0


## Best target inside the given cone (full width in degrees), or null.
func best_in_cone(space: PhysicsDirectSpaceState3D, origin: Vector3, view: Basis, max_range: float,
		yaw_deg: float, pitch_deg: float, skip: Node = null) -> Targetable:
	var best: Targetable = null
	var best_score := INF
	for t in candidates(space, origin, max_range):
		if t == skip:
			continue
		var angles := angles_to(t.global_position, origin, view)
		if absf(angles.x) > yaw_deg * 0.5 or absf(angles.y) > pitch_deg * 0.5:
			continue
		var s := score(t, angles, origin, max_range)
		if s < best_score:
			best_score = s
			best = t
	return best


## Is `t` still inside the cone it was acquired in? SPEC §5 keeps a hard lock inside 1.5× that cone.
func inside_cone(t: Targetable, origin: Vector3, view: Basis, yaw_deg: float, pitch_deg: float,
		scale_factor: float = 1.0) -> bool:
	if t == null:
		return false
	var angles := angles_to(t.global_position, origin, view)
	return absf(angles.x) <= yaw_deg * 0.5 * scale_factor and absf(angles.y) <= pitch_deg * 0.5 * scale_factor


func _group() -> Array[Node]:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_nodes_in_group(&"targetable") if tree != null else []
