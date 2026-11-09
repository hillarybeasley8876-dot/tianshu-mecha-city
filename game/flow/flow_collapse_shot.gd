class_name FlowCollapseShot
extends RefCounted
## Where the lens stands for a Hive Spire's collapse (lead brief flow-r5b item 2). The reward beat of
## the demo's main objective has to FILM: the whole 60 m spire in frame, the hero readable in front of
## it, and the lens in clear air for every frame of the shot.
##
## The shot used to be one fixed offset — 46 m back, 22 m to the side, 20 m up — built in WORLD axes
## and then handed to `camera_rig.request_cinematic`, which reads it in the DUEL FRAME (CONTRACTS §5).
## The frame's −Z is the hero's FACING once the lock is released, so the offset was rotated by the
## hero's yaw: at 90° the "wide shot from behind the hero" became a close-up from the side, 68 m from
## a 60 m spire instead of 113 m, inside whatever building happened to be there. Nothing checked the
## placement against the city at all.
##
## So the placement is solved here instead: candidate stands around the hero → spire axis, each one
## sphere-checked against the world, ray-checked to the spire's base and top, and frustum-checked for
## the framing. The first candidate that passes wins, in preference order (nearest, lowest, on the
## hero's side), so a clear site costs a handful of queries and a walled-in one costs a full sweep.

## SPEC §5's third-person FOV. The shot holds it for its whole length.
const FOV := 55.0
## m of clear air kept around the lens: the near plane, the landing dip (up to 1.2 m, SPEC §5) and the
## one-tick lag between pinning the shot and the rig applying it.
const PROBE := 3.0
## Fraction of the frame the spire's extremes must stay inside, so the ±3° of trauma shake (FEEL
## header) cannot swing them out between one tick and the next.
const EDGE := 0.10
## Aspect the horizontal half of the frustum check uses. 16:9 captures are wider than this, so the
## check is the stricter one in any window.
const ASPECT := 1.6
## m a ray may fall short of its target and still count as clear (props around the spire's base).
const RAY_SLACK := 4.0
## m up the trunk the line-of-sight test aims. The layout sets a hive's `tier` a few metres INSIDE the
## deck slab it stands on (3 m at A5 and A6), so a ray to the very foot of the trunk always grazes the
## deck it is standing on and stops a few metres short — from every stand, at every height. The shot
## needs to see the spire, not the deck under it; the FRAMING check still wants the true foot in
## frame.
const FOOT := 8.0
## m behind the hero, m to the side of the hero → spire axis, m above the hero's feet. Ordered by
## preference: the first entry that works is the shot.
const BACK: Array[float] = [46.0, 66.0, 92.0, 124.0]
const SIDE: Array[float] = [22.0, -22.0, 48.0, -48.0, 0.0]
const LIFT: Array[float] = [20.0, 38.0, 62.0, 96.0]
## The second family, for a hive whose hero-side is walled in (A6 from the south is behind a skydeck
## collar): stands on a ring round the spire itself, m from its base and m above it. Tried in bearing
## order from the hero's own side outwards, so the composition only gives up as much as it has to.
const RADII: Array[float] = [85.0, 110.0, 140.0, 175.0, 215.0]
const RING_LIFT: Array[float] = [24.0, 48.0, 80.0, 120.0, 170.0]
const RING_BEARINGS := 16
## m the lens keeps between itself and the mech: the rig's own resolve used to shove the camera out of
## the actors, and flow places the lens itself now.
const MIN_HERO_GAP := 30.0
## Fraction of the spire's height the lens aims at. Below the middle, so the crown blast at 0.78 and
## the topple both have room above it.
const FOCUS_FRACTION := 0.45
## m above the hero's origin its chest sits — the point the framing check wants in frame.
const CHEST := 8.0
## Candidates within this of a rejected eye are not offered again in the same shot.
const REJECT_RADIUS := 4.0
## The last resort when every candidate is walled in: straight up over the hive, looking down.
const OVERHEAD_LIFT := 240.0
const OVERHEAD_BACK := 60.0


## The best stand for this collapse: `{eye, focus, ok}` where `ok` is false when even the overhead
## fallback overlaps something (which the caller reports rather than hides).
static func solve(space: PhysicsDirectSpaceState3D, hero: Vector3, base: Vector3, height: float,
		reject: Array[Vector3] = []) -> Dictionary:
	var focus := base + Vector3.UP * height * FOCUS_FRACTION
	var top := base + Vector3.UP * height
	var foot := base + Vector3.UP * FOOT
	# Three levels, each giving up one requirement: the hero in frame, then the clear line to the
	# spire. What is never given up is "the lens is in clear air" and "the spire is in frame".
	for level in 3:
		var eye := _hero_side(space, level, hero, base, foot, top, focus, reject)
		if eye != Vector3.INF:
			return {"eye": eye, "focus": focus, "ok": true, "family": &"hero_side"}
		eye = _ring(space, level, hero, base, foot, top, focus, reject)
		if eye != Vector3.INF:
			return {"eye": eye, "focus": focus, "ok": true, "family": &"ring"}
	return {"eye": _overhead(space, base, _bearing(base, hero)), "focus": focus, "ok": false,
			"family": &"overhead"}


## Family one: behind and beside the hero, on the axis the player was already fighting along. This is
## the composition the beat wants — the mech small in the foreground, the spire beyond it — so it is
## tried first at every level.
static func _hero_side(space: PhysicsDirectSpaceState3D, level: int, hero: Vector3, base: Vector3,
		foot: Vector3, top: Vector3, focus: Vector3, reject: Array[Vector3]) -> Vector3:
	var back := _bearing(base, hero)   # from the hive towards the hero: `hero + back * b` backs away
	var side := Vector3.UP.cross(back).normalized()
	for b in BACK:
		for s in SIDE:
			for lift in LIFT:
				var eye := hero + back * b + side * s + Vector3.UP * lift
				if _accepts(space, level, eye, hero, base, foot, top, focus, reject):
					return eye
	return Vector3.INF


## Family two: a ring round the spire, bearings walked outwards from the hero's own side.
static func _ring(space: PhysicsDirectSpaceState3D, level: int, hero: Vector3, base: Vector3,
		foot: Vector3, top: Vector3, focus: Vector3, reject: Array[Vector3]) -> Vector3:
	var home := atan2(hero.z - base.z, hero.x - base.x)
	for r in RADII:
		for lift in RING_LIFT:
			for k in RING_BEARINGS:
				var angle := home + float(_ring_step(k)) * TAU / float(RING_BEARINGS)
				var eye := base + Vector3(cos(angle), 0.0, sin(angle)) * r + Vector3.UP * lift
				if _accepts(space, level, eye, hero, base, foot, top, focus, reject):
					return eye
	return Vector3.INF


## 0, 1, -1, 2, -2, … so the hero's own bearing is tried first and the far side of the hive last.
static func _ring_step(k: int) -> int:
	return (k + 1) / 2 * (1 if k % 2 == 1 else -1)


## The flattened unit direction from `from` to `to`.
static func _bearing(from: Vector3, to: Vector3) -> Vector3:
	var out := to - from
	out.y = 0.0
	return out.normalized() if out.length_squared() >= 1.0 else Vector3.FORWARD


## One candidate, judged. Every level keeps the lens in clear air and the spire — its true foot and
## its true top — in frame.
static func _accepts(space: PhysicsDirectSpaceState3D, level: int, eye: Vector3, hero: Vector3,
		base: Vector3, foot: Vector3, top: Vector3, focus: Vector3,
		reject: Array[Vector3]) -> bool:
	if _rejected(eye, reject) or inside(space, eye):
		return false
	if eye.distance_to(hero) < MIN_HERO_GAP:
		return false
	if level < 2 and not (ray_clear(space, eye, foot) and ray_clear(space, eye, top)):
		return false
	if not framed(eye, focus, base) or not framed(eye, focus, top):
		return false
	return level > 0 or framed(eye, focus, hero + Vector3.UP * CHEST)


## A point in the air over the hive, clear of everything, for a site no stand can see.
static func _overhead(space: PhysicsDirectSpaceState3D, base: Vector3, back: Vector3) -> Vector3:
	for lift in [OVERHEAD_LIFT, OVERHEAD_LIFT * 1.6, OVERHEAD_LIFT * 2.4]:
		var eye := base + Vector3.UP * float(lift) + back * OVERHEAD_BACK
		if not inside(space, eye):
			return eye
	return base + Vector3.UP * OVERHEAD_LIFT * 3.0


static func _rejected(eye: Vector3, reject: Array[Vector3]) -> bool:
	for at in reject:
		if eye.distance_to(at) < REJECT_RADIUS:
			return true
	return false


# --- world queries --------------------------------------------------------------------------------

static var _lens_probe: SphereShape3D = null


## True when a `radius` sphere at `at` overlaps the world — the lens is inside a collider.
static func inside(space: PhysicsDirectSpaceState3D, at: Vector3, radius: float = PROBE) -> bool:
	if space == null:
		return false
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _sphere(radius)
	params.transform = Transform3D(Basis.IDENTITY, at)
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return not space.intersect_shape(params, 1).is_empty()


## True when nothing on `Layers.MASK_SIGHT` stands between the two points.
static func ray_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	if space == null:
		return true
	var dist := from.distance_to(to)
	if dist < 1.0:
		return true
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit := space.intersect_ray(params)
	return hit.is_empty() or from.distance_to(hit["position"] as Vector3) >= dist - RAY_SLACK


static func _sphere(radius: float) -> SphereShape3D:
	if _lens_probe == null:
		_lens_probe = SphereShape3D.new()
	_lens_probe.radius = radius
	return _lens_probe


# --- framing --------------------------------------------------------------------------------------

## True when `point` lands inside the frame a lens at `eye` aimed at `focus` would see, with `EDGE` of
## margin on every side. The basis is built exactly as `CameraCinematic._apply` builds it.
static func framed(eye: Vector3, focus: Vector3, point: Vector3) -> bool:
	var p := project(eye, focus, point)
	if is_nan(p.x) or is_nan(p.y):
		return false
	return p.x >= EDGE and p.x <= 1.0 - EDGE and p.y >= EDGE and p.y <= 1.0 - EDGE


## World point → screen fractions (0..1, y down) for a lens at `eye` aimed at `focus`. NaN when the
## point is at or behind the camera plane.
static func project(eye: Vector3, focus: Vector3, point: Vector3) -> Vector2:
	var dir := focus - eye
	if dir.length_squared() < 0.01:
		return Vector2(NAN, NAN)
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
	var tan_v := tan(deg_to_rad(FOV) * 0.5)
	var v := point - eye
	var d := v.dot(-basis.z)
	if d < 0.1:
		return Vector2(NAN, NAN)
	return Vector2(v.dot(basis.x) / (d * tan_v * ASPECT) * 0.5 + 0.5,
			0.5 - v.dot(basis.y) / (d * tan_v) * 0.5)
