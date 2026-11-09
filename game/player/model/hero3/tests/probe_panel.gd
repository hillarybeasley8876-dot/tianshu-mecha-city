extends Node
## scratch: where do the glow panels' corners actually sit relative to the armour surface?
##   tools/godot.sh test res://player/model/hero3/tests/probe_panel.gd

const SCENE := "res://player/model/hero3/hero3_model.tscn"


func _ready() -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	var skel: Skeleton3D = model.skeleton
	var glow: Hero3Glow = model.rig.glow
	for pair in [["visor", glow.visor], ["vent", glow.vent]]:
		var which: String = pair[0]
		for node in pair[1] as Array[MeshInstance3D]:
			var mi := node as MeshInstance3D
			var xf := skel.global_transform * mi.global_transform
			var m := mi.mesh as Mesh
			var aabb := m.get_aabb()
			print("%s panel aabb %s" % [which, str(aabb)])
			var arrays := m.surface_get_arrays(0)
			var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var line := ""
			for i in 13:
				line += " %.2f" % vs[i * 7].z
			print("   bottom row z across the 13 columns:%s" % line)
			line = ""
			for i in 13:
				line += " %.2f" % vs[i * 7 + 3].z
			print("   middle row z:%s" % line)
			for corner in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)]:
				var p: Vector3 = xf * (aabb.position + aabb.size * corner)
				print("   corner %s -> skeleton %s" % [str(corner), str(p.snapped(Vector3.ONE * 0.01))])
	# the armour surface's own front z under each panel's footprint
	var body: MeshInstance3D = model.rig.body_mesh()
	var arrays := body.mesh.surface_get_arrays(model.rig.shade.armour_surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for band in [["Head", 13.6, 16.1], ["Spine02", 11.1, 13.6]]:
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		var n := 0
		for v in verts:
			if v.y < band[1] or v.y > band[2]:
				continue
			lo = lo.min(v)
			hi = hi.max(v)
			n += 1
		print("%s band y %s..%s  x %s..%s  z %s..%s  (%d verts)"
				% [band[0], str(snappedf(lo.y, 0.01)), str(snappedf(hi.y, 0.01)),
				str(snappedf(lo.x, 0.01)), str(snappedf(hi.x, 0.01)),
				str(snappedf(lo.z, 0.01)), str(snappedf(hi.z, 0.01)), n])
		# the front profile across x at the panel's own height
		var y_mid: float = (band[1] + band[2]) * 0.5
		var line := ""
		for i in 13:
			var x: float = lerpf(lo.x, hi.x, float(i) / 12.0)
			var front := INF
			for v in verts:
				if absf(v.x - x) > 0.12 or absf(v.y - y_mid) > 0.25:
					continue
				front = minf(front, v.z)
			line += " %.2f" % (front if front < INF else 99.0)
		print("   front z across x at y=%.1f:%s" % [y_mid, line])
	for i in 30:
		model.rig.update(1.0 / 120.0)
	for pair in [["visor", glow.visor], ["vent", glow.vent]]:
		for node in pair[1] as Array[MeshInstance3D]:
			var mat := (node as MeshInstance3D).material_override as ShaderMaterial
			var keys: Array[StringName] = [&"glow_color", &"glow_gain", &"core_gain", &"stripes",
					&"centre", &"feather", &"flat_mask", &"cavity_color", &"bar_color"]
			var line := ""
			for k in keys:
				line += " %s=%s" % [k, str(mat.get_shader_parameter(k))]
			print("%s mat:%s" % [pair[0], line])
	print("glow report ", glow.report())
	print("DONE")
	get_tree().quit(0)
