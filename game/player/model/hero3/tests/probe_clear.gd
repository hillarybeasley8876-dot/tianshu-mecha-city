extends "res://player/model/hero3/tests/test_hero3_pieces.gd"
## Scratch probe for lead r5's carried item 9: sweep the numbers behind each crossing the gate reports
## and print what the gate would say, so the clips and stances are moved to a MEASURED value.
##   tools/godot.sh test res://player/model/hero3/tests/probe_clear.gd
##
## PATCHES rows scale ONE euler component of one clip track (or the whole track) and replay.
## STANCES rows override a `Hero3Skate` stance's drop and stagger and replay.

## [label, clip, frames, pair A, pair B, track, component (-1 = all), scales...]
const PATCHES: Array = [
	["death L_Fore x", &"death", 96, "L_Forearm", "L_Upperarm", "L_Forearm", 0,
			1.0, 0.5, 0.0, -1.0, -2.0, -3.0, -4.0],
	["death L_Up x", &"death", 96, "L_Forearm", "L_Upperarm", "L_Upperarm", 0,
			1.0, 1.5, 2.0, 2.5, 3.0],
	["death L_Up z", &"death", 96, "L_Forearm", "L_Upperarm", "L_Upperarm", 2,
			1.0, 1.2, 1.4, 1.6, 1.8],
	["death R_Fore x", &"death", 96, "R_Forearm", "R_Upperarm", "R_Forearm", 0,
			1.0, 0.0, -1.0, -2.0, -3.0],
]
## [label, state, speed, pair A, pair B, [{drop, stagger}...]]
const STANCES: Array = [
	["slide", &"slide", 42.0, "R_Calf", "R_Thigh",
			[{"drop": 1.30, "stagger": 2.4}, {"drop": 1.10, "stagger": 2.8},
			{"drop": 0.90, "stagger": 3.2}, {"drop": 0.70, "stagger": 3.6},
			{"drop": 1.30, "stagger": 3.2}, {"drop": 0.90, "stagger": 2.4},
			{"drop": 0.60, "stagger": 3.0}]],
]


func _ready() -> void:
	_model = _spawn()
	_collect(_model.skeleton)
	_pairs = _adjacent(_model.skeleton)
	await _pose("rest", &"", 0)
	for row: Array in PATCHES:
		await _patched(String(row[0]), row[1], int(row[2]), String(row[3]), String(row[4]),
				String(row[5]), int(row[6]), row.slice(7))
	for row: Array in STANCES:
		await _stances(String(row[0]), row[1], float(row[2]), String(row[3]), String(row[4]),
				row[5])
	get_tree().quit(0)


func _patched(label: String, clip: StringName, frames: int, a: String, b: String, track: String,
		component: int, scales: Array) -> void:
	var out: Array[String] = []
	for k: float in scales:
		var skel := await _reach(clip, frames, track, component, k)
		out.append("x%.2f: %s" % [k, _pair(skel, skel.find_bone(a), skel.find_bone(b))])
	print("CLEAR %-16s %s" % [label, " | ".join(out)])
	await get_tree().process_frame


func _stances(label: String, state: StringName, speed: float, a: String, b: String,
		variants: Array) -> void:
	var out: Array[String] = []
	for v: Dictionary in variants:
		if _model != null:
			_model.queue_free()
		_model = _spawn()
		var skel: Skeleton3D = _model.skeleton
		_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
		_model.gait.reset()
		for i in 30:
			_tick()
		_model.gait.skate.set_override({"drop": float(v["drop"]), "lean": 12.0,
				"stagger": float(v["stagger"])})
		_model.set_locomotion(state, speed, Vector2(0.0, -1.0))
		for i in 40:
			_tick()
		out.append("d%.2f/s%.1f: %s" % [float(v["drop"]), float(v["stagger"]),
				_pair(skel, skel.find_bone(a), skel.find_bone(b))])
	print("CLEAR %-16s %s" % [label, " | ".join(out)])
	await get_tree().process_frame


## A fresh mech driven to the pose, with one euler component of one clip track scaled by `k`.
func _reach(clip: StringName, frames: int, track: String, component: int, k: float) -> Skeleton3D:
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
	_scale(_model.clips.clips[clip], track, component, k)
	_model.play_action(clip, 0.06)
	for i in frames:
		_tick()
	return skel


func _scale(clip: Dictionary, track: String, component: int, k: float) -> void:
	var wanted := track.split("+")
	for row: Dictionary in clip["tracks"]:
		if not wanted.has(String(row["bone"])):
			continue
		for key: Array in row["keys"]:
			if component < 0:
				key[1] = float(key[1]) * k
				key[2] = float(key[2]) * k
				key[3] = float(key[3]) * k
			else:
				key[component + 1] = float(key[component + 1]) * k


## What the gate would say about this one pair, added over the rest baseline.
func _pair(skel: Skeleton3D, a: int, b: int) -> String:
	var x: Array = _penetration(skel, a, b)
	var y: Array = _penetration(skel, b, a)
	var added := maxf(float(x[0]), float(y[0])) - float(_baseline.get(_key(skel, a, b), 0.0))
	return "clear" if added <= 0.005 else "+%.3f" % added
