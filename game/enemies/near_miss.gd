class_name EnemyNearMiss
extends RefCounted
## Near-miss detection for enemy fire (enemies-owned). juice-impact §11.3: a shot that passes close
## without touching you gets its own beat — `Feel.play(&"near_miss")` fires at the CLOSEST POINT of
## the shot's path, once per shot, so the flyby sound plays where the round actually went past.
##
## No physics query: the player's hurtboxes are cached node references and every test is vector
## maths on the segment the shot already swept this tick. The 4/s limit is the FEEL row's own
## cooldown (fx/events/near_miss.tres, 0.25 s) — there is no second limiter here.
##
## One `Tracker` per pooled shot. It fires when the shot is past its closest approach (a flat round
## therefore fires within a tick of that point, not when it expires) or, for a shot that ends without
## ever receding — an arcing lob whose burst the player's cover ate — when the shot is over. A shot
## that touched a hurtbox, was reached by its own blast, was held by the catch field, or was
## reflected never counts (lead decisions, r16 Round 2).


## Metres of clear air between the shot's path and the player's hurtbox surface (lead decision, r16
## Round 2). It is a surface distance on purpose: a 16 m mech's hurtbox is a 6 m-radius capsule, so
## "6 m from its centre" would be inside the player and no shot could ever miss by that little.
const RADIUS := 6.0
## Strength at the edge of the radius and right on the hurtbox: the row is already quiet, so the
## spread only makes a graze read louder than a wide pass.
const STRENGTH_FAR := 0.5
const STRENGTH_NEAR := 1.0
## A pass counts as "receding" once it is this far past its closest point, so a shot drifting along
## the radius cannot fire on numerical noise.
const RECEDE_EPS := 0.01
## Physics frames between re-resolutions of the player's hurtboxes (the cache also re-resolves the
## moment the player node dies).
const REFRESH_FRAMES := 30
## Cap on the drained log, so a test or probe that never reads it cannot grow it for ever.
const LOG_MAX := 64

## Every near miss since the last `take_log()`, oldest first: {"attack", "at", "distance"}.
static var _log: Array[Dictionary] = []
static var _player: Node3D = null
static var _shapes: Array[CollisionShape3D] = []
static var _bare: bool = false     ## the player exposes no hurtbox shape: use its centre of mass
static var _frame: int = -1000


## Drains the near-miss log (the fight probe prints one line per call from it).
static func take_log() -> Array[Dictionary]:
	var out := _log
	_log = []
	return out


## Drops the cached player — used by tests that swap the dummy out.
static func reset() -> void:
	_player = null
	_shapes.clear()
	_bare = false
	_frame = -1000
	_log.clear()


## Distance from the shot's swept path to the nearest player hurtbox surface, with the point on the
## path that achieved it. INF when there is no player to miss. `shot_radius` is the round's own
## radius, so the number is clear air between the two surfaces.
static func closest(from: Vector3, to: Vector3, shot_radius: float) -> Dictionary:
	var best := INF
	var at := to
	if _bare:
		return _closest_to_centre(from, to, shot_radius)
	for node: CollisionShape3D in shapes():
		var xf := node.global_transform
		var a := xf.origin
		var b := a
		var r := 0.0
		if node.shape is CapsuleShape3D:
			var cap := node.shape as CapsuleShape3D
			r = cap.radius
			var half: float = maxf(cap.height * 0.5 - r, 0.0)
			a = xf.origin - xf.basis.y.normalized() * half
			b = xf.origin + xf.basis.y.normalized() * half
		elif node.shape is SphereShape3D:
			r = (node.shape as SphereShape3D).radius
		else:
			r = node.shape.get_aabb().size.length() * 0.5
		var pair := _segment_pair(a, b, from, to)
		var d: float = pair[0].distance_to(pair[1]) - r - shot_radius
		if d < best:
			best = d
			at = pair[1]
	return {"distance": best, "at": at}


## The two closest points of the volume's axis and the shot's path, in that order. A degenerate axis
## (a sphere) collapses to a point-to-segment test.
static func _segment_pair(a: Vector3, b: Vector3, from: Vector3, to: Vector3) -> PackedVector3Array:
	if a.distance_squared_to(b) < 0.000001:
		return PackedVector3Array([a, Geometry3D.get_closest_point_to_segment(a, from, to)])
	return Geometry3D.get_closest_points_between_segments(a, b, from, to)


## An actor with no hurtbox at all (a stub in a test): treat it as a sphere at its centre of mass.
static func _closest_to_centre(from: Vector3, to: Vector3, shot_radius: float) -> Dictionary:
	if _player == null or not is_instance_valid(_player):
		return {"distance": INF, "at": to}
	var h: float = float(_player.get(&"body_height")) if &"body_height" in _player else 8.0
	var c := _player.global_position + Vector3.UP * h * 0.5
	var p := Geometry3D.get_closest_point_to_segment(c, from, to)
	return {"distance": p.distance_to(c) - h * 0.25 - shot_radius, "at": p}


## The player's hurtbox shapes, re-resolved every REFRESH_FRAMES or as soon as the player dies. Only
## the NODE references are cached — every transform is read fresh on each call, because a mech at
## 60 m/s covers 15 m inside the refresh window and a stale volume would invent misses behind it.
## Every hurtbox in the game is a capsule (the mech's torso and legs, the test dummy); anything else
## falls back to the bounding sphere of its AABB, which errs towards "closer" and can never invent a
## miss that did not happen.
static func shapes() -> Array[CollisionShape3D]:
	var frame := Engine.get_physics_frames()
	if _player != null and is_instance_valid(_player) and frame - _frame < REFRESH_FRAMES:
		return _shapes
	_frame = frame
	_shapes.clear()
	_bare = false
	_player = _find_player()
	if _player == null:
		return _shapes
	_collect(_player, _shapes, 0)
	_bare = _shapes.is_empty()
	return _shapes


static func _find_player() -> Node3D:
	if Game.player != null and is_instance_valid(Game.player):
		return Game.player as Node3D
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group(&"player") as Node3D if tree != null else null


static func _collect(node: Node, out: Array[CollisionShape3D], depth: int) -> void:
	if depth > 4:
		return
	for child in node.get_children():
		if child is Hurtbox:
			for shape in (child as Hurtbox).get_children():
				var cs := shape as CollisionShape3D
				if cs != null and cs.shape != null:
					out.append(cs)
		else:
			_collect(child, out, depth + 1)


## Per-shot state. The shot owns one and calls `sweep` for every segment it survives.
class Tracker:
	var attack: StringName = &""
	var _min: float = INF
	var _at: Vector3 = Vector3.ZERO
	var _fired: bool = false
	var _blocked: bool = false   ## hurtbox contact, a blast that reached the player, or a reflect
	var _radius: float = 0.0     ## the round's own radius, so the number is clear air

	func reset(id: StringName, radius: float) -> void:
		attack = id
		_min = INF
		_at = Vector3.ZERO
		_fired = false
		_blocked = false
		_radius = radius

	## The catch field froze this round: a held round never counts (lead decision, r16).
	func held() -> void:
		_blocked = true

	## The shot touched a hurtbox (whatever the hurtbox then did with it: i-frames, perfect dodge,
	## --god), its blast reached the player, or the barrier ate it — a blocked round is not a miss.
	func contact() -> void:
		_blocked = true

	## A reflected round is the player's own shot now.
	func reflected() -> void:
		_blocked = true

	## One tick of flight the shot survived. Fires the moment the round is past its closest point.
	func sweep(from: Vector3, to: Vector3) -> void:
		if _fired or _blocked:
			return
		var near := EnemyNearMiss.closest(from, to, _radius)
		var d: float = near["distance"]
		if d < _min:
			_min = d
			_at = near["at"]
			return
		if _min <= EnemyNearMiss.RADIUS and d > _min + EnemyNearMiss.RECEDE_EPS:
			_fire()

	## The shot is over (pooled, expired, detonated). A lob that never receded — its burst landed
	## behind cover — still gets its beat, at the point it passed closest.
	func finish() -> void:
		if not _fired and not _blocked and _min <= EnemyNearMiss.RADIUS:
			_fire()
		reset(&"", 0.0)

	func _fire() -> void:
		_fired = true
		var k: float = clampf(_min / EnemyNearMiss.RADIUS, 0.0, 1.0)
		var strength: float = lerpf(EnemyNearMiss.STRENGTH_NEAR, EnemyNearMiss.STRENGTH_FAR, k)
		Feel.play(&"near_miss", _at, strength)
		if EnemyNearMiss._log.size() < EnemyNearMiss.LOG_MAX:
			EnemyNearMiss._log.append({"attack": attack, "at": _at, "distance": _min})
