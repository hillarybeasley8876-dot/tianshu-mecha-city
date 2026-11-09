extends "res://player/model/hero3/tests/test_hero3_pieces.gd"
## Scratch sweep for lead r5's carried item 9: which knockdown / slide / guard numbers keep the
## armour plates out of each other. Reuses the gate's own collector and crossing metric, so whatever
## this prints is the number the gate would print.
##   tools/godot.sh test res://player/model/hero3/tests/probe_pieces.gd
##
## `SWEEP` rows are [label, clip, frames, patch] where `patch` is written into the clip's own data
## before it plays, so the sweep varies the AUTHORED numbers and nothing else.

const SWEEP: Array = [
	["kd drop 3.00 fwd 3.60", &"hit_knockdown", 26, {"drop": 3.00, "fwd": 3.60}],
	["kd drop 3.10 fwd 3.80", &"hit_knockdown", 26, {"drop": 3.10, "fwd": 3.80}],
	["kd drop 3.20 fwd 4.00", &"hit_knockdown", 26, {"drop": 3.20, "fwd": 4.00}],
	["kd drop 3.00 fwd 4.00", &"hit_knockdown", 26, {"drop": 3.00, "fwd": 4.00}],
	["kd drop 3.20 fwd 4.40", &"hit_knockdown", 26, {"drop": 3.20, "fwd": 4.40}],
	["kd drop 3.40 fwd 4.40", &"hit_knockdown", 26, {"drop": 3.40, "fwd": 4.40}],
]


func _ready() -> void:
	_model = _spawn()
	_collect(_model.skeleton)
	_pairs = _adjacent(_model.skeleton)
	await _pose("rest", &"", 0)
	print("SWEEP baseline pairs %d" % _baseline.size())
	for row: Array in SWEEP:
		await _variant(String(row[0]), row[1], int(row[2]), row[3])
	get_tree().quit(0)


## One variant of a clip, patched and measured.
func _variant(label: String, clip: StringName, frames: int, patch: Dictionary) -> void:
	if _model != null:
		_model.queue_free()
	_model = _spawn()
	var skel: Skeleton3D = _model.skeleton
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	_model.gait.reset()
	_model.stop_action()
	_model.set_aim(Vector3.ZERO, 0.0)
	for i in 30:
		_tick()
	_patch(_model.clips.clips[clip], patch)
	_model.play_action(clip, 0.06)
	for i in frames:
		_tick()
	var rows: Array = []
	for pair: Array in _pairs:
		var a: Array = _penetration(skel, int(pair[0]), int(pair[1]))
		var b: Array = _penetration(skel, int(pair[1]), int(pair[0]))
		var seen := maxf(float(a[0]), float(b[0]))
		var added := seen - float(_baseline.get(_key(skel, int(pair[0]), int(pair[1])), 0.0))
		if added > 0.005:
			rows.append([added, "%s +%.3f" % [a[2], added]])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	var knee := rad_to_deg(_knee(skel))
	print("SWEEP %-22s knee %5.1f  worst %s" % [label, knee,
			"none" if rows.is_empty() else ", ".join(PackedStringArray(
					rows.slice(0, 3).map(func(r: Array) -> String: return r[1])))])
	await get_tree().process_frame


## Rewrite the clip's root drop and its sole targets. The root key at frame 8 and 26 carry the drop;
## the sole keys carry the slide.
func _patch(clip: Dictionary, patch: Dictionary) -> void:
	var drop := float(patch.get("drop", 0.0))
	var fwd := float(patch.get("fwd", 0.0))
	var root: Array = clip["root"]
	for i in root.size():
		var k: Array = root[i]
		if float(k[0]) > 0.0:
			k[2] = -drop * (1.0 if float(k[0]) <= 26.0 else 0.45)
	var feet: Dictionary = clip["feet"]
	for side: String in feet:
		var keys: Array = feet[side]
		for i in keys.size():
			var k: Array = keys[i]
			if float(k[0]) > 0.0:
				k[3] = -fwd * (1.0 if float(k[0]) <= 26.0 else 0.5)


func _knee(skel: Skeleton3D) -> float:
	var t := skel.find_bone("R_Thigh")
	var c := skel.find_bone("R_Calf")
	var f := skel.find_bone("R_Foot")
	var a := (skel.get_bone_global_pose(t).origin - skel.get_bone_global_pose(c).origin).normalized()
	var b := (skel.get_bone_global_pose(f).origin - skel.get_bone_global_pose(c).origin).normalized()
	return PI - a.angle_to(b)
