extends "res://player/camera/tests/camera_test_base.gd"
## CameraRig test (camera-aim). Run: tools/godot.sh test res://player/camera/tests/test_camera.gd
## Runs a stand-in mech down a 24 m corridor (wall on one side, a deck overhead) and probes the camera
## for geometry intersection EVERY TICK, then checks the first/third person round trip, a cinematic and the
## cockpit coverage (shake, FOV and landing dip: test_camera_feel.gd).
## Numbers under test: SPEC §5 + lead reviews r2/r3 — arm 42 m (ADS 34, boost 46/48/52), pivot 12.5 m,
## shoulder 12 m, pitch −6°, FOV 55/38 third and 62/45 first, blend 0.35 s, boost FOV 60/66.

const AIM := preload("res://player/aim/aim_system.tscn")

const SPEED := 40.0
const RUN_TICKS := 480            ## 4 s at 120 Hz: x -80 → +80
const HERO_SIZE := Vector3(9.7, 15.4, 13.5)   ## the placeholder hero's bounds
const ARM_FULL := 42.0                          ## lead review r2: framing wins over a short arm
const ARM_ADS := 34.0            ## lead review r3: 28 m put the hero over 80 % of the height and ate the frame
## Lead review r2 (SPEC §5): the hero spans ≈ 40 % of the screen height, its body sits at ≈ 34 % of the
## width and the crosshair keeps ≥ 6 % of the width clear. All three are reachable together at arm 42 m
## with a 12 m shoulder offset (SPEC's "≈ 40 m"), and the bands below pin them so a later change to
## either number is caught immediately.
const HEIGHT_BAND := Vector2(0.36, 0.44)
const CENTRE_BAND := Vector2(0.31, 0.37)
const CLEARANCE_MIN := 0.06
## ADS framing at arm 34 m / FOV 38 (measured 79.6 %). Widening the band would hide a real regression,
## so it is pinned tight; the arm needed for a lighter zoom is in the review notes, not here.
const ADS_HEIGHT_BAND := Vector2(0.76, 0.83)
const COCKPIT_MAX_COVER := 0.18


## A lockable dummy for the cinematic's duel frame: the AimSystem needs a real actor behind the mark.
class DummyEnemy extends StaticBody3D:
	var alive: bool = true
	func take_hit(_hit: HitInfo) -> void:
		pass
	func is_alive() -> bool:
		return alive


## A building that fades out of the way (SPEC §5). The rig calls `set_fade` on anything in the
## `camera_dither` group between the hero and the camera.
class DitherBox extends StaticBody3D:
	var fade: float = 1.0
	func set_fade(amount: float) -> void:
		fade = amount


func _ready() -> void:
	await _build()
	await _test_framing()
	await _test_follow_and_collision()
	await _test_occluder_fade()
	await _test_witch_time()
	await _test_mode_toggle()
	await _test_cinematic()
	await _test_cockpit_coverage()
	_report()


## Framing bands from lead review r2, measured through the LIVE camera on a hero-sized stand-in box.
func _test_framing() -> void:
	# Open ground: nothing behind the camera. The wait covers the follow spring (10 rad/s); the arm is
	# snapped out rather than left to walk 42 m at its 10 m/s push-out speed after the teleport.
	_player.position = Vector3(0.0, 0.0, -160.0)
	await _ticks(120)
	_rig.call(&"snap_to_player")     # deterministic: seat the rig and the arm instead of waiting 4 s
	await _ticks(120)
	var box := AABB(_player.global_position - Vector3(HERO_SIZE.x * 0.5, 0.0, HERO_SIZE.z * 0.5), HERO_SIZE)
	var m := _project_box(box)
	_check(m[0] >= HEIGHT_BAND.x and m[0] <= HEIGHT_BAND.y,
			"the hero fills %.1f %% of the screen height (want %.0f–%.0f)" % [
					m[0] * 100.0, HEIGHT_BAND.x * 100.0, HEIGHT_BAND.y * 100.0])
	_check(m[1] >= CENTRE_BAND.x and m[1] <= CENTRE_BAND.y,
			"its body sits at %.1f %% of the width, left of the crosshair (want %.0f–%.0f)" % [
					m[1] * 100.0, CENTRE_BAND.x * 100.0, CENTRE_BAND.y * 100.0])
	_check(m[2] >= CLEARANCE_MIN, "the crosshair keeps %.1f %% of the width clear (want ≥ %.0f)" % [
			m[2] * 100.0, CLEARANCE_MIN * 100.0])
	_check(m[3] > 0.35, "the hero sits in the lower half of the frame (top at %.1f %%)" % [m[3] * 100.0])
	_check(absf(float(_rig.get_node(^"Yaw/Pitch/Shoulder/Arm").call(&"current_length")) - ARM_FULL) < 0.5,
			"the arm holds the review's %.0f m in the open" % ARM_FULL)
	# SPEC §5: aiming down sights pulls the arm in to 34 m over the FOV channel's own 0.25 s ramp.
	Input.action_press(&"aim")
	await _ticks(60)
	var ads_arm := float(_rig.get_node(^"Yaw/Pitch/Shoulder/Arm").call(&"current_length"))
	_check(absf(ads_arm - ARM_ADS) < 0.5, "ADS shortens the arm to %.0f m (%.1f)" % [ARM_ADS, ads_arm])
	_check(absf(_cam.fov - 38.0) < 0.5, "ADS zooms to FOV 38 (%.1f)" % _cam.fov)
	# Review r3: the zoom must stay readable — the hero grows, but stays inside the frame.
	# Measured geometry at ADS FOV 38: screen height ≈ 2706 / arm_m %, so 34 m → 79.6 %, 38 m → 71 %,
	# 45 m → 60 %. 34 m is the lead's r3 constant; the band below pins it plus the crosshair clearance.
	var ads_box := _project_box(AABB(
			_player.global_position - Vector3(HERO_SIZE.x * 0.5, 0.0, HERO_SIZE.z * 0.5), HERO_SIZE))
	_check(ads_box[0] >= ADS_HEIGHT_BAND.x and ads_box[0] <= ADS_HEIGHT_BAND.y,
			"ADS keeps the hero at %.1f %% of the height (want %.0f–%.0f)" % [
					ads_box[0] * 100.0, ADS_HEIGHT_BAND.x * 100.0, ADS_HEIGHT_BAND.y * 100.0])
	_check(ads_box[2] >= CLEARANCE_MIN, "ADS keeps the crosshair %.1f %% clear (want ≥ %.0f)" % [
			ads_box[2] * 100.0, CLEARANCE_MIN * 100.0])
	Input.action_release(&"aim")
	await _ticks(220)   # the arm pushes back out at 10 m/s after its 0.25 s hold: 8 m ≈ 1.0 s
	_check(absf(float(_rig.get_node(^"Yaw/Pitch/Shoulder/Arm").call(&"current_length")) - ARM_FULL) < 1.0,
			"the arm returns to %.0f m when ADS is released" % ARM_FULL)


## The whole point of the arm: while the mech runs along a wall and under the deck, the camera may pull
## in as far as it likes but must never end up inside the world.
func _test_follow_and_collision() -> void:
	_player.position = Vector3(-80.0, 0.0, 0.0)
	await _ticks(400)            # let the rig travel back from the framing test's teleport
	var arm_full := ARM_FULL
	var inside := 0
	var min_arm := arm_full
	var min_gap := INF
	var under_deck_min := arm_full
	var delta := 1.0 / 120.0
	for i in RUN_TICKS:
		_player.position.x += SPEED * delta
		await get_tree().physics_frame
		var arm := float(_rig.get_node(^"Yaw/Pitch/Shoulder/Arm").call(&"current_length"))
		min_arm = minf(min_arm, arm)
		if absf(_player.position.x) < 30.0:
			under_deck_min = minf(under_deck_min, arm)
		if _camera_hits_world():
			inside += 1
			if inside <= 3:
				print("      inside at tick %d cam %s arm %.1f" % [i, _cam.global_position, arm])
		min_gap = minf(min_gap, _cam.global_position.distance_to(_player.global_position))
	_check(inside == 0, "camera never inside geometry over %d ticks (%d violations)" % [RUN_TICKS, inside])
	_check(min_arm < arm_full - 1.0, "the wall forced the arm in (min %.1f m of %.0f)" % [min_arm, arm_full])
	_check(under_deck_min < arm_full - 1.0,
			"passing under the deck pulled the camera in (min %.1f m)" % under_deck_min)
	_check(min_gap > 1.0, "the camera never collapses onto the player (closest %.1f m)" % min_gap)
	# Recovery: run back into the open and the arm must extend again.
	# SPEC §5: push out at 10 m/s after a 0.25 s hold, so a full recovery from 0 m takes ~4.5 s.
	_player.position = Vector3(-80.0, 0.0, 60.0)
	await _ticks(700)
	var recovered := float(_rig.get_node(^"Yaw/Pitch/Shoulder/Arm").call(&"current_length"))
	_check(recovered > arm_full - 0.5, "the arm recovers to full length in the open (%.1f m)" % recovered)


## CONTRACTS §3 clocks: witch time runs the player at FULL speed while the world crawls, so the camera
## springs must run on `Feel.real_delta` — a camera on scaled time would trail four times further behind.
func _test_witch_time() -> void:
	_player.position = Vector3(-80.0, 0.0, -160.0)
	await _ticks(300)
	var delta := 1.0 / 120.0
	var baseline := 0.0
	for i in 120:
		_player.position.x += SPEED * delta * Feel.player_time_comp()
		await get_tree().physics_frame
		baseline = maxf(baseline, _rig.global_position.distance_to(_player.global_position
				+ Vector3.UP * 12.5))
	Feel.slow_mo(0.25, 2.0, 0.0, 0.0, true)          # witch time: the player keeps full speed
	await _ticks(2)
	_check(Feel.is_witch_time(), "witch time is running for the camera test")
	var lagged := 0.0
	for i in 120:
		# Locomotion is never slowed by witch time, so the stand-in moves the same distance per tick.
		_player.position.x += SPEED * delta
		await get_tree().physics_frame
		lagged = maxf(lagged, _rig.global_position.distance_to(_player.global_position
				+ Vector3.UP * 12.5))
	_check(lagged < maxf(baseline, 1.0) * 1.5 + 0.5,
			"the follow spring keeps up in witch time (%.1f m lag vs %.1f m at normal speed)"
			% [lagged, baseline])
	Engine.time_scale = 1.0


## SPEC §5: whatever stands between the hero and the camera dithers to 30 % and comes back when clear.
func _test_occluder_fade() -> void:
	var pillar := DitherBox.new()
	pillar.name = "Pillar"
	pillar.collision_layer = Layers.WORLD
	pillar.collision_mask = 0
	pillar.add_to_group(&"camera_dither")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 6.0)
	shape.shape = box
	pillar.add_child(shape)
	pillar.position = _player.global_position + Vector3(8.0, 13.0, 11.0)
	add_child(pillar)
	await _ticks(60)
	_check(pillar.fade < 0.45, "an occluder in the camera's way dithers to 30 %% (%.2f)" % pillar.fade)
	_rig.call(&"occluder_fade", 0.0)          # scripted beat: hide it completely
	await _ticks(60)
	_check(pillar.fade < 0.05, "occluder_fade(0) hides it outright (%.2f)" % pillar.fade)
	_rig.call(&"occluder_fade", 1.0)
	pillar.position.y += 60.0                 # out of the way
	await _ticks(120)
	_check(is_equal_approx(pillar.fade, 1.0), "it comes back solid once it is clear (%.2f)" % pillar.fade)
	pillar.queue_free()


func _test_mode_toggle() -> void:
	_check(not _rig.is_first_person(), "starts in third person")
	_check(absf((_rig.call(&"look_angles") as Vector2).y + 6.0) < 0.01,
			"the view starts at the SPEC default pitch of −6°")
	var third_gap := _cam.global_position.distance_to(_player.global_position)
	_rig.call(&"set_first_person", true)
	await _ticks(60)             # 0.35 s blend + margin
	var eye: Vector3 = _player.global_position + Vector3.UP * 13.5
	_check(_rig.is_first_person(), "set_first_person(true) took")
	_check(_mode_events.size() == 1 and _mode_events[0], "Events.camera_mode_changed fired (first person)")
	_check(_cam.global_position.distance_to(eye) < 0.6, "the eye sits at the cockpit socket (%.2f m off)"
			% _cam.global_position.distance_to(eye))
	_check(absf(_cam.fov - 62.0) < 0.5, "first person FOV is 62 (%.1f)" % _cam.fov)
	await _ticks(2)
	_check((_rig.get_node(^"Cockpit") as Node3D).visible, "the cockpit frame is shown")
	_rig.call(&"set_first_person", false)
	# The arm pushes back out at 10 m/s after a 0.25 s hold (SPEC §5): 42 m needs ~4.5 s from a pull-in.
	await _ticks(600)
	_check(not _rig.is_first_person(), "toggles back to third person")
	_check(_mode_events.size() == 2 and not _mode_events[1], "second mode event is third person")
	_check(_cam.global_position.distance_to(_player.global_position) > third_gap - 1.0,
			"the view returns behind the shoulder")
	_check(absf(_cam.fov - 55.0) < 0.5, "third person FOV is back to 55 (%.1f)" % _cam.fov)
	_check(not (_rig.get_node(^"Cockpit") as Node3D).visible, "the cockpit frame is hidden again")


## CONTRACTS §5: shots live in the DUEL FRAME (origin = midpoint of hero and target, −Z from hero to
## target), every shot is resolved against collision and against both actors, and the arm comes back.
func _test_cinematic() -> void:
	_player.position = Vector3(-80.0, 0.0, -100.0)      # open ground: the shots are not blocked
	await _ticks(200)
	var body := DummyEnemy.new()
	body.name = "Boss"
	body.collision_layer = Layers.ENEMY
	body.collision_mask = 0
	var enemy_shape := CollisionShape3D.new()
	var enemy_box := BoxShape3D.new()
	enemy_box.size = Vector3(12.0, 16.0, 12.0)
	enemy_shape.shape = enemy_box
	body.add_child(enemy_shape)
	var enemy := Targetable.new()
	enemy.name = "Mark"
	body.add_child(enemy)
	add_child(body)
	body.global_position = _player.global_position + Vector3(0.0, 8.0, -60.0)
	var aim := AIM.instantiate()
	_player.add_child(aim)
	await _ticks(4)
	aim.call(&"lock_to", enemy)
	await _ticks(4)
	_check(_rig.call(&"hard_target") == enemy, "the rig sees the locked target as the cinematic anchor")
	var midpoint := (_player.global_position + enemy.global_position) * 0.5
	var shots: Array = [
		{"offset": Vector3(0.0, 8.0, 30.0), "look": Vector3(0.0, 4.0, 0.0), "fov": 45.0, "t": 0.0},
		{"offset": Vector3(20.0, 4.0, -10.0), "fov": 35.0, "t": 0.5},
	]
	_rig.call(&"request_cinematic", shots, 1.0)
	await _ticks(2)
	_check(bool(_rig.call(&"is_cinematic")), "the cinematic took control")
	# Shot 1 sits 30 m behind the midpoint along the hero → target axis, i.e. behind the player.
	var expected: Vector3 = midpoint + Vector3(0.0, 8.0, 30.0)
	_check(_cam.global_position.distance_to(expected) < 1.5,
			"shot 1 places the camera in the duel frame (%.1f m off)"
			% _cam.global_position.distance_to(expected))
	var to_look: Vector3 = midpoint + Vector3(0.0, 4.0, 0.0) - _cam.global_position
	_check((-_cam.global_basis.z).dot(to_look.normalized()) > 0.999,
			"the shot looks at the duel-frame `look` point (dot %.4f, fwd %s want %s)" % [
					(-_cam.global_basis.z).dot(to_look.normalized()), -_cam.global_basis.z,
					to_look.normalized()])
	_check(absf(_cam.fov - 45.0) < 0.5, "shot 1 FOV applies (%.1f)" % _cam.fov)
	await _ticks(90)             # 0.75 s: the 0.25 s cross-fade into shot 2 has finished
	_check(absf(_cam.fov - 35.0) < 0.5, "shot 2 FOV blends in (%.1f)" % _cam.fov)
	# Shot 2 is beside the pair, 20 m out: it must be clear of both actors and of the world.
	_check(not _point_in_actors(_cam.global_position),
			"a shot is never inside an actor (camera at %s)" % _cam.global_position)
	await _ticks(60)
	_check(not bool(_rig.call(&"is_cinematic")), "control returns after the duration")
	var arm_node := _rig.get_node(^"Yaw/Pitch/Shoulder/Arm")
	_check(float(arm_node.call(&"current_length")) > float(arm_node.call(&"_free_length")) - 0.5,
			"the arm is restored at once, not crept out (%.1f of %.1f m free)" % [
					float(arm_node.call(&"current_length")), float(arm_node.call(&"_free_length"))])
	_check(bool(_rig.get_node(^"Look").get(&"enabled")), "look input is handed back")
	await _ticks(40)
	_check(absf(_cam.fov - 55.0) < 2.0, "the FOV override is released (%.1f)" % _cam.fov)
	_check(_rig.global_basis.z.distance_to(Vector3.BACK) < 0.001,
			"the rig's own basis is cleared: a shot's rotation must not survive the cinematic (%s)"
			% _rig.global_basis.z)
	# A shot aimed into a wall must be pulled back in front of it instead of ending up inside.
	_box("shot_wall", Vector3(-80.0, 20.0, -66.0), Vector3(80.0, 60.0, 4.0))
	_rig.call(&"request_cinematic", [{"offset": Vector3(0.0, 8.0, 60.0), "fov": 50.0, "t": 0.0}], 0.5)
	await _ticks(4)
	_check(not _camera_hits_world(), "a shot into a wall is resolved in front of it (%s)"
			% _cam.global_position)
	await _ticks(90)
	aim.call(&"lock_to", null)
	body.queue_free()


## The 3 m inflation CONTRACTS §5 requires around each actor, mirrored from CameraCinematic.
func _point_in_actors(point: Vector3) -> bool:
	for actor: Node3D in [_player as Node3D, _rig.call(&"hard_target") as Node3D]:
		if actor == null or not is_instance_valid(actor):
			continue
		if AABB(actor.global_position - Vector3(6.0, 6.0, 6.0), Vector3(12.0, 12.0, 12.0)) \
				.grow(3.0).has_point(point):
			return true
	return false


# --- helpers --------------------------------------------------------------------------------------

## Marking helpers for the cockpit rasterisation (`_project_point` and `_corners_of` live in the base).


## Lead review r1: the cockpit frame may cover at most 18 % of the screen. The mask is a 160×90
## rasterisation of every opaque part's projected footprint (the glass is transparent and excluded), so
## a strut that drifts into the middle of the view fails the test instead of being eyeballed.
func _test_cockpit_coverage() -> void:
	_rig.call(&"set_look", 0.0, -6.0)      # the cinematic above left the view yawed
	_rig.call(&"set_first_person", true)
	await _ticks(120)
	var canopy := _rig.get_node(^"Cockpit/Canopy")
	_check(canopy != null and (canopy as Node3D).visible, "the canopy is shown in first person")
	var cols := 160
	var rows := 90
	var mask := PackedByteArray()
	mask.resize(cols * rows)
	var bands: Array[String] = []
	for child in canopy.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.name == &"canopy_glass":
			continue
		var band := _rasterise(_screen_points_of(mi), mask, cols, rows)
		bands.append("%s %.0f–%.0f%%" % [mi.name, band.position.y * 100.0,
				(band.position.y + band.size.y) * 100.0])
	var covered := 0
	for cell in mask:
		covered += cell
	var cover := float(covered) / float(cols * rows)
	print("      cockpit bands: " + ", ".join(bands))
	_check(cover <= COCKPIT_MAX_COVER, "the cockpit frame covers %.1f %% of the screen (limit %.0f %%)"
			% [cover * 100.0, COCKPIT_MAX_COVER * 100.0])
	var dash := _rasterise(_screen_points_of(canopy.get_node(^"dash") as MeshInstance3D),
			PackedByteArray(), 1, 1)
	_check(dash.position.y > 0.86 and dash.position.y < 0.95
					and dash.position.y + dash.size.y > 0.95,
			"the console sits in the bottom 8–10 %% of the frame (%.0f–%.0f %%)"
			% [dash.position.y * 100.0, (dash.position.y + dash.size.y) * 100.0])
	var glass := (canopy.get_node(^"canopy_glass") as MeshInstance3D).material_override as ShaderMaterial
	var alpha: Variant = glass.get_shader_parameter(&"max_alpha") if glass != null else null
	_check(alpha != null and float(alpha) <= 0.08, "the canopy glass stays at alpha ≤ 0.08")
	_rig.call(&"set_first_person", false)
	await _ticks(700)


## Marks the cells covered by a box and returns its screen band as Rect2 in fractions. A box is convex,
## so the 8 projected corners are hulled and scan-filled: a bounding rectangle would count the empty
## wedge beside a raked pillar as covered and put the measurement 3× over.
func _rasterise(points: Array[Vector2], mask: PackedByteArray, cols: int, rows: int) -> Rect2:
	var hull := _hull(points)
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p in hull:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	if hull.size() < 3:
		return Rect2()
	var y0 := clampi(int(floor(min_p.y * rows)), 0, rows - 1)
	var y1 := clampi(int(ceil(max_p.y * rows)), 0, rows)
	for row in range(y0, y1):
		var y := (row + 0.5) / float(rows)
		var lo := INF
		var hi := -INF
		for i in hull.size():
			var a: Vector2 = hull[i]
			var b: Vector2 = hull[(i + 1) % hull.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				var x: float = a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)
				lo = minf(lo, x)
				hi = maxf(hi, x)
		if lo > hi:
			continue
		var x0 := clampi(int(floor(lo * cols)), 0, cols - 1)
		var x1 := clampi(int(ceil(hi * cols)), 0, cols)
		for x in range(x0, x1):
			mask[row * cols + x] = 1
	return Rect2(min_p, max_p - min_p)


## Screen fractions (0..1) of a mesh instance's own corners — the mesh's local box transformed point by
## point. (Transform3D * AABB would return the ENCLOSING box of a rotated strut, three times its width.)
func _screen_points_of(mi: MeshInstance3D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for c in _corners_of(mi.get_aabb()):
		var p := _project_point(mi.global_transform * c)
		if is_nan(p.x):
			return []
		out.append(p)
	return out


## Andrew's monotone chain: the 2D convex hull of the projected corners, counter-clockwise.
func _hull(points: Array[Vector2]) -> Array[Vector2]:
	if points.size() < 3:
		return points
	var pts := points.duplicate()
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return a.x < b.x if not is_equal_approx(a.x, b.x) else a.y < b.y)
	var cross := func(o: Vector2, a: Vector2, b: Vector2) -> float:
		return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
	var lower: Array[Vector2] = []
	for p in pts:
		while lower.size() >= 2 and cross.call(lower[lower.size() - 2], lower[lower.size() - 1], p) <= 0.0:
			lower.pop_back()
		lower.append(p)
	var upper: Array[Vector2] = []
	for i in range(pts.size() - 1, -1, -1):
		var p: Vector2 = pts[i]
		while upper.size() >= 2 and cross.call(upper[upper.size() - 2], upper[upper.size() - 1], p) <= 0.0:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	return lower + upper
