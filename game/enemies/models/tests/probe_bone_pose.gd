extends Node
## What Godot actually poses each bone at, for one clip (monster-assets, lead r6).
##
## The engine that ships the model is the ground truth. `probe_floor` measures the lowest skinned
## vertex through Godot and `diag_glb_floor` measures the same `.glb` the way any glTF consumer
## would; when those two disagree, this says which side is wrong, because it prints the bone poses
## the engine really plays next to the rest pose it rebuilt the rig from.
##
## It is how the r6 engine-side residual was pinned down: Godot's glTF importer compresses imported
## animations (71 keys per rotation track arrive as 66), and the divergence that costs grows down the
## bone chain while `BoneRoot`, `Hip` and `Pelvis` stay exact.
##   tools/godot.sh test res://enemies/models/tests/probe_bone_pose.gd -- --type=titan --clip=walk
## Options: `--type=`, `--clip=`, `--at=0.1,0.5,0.9` (fractions of the clip).

## The chain to walk: root, then a leg. Comparing the two ends is what shows a divergence growing.
const BONES: Array[String] = ["BoneRoot", "Hip", "Pelvis", "L_Thigh", "L_Calf", "L_Foot",
		"L_ToeBase"]
## Fractions of the clip to sample; `--at=` overrides.
const DEFAULT_AT: Array[float] = [0.0, 0.25, 0.5, 0.75]
## How many rotation tracks to report key counts for — the compression evidence.
const TRACKS_SHOWN := 6

var _at: Array[float] = DEFAULT_AT.duplicate()


func _ready() -> void:
	var args := _args()
	var body := String(args.get("type", "juggernaut"))
	var clip := String(args.get("clip", "charge_run"))
	if args.has("at"):
		_at = []
		for part in String(args["at"]).split(",", false):
			_at.append(float(part))
	var scene := "res://enemies/models/%s/%s_model.tscn" % [body, body]
	if not ResourceLoader.exists(scene):
		push_error("probe_bone_pose: %s has no model scene" % body)
		get_tree().quit(1)
		return
	var model := (load(scene) as PackedScene).instantiate() as Node3D
	add_child(model)
	await get_tree().process_frame
	model.set_process(false)
	var mi := (model.get("meshes") as Array)[0] as MeshInstance3D
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var ap := model.get("animation") as AnimationPlayer
	var clips: Dictionary = (model.get("_playback") as Object).get("clips")
	if not clips.has(clip):
		print("BONEPOSE %s has no clip '%s'; have %s" % [body, clip, clips.keys()])
		get_tree().quit(1)
		return
	var lib := String((clips[clip] as Dictionary)["name"])
	var anim := ap.get_animation(lib)
	print("BONEPOSE %s clip %s (library '%s') length %.3f s, %d bones, mesh '%s' %d verts"
			% [body, clip, lib, anim.length, skel.get_bone_count(), mi.name,
			mi.mesh.surface_get_array_len(0)])
	_tracks(anim)
	_rest(body, skel)
	for fraction in _at:
		var t: float = anim.length * fraction
		ap.play(lib, 0.0)
		ap.seek(t, true)
		ap.pause()
		print("BONEPOSE t %.3f s (%.0f%%)" % [t, fraction * 100.0])
		for bone in BONES:
			var idx := skel.find_bone(bone)
			if idx < 0:
				print("    %-10s MISSING" % bone)
				continue
			var origin := skel.get_bone_global_pose(idx).origin
			print("    %-10s %8.3f %8.3f %8.3f" % [bone, origin.x, origin.y, origin.z])
	get_tree().quit(0)


## Key counts per rotation track: what Godot kept of what the file carries.
func _tracks(anim: Animation) -> void:
	var shown := 0
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D or shown >= TRACKS_SHOWN:
			continue
		shown += 1
		print("TRACK %-38s keys %d"
				% [str(anim.track_get_path(i)), anim.track_get_key_count(i)])


## The rig Godot rebuilt: local rest transform and orientation per bone. A rest that differs from
## the file's node hierarchy would move every clip, so this is the first thing to compare.
func _rest(body: String, skel: Skeleton3D) -> void:
	print("BONEREST %s" % body)
	for bone in BONES:
		var idx := skel.find_bone(bone)
		if idx < 0:
			continue
		var rest := skel.get_bone_rest(idx)
		var quat := rest.basis.get_rotation_quaternion()
		print("    %-10s rest %8.3f %8.3f %8.3f  quat %+.6f %+.6f %+.6f %+.6f"
				% [bone, rest.origin.x, rest.origin.y, rest.origin.z,
				quat.x, quat.y, quat.z, quat.w])


func _args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("--") and text.contains("="):
			var split := text.substr(2).split("=", true, 1)
			out[split[0]] = split[1]
	return out
