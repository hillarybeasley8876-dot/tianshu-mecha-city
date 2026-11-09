extends Node
## Execution mini-cinematics (camera-aim, CONTRACTS §5). Owns the shot list, the DUEL FRAME and the blend
## between shots; the rig keeps the follow/look code and exposes the hooks this drives.
## Duel frame: origin = midpoint of player and hard target, −Z = the flattened direction player → target,
## +Y up, +X right. A shot is {offset: Vector3, look: Vector3 (same frame, default 0), fov, t}, so
## `(36, 10, 0)` is a side view of both fighters and `(-14, 22, 40)` sits behind the player.
## Every shot is resolved against collision — a sphere cast from the frame origin on MASK_SIGHT plus both
## actors' AABBs inflated by 3 m — so the camera never ends up inside a building or inside the hero.

const BLEND := 0.25                  ## s cross-fade between shots
const PROBE_RADIUS := 0.8            ## m of camera volume kept clear of geometry
const MARGIN := 0.6                  ## m pulled back from a hit surface
const ACTOR_PAD := 3.0               ## m the actors' AABBs are inflated by (CONTRACTS §5)
const ACTOR_PUSH := 1.2              ## m the camera is pushed out along the ray when inside an actor

var active: bool = false
## True when this request's timeline runs on player time (melee executions, CONTRACTS §5). The rig reads
## it to decide which clock it feeds `advance()`.
var player_clock: bool = false

var _rig: Node3D = null
var _shots: Array[Dictionary] = []
var _time: float = 0.0
var _left: float = 0.0
var _player: Node3D = null
var _target: Node3D = null
var _probe := SphereShape3D.new()


func setup(rig: Node3D) -> void:
	_rig = rig
	_probe.radius = PROBE_RADIUS


## `shots` are keyed by `t` (seconds from the start); control returns after `duration`. The frame is
## rebuilt every tick from the live actors, so the shot tracks them as they move. `clock` is `&"player"`
## when the caller times its own beats on `Feel.player_delta` (an execution's hit-stops hold the cut)
## and `&"real"` for presentation beats — the rig feeds `advance()` from the matching clock.
func request(shots: Array, duration: float, clock: StringName = &"real") -> void:
	_shots.clear()
	for shot: Dictionary in shots:
		_shots.append(shot)
	_shots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	_time = 0.0
	_left = maxf(duration, 0.0)
	player_clock = clock == &"player"
	_player = Game.player as Node3D
	_target = _rig.call(&"hard_target") as Node3D
	active = _left > 0.0 and _player != null
	if not active:
		# Also covers replacing a live cinematic with an empty request: end_cinematic() is idempotent.
		cancel()
		_rig.call(&"end_cinematic")
		return
	_rig.call(&"set_look_enabled", false)
	if not _shots.is_empty():
		_apply(_shots[0], 0.0)


## Drop the shot list without calling back into the rig: `CameraRig.end_cinematic()` calls this and must
## not recurse (CONTRACTS §5). Restoring look, FOV and arm is the rig's job in that same call.
func cancel() -> void:
	active = false
	player_clock = false
	_shots.clear()
	_player = null
	_target = null


## Called by the rig every physics tick while active.
func advance(delta: float) -> void:
	_time += delta
	_left -= delta
	if _left <= 0.0:
		_finish()
		return
	if _shots.is_empty() or _player == null:
		return
	var idx := 0
	for i in _shots.size():
		if float(_shots[i].get("t", 0.0)) <= _time:
			idx = i
	_apply(_shots[idx], _blend_from(idx))


## Seconds into the cross-fade from the previous shot (0 = fully on the previous one).
func _blend_from(idx: int) -> float:
	if idx == 0:
		return 1.0
	var span := maxf(float(_shots[idx].get("t", 0.0)) - float(_shots[idx - 1].get("t", 0.0)), 0.001)
	var into := _time - float(_shots[idx].get("t", 0.0))
	return smoothstep(0.0, 1.0, clampf(into / minf(BLEND, span), 0.0, 1.0))


func _apply(shot: Dictionary, weight: float) -> void:
	var offset := shot.get("offset", Vector3.ZERO) as Vector3
	var look := shot.get("look", Vector3.ZERO) as Vector3
	if weight < 1.0:
		var idx := _shots.find(shot)
		if idx > 0:
			var prev := _shots[idx - 1]
			offset = offset.lerp(prev.get("offset", Vector3.ZERO) as Vector3, 1.0 - weight)
			look = look.lerp(prev.get("look", Vector3.ZERO) as Vector3, 1.0 - weight)
	var frame := duel_frame()
	var eye := _resolve(frame * offset, frame.origin)
	var aim := frame * look
	var dir := aim - eye
	var basis := frame.basis if dir.length_squared() < 0.01 \
			else Basis.looking_at(dir.normalized(), Vector3.UP)
	_rig.global_transform = Transform3D(basis, eye)
	_rig.call(&"set_arm_length", 0.0)
	if shot.has("fov"):
		_rig.call(&"hold_fov", float(shot["fov"]))


## The duel frame for this tick: midpoint of the two actors, −Z along player → target.
func duel_frame() -> Transform3D:
	var a := _player.global_position
	var b := a + Vector3.FORWARD * 10.0
	if _target != null and is_instance_valid(_target):
		b = _target.global_position
	var forward := b - a
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = -_player.global_basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.01:
			forward = Vector3.FORWARD
	var z := -forward.normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Transform3D(Basis(x, Vector3.UP, z), (a + b) * 0.5)


## Pulls `want` back along the ray from the frame origin until it is clear of the world and of both
## actors (their AABBs inflated by ACTOR_PAD). Returns a point that is always outside everything.
func _resolve(want: Vector3, origin: Vector3) -> Vector3:
	var to := want - origin
	var dist := to.length()
	if dist < 0.01:
		return want
	var dir := to / dist
	var clear := _world_clearance(origin, dir, dist)
	var limit := minf(dist, maxf(clear - MARGIN, 0.0))
	# Actors are not on MASK_SIGHT's hit list for this query's purposes: test them explicitly so a shot
	# never ends up inside the hero or the boss.
	var t := limit
	while t > 0.5 and _inside_actor(origin + dir * t):
		t -= ACTOR_PUSH
	return origin + dir * maxf(t, 0.5)


## Distance the camera may travel from `origin` along `dir` before the probe touches scenery.
func _world_clearance(origin: Vector3, dir: Vector3, dist: float) -> float:
	var space := _space()
	if space == null:
		return dist
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _probe
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.motion = dir * dist
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit := space.cast_motion(params)
	if hit.is_empty():
		return 0.0 if _blocked_at(origin, space) else dist
	var safe := float(hit[0])
	return dist if safe >= 1.0 else dist * maxf(safe, 0.0)


func _blocked_at(origin: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _probe
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return not space.intersect_shape(params, 1).is_empty()


## True when a world point sits inside either actor's AABB inflated by ACTOR_PAD. A Targetable marker is
## resolved to the actor it belongs to, so the whole body counts, not just the marker.
func _inside_actor(point: Vector3) -> bool:
	for node in [_player, _target]:
		if node == null or not is_instance_valid(node):
			continue
		var actor := node.call(&"actor") as Node3D if node.has_method(&"actor") else node as Node3D
		if actor != null and _actor_box(actor).grow(ACTOR_PAD).has_point(point):
			return true
	return false


## World bounds of an actor from its meshes, falling back to a 12 m box (a 16 m mech with no model yet).
func _actor_box(actor: Node3D) -> AABB:
	var body := actor
	if actor.has_method(&"model"):
		var model := actor.call(&"model") as Node3D
		if model != null:
			body = model
	var out := AABB()
	var found := false
	for node in _meshes(body):
		var box: AABB = (node as MeshInstance3D).global_transform * (node as MeshInstance3D).get_aabb()
		out = box if not found else out.merge(box)
		found = true
	return out if found else AABB(actor.global_position - Vector3(6, 6, 6), Vector3(12, 12, 12))


func _meshes(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node is MeshInstance3D:
		found.append(node)
	for c in node.get_children():
		found.append_array(_meshes(c))
	return found


func _space() -> PhysicsDirectSpaceState3D:
	return _rig.get_world_3d().direct_space_state if _rig != null and _rig.is_inside_tree() else null


## Control goes back to the player. One path: `cancel()` drops the shot list, then the rig's
## `end_cinematic()` restores look input, releases the held FOV and restores the arm length the shots
## collapsed to zero (restored at full length instead of creeping out at 10 m/s).
func _finish() -> void:
	var was := active
	cancel()
	if not was:
		return
	_rig.call(&"end_cinematic")
