extends Node
## Scratch: does the gait's pelvis bob reach the `cockpit` socket? If the spine chain is written
## absolutely the head does not follow the hips, and the first-person view was never shaking.
##   tools/godot.sh test res://player/model/hero3/tests/probe_eye.gd

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 60.0

var _m: Node3D
var _skel: Skeleton3D

func _ready() -> void:
	_m = (load(SCENE) as PackedScene).instantiate()
	_m.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_m)
	_skel = _m.skeleton
	_m.set_locomotion(&"walk", 9.0, Vector2(0.0, -1.0))
	_m.gait.reset()
	var pelvis: Array[float] = []
	var head: Array[float] = []
	var socket: Array[float] = []
	for f in 180:
		_m.position += Vector3(0.0, 0.0, -9.0) * DT
		_tick()
		pelvis.append(_at("Pelvis").y)
		head.append(_at("Head").y)
		var s := _m.socket(&"cockpit") as Node3D
		socket.append(s.global_position.y if s != null else 0.0)
	_report("walk 9 m/s", pelvis, head, socket)
	_m.set_locomotion(&"run", 16.0, Vector2(0.0, -1.0))
	_m.gait.reset()
	pelvis.clear(); head.clear(); socket.clear()
	for f in 180:
		_m.position += Vector3(0.0, 0.0, -16.0) * DT
		_tick()
		pelvis.append(_at("Pelvis").y)
		head.append(_at("Head").y)
		var s2 := _m.socket(&"cockpit") as Node3D
		socket.append(s2.global_position.y if s2 != null else 0.0)
	_report("run 16 m/s", pelvis, head, socket)
	get_tree().quit(0)


func _report(label: String, pelvis: Array[float], head: Array[float], socket: Array[float]) -> void:
	print("EYE %-11s pelvis %.3f-%.3f (%.3f)  head %.3f-%.3f (%.3f)  cockpit %.3f-%.3f (%.3f)"
			% [label, pelvis.min(), pelvis.max(), pelvis.max() - pelvis.min(),
			head.min(), head.max(), head.max() - head.min(),
			socket.min(), socket.max(), socket.max() - socket.min()])


func _at(bone: String) -> Vector3:
	return _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(bone)).origin


func _tick() -> void:
	_m.clips.update(DT)
	_m.gait.update(DT)
	_m.clips.apply()
	_m.rig.update(DT)
