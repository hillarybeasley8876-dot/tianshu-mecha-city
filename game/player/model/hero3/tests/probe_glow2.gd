extends Node
## scratch: where did `Hero3Glow` actually put the visor, the vent and the drone tips?
##   tools/godot.sh test res://player/model/hero3/tests/probe_glow2.gd

const SCENE := "res://player/model/hero3/hero3_model.tscn"


func _ready() -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	var glow: Hero3Glow = model.rig.glow
	var skel: Skeleton3D = model.skeleton
	for pair in [["visor", glow.visor], ["vent", glow.vent]]:
		var node := pair[1] as MeshInstance3D
		if node == null:
			print("%s MISSING" % pair[0])
			continue
		var mesh := node.mesh as BoxMesh
		print("%-6s bone=%s size=%s" % [pair[0], node.get_parent().name, str(mesh.size)])
	for i in glow.tips.size():
		var tip := glow.tips[i]
		var mesh := tip.mesh as BoxMesh
		print("tip%-2d bone=%-9s pos=%s size=%s" % [i, tip.get_parent().name,
				str(tip.position.snapped(Vector3.ONE * 0.01)), str(mesh.size.snapped(Vector3.ONE * 0.01))])
	print("visor_at %s  vent_at %s" % [str(glow.visor_at.snapped(Vector3.ONE * 0.01)),
			str(glow.vent_at.snapped(Vector3.ONE * 0.01))])
	print("head rest %s" % str(skel.get_bone_global_rest(skel.find_bone("Head")).origin))
	print("spine02 rest %s" % str(skel.get_bone_global_rest(skel.find_bone("Spine02")).origin))
	get_tree().quit(0)
