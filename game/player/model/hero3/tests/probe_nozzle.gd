extends Node
## hero-v3 r9 item 2: where ARE the thruster nozzles on this mesh? (headless, no window)
##   tools/godot.sh test res://player/model/hero3/tests/probe_nozzle.gd -- --bone=BackFrame
##
## The r8 `THRUSTERS` table guessed them -- a bone name, a fraction along the bone and a hand-typed
## offset -- and that is why the plumes floated over the hero's head. This measures the real surface
## instead: every vertex whose dominant bone is the one asked for, in SKELETON space (the rest pose),
## printed as a DEPTH MAP of the rearmost surface. The mech faces -Z, so +Z is behind it and a nozzle
## is a recess: a patch of the map that is markedly SHALLOWER than the plate around it.
##
## `--dump` prints every skinned piece's bounds first, which is how the candidate bones were chosen.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
## Depth-map resolution, in cells across the piece's own bounds.
const COLS := 56
const ROWS := 34
const EMPTY := " "

var skeleton: Skeleton3D
var _bone: String = "BackFrame"
var _dump: bool = false
## `--win=x0,x1,y0,y1` restricts the map to a window of the model, and `--bone=*` takes every bone:
## together they map the whole BACK of the mech rather than one bone's share of it.
var _win: String = ""
## `--ywin=lo,hi` keeps the mouth search inside a height band, and `--nrm=` keeps only vertices whose
## normal is at least that aligned with the exhaust axis -- together they cut the drone blades and the
## pack's side plates out of the measurement and leave the rear face itself.
var _ywin: String = ""


func _ready() -> void:
	_bone = _arg("--bone=", "BackFrame")
	_dump = not _arg("--dump=", "").is_empty()
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	skeleton = model.skeleton
	skeleton.force_update_all_bone_transforms()
	if _dump:
		_dump_pieces()
	_win = _arg("--win=", "")
	_depth_map(_bone)
	if not _arg("--mouth=", "").is_empty():
		_ywin = _arg("--ywin=", "")
		_mouths(_bone, float(_arg("--mouth=", "0.2")), float(_arg("--nrm=", "0.0")))
	print("PASS")
	get_tree().quit(0)


## Every skinned piece: its bind count, vertex count and bounds in SKELETON space.
func _dump_pieces() -> void:
	for n in skeleton.get_children():
		var mi := n as MeshInstance3D
		if mi == null or mi.skin == null or mi.mesh == null:
			continue
		var aabb := AABB()
		var count := 0
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			if bones == null:
				continue
			for i in verts.size():
				var p := _rest_at(mi, bones, i)
				if count == 0:
					aabb = AABB(p, Vector3.ZERO)
				else:
					aabb = aabb.expand(p)
				count += 1
		print("PIECE %-14s binds %3d verts %7d  pos %s  size %s"
				% [mi.name, mi.skin.get_bind_count(), count,
				str(aabb.position.snapped(Vector3.ONE * 0.01)),
				str(aabb.size.snapped(Vector3.ONE * 0.01))])


## The rearmost surface of one bone's armour, as a character map. `.` is the shallowest cell in the
## piece and `@` the deepest (the part that sticks out furthest behind the mech); a cell with no
## geometry is blank. Read it like a contour map seen from behind, +x to the right.
func _depth_map(bone_name: String) -> void:
	var verts := _bone_verts(bone_name)
	if verts.is_empty():
		print("NOZZLE %s has no geometry" % bone_name)
		return
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	if not _win.is_empty():
		var w := _win.split(",")
		aabb.position = Vector3(float(w[0]), float(w[2]), aabb.position.z)
		aabb.size = Vector3(float(w[1]) - float(w[0]), float(w[3]) - float(w[2]), aabb.size.z)
	var grid := PackedFloat32Array()
	grid.resize(COLS * ROWS)
	for i in grid.size():
		grid[i] = -INF
	for v in verts:
		if v.x < aabb.position.x or v.x > aabb.end.x or v.y < aabb.position.y or v.y > aabb.end.y:
			continue
		var cx := clampi(int((v.x - aabb.position.x) / aabb.size.x * COLS), 0, COLS - 1)
		var cy := clampi(int((v.y - aabb.position.y) / aabb.size.y * ROWS), 0, ROWS - 1)
		var k := cy * COLS + cx
		grid[k] = maxf(grid[k], v.z)
	var lo := INF
	var hi := -INF
	for z in grid:
		if is_finite(z):
			lo = minf(lo, z)
			hi = maxf(hi, z)
	print("NOZZLE %s  %d verts  x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f"
			% [bone_name, verts.size(), aabb.position.x, aabb.end.x, aabb.position.y, aabb.end.y,
			lo, hi])
	var ramp := ".:-=+*#@"
	for row in range(ROWS - 1, -1, -1):
		var line := ""
		for col in COLS:
			var z := grid[row * COLS + col]
			if not is_finite(z):
				line += EMPTY
				continue
			var t := (z - lo) / maxf(hi - lo, 0.001)
			line += ramp[clampi(int(t * float(ramp.length() - 1) + 0.5), 0, ramp.length() - 1)]
		print("NOZZLE y%6.2f |%s|" % [aabb.position.y + aabb.size.y * float(row) / float(ROWS), line])
	print("NOZZLE x from %.2f to %.2f in %d columns" % [aabb.position.x, aabb.end.x, COLS])


## Every vertex whose dominant bone is `bone_name`, in skeleton space (the rest pose).
func _bone_verts(bone_name: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in skeleton.get_children():
		var mi := n as MeshInstance3D
		if mi == null or mi.skin == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or verts.is_empty():
				continue
			var per := int(bones.size() / verts.size())
			for i in verts.size():
				var best := -1.0
				var top := 0
				for j in per:
					if weights[i * per + j] > best:
						best = weights[i * per + j]
						top = int(bones[i * per + j])
				if bone_name != "*" and _bind_name(mi, top) != bone_name:
					continue
				out.append(_rest(mi, top) * verts[i])
	return out


## The rest position of vertex `i`: `bone_global_rest * bind_pose * v`, the skinning formula with the
## bone at its rest transform.
func _rest_at(mi: MeshInstance3D, bones: Variant, i: int) -> Vector3:
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(
			mi.mesh.get_surface_count() - 1)[Mesh.ARRAY_VERTEX]
	return _rest(mi, int(bones[i])) * verts[i]


func _rest(mi: MeshInstance3D, bind: int) -> Transform3D:
	return skeleton.get_bone_global_rest(_bind_index(mi, bind)) * mi.skin.get_bind_pose(bind)


func _bind_index(mi: MeshInstance3D, bind: int) -> int:
	var bone := mi.skin.get_bind_bone(bind)
	if bone < 0:
		bone = skeleton.find_bone(String(mi.skin.get_bind_name(bind)))
	return bone


func _bind_name(mi: MeshInstance3D, bind: int) -> String:
	return skeleton.get_bone_name(_bind_index(mi, bind))


## The exhaust MOUTHS of one bone, MEASURED: for each side of the mech, the rearmost `band` metres of
## that bone's armour, its centroid, its mean surface normal (the exhaust axis) and its radius. This
## is what `Hero3Rig.THRUSTERS` is built from -- a measured mouth and a measured axis in the bone's
## own frame, never a hand-typed offset.
func _mouths(bone_name: String, band: float, nrm: float) -> void:
	var verts := _bone_verts(bone_name)
	if verts.is_empty():
		return
	var normals := _bone_normals(bone_name)
	var lo := -INF
	var hi := INF
	if not _ywin.is_empty():
		var w := _ywin.split(",")
		lo = float(w[0])
		hi = float(w[1])
	var out: Array = []
	for side in [-1.0, 1.0]:
		var rear := -INF
		for i in verts.size():
			if _keeps(verts[i], normals[i], side, lo, hi, nrm, -INF, band):
				rear = maxf(rear, verts[i].z)
		if not is_finite(rear):
			continue
		var centre := Vector3.ZERO
		var axis := Vector3.ZERO
		var n := 0
		for i in verts.size():
			if not _keeps(verts[i], normals[i], side, lo, hi, nrm, rear, band):
				continue
			centre += verts[i]
			axis += normals[i]
			n += 1
		if n < 8:
			print("MOUTH %-10s %s side: only %d vertices in the rearmost %.2f m -- no port here"
					% [bone_name, "L" if side < 0.0 else "R", n, band])
			continue
		centre /= float(n)
		axis = axis.normalized() if axis.length() > 0.01 else Vector3.BACK
		if axis.z < 0.0:
			axis = -axis
		var radius := 0.0
		for i in verts.size():
			if not _keeps(verts[i], normals[i], side, lo, hi, nrm, rear, band):
				continue
			radius = maxf(radius, (verts[i] - centre).length())
		out.append({"side": side, "centre": centre, "axis": axis, "r": radius, "n": n})
		print("MOUTH %-10s %s  centre %s  axis %s  r %.2f  n %d  rear z %.2f"
				% [bone_name, "L" if side < 0.0 else "R", str(centre.snapped(Vector3.ONE * 0.01)),
				str(axis.snapped(Vector3.ONE * 0.01)), radius, n, rear])


## Does this vertex belong to the mouth being measured?
func _keeps(v: Vector3, n: Vector3, side: float, lo: float, hi: float, nrm: float, rear: float,
		band: float) -> bool:
	if signf(v.x) != side or v.y < lo or v.y > hi:
		return false
	if is_finite(rear) and v.z < rear - band:
		return false
	return n.z >= nrm


## The rest-pose NORMAL of every vertex `_bone_verts` returns, in the same order.
func _bone_normals(bone_name: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in skeleton.get_children():
		var mi := n as MeshInstance3D
		if mi == null or mi.skin == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or verts.is_empty() or norms.is_empty():
				continue
			var per := int(bones.size() / verts.size())
			for i in verts.size():
				var best := -1.0
				var top := 0
				for j in per:
					if weights[i * per + j] > best:
						best = weights[i * per + j]
						top = int(bones[i * per + j])
				if bone_name != "*" and _bind_name(mi, top) != bone_name:
					continue
				out.append((_rest(mi, top).basis * norms[i]).normalized())
	return out


func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return fallback
