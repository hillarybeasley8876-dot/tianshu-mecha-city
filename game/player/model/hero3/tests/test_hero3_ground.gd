extends Node
## hero-v3 gate for lead r4 item 3: a ground clip keeps the mech ON the floor.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_ground.gd
##
## The FULL clips used to fold the thighs and calves with FK keys while the pelvis stayed at standing
## height, so both feet left the ground: death hung in the air with its lower ankle at 5.6 m. They now
## key the ROOT and the FEET and `Hero3LegIk` solves the legs, so this asserts the result on the
## SKINNED MESH, not on the targets:
##
##   * in every frame of every ground clip the lowest skinned vertex is within 0.15 m of where it
##     sits at rest, and never more than 0.05 m below it
##   * the pelvis numbers the lead set: death down 4 m to one knee and ending at 3 m or less,
##     hit_knockdown down 3 m inside 8 frames and back to standing by the end, hit_heavy 0.8-1.2 m,
##     hit_light 0.3-0.5 m
##
## Airborne clips are exempt -- a jump is supposed to leave the floor.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 60.0
const VSTRIDE := 12
const SAMPLE_EVERY := 3
const SINK_GATE := 0.05
const TOUCH_GATE := 0.15
const BLEND := 0.06
## The clips that are allowed to leave the ground.
const AIR: Array[StringName] = [&"jump", &"fall", &"hover", &"fly", &"plunge_dive",
		&"air_l1", &"air_l2"]
## clip -> what its pelvis has to do. `drop` is metres below the rest hip (8.60 m).
const PELVIS: Dictionary = {
	&"death": {"drop_min": 4.0, "end_max": 3.0},
	&"hit_knockdown": {"drop_min": 3.0, "by_frame": 8, "end_min": 7.5},
	&"hit_heavy": {"drop_min": 0.8, "drop_max": 1.2},
	&"hit_light": {"drop_min": 0.3, "drop_max": 0.5},
}

var failures: Array[String] = []
var _verts: Array = []
var _rest_low: float = 0.0
var _rest_hip: float = 0.0


func _ready() -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	var skel: Skeleton3D = model.skeleton
	var gait: Hero3Gait = model.gait
	var clips: Hero3ClipPlayer = model.clips
	_collect(model, skel)
	_rest_low = _low(skel)
	_rest_hip = skel.get_bone_global_rest(skel.find_bone("Pelvis")).origin.y
	print("GROUND rest lowest vertex %.3f m, rest hip %.2f m | %d verts sampled"
			% [_rest_low, _rest_hip, _verts.size()])
	var ids: Array = clips.clips.keys()
	ids.sort()
	for id: StringName in ids:
		if AIR.has(id):
			continue
		await _clip(model, id)
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for line in failures:
			print("FAIL %s" % line)
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


## One clip, played alone at idle with the blend the game uses.
func _clip(model: Node3D, id: StringName) -> void:
	var gait: Hero3Gait = model.gait
	var clips: Hero3ClipPlayer = model.clips
	var skel: Skeleton3D = model.skeleton
	var pelvis := skel.find_bone("Pelvis")
	model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	gait.reset()
	model.stop_action()
	for i in 60:
		_tick(gait, clips)
	var frames := int(float(clips.clips[id]["frames"]))
	model.play_action(id, BLEND)
	var worst_sink := -INF
	var worst_float := -INF
	var worst_at := 0
	var drop := 0.0
	var drop_by := 0.0
	var drop_end := 0.0
	var at_frame := int(PELVIS.get(id, {}).get("by_frame", 0))
	for f in frames + 8:
		_tick(gait, clips)
		var hip: float = skel.get_bone_global_pose(pelvis).origin.y
		drop = maxf(drop, _rest_hip - hip)
		if f == at_frame:
			drop_by = _rest_hip - hip
		if f == frames - 1:
			drop_end = _rest_hip - hip
		if f % SAMPLE_EVERY != 0:
			continue
		var low := _low(skel) - _rest_low
		if low < -SINK_GATE:
			worst_sink = minf(worst_sink, low)
			worst_at = f
		if low > TOUCH_GATE:
			worst_float = maxf(worst_float, low)
			worst_at = f
	_report(id, frames, worst_sink, worst_float, worst_at, drop, drop_by, drop_end)
	await get_tree().process_frame


func _report(id: StringName, frames: int, sink: float, float_off: float, at: int,
		drop: float, drop_by: float, drop_end: float) -> void:
	var line := "GROUND %-15s %3d f | pelvis drop %.2f m" % [id, frames, drop]
	var spec: Dictionary = PELVIS.get(id, {})
	if not spec.is_empty():
		line += " (%.2f m at f%d, %.2f m at the end)" % [drop_by, int(spec.get("by_frame", 0)), drop_end]
	if sink > -INF:
		line += " | SANK %.3f m at f%d" % [sink, at]
		_fail("%s put a skinned vertex %.3f m below the rest baseline at f%d, gate %.2f"
				% [id, -sink, at, SINK_GATE])
	if float_off > -INF:
		line += " | LEFT THE FLOOR %.3f m at f%d" % [float_off, at]
		_fail("%s left the lowest skinned vertex %.3f m above the floor at f%d, gate %.2f"
				% [id, float_off, at, TOUCH_GATE])
	print(line)
	if spec.is_empty():
		return
	if drop < float(spec["drop_min"]):
		_fail("%s only dropped the pelvis %.2f m, gate %.2f" % [id, drop, float(spec["drop_min"])])
	if spec.has("drop_max") and drop > float(spec["drop_max"]):
		_fail("%s dropped the pelvis %.2f m, gate at most %.2f" % [id, drop, float(spec["drop_max"])])
	if spec.has("by_frame") and drop_by < float(spec["drop_min"]):
		_fail("%s had only dropped %.2f m by frame %d, gate %.2f"
				% [id, drop_by, int(spec["by_frame"]), float(spec["drop_min"])])
	if spec.has("end_max") and _rest_hip - drop_end > float(spec["end_max"]):
		_fail("%s ends with the pelvis at %.2f m, gate at most %.2f"
				% [id, _rest_hip - drop_end, float(spec["end_max"])])
	if spec.has("end_min") and _rest_hip - drop_end < float(spec["end_min"]):
		_fail("%s ends with the pelvis at %.2f m, it has to be standing again by %.2f"
				% [id, _rest_hip - drop_end, float(spec["end_min"])])


func _tick(gait: Hero3Gait, clips: Hero3ClipPlayer) -> void:
	clips.update(DT)
	gait.update(DT)
	clips.apply()


func _fail(line: String) -> void:
	failures.append(line)


## The lowest skinned vertex of the WHOLE mech, in metres above the ground plane. Every piece is
## collected, not just the feet: a death ends with the mech lying down, and the plate that touches the
## floor then is a back or a shoulder.
func _low(skel: Skeleton3D) -> float:
	var xf := skel.global_transform
	var cache := {}
	var low := INF
	for row in _verts:
		var mi: MeshInstance3D = row[3]
		var binds: PackedInt32Array = row[1]
		var wts: PackedFloat32Array = row[2]
		var p := Vector3.ZERO
		for j in wts.size():
			var key := Vector2i(mi.get_instance_id() % 100000, binds[j * 2 + 1])
			if not cache.has(key):
				cache[key] = skel.get_bone_global_pose(binds[j * 2]) \
						* mi.skin.get_bind_pose(binds[j * 2 + 1])
			p += (cache[key] as Transform3D) * (row[0] as Vector3) * wts[j]
		low = minf(low, (xf * p).y)
	return low - skel.global_position.y


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
			_collect_surface(mi, s, bind_bone)


func _collect_surface(mi: MeshInstance3D, surface: int, bind_bone: PackedInt32Array) -> void:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bones == null or verts.is_empty():
		return
	var per := int(bones.size() / verts.size())
	for i in range(0, verts.size(), VSTRIDE):
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
		if not wts.is_empty():
			_verts.append([verts[i], binds, wts, mi])
