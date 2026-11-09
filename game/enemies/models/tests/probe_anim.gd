extends Node
## Acceptance asset-QA animation probe (lead acceptance team; scratch, never shipped). Headless.
## Every clip of every monster, sampled at --qa-hz (default 20) on the CPU-skinned LOD0 mesh:
## the worst edge stretch against the bind mesh (a torn / shredded skin shows as edges several times
## their rest length), how many sampled edges pass 2x and 4x, when the worst happens, and which bones
## the torn vertices are weighted to; plus which skeleton bones each clip leaves un-keyed.
##   godot --headless --path game -s res://tools/test_host.gd -- \
##       --test=res://enemies/models/tests/probe_anim.gd --timeout=1200 [--qa-types=ripper] [--qa-hz=20]

const TYPES: Array[StringName] = [&"ripper", &"mantis", &"spitter", &"harrier", &"juggernaut",
		&"titan", &"titan_skyline"]
const TARGET_TRIS := 4000
const MIN_REST := 0.02

var _hz: float = 20.0


func _ready() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-types="):
			only = arg.trim_prefix("--qa-types=")
		elif arg.begins_with("--qa-hz="):
			_hz = float(arg.trim_prefix("--qa-hz="))
	var types: Array[StringName] = TYPES
	if not only.is_empty():
		types = []
		for t in only.split(",", false):
			types.append(StringName(t))
	for type in types:
		await _probe_type(type)
	print("ANIM done")
	get_tree().quit(0)


func _probe_type(type: StringName) -> void:
	var packed := load("res://enemies/models/%s/%s_model.tscn" % [type, type]) as PackedScene
	if packed == null:
		print("ANIM %s FAIL cannot load" % type)
		return
	var model := packed.instantiate() as Node3D
	add_child(model)
	await get_tree().process_frame
	model.set_process(false)
	var meshes: Array = model.get("meshes")
	var mi := meshes[0] as MeshInstance3D
	var ap := model.get("animation") as AnimationPlayer
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var skin := mi.skin
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var xf := mi.global_transform
	# sampled edges and the vertex set they use
	var tri_count := index.size() / 3
	var stride := maxi(1, tri_count / TARGET_TRIS)
	var edge_a := PackedInt32Array()
	var edge_b := PackedInt32Array()
	var rest_len := PackedFloat32Array()
	var used: Dictionary = {}
	for t in range(0, tri_count, stride):
		for e in 3:
			var a := index[t * 3 + e]
			var b := index[t * 3 + (e + 1) % 3]
			var l := (xf * verts[a]).distance_to(xf * verts[b])
			if l < MIN_REST:
				continue
			edge_a.append(a)
			edge_b.append(b)
			rest_len.append(l)
			used[a] = true
			used[b] = true
	var vlist := PackedInt32Array(used.keys())
	var slot: Dictionary = {}
	for i in vlist.size():
		slot[vlist[i]] = i
	print("ANIM %s mesh %s verts %d sampled_edges %d sampled_verts %d bones %d binds %d" % [type, mi.name,
			verts.size(), edge_a.size(), vlist.size(), skel.get_bone_count(), skin.get_bind_count()])
	_rest_check(type, mi, skel, skin, verts, bones, weights, per, xf)
	var clips: Dictionary = (model.get("_playback") as Object).get("clips")
	var ids: Array = clips.keys()
	ids.sort()
	for clip_id: Variant in ids:
		var lib_name := String((clips[clip_id] as Dictionary)["name"])
		var anim := ap.get_animation(lib_name)
		_unkeyed(type, String(clip_id), anim, skel)
		var steps := maxi(int(ceil(anim.length * _hz)), 1)
		var worst := 1.0
		var worst_t := 0.0
		var worst_edge := -1
		var over2 := 0
		var over4 := 0
		var frames_over2 := 0
		for s in steps + 1:
			var t := minf(anim.length, float(s) / _hz)
			ap.play(lib_name, 0.0)
			ap.seek(t, true)
			ap.pause()
			var binds := _binds(skel, skin)
			var pos := PackedVector3Array()
			pos.resize(vlist.size())
			for i in vlist.size():
				var v := vlist[i]
				var p := Vector3.ZERO
				var wsum := 0.0
				for k in per:
					var w := weights[v * per + k]
					if w > 0.0:
						p += (binds[bones[v * per + k]] * verts[v]) * w
						wsum += w
				pos[i] = xf * (p / maxf(wsum, 1e-6))
			var frame_over2 := 0
			for e in edge_a.size():
				var r := pos[int(slot[edge_a[e]])].distance_to(pos[int(slot[edge_b[e]])]) / rest_len[e]
				if r > 2.0:
					over2 += 1
					frame_over2 += 1
				if r > 4.0:
					over4 += 1
				if r > worst:
					worst = r
					worst_t = t
					worst_edge = e
			if frame_over2 > 0:
				frames_over2 += 1
		var who := ""
		if worst_edge >= 0:
			who = "%s | %s" % [_weights_of(edge_a[worst_edge], bones, weights, per, skel, skin),
					_weights_of(edge_b[worst_edge], bones, weights, per, skel, skin)]
		print("ANIM %s %-12s len %5.2f worst_stretch %6.2fx @ %.2f s | edge-samples >2x %d >4x %d | frames with >2x %d/%d | worst edge verts: %s"
				% [type, clip_id, anim.length, worst, worst_t, over2, over4, frames_over2, steps + 1, who])
	model.queue_free()
	await get_tree().process_frame


func _binds(skel: Skeleton3D, skin: Skin) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bi := skin.get_bind_bone(b)
		if bi < 0:
			bi = skel.find_bone(skin.get_bind_name(b))
		out.append(skel.get_bone_global_pose(bi) * skin.get_bind_pose(b) if bi >= 0 else Transform3D.IDENTITY)
	return out


func _weights_of(v: int, bones: PackedInt32Array, weights: PackedFloat32Array, per: int,
		skel: Skeleton3D, skin: Skin) -> String:
	var parts: PackedStringArray = []
	for k in per:
		var w := weights[v * per + k]
		if w > 0.01:
			var b := bones[v * per + k]
			var bi := skin.get_bind_bone(b)
			var bname := skel.get_bone_name(bi) if bi >= 0 else String(skin.get_bind_name(b))
			parts.append("%s %.2f" % [bname, w])
	return ", ".join(parts)


## Bones of the skeleton that the clip never keys (they hold the rest / reset value while it plays).
func _unkeyed(type: StringName, clip_id: String, anim: Animation, skel: Skeleton3D) -> void:
	var keyed: Dictionary = {}
	for tr in anim.get_track_count():
		var path := String(anim.track_get_path(tr))
		var colon := path.find(":")
		if colon >= 0:
			keyed[path.substr(colon + 1)] = true
	var missing: PackedStringArray = []
	for b in skel.get_bone_count():
		if not keyed.has(skel.get_bone_name(b)):
			missing.append(skel.get_bone_name(b))
	print("ANIMKEYS %s %-12s tracks %d bones %d unkeyed %d%s" % [type, clip_id, anim.get_track_count(),
			skel.get_bone_count(), missing.size(), (": " + ", ".join(missing.slice(0, 12))) if not missing.is_empty() else ""])


## Sanity of the probe itself: at the skeleton's rest pose the CPU skin must reproduce the bind mesh.
func _rest_check(type: StringName, mi: MeshInstance3D, skel: Skeleton3D, skin: Skin, verts: PackedVector3Array,
		bones: PackedInt32Array, weights: PackedFloat32Array, per: int, xf: Transform3D) -> void:
	var saved: Array[Transform3D] = []
	for b in skel.get_bone_count():
		saved.append(skel.get_bone_pose(b))
	skel.reset_bone_poses()
	var binds := _binds(skel, skin)
	var worst := 0.0
	var mean := 0.0
	var n := 0
	for v in range(0, verts.size(), 7):
		var p := Vector3.ZERO
		var wsum := 0.0
		for k in per:
			var w := weights[v * per + k]
			if w > 0.0:
				p += (binds[bones[v * per + k]] * verts[v]) * w
				wsum += w
		var d := (xf * (p / maxf(wsum, 1e-6))).distance_to(xf * verts[v])
		worst = maxf(worst, d)
		mean += d
		n += 1
	print("ANIMREST %s rest-pose skin vs bind mesh: mean %.4f m worst %.4f m (n %d); skeleton xf %s mesh xf %s"
			% [type, mean / maxf(float(n), 1.0), worst, n, skel.global_transform.origin, mi.global_transform.origin])
	for b in skel.get_bone_count():
		skel.set_bone_pose(b, saved[b])
