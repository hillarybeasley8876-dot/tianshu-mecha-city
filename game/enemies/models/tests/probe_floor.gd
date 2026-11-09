extends Node
## Floor contact for every grounded clip of every grounded monster (monster-assets, lead r6).
## Headless. For each clip, every LOD0 vertex is skinned at 30 Hz (bridge-triangle vertices excluded,
## so torn sheets do not count as feet): per frame the lowest surface point and the bone that carries
## it. A planted gait keeps that near 0 m every frame.
##
## The gate the lead set: nothing below -0.15 m, and nothing hovering above +0.3 m for more than
## three consecutive frames.
##   tools/godot.sh test res://enemies/models/tests/probe_floor.gd -- --timeout=1800

## The harrier flies and the hive does not animate, so neither has a floor to keep.
const TYPES: Array[StringName] = [&"ripper", &"mantis", &"spitter", &"juggernaut", &"titan",
		&"titan_skyline"]
## Clips that are *meant* to leave the floor (`mon_types.GROUND_CONST`): a leap, a dive, a death
## fall. They keep their arc and only their lowest point is planted, so they are reported but not
## gated.
const AIRBORNE: Array[String] = ["leap", "dive", "death", "death_fall", "climb_over",
		"beam_breath", "summon"]
const HZ := 30.0
const MAX_HOPS := 3
## The gate.
const SINK_GATE := -0.15
const HOVER_GATE := 0.3
const HOVER_FRAMES := 3

var _rows: Array[Dictionary] = []
## `--type=` / `--clip=` narrow a run to one monster or one clip; a full pass is ~9 minutes, and
## chasing a single number should not cost that.
var _only_type := ""
var _only_clip := ""
## `--frames=1` prints every sampled frame, not just the worst.
var _print_frames := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("--type="):
			_only_type = text.substr(7)
		elif text.begins_with("--clip="):
			_only_clip = text.substr(7)
		elif text.begins_with("--frames="):
			_print_frames = text.substr(9) == "1"
	for type in TYPES:
		if _only_type.is_empty() or String(type) == _only_type:
			await _probe(type)
	_report()
	get_tree().quit(0)


func _hops(skel: Skeleton3D, a: int, b: int) -> int:
	var chain: Array[int] = []
	var n := a
	while n >= 0:
		chain.append(n)
		n = skel.get_bone_parent(n)
	var steps := 0
	n = b
	while n >= 0:
		var i := chain.find(n)
		if i >= 0:
			return i + steps
		n = skel.get_bone_parent(n)
		steps += 1
	return 99


func _probe(type: StringName) -> void:
	var scene := "res://enemies/models/%s/%s_model.tscn" % [type, type]
	if not ResourceLoader.exists(scene):
		push_warning("probe_floor: %s has no model scene" % type)
		return
	var model := (load(scene) as PackedScene).instantiate() as Node3D
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
		var best := 0
		var bw := -1.0
		for k in per:
			if weights[v * per + k] > bw:
				bw = weights[v * per + k]
				best = bones[v * per + k]
		var bi := skin.get_bind_bone(best)
		dominant[v] = bi if bi >= 0 else skel.find_bone(skin.get_bind_name(best))
	var bridged := {}
	for t in range(0, index.size(), 3):
		for e in 3:
			if _hops(skel, dominant[index[t + e]], dominant[index[t + (e + 1) % 3]]) > MAX_HOPS:
				bridged[index[t]] = true
				bridged[index[t + 1]] = true
				bridged[index[t + 2]] = true
	var keep := PackedInt32Array()
	for v in verts.size():
		if not bridged.has(v):
			keep.append(v)
	var ap := model.get("animation") as AnimationPlayer
	var clips: Dictionary = (model.get("_playback") as Object).get("clips")
	for clip: String in _grounded(clips):
		_clip(type, clip, ap, clips, skel, skin, verts, weights, bones, per, keep,
				dominant, xf, bridged.size())
	model.queue_free()
	await get_tree().process_frame


## The type's clips, in a stable order, minus the ones that are meant to leave the ground.
func _grounded(clips: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for clip: String in clips:
		if not AIRBORNE.has(clip) and (_only_clip.is_empty() or clip == _only_clip):
			out.append(clip)
	out.sort()
	return out


func _clip(type: StringName, clip: String, ap: AnimationPlayer, clips: Dictionary,
		skel: Skeleton3D, skin: Skin, verts: PackedVector3Array, weights: PackedFloat32Array,
		bones: PackedInt32Array, per: int, keep: PackedInt32Array, dominant: PackedInt32Array,
		xf: Transform3D, bridged: int) -> void:
	var lib := String((clips[clip] as Dictionary)["name"])
	var anim := ap.get_animation(lib)
	var steps := maxi(int(ceil(anim.length * HZ)), 1)
	var lowest := INF
	var worst_t := 0.0
	var worst_bone := ""
	var highest := -INF
	var high_t := 0.0
	var hover_run := 0
	var hover_start := 0.0
	var hover_worst := 0
	var hover_at := 0.0
	var sink_frames := 0
	for s in steps:
		var t := anim.length * float(s) / float(steps)
		ap.play(lib, 0.0)
		ap.seek(t, true)
		ap.pause()
		var binds: Array[Transform3D] = []
		for b in skin.get_bind_count():
			var bi := skin.get_bind_bone(b)
			if bi < 0:
				bi = skel.find_bone(skin.get_bind_name(b))
			binds.append(skel.get_bone_global_pose(bi) * skin.get_bind_pose(b))
		var frame_min := INF
		var frame_vert := 0
		for v in keep:
			var y := 0.0
			var ws := 0.0
			for k in per:
				var w := weights[v * per + k]
				if w > 0.0:
					y += (xf * (binds[bones[v * per + k]] * verts[v])).y * w
					ws += w
			y /= maxf(ws, 1e-6)
			if y < frame_min:
				frame_min = y
				frame_vert = v
		if _print_frames:
			print("    t %6.3f  lowest %+.3f m  bone %s"
					% [t, frame_min, skel.get_bone_name(dominant[frame_vert])])
		if frame_min < lowest:
			lowest = frame_min
			worst_t = t
			worst_bone = skel.get_bone_name(dominant[frame_vert])
		if frame_min > highest:
			highest = frame_min
			high_t = t
		if frame_min < SINK_GATE:
			sink_frames += 1
		if frame_min > HOVER_GATE:
			if hover_run == 0:
				hover_start = t
			hover_run += 1
			if hover_run > hover_worst:
				hover_worst = hover_run
				hover_at = hover_start
		else:
			hover_run = 0
	var gated := hover_worst <= HOVER_FRAMES and lowest >= SINK_GATE
	_rows.append({"type": String(type), "clip": clip, "len": anim.length, "low": lowest,
			"bone": worst_bone, "low_t": worst_t, "high": highest, "high_t": high_t,
			"hover": hover_worst, "hover_t": hover_at, "sink": sink_frames, "steps": steps,
			"bridged": bridged, "ok": gated})
	print("FLOOR %-13s %-12s len %5.2f | lowest %+.2f m (%s) @ %.2f s | highest %+.2f m @ %.2f s | hover run %d/%d @ %.2f s | sink frames %d/%d | bridge verts %d | %s"
			% [type, clip, anim.length, lowest, worst_bone, worst_t, highest, high_t,
			hover_worst, steps, hover_at, sink_frames, steps, bridged,
			"OK" if gated else "OUT OF BAND"])


func _report() -> void:
	print("FLOOR TABLE  gate: lowest >= %.2f m, no more than %d consecutive frames above %.2f m"
			% [SINK_GATE, HOVER_FRAMES, HOVER_GATE])
	print("  %-13s %-12s %8s %-14s %8s %7s %6s  %s"
			% ["type", "clip", "lowest", "bone", "highest", "hover", "sink", "verdict"])
	var bad := 0
	for row in _rows:
		if not bool(row["ok"]):
			bad += 1
		print("  %-13s %-12s %+8.2f %-14s %+8.2f %7d %6d  %s"
				% [row["type"], row["clip"], row["low"], row["bone"], row["high"],
				row["hover"], row["sink"], "OK" if row["ok"] else "OUT OF BAND"])
	print("FLOOR SUMMARY %d clips, %d out of band" % [_rows.size(), bad])
