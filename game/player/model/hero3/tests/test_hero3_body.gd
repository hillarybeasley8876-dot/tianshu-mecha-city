extends Node
## hero-v3 gate A5 + A6 (lead r3): the waist never splits open, and the legs hold an air pose.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_body.gd
##
##   A5  the Pelvis-weighted and Spine01-weighted plates overlap by >= 0.2 m in every frame
##   A6  in the air the ankle-to-hip distance is <= 5.8 m and never more than 3 m behind the hip
##
## A5 is measured the way `tmp/lead/probe/probe_waist.gd` measures it: CPU-skin the plates that hang
## off each bone and compare their spans. The first version translated Spine01 up by 45 % of the
## pelvis drop to keep the head level, which opened a 0.46 m gap at the deepest drop.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 120.0
const WAIST_GATE := 0.20
const AIR_REACH_GATE := 5.80
const AIR_BEHIND_GATE := 3.0
const AIR_STATES: Array[StringName] = [&"hover", &"fly", &"jump", &"fall", &"plunge_dive"]

var failures: Array[String] = []
var _plates: Dictionary = {}
## Every model this test spawns, kept alive until the end: `_plates` caches the skin resources of the
## FIRST instance, and freeing it turns the second pass's spans into zeroes.
var _keep: Array[Node3D] = []


func _ready() -> void:
	for spec in [["walk", &"walk", 9.0], ["run", &"run", 16.0]]:
		await _waist(spec)
	for state in AIR_STATES:
		await _air(state)
	for node in _keep:
		node.queue_free()
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


## The overlap of the two waist plates at the deepest pelvis drop of a walk or a run.
func _waist(spec: Array) -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	var gait: Hero3Gait = model.gait
	var skel: Skeleton3D = model.skeleton
	if _plates.is_empty():
		_collect(model, skel)
	model.set_locomotion(spec[1], float(spec[2]), Vector2(0.0, -1.0))
	gait.reset()
	var worst := INF
	var worst_at := 0.0
	for tick in 480:
		model.position += Vector3(0.0, 0.0, -float(spec[2]) * DT)
		gait.update(DT)
		if tick < 120 or tick % 3 != 0:
			continue
		var pelvis := _span("Pelvis", skel)
		var spine := _span("Spine01", skel)
		var overlap := pelvis.y - spine.x
		if overlap < worst:
			worst = overlap
			worst_at = float(gait.report()["drop"])
	print("WAIST %-4s  Pelvis top %.2f  Spine01 bottom %.2f  overlap %.3f m (gate %.2f, at drop %.2f)"
			% [spec[0], _span("Pelvis", skel).y, _span("Spine01", skel).x, worst, WAIST_GATE, worst_at])
	if worst < WAIST_GATE:
		_fail("%s: the waist plates overlap by only %.3f m at drop %.2f, gate %.2f -- the mech splits open"
				% [spec[0], worst, worst_at, WAIST_GATE])
	_keep.append(model)
	await get_tree().process_frame


## Where the legs point while flying: the first version kept aiming the IK at the plants the mech
## left on the ground, so after a second of flight the target was 26 m away.
func _air(state: StringName) -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	var gait: Hero3Gait = model.gait
	var skel: Skeleton3D = model.skeleton
	model.set_locomotion(&"run", 16.0, Vector2(0.0, -1.0))
	gait.reset()
	for tick in 120:
		model.position += Vector3(0.0, 0.0, -16.0 * DT)
		gait.update(DT)
	model.set_locomotion(state, 20.0, Vector2(0.0, -1.0))
	var worst_reach := 0.0
	var worst_behind := 0.0
	for tick in 180:
		model.position += Vector3(0.0, 8.0 * DT, -20.0 * DT)
		gait.update(DT)
		if tick < 30:
			continue
		for leg in [&"L", &"R"]:
			var hip := skel.get_bone_global_pose(skel.find_bone("%s_Thigh" % leg)).origin
			var ankle := skel.get_bone_global_pose(skel.find_bone("%s_Foot" % leg)).origin
			worst_reach = maxf(worst_reach, ankle.distance_to(hip))
			worst_behind = maxf(worst_behind, ankle.z - hip.z)
	print("AIR %-11s ankle-hip %.2f m (gate %.2f)  ankle behind the hip %.2f m (gate %.1f)"
			% [state, worst_reach, AIR_REACH_GATE, worst_behind, AIR_BEHIND_GATE])
	if worst_reach > AIR_REACH_GATE:
		_fail("%s: the ankle is %.2f m from its hip, gate %.2f -- the leg is reaching for a plant"
				% [state, worst_reach, AIR_REACH_GATE])
	if worst_behind > AIR_BEHIND_GATE:
		_fail("%s: the ankle hangs %.2f m behind the hip, gate %.1f"
				% [state, worst_behind, AIR_BEHIND_GATE])
	_keep.append(model)
	await get_tree().process_frame


## The vertices whose DOMINANT bone is Pelvis or Spine01, within 1.6 m of the centreline: the
## outboard plates belong to the tassets and would report a span that has nothing to do with the
## waist seam.
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
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or verts.is_empty():
				continue
			var per := int(bones.size() / verts.size())
			for i in range(0, verts.size(), 3):
				if absf(verts[i].x) > 1.6:
					continue
				var best := -1.0
				var bb := -1
				for j in per:
					if weights[i * per + j] > best:
						best = weights[i * per + j]
						bb = int(bones[i * per + j])
				var bone_name := skel.get_bone_name(bind_bone[bb])
				if bone_name == "Pelvis" or bone_name == "Spine01":
					if not _plates.has(bone_name):
						_plates[bone_name] = []
					_plates[bone_name].append([mi, verts[i], bind_bone[bb], bb])


## The (lowest, highest) y of a plate's skinned vertices this instant.
func _span(bone_name: String, skel: Skeleton3D) -> Vector2:
	var lo := INF
	var hi := -INF
	for row: Array in _plates.get(bone_name, []):
		var mi: MeshInstance3D = row[0]
		var m := skel.get_bone_global_pose(int(row[2])) * mi.skin.get_bind_pose(int(row[3]))
		var y := (m * (row[1] as Vector3)).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return Vector2(lo, hi)


func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL %s" % message)

