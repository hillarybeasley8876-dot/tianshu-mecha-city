class_name MechStepping
extends RefCounted
## SPEC §4 "Stepping". Godot 4's `CharacterBody3D` cannot climb a kerb at all, so the mech probes the
## world itself before every move: `try_step` lifts it onto any walkable top within `step_height`, and
## while the thrusters are lit `try_hop` throws it over anything up to `hop_max_height` tall.
## Both run before `move_and_slide()`, so neither costs the mech a frame of speed.
##
## The obstacle is measured with rays rather than a capsule sweep: a 3.5 m capsule meets a 2 m kerb on
## its rounded bottom hemisphere, so `test_move` reports the kerb's top EDGE (a normal tilted ~60 deg,
## never walkable) instead of its top face. The rays give the face position and the top height; the
## body is then verified with test_move up -> forward before the coast walks it there. The coast ends
## `LIFT_EXTRA` above the top face, and `move_and_slide`'s 0.6 m floor snap settles it from there.

const ANKLE := 0.5      ## height above the feet the forward probe runs at
const MIN_RISE := 0.08  ## below this the "step" is the ground the mech is already standing on
const STEP_PAST := 0.3  ## metres past the face the body is placed, so it lands on the top face
const LIFT_EXTRA := 0.05  ## clear the top by a hair: a capsule that exactly grazes it cannot slide


## Steps onto a kerb: find the face and its top, then hand the whole displacement to the locomotion's
## coast (`MechLocomotion.begin_coast`). Fires while the face is still `step_probe` away, because once
## `move_and_slide` has hit the wall the velocity is gone and the mech would have to accelerate from a
## standstill. r8 item 1: the body is NOT teleported any more — a 3.5 m-radius capsule has to travel
## ~4.2 m forward to get its bottom point over the face, and doing that in one tick threw the hip
## 7 m past the trailing foot's plant, past the end of the leg. The coast walks the same displacement
## at the speed the mech already had, so nothing stalls and the legs can follow.
static func try_step(l: MechLocomotion, _delta: float) -> bool:
	var b := l.body
	var t := l.tuning
	if not l._on_floor or l.coasting():
		return false  # airborne: the air states own the vertical; coasting: the step is already running
	var hv := Vector3(b.velocity.x, 0.0, b.velocity.z)
	var speed := hv.length()
	var dir := Vector3.ZERO
	if speed > 0.5:
		dir = hv / speed
	elif l.input.move.length() > 0.05:
		dir = l.wish_dir()  # crawling into a kerb still climbs it
		speed = t.walk_speed
	else:
		return false
	var probe := _probe_top(l, dir, t.capsule_radius + t.step_probe, t.step_height)
	if probe.is_empty() or float(probe["rise"]) > t.step_height:
		return false
	var up := Vector3.UP * (float(probe["rise"]) + LIFT_EXTRA)
	if b.test_move(b.global_transform, up, null, b.safe_margin):
		return false  # no headroom to lift into
	var forward := dir * (maxf(float(probe["gap"]), 0.0) + STEP_PAST)
	if b.test_move(b.global_transform.translated(up), forward, null, b.safe_margin):
		return false  # something else is in the way up there
	l.begin_coast(up + forward, float(probe["rise"]), speed)
	return true


## Boost hop (SPEC §4): the same probe, but anything up to `hop_max_height` tall is cleared with
## thrust instead of a step. A taller wall is left alone, so the boost slides along it.
static func try_hop(l: MechLocomotion) -> bool:
	var b := l.body
	var t := l.tuning
	if not l._on_floor or l._hop_cd > 0.0:
		return false
	var hv := Vector3(b.velocity.x, 0.0, b.velocity.z)
	var speed := hv.length()
	if speed < t.hop_min_speed:
		return false  # at walking pace the step-up is enough
	var dir := hv / speed
	var probe := _probe_top(l, dir, speed * t.hop_lookahead * t.hop_lookahead_scale,
			t.hop_max_height)
	if probe.is_empty() or float(probe["rise"]) <= t.step_height:
		return false
	# The thrust must clear the top by the time the mech ARRIVES, not eventually: solve the ballistic
	# rise for the time the capsule front has left before it touches the face.
	var flight := maxf(float(probe["gap"]) - t.capsule_radius, 0.25) / speed
	var v0 := (float(probe["rise"]) + t.hop_clearance) / flight + 0.5 * t.fall_gravity * flight
	if v0 > t.hop_max_impulse:
		return false  # too late to make it: better to hit the wall than to pop into orbit
	b.velocity.y = maxf(b.velocity.y, v0)
	l._hop_cd = t.hop_cooldown
	l.hop_events += 1
	l._air_start_y = b.global_position.y
	Feel.play(&"jump", b.global_position)
	return true


## Face and top of the obstacle straight ahead, as {"gap": m to the face, "rise": m above the feet,
## "normal": top normal}, or {} when the way is clear / the top is out of reach or not walkable.
static func _probe_top(l: MechLocomotion, dir: Vector3, reach: float, max_rise: float) -> Dictionary:
	var b := l.body
	var t := l.tuning
	var space := b.get_world_3d().direct_space_state
	var feet := b.global_position.y - t.capsule_height * 0.5
	var face := _ray(space, Vector3(b.global_position.x, feet + ANKLE, b.global_position.z),
			dir, reach, b.collision_mask)
	if face.is_empty():
		return {}
	var face_normal := face["normal"] as Vector3
	if face_normal.angle_to(Vector3.UP) <= b.floor_max_angle:
		return {}  # a walkable slope, not a kerb: move_and_slide already climbs it
	var hit := face["position"] as Vector3
	var over := hit + dir * t.capsule_radius * 0.5  # a little past the face: over the top face
	var from_above := Vector3(over.x, feet + max_rise + ANKLE, over.z)
	var top := _ray(space, from_above, Vector3.DOWN, max_rise + ANKLE, b.collision_mask)
	if top.is_empty():
		return {}  # taller than `max_rise`, or nothing to land on at all
	var normal := top["normal"] as Vector3
	var rise := (top["position"] as Vector3).y - feet
	if rise < MIN_RISE or normal.angle_to(Vector3.UP) > b.floor_max_angle:
		return {}  # flat ground, or a top too steep to stand on
	return {"gap": (hit - b.global_position).dot(dir), "rise": rise, "normal": normal}


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, dist: float,
		mask: int) -> Dictionary:
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * dist)
	params.collision_mask = mask
	params.hit_from_inside = false
	return space.intersect_ray(params)
