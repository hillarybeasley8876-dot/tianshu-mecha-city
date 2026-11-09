class_name ArtShadows
extends RefCounted
## city-art r13: who casts a sun shadow. The sun's shadow pass was the single biggest environment cost
## in the frame budget (3.7 ms of a 26 ms street frame), and most of what it drew was dressing smaller
## than a mech: 1 800 props, 1 210 roof units, signs, cables and cloth. A 1 m crate's shadow is a few
## pixels of contact darkening; the pass it costs is not.
##
## Two rules, both applied at load and both reversible with a flag:
##   `small`  — a mesh whose own AABB is under `SMALL_M` in every axis stops casting.
##   `far`    — the far tier (city-kit's `_far` LODs, city-build's `_hlod` merges and the skyline ring)
##              stops casting: it is beyond the shadow distance anyway, or nearly.
##
##   tools/godot.sh test res://world/art/tests/test_shadows.gd
## `--shadows=all` puts every rule back for an A/B, `--shadows=none` is the "no dressing casts" arm.

## A mesh smaller than this in every axis is dressing, not architecture.
const SMALL_M := 2.0
## Node-name fragments that mark the far tier.
const FAR_NAMES: Array[String] = ["_far", "_hlod", "Skyline"]


## Applies both rules under `root`. Returns {"small": n, "far": n} so the caller can print what it did.
static func apply(root: Node, mode: String = "") -> Dictionary:
	var policy := mode if not mode.is_empty() else Game.flag("shadows", "auto")
	if policy == "all":
		return {"small": 0, "far": 0}
	var small := 0
	var far := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var gi := n as GeometryInstance3D
		if gi != null and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			if policy != "none" and is_far(n):
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				far += 1
			elif is_small(size_of(gi)):
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				small += 1
		stack.append_array(n.get_children())
	return {"small": small, "far": far}


## Is this mesh dressing? Every axis has to be under the threshold: a 20 m banner is 0.05 m thick but it
## is not a small object, and a flat road decal is not either.
static func is_small(size: Vector3) -> bool:
	return size.x <= SMALL_M and size.y <= SMALL_M and size.z <= SMALL_M


## Is this node part of the far tier? The name is the contract: city-kit names its LODs `<id>_far` and
## city-build names its merged blocks `<tile>_hlod`.
static func is_far(node: Node) -> bool:
	var n := node as Node
	while n != null:
		for frag in FAR_NAMES:
			if String(n.name).contains(frag):
				return true
		n = n.get_parent()
	return false


## The size of the thing that is actually instanced: a MultiMesh's own mesh, not the batch's AABB, or
## one prop scattered over a whole district would look like a 400 m object. A mesh-less node answers
## INF, so it is never mistaken for dressing.
static func size_of(gi: GeometryInstance3D) -> Vector3:
	var mesh: Mesh = null
	var mmi := gi as MultiMeshInstance3D
	if mmi != null and mmi.multimesh != null:
		mesh = mmi.multimesh.mesh
	else:
		mesh = (gi as MeshInstance3D).mesh if gi is MeshInstance3D else null
	if mesh == null:
		return Vector3(INF, INF, INF)
	return mesh.get_aabb().size.abs()
