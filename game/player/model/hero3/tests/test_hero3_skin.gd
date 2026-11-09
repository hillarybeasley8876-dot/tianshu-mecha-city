extends Node
## hero-v3 gate A2 + A3 + A4 (lead r3): what the SKINNED mesh does, not what the targets say.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_skin.gd
##
##   A2  no skinned foot or toe vertex sinks more than 0.05 m below the rest-pose baseline
##   A3  the left and right leg meshes never share a 0.30 m voxel
##   A4  in the PELVIS frame each ankle stays on its own side, >= 1.8 m apart, in all 8 directions
##
## The CPU skinning here is the same measure `tmp/lead/probe/probe_skin.gd` uses. A4 is measured in
## the pelvis frame on purpose: on a strafe the lower body yaws toward the travel direction, so the
## ankles cross in MODEL x while staying 4 m apart across the stance axis -- which is the whole point
## of the yaw, and the reason the lead's own model-x probe still prints a negative number.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 120.0
const CELL := 0.30
const SINK_GATE := 0.05
const SEP_GATE := 1.8
const VSTRIDE := 3           ## every third vertex: the sole has thousands, only extremes matter
const TICK_STRIDE := 6
const TICKS := 420
const WARM := 120
## label, state, speed, stick. The eight directions are walked and run.
const DIRECTIONS: Array = [
	["forward", Vector2(0.0, -1.0)], ["forward-right", Vector2(0.707, -0.707)],
	["right", Vector2(1.0, 0.0)], ["back-right", Vector2(0.707, 0.707)],
	["back", Vector2(0.0, 1.0)], ["back-left", Vector2(-0.707, 0.707)],
	["left", Vector2(-1.0, 0.0)], ["forward-left", Vector2(-0.707, -0.707)],
]

var failures: Array[String] = []
var _verts: Array = []
var _baseline := 0.0


func _ready() -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	_collect(model, model.skeleton)
	# the exported toe plates already sit 0.10 m below y = 0, so every sink is measured against the
	# rest pose rather than against zero
	_baseline = float(_sample(model.skeleton)[0])
	print("SKIN rest pose deepest foot/toe vertex %.3f m below ground (%d verts sampled)"
			% [_baseline, _verts.size()])
	for spec in [["walk", &"walk", 9.0, Vector2(0.0, -1.0)], ["run", &"run", 16.0, Vector2(0.0, -1.0)],
			["strafe", &"walk", 9.0, Vector2(-1.0, 0.0)], ["back", &"walk", 9.0, Vector2(0.0, 1.0)],
			["turn", &"walk", 0.0, Vector2.ZERO]]:
		await _skin_pass(model, spec)
	for speed in [9.0, 16.0]:
		for row in DIRECTIONS:
			await _separation_pass(model, String(row[0]), speed, row[1])
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


## One locomotion pass, CPU-skinning the leg vertices every TICK_STRIDE ticks.
func _skin_pass(model: Node3D, spec: Array) -> void:
	var gait: Hero3Gait = model.gait
	var skel: Skeleton3D = model.skeleton
	var turning := String(spec[0]) == "turn"
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	model.set_locomotion(spec[1], float(spec[2]), spec[3])
	gait.reset()
	var dir := Vector3((spec[3] as Vector2).x, 0.0, (spec[3] as Vector2).y).normalized()
	var worst := 0.0
	var worst_at := ""
	var overlap := 0
	var overlap_at := ""
	for tick in TICKS:
		if turning:
			model.rotate_y(deg_to_rad(55.0) * DT)
		else:
			model.position += dir * float(spec[2]) * DT
		gait.update(DT)
		if tick < WARM or tick % TICK_STRIDE != 0:
			continue
		var result := _sample(skel)
		var sink: float = result[0] - _baseline
		if sink > worst:
			worst = sink
			worst_at = "tick %d phase %.2f" % [tick, float(gait.report()["phase"])]
		if int(result[1]) > overlap:
			overlap = int(result[1])
			overlap_at = "tick %d phase %.2f %s" % [tick, float(gait.report()["phase"]), result[2]]
	print("SKIN %-6s deepest below baseline %.3f m (gate %.2f, %s)  max L/R shared voxels %d (%s)"
			% [spec[0], worst, SINK_GATE, worst_at, overlap, overlap_at])
	if worst > SINK_GATE:
		_fail("%s: a skinned foot vertex sank %.3f m below the rest baseline, gate %.2f (%s)"
				% [spec[0], worst, SINK_GATE, worst_at])
	if overlap > 0:
		_fail("%s: the leg meshes share %d voxel hits (%s)" % [spec[0], overlap, overlap_at])
	await get_tree().process_frame


## The deepest foot/toe vertex below the ground this tick, and how many right-leg vertices land in a
## voxel a left-leg vertex also occupies. Two passes, because the mesh rows are not sorted by side.
func _sample(skel: Skeleton3D) -> Array:
	var xf := skel.global_transform
	var ground := skel.global_position.y
	var cache := {}
	var left := {}
	var shared := 0
	var low := INF
	var pairs := {}
	for side in ["L", "R"]:
		for row in _verts:
			if row[3] != side:
				continue
			var mi: MeshInstance3D = row[4]
			var binds: PackedInt32Array = row[1]
			var wts: PackedFloat32Array = row[2]
			var p := Vector3.ZERO
			for j in wts.size():
				var key := Vector2i(mi.get_instance_id() % 100000, binds[j * 2 + 1])
				if not cache.has(key):
					cache[key] = skel.get_bone_global_pose(binds[j * 2]) \
							* mi.skin.get_bind_pose(binds[j * 2 + 1])
				p += (cache[key] as Transform3D) * (row[0] as Vector3) * wts[j]
			var w := xf * p
			low = minf(low, w.y)
			var cell := Vector3i(floori(w.x / CELL), floori(w.y / CELL), floori(w.z / CELL))
			if side == "L":
				left[cell] = row[5]
			elif left.has(cell):
				shared += 1
				var pair := "%s/%s" % [left[cell], row[5]]
				pairs[pair] = int(pairs.get(pair, 0)) + 1
	var worst_pair := ""
	var worst_count := 0
	for key: String in pairs:
		if int(pairs[key]) > worst_count:
			worst_count = int(pairs[key])
			worst_pair = "%s x%d" % [key, worst_count]
	return [ground - low, shared, worst_pair]


## A4: run one direction and measure the two ankles in the PELVIS frame -- along the pelvis' own
## stance axis, which is what the lower-body yaw rotates. No skinning needed, so all 8 directions at
## both speeds are cheap.
func _separation_pass(model: Node3D, label: String, speed: float, input: Vector2) -> void:
	var gait: Hero3Gait = model.gait
	var skel: Skeleton3D = model.skeleton
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	model.set_locomotion(&"run" if speed > 12.0 else &"walk", speed, input)
	gait.reset()
	var pelvis := skel.find_bone("Pelvis")
	var lf := skel.find_bone("L_Foot")
	var rf := skel.find_bone("R_Foot")
	var dir := Vector3(input.x, 0.0, input.y).normalized()
	var worst := INF
	var worst_at := ""
	for tick in TICKS:
		model.position += dir * speed * DT
		gait.update(DT)
		if tick < WARM or tick % 2 != 0:
			continue
		var pose := skel.get_bone_global_pose(pelvis)
		var axis := (skel.global_transform.basis * pose.basis.x)
		axis.y = 0.0
		axis = axis.normalized()
		var origin := skel.global_transform * pose.origin
		var la := (skel.global_transform * skel.get_bone_global_pose(lf).origin) - origin
		var ra := (skel.global_transform * skel.get_bone_global_pose(rf).origin) - origin
		var sep := ra.dot(axis) - la.dot(axis)
		if sep < worst:
			worst = sep
			worst_at = "tick %d yaw %.0f deg" % [tick, rad_to_deg(gait.body_yaw())]
	print("STANCE %-13s %2.0f m/s  min pelvis-frame ankle separation %.2f m (gate %.1f, %s)"
			% [label, speed, worst, SEP_GATE, worst_at])
	if worst < SEP_GATE:
		_fail("%s at %.0f m/s: the ankles close to %.2f m in the pelvis frame, gate %.1f (%s)"
				% [label, speed, worst, SEP_GATE, worst_at])
	await get_tree().process_frame


## Every leg vertex this gate skins, with the bind indices it needs. Only Foot, Toe, Calf and Thigh
## pieces: the arms and the back frame cannot touch the floor.
func _collect(model: Node3D, skel: Skeleton3D) -> void:
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		var bind_bone := PackedInt32Array()
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			if bone < 0:
				bone = skel.find_bone(String(mi.skin.get_bind_name(b)))
			bind_bone.append(bone)
		for s in mi.mesh.get_surface_count():
			_collect_surface(mi, s, bind_bone, skel)


func _collect_surface(mi: MeshInstance3D, surface: int, bind_bone: PackedInt32Array,
		skel: Skeleton3D) -> void:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bones == null or verts.is_empty():
		return
	var per := int(bones.size() / verts.size())
	for i in range(0, verts.size(), VSTRIDE):
		var best := -1.0
		var side := ""
		var binds := PackedInt32Array()
		var wts := PackedFloat32Array()
		for j in per:
			var w := weights[i * per + j]
			if w <= 0.0:
				continue
			var b := int(bones[i * per + j])
			binds.append(bind_bone[b])
			binds.append(b)
			wts.append(w)
			if w > best:
				best = w
				side = skel.get_bone_name(bind_bone[b])
		if side.begins_with("L_") or side.begins_with("R_"):
			if side.contains("Thigh") or side.contains("Calf") or side.contains("Foot") \
					or side.contains("Toe"):
				_verts.append([verts[i], binds, wts, side.substr(0, 1), mi, side.substr(2)])


func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL %s" % message)



