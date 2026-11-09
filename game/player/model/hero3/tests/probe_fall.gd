extends "res://player/model/hero3/tests/test_hero3_pieces.gd"
## Scratch sweep for the `fall` brace (lead r8): the r7 numbers drove the left clavicle 1.5 m through
## the shoulder and nothing had ever measured it, because no pose in the gate played an air clip.
##   tools/godot.sh test res://player/model/hero3/tests/probe_fall.gd
##
## `SWEEP` rows are [label, lean, fold, spread, swing] -- the parameters `Hero3ClipsMove._fall` now
## takes. Every row rebuilds the clip and measures it with the GATE'S own metric, so whatever this
## prints is the number `test_hero3_pieces` would print for that pose.

const SWEEP: Array = [
	["lean -0.12 fold -0.75 spread 0.24 swing -0.42", -0.12, -0.75, 0.24, -0.42],
	["swing -0.36", -0.12, -0.75, 0.24, -0.36],
	["swing -0.30", -0.12, -0.75, 0.24, -0.30],
	["swing -0.48", -0.12, -0.75, 0.24, -0.48],
	["swing -0.54", -0.12, -0.75, 0.24, -0.54],
	["swing -0.36 spread 0.18", -0.12, -0.75, 0.18, -0.36],
	["swing -0.36 fold -0.60", -0.12, -0.60, 0.24, -0.36],
	["swing -0.30 spread 0.18", -0.12, -0.75, 0.18, -0.30],
]


func _ready() -> void:
	_model = _spawn()
	_collect(_model.skeleton)
	_pairs = _adjacent(_model.skeleton)
	await _pose("rest", &"", 0)
	print("SWEEP baseline pairs %d" % _baseline.size())
	for row: Array in SWEEP:
		await _variant(String(row[0]), float(row[1]), float(row[2]), float(row[3]), float(row[4]))
	get_tree().quit(0)


func _variant(label: String, lean: float, fold: float, spread: float, swing: float) -> void:
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
	# `Hero3Clips.build` post-processes every clip into `{bones: {name: keys}, length: seconds}`; the
	# raw family dictionary is not what the player samples, so the sweep goes through `_finish` too.
	_model.clips.clips[&"fall"] = Hero3Clips._finish(Hero3ClipsMove._fall(lean, fold, spread, swing))
	_model.play_action(&"fall", 0.06)
	for i in 40:
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
	print("SWEEP %-38s worst %s" % [label,
			"none" if rows.is_empty() else ", ".join(PackedStringArray(
					rows.slice(0, 3).map(func(r: Array) -> String: return r[1])))])
	await get_tree().process_frame
