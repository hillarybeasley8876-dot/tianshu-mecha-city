class_name FlowDebugView
extends RefCounted
## Where the scripted run stands and what it sees (flow r3 E2E harness): travel to a map marker, stand
## off a spire, point the camera at a world position and capture the frame. Split out of
## `flow_debug.gd` so the command table there stays readable.
##
## Only `FlowDebug` builds one, and only under `--flow-script`.

## m: how far round a marker `goto` looks for a floor to stand on — an arena marker can sit under a
## container stack, and a mech on top of one is out of the fight it came for.
const SAMPLE_RING := 55.0
## Where the third-person lens sits relative to the mech it is following, for the candidate scoring in
## `approach_spire`: `CameraRig`'s own arm and pivot height (arm 42 m, chest pivot 12.5 m).
const LENS_BACK := 42.0
const LENS_UP := 12.5
## m: a probe this short means the camera is in a wall, not merely close to one (r4 brief item 4).
const PROBE := 14.0
## 0…1: how open a mech's own pocket has to be before a stand counts as standable.
const STAND_OPEN := 0.5
## Candidate firing/filming stands round a spire. The close ranges matter for the rooftop arenas
## (A6 is a Sky Garden deck at +144): at 90 m out every bearing is a 144 m drop, so a search that only
## looked far out reported "the site is enclosed" for a site that is simply in the air.
const STAND_BEARINGS := 8
const STAND_RANGES: Array[float] = [50.0, 75.0, 90.0, 120.0, 165.0]
## m: how far out from the axis the sight-line test aims. The hive's hull is ~24 m across at the
## middle, so this lands on the near face rather than inside the trunk.
const AIM_OUT := 22.0
## The rig follows on a critically damped spring (omega 10): after a teleport of several hundred
## metres it needs most of a second to arrive, and a capture taken before that films the place the
## mech just left. SETTLE_NEAR is how close the lens has to be to call it arrived.
const SETTLE := 2.5
const SETTLE_NEAR := 60.0
## How many times a buried capture lifts the mech before it gives up and files the beat as failed.
const REPAIRS := 3
const REPAIR_LIFT := 26.0

var _host: Node = null


func setup(host: Node) -> void:
	_host = host


## Travel to a named place of the live world (CONTRACTS §7): a `spawn_zone` id (`S4`, `B1`, `K3`…) or
## a marker by name, dropped onto the first floor under it.
func goto_place(id: StringName, lift: float) -> void:
	var at := zone_position(id)
	if at == Vector3.INF:
		at = marker_position(id)
	if at == Vector3.INF:
		push_error("FlowDebug: the world has no zone or marker '%s'" % id)
		return
	# The mech's ORIGIN is its capsule CENTRE, so "2 m above the floor" buried it 5.5 m in the ground:
	# on a tiered arena the solver pushed it out downward and it fell out of the world (r5 — the
	# checkpoint matrix's `goto A1` did exactly this).
	at = lowest_floor(at, lift) + Vector3.UP * (FlowBounds.half_height(Game.player) + 2.0)
	teleport(at)
	print("FLOWDBG goto %s at %.0f,%.0f,%.0f" % [id, at.x, at.y, at.z])


## Stand off a spire so it fills the frame, looking at the middle of its trunk. The stand is chosen,
## not inherited: every bearing × range round the trunk is scored for what the LENS would see (the
## trunk, the pods, and whether that pocket of the world is open at all), because the arena's own
## structure is what put a wall in the r3 captures.
func approach_spire(spire: FlowHiveSpire, distance: float, lift: float) -> void:
	if spire == null or Game.player == null:
		return
	var at := _stand(spire, distance, lift)
	teleport(at)
	var out := at - spire.global_position
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 0.01 else Vector3.FORWARD
	aim_from(_lens_of(at, out), spire.global_position + Vector3.UP * spire.height * 0.45)
	print("FLOWDBG approach spire %s (%s) at %.0f,%.0f,%.0f" % [spire.spire_id, spire.arena_id,
			at.x, at.y, at.z])


## The best-scoring stand round the trunk; the caller's `distance` is the middle of the search. A
## candidate with no floor under it scores nothing at all — the ray-miss fallback used to answer with
## the probe point itself, which is thin air, and the mech then fell through the world for the whole
## beat.
func _stand(spire: FlowHiveSpire, distance: float, lift: float) -> Vector3:
	var best := Vector3.INF
	var best_score := 0.0
	var saw_trunk := false
	var no_floor := 0
	for i in STAND_BEARINGS:
		var out := Vector3(cos(TAU * float(i) / float(STAND_BEARINGS)), 0.0,
				sin(TAU * float(i) / float(STAND_BEARINGS)))
		var trunk := _aim_point(spire, out)
		for scale: float in STAND_RANGES:
			var range_m := distance * scale / 120.0
			var probe := spire.global_position + out * range_m + Vector3.UP * lift
			var floor_at := floor_under(probe, lift + 60.0)
			if floor_at == Vector3.INF:
				no_floor += 1
				continue
			var at := floor_at + Vector3.UP * (FlowBounds.half_height(Game.player) + 2.0)
			var score := _score_stand(at, out, spire, trunk)
			saw_trunk = saw_trunk or sees(_lens_of(at, out), trunk)
			if score > best_score:
				best_score = score
				best = at
	if not saw_trunk:
		# Every bearing is blind: the site is walled in, and no capture from round it will show the
		# hive. Say so — this is the evidence for where the site needs to move (city-layout r6).
		push_warning("FlowDebugView: no stand round %s (%s) can see the trunk — the site is enclosed"
				% [spire.spire_id, spire.arena_id])
	if best == Vector3.INF:
		# Every bearing is a hole or a wall: fall back to where the run already stands.
		push_warning("FlowDebugView: no stand round %s (%d of %d candidates had no floor) — holding"
				% [spire.spire_id, no_floor, STAND_BEARINGS * STAND_RANGES.size()])
		return Game.player.global_position
	print("FLOWDBG stand score %.2f at %.0f,%.0f,%.0f trunk=%s"
			% [best_score, best.x, best.y, best.z, str(saw_trunk)])
	return best


## Stand square on a spire's core, `distance` metres out along the core's own normal at the core's
## height, and point the lens at it. `approach_spire` SEARCHES for a stand, so two runs of the same
## build frame the hive from two different places; this one is pinned, which is what an A/B of the
## torn opening needs (flow-look-r1 polish 1) — the "before" and "after" frames share a stand.
func core_stand(spire: FlowHiveSpire, distance: float) -> void:
	if spire == null or Game.player == null:
		return
	var core := spire.core_world_position()
	var out := spire.core_out()
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 0.01 else Vector3.FORWARD
	var at := core + out * distance
	teleport(at)
	aim_from(_lens_of(at, out), core)
	print("FLOWDBG core stand %s at %.0f,%.0f,%.0f core %.0f,%.0f,%.0f out %.2f,%.2f"
			% [spire.spire_id, at.x, at.y, at.z, core.x, core.y, core.z, out.x, out.z])


## Where the lens would sit for a stand on this bearing.
func _lens_of(at: Vector3, out: Vector3) -> Vector3:
	return at + out * LENS_BACK + Vector3.UP * LENS_UP


## The point on the trunk a stand on `out` is trying to see: the middle of the spire, pushed out to
## the side the stand is on. The axis itself is inside the spire's own hull, so a sight line to it is
## blocked by the spire — scoring against it made every stand round every hive read as enclosed.
func _aim_point(spire: FlowHiveSpire, out: Vector3) -> Vector3:
	return spire.global_position + Vector3.UP * spire.height * 0.45 + out * AIM_OUT


## What this stand is worth: the trunk in sight, the pods in sight, an open pocket for the lens and for
## the mech itself.
func _score_stand(at: Vector3, out: Vector3, spire: FlowHiveSpire, trunk: Vector3) -> float:
	# A mech inside a container stack, or on a ledge it slides off, films nothing worth having.
	if not standable(at):
		return 0.0
	var lens := _lens_of(at, out)
	var score := 0.0
	if sees(lens, trunk):
		score += 1.0
	else:
		# A stand that cannot see the trunk is not a stand for this shot, whatever else it has going.
		return 0.0
	for pod: Vector3 in spire.pod_world_positions():
		if sees(lens, pod):
			score += 0.6
	score += 1.2 * openness(lens)
	return score


## Is there nothing between these two points? (MASK_SIGHT, CONTRACTS §4.)
static func sees(from: Vector3, to: Vector3) -> bool:
	if Game.player == null:
		return false
	var params := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_SIGHT)
	params.collide_with_areas = false
	var space := Game.player.get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return true
	var at: Vector3 = hit["position"]
	return at.distance_to(from) >= from.distance_to(to) - 2.0


## 0…1: how many of six axis probes from a point reach PROBE metres. A lens inside a wall scores 0 —
## the containment test first, because a ray cast from inside a solid hits nothing at all and would
## report a buried camera as the most open place on the map.
static func openness(at: Vector3) -> float:
	if Game.player == null:
		return 1.0
	if inside_solid(at):
		return 0.0
	var clear := 0
	for axis: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN,
			Vector3.BACK, Vector3.FORWARD]:
		if sees(at, at + axis * PROBE):
			clear += 1
	return float(clear) / 6.0


## Is there a collider overlapping this point? (`intersect_point` on MASK_SIGHT, CONTRACTS §4.)
static func inside_solid(at: Vector3) -> bool:
	if Game.player == null:
		return false
	var point := PhysicsPointQueryParameters3D.new()
	point.position = at
	point.collision_mask = Layers.MASK_SIGHT
	point.collide_with_areas = false
	return not Game.player.get_world_3d().direct_space_state.intersect_point(point, 1).is_empty()


## Can a 16 m mech stand here? Nothing overlapping its chest and an open pocket around it — a position
## inside a prop, or on a ledge it slides off, is not a firing position (the r4 log is full of mechs
## placed on a 182 m deck edge that then fell 32 m to the real floor).
static func standable(at: Vector3) -> bool:
	if Game.player == null:
		return false
	var chest := at + Vector3.UP * 8.0
	return openness(chest) >= STAND_OPEN


## The verdict on where the camera actually is, taken at the frame being captured (r4 brief item 4):
## `inside` = a collider overlaps the lens itself, `open` = the six-probe fraction.
static func camera_state() -> Dictionary:
	var rig := Game.camera_rig
	var cam: Camera3D = rig.call(&"camera") as Camera3D if rig != null and rig.has_method(&"camera") \
			else null
	var at := cam.global_position if cam != null else FlowDebugView.eye()
	var open := openness(at)
	var inside := false
	var who := "-"
	if Game.player != null:
		var point := PhysicsPointQueryParameters3D.new()
		point.position = at
		point.collision_mask = Layers.MASK_SIGHT
		point.collide_with_areas = false
		var hits := Game.player.get_world_3d().direct_space_state.intersect_point(point, 4)
		if not hits.is_empty():
			inside = true
			who = String((hits[0] as Dictionary)["collider"].get(&"name"))
	return {"at": at, "open": open, "inside": inside, "who": who}


func teleport(at: Vector3) -> void:
	if Game.player == null:
		push_error("FlowDebug: no player to move")
		return
	Game.player.call(&"debug_teleport", [at.x, at.y, at.z], 0.0)


## The lowest floor of five samples round `at` (centre + a ring at SAMPLE_RING), or `at` itself when
## none of the rays finds ground.
func lowest_floor(at: Vector3, lift: float) -> Vector3:
	var best := floor_under(at + Vector3.UP * lift, lift + 90.0)
	for i in 4:
		var a := TAU * float(i) / 4.0
		var probe := at + Vector3(cos(a), 0.0, sin(a)) * SAMPLE_RING
		var hit := floor_under(probe + Vector3.UP * lift, lift + 90.0)
		if hit != Vector3.INF and (best == Vector3.INF or hit.y < best.y):
			best = hit
	return best if best != Vector3.INF else at


## The first solid surface under `from`, or `Vector3.INF` when the ray finds nothing — the caller has
## to decide what thin air means, and "the probe point itself" is never the answer.
func floor_under(from: Vector3, reach: float) -> Vector3:
	return ray(from, from + Vector3.DOWN * reach)


## First scenery hit along a segment (MASK_SIGHT, CONTRACTS §4), or `Vector3.INF`.
func ray(from: Vector3, to: Vector3) -> Vector3:
	if Game.player == null:
		return Vector3.INF
	var params := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_SIGHT)
	params.collide_with_areas = false
	var hit := Game.player.get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return Vector3.INF
	var at: Vector3 = hit["position"]
	return at


## Point the rig at a world position. Yaw is measured against where the camera is actually looking, so
## this works whatever the mech's own facing is.
func look_at(want: Vector3) -> void:
	aim_from(eye(), want)


## `look_at` measured from the wrong place after a teleport: the rig follows on a spring, so in the
## frame the mech is moved the lens is still hundreds of metres away and the pitch came out of that
## stale vector — the r5 look captures framed the sky above a hive 35 m below the crosshair. A caller
## that knows where the lens is going to be passes it in.
func aim_from(from: Vector3, want: Vector3) -> void:
	var rig := Game.camera_rig
	if rig == null or not rig.has_method(&"set_look") or not rig.has_method(&"look_angles"):
		return
	var to := want - from
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.01:
		return
	var angles: Vector2 = rig.call(&"look_angles")
	var yaw := angles.x
	if rig.has_method(&"look_dir"):
		var current: Vector3 = rig.call(&"look_dir")
		current.y = 0.0
		if current.length_squared() > 0.01:
			yaw += rad_to_deg(current.normalized().signed_angle_to(flat.normalized(), Vector3.UP))
	rig.call(&"set_look", yaw, rad_to_deg(atan2(to.y, flat.length())))


## Where the shots come from: the camera, because that is what the crosshair ray starts at — a mech
## with its nose against a wall has line of sight from its chest and no shot at all.
static func eye() -> Vector3:
	var rig := Game.camera_rig
	if rig != null and rig.has_method(&"camera"):
		var cam := rig.call(&"camera") as Camera3D
		if cam != null:
			return cam.global_position
	return Game.player.global_position if Game.player != null else Vector3.ZERO


## True from the moment `shot()` is asked for until the .jpg is on disk. `FlowDebug` blocks the script
## on it (r5 brief item 8): the script used to move on after a fixed 0.9 s hold while the capture was
## still waiting for the rig, so several beats fired together and saved the same picture —
## `e_spire0_collapse` and `f_game_over` were byte-identical.
var saving: bool = false


## Capture the frame for the evidence set → `captures/e2e_<name>.jpg`.
func shot(shot_name: String) -> void:
	var dir := Game.flag("outdir", ProjectSettings.globalize_path("res://").path_join("../captures"))
	DirAccess.make_dir_recursive_absolute(dir)
	saving = true
	_capture.call_deferred(dir.path_join("e2e_%s.jpg" % shot_name), shot_name)


## The capture is checked against the world at the frame it saves (r4 brief item 4). A lens inside a
## wall films a dark rectangle, which is worse than no evidence: the beat is filed as `buried`, the
## mech is lifted out of the pocket and the frame taken again, and either way the verdict goes in the
## log and in the host's tally. The wait first lets the rig arrive — after a teleport of several
## hundred metres its follow spring is still crossing the map, and the frame would show the place the
## run just left.
func _capture(path: String, shot_name: String) -> void:
	if _host == null or not is_instance_valid(_host):
		saving = false
		return
	await _settle()
	var verdict := "ok"
	for attempt in REPAIRS + 1:
		await RenderingServer.frame_post_draw
		var cam := camera_state()
		if not bool(cam["inside"]) and float(cam["open"]) > 0.0:
			_save(path, shot_name, verdict, cam)
			saving = false
			return
		var at: Vector3 = cam["at"]
		print("E2ECAM %s buried in %s at %.0f,%.0f,%.0f (open %.2f) — lifting the mech"
				% [shot_name, cam["who"], at.x, at.y, at.z, float(cam["open"])])
		verdict = "lifted"
		await _lift()
	await RenderingServer.frame_post_draw
	_save(path, shot_name, "buried", camera_state())
	saving = false


## Wait for the rig's follow spring to arrive at the mech, up to SETTLE seconds. A CINEMATIC owns the
## lens and never comes within SETTLE_NEAR of the hero, so waiting for the spring there burned the
## whole SETTLE on every beat of the drop-in, the catapult and the collapse (r5 brief item 8): the
## script moved on and the frames landed together. In a cinematic one frame is the settle.
func _settle() -> void:
	if Game.player == null or _in_cinematic():
		return
	var waited := 0.0
	while waited < SETTLE:
		var cam := eye()
		if cam.distance_to(Game.player.global_position) < SETTLE_NEAR:
			return
		await _host.get_tree().process_frame
		waited += _host.get_tree().root.get_process_delta_time()
	print("FLOWDBG settle gave up after %.1f s" % waited)


static func _in_cinematic() -> bool:
	var rig := Game.camera_rig
	return rig != null and is_instance_valid(rig) and rig.has_method(&"is_cinematic") \
			and bool(rig.call(&"is_cinematic"))


func _save(path: String, shot_name: String, verdict: String, cam: Dictionary) -> void:
	_host.get_viewport().get_texture().get_image().save_jpg(path, 0.85)
	var at: Vector3 = cam["at"]
	var subject := subject_in_frame()
	print("E2ESHOT %s -> %s (camera %s at %.0f,%.0f,%.0f open %.2f inside %s subject %s)"
			% [shot_name, path, verdict, at.x, at.y, at.z, float(cam["open"]), cam["who"], subject])
	_host.call(&"note_camera", shot_name, verdict, at, float(cam["open"]), String(cam["who"]),
			FileAccess.get_md5(path), subject)


## What the saved frame actually shows (r5 brief item 8): the hero, and how many lock points are in
## the frustum. "camera ok" only ever said the lens was not inside a wall — it said nothing about
## whether the beat's subject was in the picture, which is how `e2e_a_dropin` came back as a frame
## taken after the landing and `e2e_n_crown_boss` as the inside of the catapult beam.
static func subject_in_frame() -> String:
	var rig := Game.camera_rig
	var cam := rig.call(&"camera") as Camera3D if rig != null and rig.has_method(&"camera") else null
	if cam == null:
		return "no-camera"
	var out := ""
	var player := Game.player as Node3D
	if player != null and cam.is_position_in_frustum(player.global_position + Vector3.UP * 4.0):
		out = "hero"
	var targets := 0
	for node in cam.get_tree().get_nodes_in_group(&"targetable"):
		var t := node as Node3D
		if t != null and cam.is_position_in_frustum(t.global_position):
			targets += 1
	if targets > 0:
		out = out + ("+targets%d" % targets) if out != "" else "targets%d" % targets
	return out if out != "" else "NONE"


## Put air under the mech: the rig follows it, so the lens comes out of the wall with it. Two frames,
## because the rig eases toward the mech rather than snapping to it.
func _lift() -> void:
	if Game.player == null:
		return
	var at := Game.player.global_position + Vector3.UP * REPAIR_LIFT
	Game.player.call(&"debug_teleport", [at.x, at.y, at.z], 0.0)
	await _host.get_tree().process_frame
	await _host.get_tree().process_frame


static func zone_position(id: StringName) -> Vector3:
	for node in FlowWorld.world_group(&"spawn_zone"):
		if StringName(node.get_meta(&"zone_id", node.name)) == id:
			return node.global_position
	return Vector3.INF


static func marker_position(id: StringName) -> Vector3:
	var node := FlowWorld.world_marker(id)
	return node.global_position if node != null else Vector3.INF
