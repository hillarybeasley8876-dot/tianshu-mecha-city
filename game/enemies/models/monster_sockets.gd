class_name MonsterSockets
extends RefCounted
## The socket markers on a HUSK monster (monster-assets): `mouth`/`muzzle`, `claw_l`/`claw_r`,
## `core`, and a `weak_*` marker at every violet core (brief: the enemies unit puts its weak-point
## Hurtboxes and Targetables there).
##
## Split out of `monster_model.gd` (lead split r1). The positions come from `<type>_rig.json` in plain
## model space; a socket bound to a bone rides the animation through a BoneAttachment3D, and the
## bone-local offset is solved once from the rest pose so no bone-axis conversion leaks into the
## build.

var _markers: Dictionary = {}
var _body_type: StringName = &""


func setup(visual: Node3D, skeleton: Skeleton3D, rig: Dictionary,
		body_type: StringName) -> void:
	_body_type = body_type
	var table := rig.get("sockets", {}) as Dictionary
	for socket_name: String in table:
		var entry := table[socket_name] as Dictionary
		var target := _to_vector(entry.get("pos", [0, 0, 0]))
		var marker := Marker3D.new()
		marker.name = socket_name
		var bone := String(entry.get("bone", ""))
		var index := skeleton.find_bone(bone) if skeleton != null and bone != "" else -1
		if index < 0:
			visual.add_child(marker)
			marker.position = target
		else:
			var attach := BoneAttachment3D.new()
			attach.name = "%s_attach" % socket_name
			attach.bone_idx = index
			skeleton.add_child(attach)
			attach.add_child(marker)
			var rest := skeleton.get_bone_global_pose(index)
			marker.position = rest.basis.inverse() * (target - rest.origin)
		_markers[StringName(socket_name)] = marker
	for required: StringName in [&"core"]:
		if not _markers.has(required):
			push_warning("MonsterModel(%s): no '%s' socket" % [body_type, required])


## The marker for `name`, or null when this type has none — the caller warns and answers with its
## visual root, which is the placeholder's contract.
func marker(name: StringName) -> Node3D:
	return _markers.get(name) as Node3D


## Every weak-point marker this model carries, in name order (`weak_0` … `weak_3`).
func weak_points() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var names: Array = _markers.keys()
	names.sort()
	for key: StringName in names:
		if String(key).begins_with("weak_"):
			out.append(_markers[key] as Node3D)
	return out


func _to_vector(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var a := value as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	push_warning("MonsterModel(%s): socket position %s is not a 3-array" % [_body_type, value])
	return Vector3.ZERO
