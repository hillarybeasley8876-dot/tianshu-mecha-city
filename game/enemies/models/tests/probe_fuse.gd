extends Node
## Acceptance asset-QA fused-geometry probe (lead acceptance team; scratch, never shipped). Headless.
## A Tripo remesh is one closed shell, so wherever two body parts touched in the source pose they are
## stitched together by triangles. Those "bridge" triangles join vertices driven by bones that are far
## apart in the skeleton (a claw and a thigh), and they tear into sheets as soon as the parts move
## apart. Per type: bridge triangles in the bind mesh (dominant bones more than MAX_HOPS apart in the
## bone tree), grouped by bone pair with their rest-pose centre, and how far they open in each clip.
##   godot --headless --path game -s res://tools/test_host.gd -- \
##       --test=res://enemies/models/tests/probe_fuse.gd --timeout=900 [--qa-types=ripper]

const TYPES: Array[StringName] = [&"ripper", &"mantis", &"spitter", &"harrier", &"juggernaut", &"titan"]
const MAX_HOPS := 3


func _ready() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-types="):
			only = arg.trim_prefix("--qa-types=")
	var types: Array[StringName] = TYPES
	if not only.is_empty():
		types = []
		for t in only.split(",", false):
			types.append(StringName(t))
	for type in types:
		await _probe(type)
	print("FUSE done")
	get_tree().quit(0)


func _hops(skel: Skeleton3D, a: int, b: int) -> int:
	var chain_a: Array[int] = []
	var n := a
	while n >= 0:
		chain_a.append(n)
		n = skel.get_bone_parent(n)
	var steps := 0
	n = b
	while n >= 0:
		var i := chain_a.find(n)
		if i >= 0:
			return i + steps
		n = skel.get_bone_parent(n)
		steps += 1
	return 99


func _probe(type: StringName) -> void:
	var packed := load("res://enemies/models/%s/%s_model.tscn" % [type, type]) as PackedScene
	var model := packed.instantiate() as Node3D
	add_child(model)
	await get_tree().process_frame
	model.set_process(false)
	var mi := (model.get("meshes") as Array)[0] as MeshInstance3D
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var skin := mi.skin
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var xf := mi.global_transform
	var dominant := PackedInt32Array()
	dominant.resize(verts.size())
	for v in verts.size():
		var best := -1
		var best_w := -1.0
		for k in per:
			if weights[v * per + k] > best_w:
				best_w = weights[v * per + k]
				best = bones[v * per + k]
		var bi := skin.get_bind_bone(best)
		dominant[v] = bi if bi >= 0 else skel.find_bone(skin.get_bind_name(best))
	var pairs: Dictionary = {}       # "a|b" -> [count, centre sum, area]
	var bridge_tris := PackedInt32Array()
	var total_area := 0.0
	for t in range(0, index.size(), 3):
		var ids := [index[t], index[t + 1], index[t + 2]]
		var worst := 0
		var pa := -1
		var pb := -1
		for e in 3:
			var a: int = dominant[ids[e]]
			var b: int = dominant[ids[(e + 1) % 3]]
			if a == b:
				continue
			var h := _hops(skel, a, b)
			if h > worst:
				worst = h
				pa = mini(a, b)
				pb = maxi(a, b)
		var p0 := xf * verts[ids[0]]
		var p1 := xf * verts[ids[1]]
		var p2 := xf * verts[ids[2]]
		var area := (p1 - p0).cross(p2 - p0).length() * 0.5
		total_area += area
		if worst > MAX_HOPS:
			bridge_tris.append(t)
			var key := "%s|%s" % [skel.get_bone_name(pa), skel.get_bone_name(pb)]
			var entry: Array = pairs.get(key, [0, Vector3.ZERO, 0.0, worst])
			entry[0] = int(entry[0]) + 1
			entry[1] = (entry[1] as Vector3) + (p0 + p1 + p2) / 3.0
			entry[2] = float(entry[2]) + area
			pairs[key] = entry
	var keys: Array = pairs.keys()
	keys.sort_custom(func(x: Variant, y: Variant) -> bool: return int(pairs[x][0]) > int(pairs[y][0]))
	print("FUSE %s bridge triangles %d of %d (%.2f%%) between bones > %d hops apart; %d bone pairs" % [type,
			bridge_tris.size(), index.size() / 3, 100.0 * float(bridge_tris.size()) / float(index.size() / 3),
			MAX_HOPS, keys.size()])
	for i in mini(8, keys.size()):
		var e: Array = pairs[keys[i]]
		var c := (e[1] as Vector3) / float(e[0])
		print("FUSE %s   %-44s tris %4d  hops %2d  area %.2f m2  rest centre (%.1f, %.1f, %.1f)" % [type,
				keys[i], int(e[0]), int(e[3]), float(e[2]), c.x, c.y, c.z])
	# how far the bridges open in each clip: the longest bridge-triangle edge vs its rest length
	var ap := model.get("animation") as AnimationPlayer
	var clips: Dictionary = (model.get("_playback") as Object).get("clips")
	var ids_sorted: Array = clips.keys()
	ids_sorted.sort()
	var line: PackedStringArray = []
	for clip_id: Variant in ids_sorted:
		var lib := String((clips[clip_id] as Dictionary)["name"])
		var anim := ap.get_animation(lib)
		var worst_len := 0.0
		for s in 11:
			ap.play(lib, 0.0)
			ap.seek(anim.length * float(s) / 10.0, true)
			ap.pause()
			var binds: Array[Transform3D] = []
			for b in skin.get_bind_count():
				var bi := skin.get_bind_bone(b)
				if bi < 0:
					bi = skel.find_bone(skin.get_bind_name(b))
				binds.append(skel.get_bone_global_pose(bi) * skin.get_bind_pose(b))
			for t in bridge_tris:
				var q: Array[Vector3] = []
				for k in 3:
					var v := index[t + k]
					var p := Vector3.ZERO
					var ws := 0.0
					for j in per:
						var w := weights[v * per + j]
						if w > 0.0:
							p += (binds[bones[v * per + j]] * verts[v]) * w
							ws += w
					q.append(xf * (p / maxf(ws, 1e-6)))
				worst_len = maxf(worst_len, maxf(q[0].distance_to(q[1]), maxf(q[1].distance_to(q[2]), q[2].distance_to(q[0]))))
		line.append("%s %.1fm" % [clip_id, worst_len])
	print("FUSE %s   longest bridge edge per clip: %s" % [type, ", ".join(line)])
	model.queue_free()
	await get_tree().process_frame
