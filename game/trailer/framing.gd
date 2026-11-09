class_name TrailerFraming
extends RefCounted
## Framing metrics for a trailer camera (trailer unit, lead brief trailer-r2 §2).
##
## A trailer shot only works if the mech reads, nothing is in the way, and the fight is visible. Those
## three facts are measured, not eyeballed: the camera kit logs them every frame and the stage scout
## scores candidate arenas with them before a single take is recorded.
##
##   bbox    the hero's screen-space height as a fraction of the frame (0 = off screen / behind)
##   blocked a scenery ray from the camera to the hero's chest hits something (MASK_SIGHT only, so
##           the hero's own collider and the enemies are never what blocks it)
##   foes    live enemies on screen whose chest ray is also unblocked
##   open    fraction of the frame whose rays reach nothing, or something far away — sky, the far city
##           or a landmark. A near wall is anything within NEAR_WALL metres.
##
## Everything here is pure maths + physics queries, so it runs headless (the stage scout) and in a
## movie take (the rigs) with identical numbers.

## Scenery closer than this to the camera counts as a wall; further is far city / landmark.
const NEAR_WALL := 220.0
## Ray length for the open-frame test. Beyond the skyline ring there is nothing to hit.
const OPEN_RAY := 3000.0
## The hero is 16 m tall (CONTRACTS §2 H 16) and PlayerMech's origin is its capsule centre.
const HERO_H := 16.0
## A scenery hit below this height above the hero's feet is the deck it stands on, not a wall.
const WALL_FLOOR := 6.0


## One measurement of one camera. Keys: bbox, blocked, foes, open, med, on_screen.
## `subject` is what is being framed (the hero by default — the boss take measures the Titan instead)
## and `height_m` its world height, which sets the feet/head reference points.
static func sample(cam: Camera3D, open_rays: bool = false, subject: Node3D = null,
		height_m: float = HERO_H) -> Dictionary:
	var out := {"bbox": 0.0, "blocked": true, "foes": 0, "open": -1.0, "med": -1.0, "on_screen": false}
	var node := subject if subject != null else Game.player
	if cam == null or node == null or not is_instance_valid(node):
		return out
	var origin := node.global_position
	var half := height_m * 0.5
	out["bbox"] = bbox_fraction(cam, origin, height_m)
	out["on_screen"] = out["bbox"] > 0.0
	out["blocked"] = sight_blocked(cam, origin + Vector3.UP * half * 0.1, node)
	out["foes"] = visible_enemies(cam)
	if open_rays:
		var d := open_detail(cam, origin.y - half + WALL_FLOOR)
		out["open"] = d["open"]
		out["med"] = d["med"]
	return out


## The subject's screen-space height as a fraction of the frame height, or 0.0 when any reference point
## is behind the camera (a partly-behind subject has no meaningful bbox and is a failed frame anyway).
static func bbox_fraction(cam: Camera3D, origin: Vector3, height_m: float = HERO_H) -> float:
	var vp := cam.get_viewport()
	if vp == null:
		return 0.0
	var h := vp.get_visible_rect().size.y
	if h <= 1.0:
		return 0.0
	var half := height_m * 0.5
	var feet := origin + Vector3.UP * -half
	var head := origin + Vector3.UP * half
	if cam.is_position_behind(feet) or cam.is_position_behind(head):
		return 0.0
	return absf(cam.unproject_position(head).y - cam.unproject_position(feet).y) / h


## True when scenery stands between the camera and `to`. `ignore` is excluded from the query so a rig
## can measure the hero without the hero's own body answering.
static func sight_blocked(cam: Camera3D, to: Vector3, ignore: Node = null) -> bool:
	return not sight_hit(cam, to, ignore).is_empty()


## The scenery hit between the camera and `to` (empty when the way is clear) — `sight_blocked` plus the
## collider, which is what a scout needs to say *what* is in the way.
## The same ray from an arbitrary point — the camera kit's blocked-repair probes bearings the camera
## is not at yet, so it cannot go through a Camera3D.
static func sight_hit_at(from: Vector3, to: Vector3, ignore: Node = null) -> Dictionary:
	var space := _space_of(ignore)
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_SIGHT)
	q.hit_from_inside = false
	if ignore != null:
		q.exclude = [ignore.get_rid()]
	return space.intersect_ray(q)


static func sight_hit(cam: Camera3D, to: Vector3, ignore: Node = null) -> Dictionary:
	var space := _space(cam)
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, to, Layers.MASK_SIGHT)
	q.hit_from_inside = false
	if ignore != null:
		q.exclude = [ignore.get_rid()]
	return space.intersect_ray(q)


## Live enemies that are on screen and unblocked. An enemy behind the camera, off the edge of the
## frame or hidden by scenery does not count: the point is what the viewer can actually see.
static func visible_enemies(cam: Camera3D) -> int:
	var n := 0
	for e: Node in (Engine.get_main_loop() as SceneTree).get_nodes_in_group(&"enemy"):
		var node := e as Node3D
		if node == null or not node.visible:
			continue
		if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")):
			continue
		var chest := node.global_position + Vector3.UP * 2.0
		if cam.is_position_behind(chest) or not _in_frame(cam, chest):
			continue
		if sight_blocked(cam, chest, node):
			continue
		n += 1
	return n


## Fraction of the frame that is sky / far city / a distant landmark rather than a near wall.
## A 9x5 grid of rays through the frame; the answer is coarse on purpose — it separates "open" from
## "a wall of boxes", which is the only distinction the shot list cares about.
##
## `floor_y` is the height below which a hit is the ground the mech is standing on (or a street further
## down), not a wall: a frame that is half deck and half sky is open, a frame that is half deck and half
## lit-window grid is not. Pass the hero's feet; the default is "everything counts".
static func open_fraction(cam: Camera3D, floor_y: float = -INF) -> float:
	return float(open_detail(cam, floor_y)["open"])


static func open_detail(cam: Camera3D, floor_y: float = -INF) -> Dictionary:
	var vp := cam.get_viewport()
	var space := _space(cam)
	if vp == null or space == null:
		return {"open": -1.0, "med": -1.0}
	var size := vp.get_visible_rect().size
	var hits: Array[float] = []
	var open := 0
	for iy in 5:
		for ix in 9:
			var uv := Vector2(size.x * (float(ix) + 0.5) / 9.0, size.y * (float(iy) + 0.5) / 5.0)
			var from := cam.project_ray_origin(uv)
			var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(uv) * OPEN_RAY,
					Layers.MASK_SIGHT)
			var hit := space.intersect_ray(q)
			var d := OPEN_RAY
			var wall := false
			if not hit.is_empty():
				var at := hit["position"] as Vector3
				d = (from - at).length()
				wall = d <= NEAR_WALL and at.y > floor_y
			hits.append(d)
			if not wall:
				open += 1
	hits.sort()
	return {"open": float(open) / float(maxi(hits.size(), 1)), "med": hits[hits.size() / 2]}


static func _space(cam: Camera3D) -> PhysicsDirectSpaceState3D:
	if cam == null or not cam.is_inside_tree():
		return null
	var w := cam.get_world_3d()
	return null if w == null else w.direct_space_state


## The space a node lives in, for the probes that have no camera to hand.
static func _space_of(node: Node) -> PhysicsDirectSpaceState3D:
	if node == null or not node.is_inside_tree():
		return null
	var n3 := node as Node3D
	if n3 == null:
		return null
	var w := n3.get_world_3d()
	return null if w == null else w.direct_space_state


## Every live enemy in the tree, whatever the camera can see — the sanity check for `visible_enemies`
## (a scout that reports 0 visible and 0 alive is looking at an empty arena, not a framing problem).
static func enemy_count() -> int:
	var n := 0
	for e: Node in (Engine.get_main_loop() as SceneTree).get_nodes_in_group(&"enemy"):
		if e is Node3D and (not e.has_method(&"is_alive") or bool(e.call(&"is_alive"))):
			n += 1
	return n


static func _in_frame(cam: Camera3D, at: Vector3) -> bool:
	var vp := cam.get_viewport()
	if vp == null:
		return false
	var p := cam.unproject_position(at)
	var size := vp.get_visible_rect().size
	return p.x >= 0.0 and p.x <= size.x and p.y >= 0.0 and p.y <= size.y
