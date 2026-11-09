extends Node
## scratch: measure where the visor / chest vent / drone tips sit on the body mesh, in skeleton
## space, so `hero3_glow.gd` can place modelled emissive parts on measured numbers.
##   tools/godot.sh test res://player/model/hero3/tests/probe_glow.gd

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const BONES: Array[String] = ["Head", "Spine02", "Spine01", "Drone_1", "Drone_5", "Drone_7"]


func _ready() -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	var skel: Skeleton3D = model.skeleton
	var body := _find(model, "Hero3Body") as MeshInstance3D
	if body == null:
		print("FAIL no Hero3Body")
		get_tree().quit(1)
		return
	var arrays := body.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var bind := _bind(body, skel)
	var per := int(bones.size() / verts.size())
	for bone_name in BONES:
		var want := skel.find_bone(bone_name)
		var pts: Array[Vector3] = []
		for i in verts.size():
			var top := -1
			var w := -1.0
			for j in per:
				if weights[i * per + j] > w:
					w = weights[i * per + j]
					top = int(bones[i * per + j])
			if top >= 0 and bind[top] == want:
				pts.append(verts[i])
		_report(bone_name, pts)
	get_tree().quit(0)


func _report(bone_name: String, pts: Array[Vector3]) -> void:
	if pts.is_empty():
		print("BONE %s  EMPTY" % bone_name)
		return
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	print("BONE %-9s n=%5d  x[%.2f %.2f] y[%.2f %.2f] z[%.2f %.2f]"
			% [bone_name, pts.size(), lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])
	# front-most z per horizontal slice, so a visor band is a measured choice
	var slices := 8
	for s in slices:
		var y0 := lerpf(lo.y, hi.y, float(s) / slices)
		var y1 := lerpf(lo.y, hi.y, float(s + 1) / slices)
		var fz := INF
		var fx := Vector2(INF, -INF)
		for p in pts:
			if p.y < y0 or p.y > y1:
				continue
			fz = minf(fz, p.z)
			fx.x = minf(fx.x, p.x)
			fx.y = maxf(fx.y, p.x)
		if fz < INF:
			print("   y[%.2f %.2f]  front z=%.2f  x[%.2f %.2f]" % [y0, y1, fz, fx.x, fx.y])


func _bind(mi: MeshInstance3D, skel: Skeleton3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	for b in mi.skin.get_bind_count():
		var bone := mi.skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(String(mi.skin.get_bind_name(b)))
		out.append(bone)
	return out


func _find(root: Node, name: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.name == name:
			return node
		stack.append_array(node.get_children())
	return null
