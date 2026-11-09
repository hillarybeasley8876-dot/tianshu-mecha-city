extends Node3D
## Stand-in hero for the fx unit's afterimage work (fx/tests only): the feel director ghosts
## `Game.player.model()`, so the stand-in only has to answer `model()` with a node that carries the
## meshes — a single MeshInstance3D in `test_feel.gd`, the placeholder mech in the gallery.
## AfterimagePool.spawn() walks the whole subtree, so a rig root works as well as a bare mesh.

var _model: Node3D = null


func model() -> Node3D:
	if _model == null:
		_model = self
		for child in get_children():
			if child is Node3D:
				_model = child as Node3D
				break
	return _model
