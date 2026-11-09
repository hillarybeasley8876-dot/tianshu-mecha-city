extends Node
## hero-v3 r9 item 2 + r10 gate: every plume starts ON its nozzle mouth and runs ALONG its exhaust
## axis, and it LOOKS like a jet rather than the flat white slab r9 drew.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_thruster.gd
##
## The geometry half (r9, unchanged): the plume mesh's own BASE RING -- the vertices at the cone's -Y
## end, which is the end the shader calls `along = 0` -- transformed to world space and compared with
## the nozzle mouth the mesh measured (`Hero3Nozzle`). Nothing here trusts the rig's arithmetic: it
## reads the vertices.
##
## The scale half (r10 item 2): the plume's real world LENGTH and WIDTH, measured off those same
## transformed vertices, have to grow monotonically with the throttle across the states the game
## actually drives.
##
## The look half (r10 item 1) is `hero3_plume_check.gd`: the shader compiles, every uniform the profile
## writes reaches it, the core alpha at the nozzle is over 0.8, the tip is under 0.1, mid-plume is the
## accent hue, the radial falloff is soft, the white is a core and the shock diamonds band and move.
##
## The states are the ones the lead named: at rest, in a walk, in a boost, in a hover, and in flight
## at the 50 m/s cruise and the 84 m/s assault. Flight is driven through `set_thrust_dir` with the
## directions `Hero3Flight` produces, because that is the only thing flight changes about a plume.

const PlumeCheck := preload("res://player/model/hero3/tests/hero3_plume_check.gd")

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const GATE := 0.30          ## metres from the mouth the flame's root may sit
const AXIS_GATE := 12.0     ## degrees the plume may stray from its exhaust axis
const DT := 1.0 / 120.0

var failures: Array[String] = []
## One `{level, length, width}` per state, for the monotonicity gate.
var extents: Array[Dictionary] = []
var model: Node3D
var rig: Hero3Rig
var skeleton: Skeleton3D


func _ready() -> void:
	model = (load(SCENE) as PackedScene).instantiate()
	add_child(model)
	rig = model.rig
	skeleton = model.skeleton
	var nozzles := rig.nozzles()
	_ok(nozzles.size() == 2, "two nozzles measured off the mesh", "%d found" % nozzles.size())
	for n: Dictionary in nozzles:
		_ok(String(n["bone"]) == "BackFrame", "nozzle rides the back frame", String(n["bone"]))
	_no_calf()
	# Without this the geometry gate passes VACUOUSLY when the plume material fails to load: the rig
	# returns early, `thruster_nodes()` is empty, and `mini(nozzles, flames)` is 0, so every loop in
	# `_state` is skipped and `worst` stays 0.000 -- a perfect score for a mech with no flame at all.
	_ok(rig.thruster_nodes().size() == nozzles.size(), "every measured nozzle has a plume",
			"%d nozzles, %d plumes" % [nozzles.size(), rig.thruster_nodes().size()])
	for row: Array in states:
		await _state(String(row[0]), float(row[1]), row[2] as Vector3, float(row[3]))
	_scale()
	for message: String in PlumeCheck.run():
		failures.append(message)
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


## label, throttle, world thrust direction (ZERO = leave the plumes on their own bones), walk speed.
## The flight directions are the ones `Hero3Flight` produces at the 26.7 deg and 38.0 deg leans the r8
## drive measured.
var states: Array = [
	["rest", 0.0, Vector3.ZERO, 0.0],
	["walk", 0.0, Vector3.ZERO, 9.0],
	["boost", 0.8, Vector3.ZERO, 42.0],
	["hover", 0.45, Vector3(0.0, -1.0, 0.0), 0.0],
	["flight 50 m/s", 0.85, Vector3(0.0, 0.12, 1.0).normalized(), 50.0],
	["flight 84 m/s", 1.0, Vector3(0.0, 0.28, 1.0).normalized(), 84.0],
]


## The mesh has no calf port (measured by `probe_nozzle.gd`: the rearmost surface of a calf is the
## calf), so a plume on a leg bone is a floating flame by definition.
func _no_calf() -> void:
	var bad := 0
	for flame in rig.thruster_nodes():
		var attach := flame.get_parent() as BoneAttachment3D
		if attach == null:
			continue
		var bone := skeleton.get_bone_name(attach.bone_idx)
		if bone.contains("Calf") or bone.contains("Thigh") or bone.contains("Foot"):
			bad += 1
	_ok(bad == 0, "no plume hangs off a leg bone", "%d do" % bad)


func _state(label: String, level: float, thrust: Vector3, speed: float) -> void:
	model.set_locomotion(&"run" if speed > 12.0 else (&"walk" if speed > 0.6 else &"idle"),
			speed, Vector2(0.0, -1.0))
	model.gait.reset()
	for i in 90:
		model.gait.update(DT)
	rig.set_thrusters(level)
	rig.set_thrust_dir(thrust)
	rig.update(DT)
	var nozzles := rig.nozzles()
	var flames := rig.thruster_nodes()
	var worst := 0.0
	var worst_axis := 0.0
	var longest := 0.0
	var widest := 0.0
	for i in mini(nozzles.size(), flames.size()):
		var mouth := _mouth_world(nozzles[i])
		var base := _base_ring(flames[i])
		worst = maxf(worst, base["centre"].distance_to(mouth))
		# with a commanded thrust the plume deliberately LEAVES the nozzle axis (that is what hovering
		# on downward thrust means), so the axis gate compares it with what was commanded
		var want := _axis_world(nozzles[i]) if thrust == Vector3.ZERO else thrust
		worst_axis = maxf(worst_axis, rad_to_deg(base["axis"].angle_to(want)))
		var extent := _plume_extent(flames[i], mouth, base["axis"])
		longest = maxf(longest, float(extent["length"]))
		widest = maxf(widest, float(extent["width"]))
	extents.append({"label": label, "level": level, "length": longest, "width": widest})
	print("THRUST %-14s throttle %.2f  root %.3f m off the mouth (gate %.2f)  axis off by %.1f deg  flame %.2f m long, %.2f m wide"
			% [label, level, worst, GATE, worst_axis, longest, widest])
	if worst > GATE:
		_fail("%s: the plume's root sits %.3f m from its nozzle mouth, gate %.2f" % [label, worst, GATE])
	if worst_axis > AXIS_GATE:
		_fail("%s: the plume runs %.1f deg off its exhaust axis, gate %.0f"
				% [label, worst_axis, AXIS_GATE])
	await get_tree().process_frame


## The measured mouth in WORLD space: the bone's current global pose times the mouth in its own frame.
func _mouth_world(nozzle: Dictionary) -> Vector3:
	var bone := skeleton.find_bone(String(nozzle["bone"]))
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone) * (nozzle["at"] as Vector3)


func _axis_world(nozzle: Dictionary) -> Vector3:
	var bone := skeleton.find_bone(String(nozzle["bone"]))
	return (skeleton.global_transform.basis * skeleton.get_bone_global_pose(bone).basis \
			* (nozzle["axis"] as Vector3)).normalized()


## The plume cone's own base ring: every vertex within 5 % of the cone's -Y end, in world space, with
## the direction the cone runs.
func _base_ring(flame: MeshInstance3D) -> Dictionary:
	var arrays := flame.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := -INF
	for v in verts:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	var centre := Vector3.ZERO
	var n := 0
	for v in verts:
		if v.y > lo + (hi - lo) * 0.05:
			continue
		centre += flame.global_transform * v
		n += 1
	centre /= maxf(float(n), 1.0)
	var axis := (flame.global_transform.basis * Vector3.UP).normalized()
	return {"centre": centre, "axis": axis, "n": n}


## The plume's real world LENGTH along its own axis and WIDTH across it, measured off the same
## transformed vertices -- so the length gate reads the mesh the GPU will draw, not `Hero3Plume`'s
## arithmetic about it (lead r10 item 2).
func _plume_extent(flame: MeshInstance3D, mouth: Vector3, axis: Vector3) -> Dictionary:
	var arrays := flame.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var longest := 0.0
	var widest := 0.0
	for v in verts:
		var d := (flame.global_transform * v) - mouth
		var along := d.dot(axis)
		longest = maxf(longest, along)
		widest = maxf(widest, (d - axis * along).length())
	return {"length": longest, "width": widest}


## r10 item 2: the flame grows monotonically with the throttle across the states the game drives --
## a grounded mech's ember, a hover's medium plume, an assault's long one. Sorted by throttle first,
## because the states are listed in the order the lead named them, not in throttle order.
func _scale() -> void:
	extents.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["level"]) < float(b["level"]))
	var rows: Array[String] = []
	for row: Dictionary in extents:
		rows.append("%.2f->%.2f m x %.2f m" % [float(row["level"]), float(row["length"]),
				float(row["width"])])
	print("PLUME  length/width by throttle: %s" % ", ".join(rows))
	_ok(_grows("length"), "scale.length_grows_with_thrust",
			"; ".join(rows))
	_ok(_grows("width"), "scale.width_grows_with_thrust", "; ".join(rows))


## Non-decreasing in the throttle across the sorted states, with a real spread between the ground and
## the assault -- a flame that only ever gets BRIGHTER would satisfy monotonicity and still read as
## one slab.
func _grows(key: String) -> bool:
	var last := -INF
	var lo := INF
	var hi := -INF
	for row: Dictionary in extents:
		var v := float(row[key])
		if v < last - 0.001:
			return false
		last = v
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi > lo * 1.5


func _ok(cond: bool, label: String, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if cond else "FAIL", label, ("  [" + detail + "]") if detail != "" else ""])
	if not cond:
		failures.append(label)


func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL %s" % message)
