extends Node
## The hive collapse must FILM (lead brief flow-r5b item 2). The trailer's showcase reel caught the
## lens parked inside geometry about a second after the core died, so this runs the REAL collapse at
## the REAL city sites — A2, A5 and A6, read from the world's own `&"hive_site"` markers — with the
## real CameraRig and the real AimSystem, and judges every frame of the 2 s shot:
##
##   1. the lens is outside every collider (a sphere overlap at the camera, `Layers.MASK_SIGHT`);
##   2. the spire's base and its top are both inside the frustum, with a margin;
##   3. a ray from the lens to each of them is clear.
##
## The hero is placed where a player actually stands when the core dies — on the deck, `HERO_STAND`
## metres out — at four bearings around the hive, and the last bearing of each hive also WALKS, which
## is what proves the shot is pinned to the world instead of riding the hero's own frame.
##
##   tools/godot.sh test res://flow/tests/test_collapse_camera.gd
##
## Headless, but it loads the whole city, so it is slow: expect a couple of minutes.

const CITY := "res://world/city.tscn"
const RIG := preload("res://player/camera/camera_rig.tscn")
const AIM := preload("res://player/aim/aim_system.tscn")
const SPIRE := preload("res://flow/hive_spire.tscn")

## s of camera the collapse holds before control goes back (`FlowHiveCollapse.SHOT_TIME`).
const SHOT_SECONDS := 2.0
## Bearings round the hive the hero is stood at. The last one also walks.
const BEARINGS := 4
## m from the hive's base — the layout's own `assault_r`.
const HERO_STAND := 70.0
## m/s the walking hero crosses the shot at (a mech's walk, SPEC §4).
const WALK_SPEED := 12.0
## m of clear air the lens must keep around it — the landing dip moves the camera up to 1.2 m.
const PROBE := 3.0
## Fraction of the frame the spire's extremes must stay inside, so the ±3° of trauma shake (FEEL
## header) cannot swing them out between one tick and the next.
const EDGE := 0.06
## ms the stand solver may take. It runs on the frame the core dies, in the middle of the reward beat,
## so a sweep that costs more than a frame or two is a visible hitch.
const SOLVE_BUDGET_MS := 25.0

## Stand-in hero: the collapse asks it for `aim()` (the duel frame's hard target) and shoves it clear
## of the wreck when it is inside `FlowHiveCollapse.PUSH_RANGE`.
class Hero extends Node3D:
	var walk: Vector3 = Vector3.ZERO

	func aim() -> Node:
		return get_node_or_null(^"AimSystem")

	func apply_impulse(v: Vector3) -> void:
		walk += v

	func _physics_process(delta: float) -> void:
		global_position += walk * delta


var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _skips: PackedStringArray = PackedStringArray()
var _rig: Node3D = null
var _cam: Camera3D = null
var _hero: Hero = null
var _probe := SphereShape3D.new()
## ms the slowest solve of the run took, reported at the end.
var _slowest: float = 0.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_probe.radius = PROBE
	if not ResourceLoader.exists(CITY):
		_fail("city", "no city scene at " + CITY)
		_finish()
		return
	var city := (load(CITY) as PackedScene).instantiate()
	city.name = "World"
	add_child(city)
	Game.world = city as Node3D
	var waited := 0.0
	while not Game.world_built() and waited < 120.0:
		await get_tree().physics_frame
		waited += 1.0 / 120.0
	if not _check("city.built", Game.world_built(), "the city never reported world_built"):
		_finish()
		return
	_rig = RIG.instantiate() as Node3D
	add_child(_rig)
	_cam = _rig.call(&"camera") as Camera3D
	# The shipped VfxLibrary, so the collapse runs its real debris and smoke column. Without it the
	# beat has no wreck to hold and the run is not the one the game plays.
	var fx := VfxLibrary.new()
	fx.name = "Vfx"
	add_child(fx)
	_hero = Hero.new()
	_hero.name = "Hero"
	var aim := AIM.instantiate()
	aim.name = "AimSystem"
	_hero.add_child(aim)
	add_child(_hero)
	Game.register_player(_hero)
	await _step(4)

	var hives := FlowWorld.hives()
	if not _check("hives.found", hives.size() == 3,
			"the city offers %d hive sites, the brief names three (A2, A5, A6)" % hives.size()):
		_finish()
		return
	for row in hives:
		var floor_here := _floor_under(row["pos"] as Vector3, (row["pos"] as Vector3).y + 12.0)
		print("COLLAPSE site %s (%s) at %.0f,%.0f,%.0f, %.0f m tall, deck under it %s"
				% [row["id"], row["arena"], (row["pos"] as Vector3).x, (row["pos"] as Vector3).y,
				(row["pos"] as Vector3).z, float(row["height"]),
				"none" if floor_here == Vector3.INF else "%.0f" % floor_here.y])
		for i in BEARINGS:
			await _one(row, i)
	_finish()


## One collapse: the hero on the deck at bearing `i` of `BEARINGS` round the hive, the real spire, the
## real collapse, and a verdict on every frame of the shot.
func _one(row: Dictionary, bearing: int) -> void:
	var id := String(row["id"])
	var at := row["pos"] as Vector3
	var height := float(row["height"])
	var angle := TAU * float(bearing) / float(BEARINGS)
	var out := Vector3(cos(angle), 0.0, sin(angle))
	var floor_at := _floor_under(at + out * HERO_STAND, at.y + 12.0)
	if floor_at == Vector3.INF:
		_skip("%s bearing %d: no deck under the hero's stand at %.0f,%.0f,%.0f"
				% [id, bearing, (at + out * HERO_STAND).x, (at + out * HERO_STAND).y,
				(at + out * HERO_STAND).z])
		return
	_hero.walk = Vector3.ZERO
	_hero.global_position = floor_at + Vector3.UP * 8.0
	_hero.global_rotation = Vector3(0.0, atan2(out.x, out.z), 0.0)
	# The last bearing walks: a shot that rides the hero's own frame slides out of the composition
	# (and into the scenery) as soon as the player moves, which is the whole point of the gate.
	if bearing == BEARINGS - 1:
		_hero.walk = Vector3(-out.z, 0.0, out.x) * WALK_SPEED
	_rig.call(&"snap_to_player")
	await _step(2)

	# The solve runs on the frame the core dies, in the middle of the reward beat: a sweep that costs
	# a frame is a visible hitch. This is the same call `FlowHiveCollapse._place` makes.
	var t_solve := Time.get_ticks_usec()
	var probe := FlowCollapseShot.solve(_space(), _hero.global_position, at, height)
	var solve_ms := float(Time.get_ticks_usec() - t_solve) / 1000.0
	_slowest = maxf(_slowest, solve_ms)

	var spire := SPIRE.instantiate() as FlowHiveSpire
	spire.height = height
	spire.setup(StringName(id), StringName(row["arena"]))
	# `height` and the position both have to be set before `_ready` builds the visual and the trunk.
	spire.position = at
	add_child(spire)
	await _step(2)
	spire.collapse()

	var base := at
	var top := at + Vector3.UP * height
	var t0 := Feel.real_now()
	var ticks := 0
	var frames := 0
	var buried := 0
	var clipped := 0
	var blocked := 0
	var first_bad := ""
	var shown := 0
	while Feel.real_now() - t0 < SHOT_SECONDS and ticks < 1500:
		await get_tree().physics_frame
		ticks += 1
		if not bool(_rig.call(&"is_cinematic")):
			break
		frames += 1
		if ticks % 30 == 0:
			print("COLLAPSE   %s b%d t=%.2f cam %.0f,%.0f,%.0f rig %.0f,%.0f,%.0f hero %.0f m fov %.0f"
					% [id, bearing, Feel.real_now() - t0, _cam.global_position.x,
					_cam.global_position.y, _cam.global_position.z, _rig.global_position.x,
					_rig.global_position.y, _rig.global_position.z,
					_cam.global_position.distance_to(_hero.global_position), _cam.fov])
		var bad := _verdict(base, top)
		if bad == "":
			continue
		if first_bad == "":
			first_bad = "t=%.2f %s" % [Feel.real_now() - t0, bad]
		if shown < 3:
			shown += 1
			print("COLLAPSE   %s t=%.2f %s" % [id, Feel.real_now() - t0, bad])
		if bad.begins_with("buried"):
			buried += 1
		elif bad.begins_with("clipped"):
			clipped += 1
		else:
			blocked += 1
	_hero.walk = Vector3.ZERO
	var label := "%s bearing %d" % [id, bearing]
	_check(label + " lens clear", buried == 0,
			"%d of %d frames have the lens inside geometry (%s)" % [buried, frames, first_bad])
	_check(label + " spire framed", clipped == 0,
			"%d of %d frames lose the spire's base or top out of frame (%s)"
			% [clipped, frames, first_bad])
	_check(label + " spire visible", blocked == 0,
			"%d of %d frames have scenery between the lens and the spire (%s)"
			% [blocked, frames, first_bad])
	_check(label + " frames", frames > 30, "the shot only ran %d frames" % frames)
	_check(label + " solve cost", solve_ms <= SOLVE_BUDGET_MS,
			"solving the stand took %.1f ms (budget %.0f), family %s"
			% [solve_ms, SOLVE_BUDGET_MS, str(probe["family"])])
	print("COLLAPSE %s: %d frames, buried=%d clipped=%d blocked=%d, lens at %.0f,%.0f,%.0f, %s stand"
			% [label, frames, buried, clipped, blocked, _cam.global_position.x,
			_cam.global_position.y, _cam.global_position.z, _family_of(spire)])
	_rig.call(&"end_cinematic")
	spire.queue_free()
	await _step(2)


# --- the per-frame verdict ------------------------------------------------------------------------

## Which candidate family the collapse's own solver picked, for the run log.
func _family_of(spire: Node) -> String:
	for child in spire.get_children():
		if child is FlowHiveCollapse:
			return String((child as FlowHiveCollapse).family)
	return "?"

## "" when this frame films the spire, or a readable reason why it does not.
##
## The FRAMING is judged on the true foot of the trunk and its true top. The LINE OF SIGHT is judged
## `FlowCollapseShot.FOOT` metres up the trunk, because the layout sets a hive's tier a few metres
## inside the deck slab it stands on (3 m at A5 and A6) and a ray to the very foot always grazes that
## slab and stops short — from every stand, at every height.
func _verdict(base: Vector3, top: Vector3) -> String:
	var eye := _cam.global_position
	if _inside_solid(eye):
		return "buried: the lens at %.0f,%.0f,%.0f overlaps a collider" % [eye.x, eye.y, eye.z]
	for point: Vector3 in [base, top]:
		var p := _project(point)
		if not _in_frame(p):
			return "clipped: %s projects to (%.3f, %.3f), fov %.1f, lens %.0f m out" \
					% ["base" if point == base else "top", p.x, p.y, _cam.fov,
					eye.distance_to(base)]
	for point: Vector3 in [base + Vector3.UP * FlowCollapseShot.FOOT, top]:
		if not _clear_ray(eye, point):
			return "blocked: %s — the ray stops %.1f m short of the spire's %s" \
					% [_ray_hit(eye, point), eye.distance_to(point)
					- eye.distance_to(_ray_at(eye, point)),
					"foot" if point.y < top.y else "top"]
	return ""


## The lens sits inside a collider when a `PROBE` sphere at the camera overlaps the world.
func _inside_solid(at: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _probe
	params.transform = Transform3D(Basis.IDENTITY, at)
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return not _space().intersect_shape(params, 1).is_empty()


func _clear_ray(from: Vector3, to: Vector3) -> bool:
	var dist := from.distance_to(to)
	if dist < 1.0:
		return true
	return _ray_at(from, to).distance_to(from) >= dist - 4.0


## Where the ray stops: the target itself when nothing is in the way.
func _ray_at(from: Vector3, to: Vector3) -> Vector3:
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit := _space().intersect_ray(params)
	return hit["position"] as Vector3 if not hit.is_empty() else to


## What the ray hit, for the failure text.
func _ray_hit(from: Vector3, to: Vector3) -> String:
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit := _space().intersect_ray(params)
	if hit.is_empty():
		return "nothing"
	var body := hit["collider"] as Node
	return "%s at %.0f,%.0f,%.0f" % [body.name if body != null else "?",
			(hit["position"] as Vector3).x, (hit["position"] as Vector3).y,
			(hit["position"] as Vector3).z]


## World point -> screen fractions (0..1, y down) through the LIVE camera, analytically for a 16:9
## frame so the numbers do not depend on the headless window size. NaN when it is behind the lens.
func _project(world: Vector3) -> Vector2:
	var basis := _cam.global_basis
	var tan_v := tan(deg_to_rad(_cam.fov) * 0.5)
	var v := world - _cam.global_position
	var d := v.dot(-basis.z)
	if d < 0.1:
		return Vector2(NAN, NAN)
	return Vector2(v.dot(basis.x) / (d * tan_v * (16.0 / 9.0)) * 0.5 + 0.5,
			0.5 - v.dot(basis.y) / (d * tan_v) * 0.5)


func _in_frame(p: Vector2) -> bool:
	if is_nan(p.x) or is_nan(p.y):
		return false
	return p.x >= EDGE and p.x <= 1.0 - EDGE and p.y >= EDGE and p.y <= 1.0 - EDGE


## The deck under a stand, or `Vector3.INF` when the hero would be falling. The ray starts just above
## the hive's own foot, NOT high overhead: A2 is a five-tier interchange and a ray from 300 m up lands
## on a deck 48 m above the hive, which is not where a player fighting it stands.
func _floor_under(at: Vector3, from_y: float = INF) -> Vector3:
	var top := at.y + 300.0 if is_inf(from_y) else from_y
	var params := PhysicsRayQueryParameters3D.create(Vector3(at.x, top, at.z),
			Vector3(at.x, at.y - 300.0, at.z))
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	var hit := _space().intersect_ray(params)
	return hit["position"] as Vector3 if not hit.is_empty() else Vector3.INF


func _space() -> PhysicsDirectSpaceState3D:
	return get_viewport().world_3d.direct_space_state


func _step(seconds: float) -> void:
	var t0 := Feel.real_now()
	while Feel.real_now() - t0 < seconds:
		await get_tree().physics_frame


# --- reporting ------------------------------------------------------------------------------------

func _check(id: String, ok: bool, detail: String) -> bool:
	_checks += 1
	if not ok:
		_failures.append("%s: %s" % [id, detail])
	return ok


func _skip(what: String) -> void:
	_skips.append(what)
	print("TEST SKIP ", what)


func _fail(id: String, detail: String) -> void:
	_check(id, false, detail)


func _finish() -> void:
	print("TEST %d checks, %d failed, %d skipped (slowest solve %.1f ms)"
			% [_checks, _failures.size(), _skips.size(), _slowest])
	for line in _failures:
		print("TEST FAIL ", line)
	print("PASS" if _failures.is_empty() else "FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)
