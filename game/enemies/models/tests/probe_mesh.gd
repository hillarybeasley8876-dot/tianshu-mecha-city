extends Node
## Acceptance asset-QA mesh audit (lead acceptance team; scratch, never shipped). Headless.
## For every monster GLB as SHIPPED (the imported scene Godot really loads):
## position-welded topology (open / non-manifold edges, open-boundary loops = holes with their
## perimeter and centre), connected shells (detached / floating parts), winding against the vertex
## normals and the signed volume (inverted normals), degenerate and zero-UV-area triangles (smears),
## skin weights (unweighted vertices), bounds vs the SPEC / prop table size, albedo texture size.
##   godot --headless --path game -s res://tools/test_host.gd -- \
##       --test=res://enemies/models/tests/probe_mesh.gd --timeout=900 [--qa-only=ripper,bus]

const WELD := 0.0001
const MONSTERS: Array[StringName] = [&"ripper", &"mantis", &"spitter", &"harrier", &"juggernaut",
		&"titan", &"titan_skyline", &"hive"]
const MONSTER_SIZE: Dictionary = {
	&"ripper": [6.0, "length"], &"mantis": [14.0, "height"], &"spitter": [12.0, "height"],
	&"harrier": [16.0, "span"], &"juggernaut": [22.0, "height"], &"titan": [60.0, "height"],
	&"titan_skyline": [60.0, "height"], &"hive": [60.0, "height"],
}

var _only: PackedStringArray = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-only="):
			_only = arg.trim_prefix("--qa-only=").split(",", false)
	for type in MONSTERS:
		if _skip(type):
			continue
		_audit_scene("MON", type, "res://enemies/models/%s/%s.glb" % [type, type])
	print("AUDIT done")
	get_tree().quit(0)


func _skip(name: StringName) -> bool:
	return not _only.is_empty() and not _only.has(String(name))


func _audit_scene(kind: String, name: StringName, path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		print("AUDIT %s %s FAIL cannot load %s" % [kind, name, path])
		return
	var root := packed.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	var total_box := AABB()
	var first := true
	for mi in meshes:
		var box := _audit_mesh(kind, name, mi, root)
		total_box = box if first else total_box.merge(box)
		first = false
	var size := total_box.size
	var line := "AUDIT %s %s BOUNDS min %s size %s" % [kind, name, _v(total_box.position), _v(size)]
	print(line)
	root.free()


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, out)


func _xf_to_root(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	if root is Node3D:
		xf = (root as Node3D).transform * xf
	return xf


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func _audit_mesh(kind: String, name: StringName, mi: MeshInstance3D, root: Node) -> AABB:
	var mesh := mi.mesh
	var xf := _xf_to_root(mi, root)
	var weld_ids: Dictionary = {}
	var positions := PackedVector3Array()
	var tris := PackedInt32Array()      # welded ids, 3 per triangle
	var tri_flip := 0
	var tri_degenerate := 0
	var tri_zero_uv := 0
	var uv_outside := 0
	var verts_total := 0
	var unweighted := 0
	var max_influences := 0
	var signed_volume := 0.0
	var area := 0.0
	var tex_info: PackedStringArray = []
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
		verts_total += verts.size()
		var local_ids := PackedInt32Array()
		local_ids.resize(verts.size())
		for i in verts.size():
			var p := xf * verts[i]
			var key := Vector3i(roundi(p.x / WELD), roundi(p.y / WELD), roundi(p.z / WELD))
			if not weld_ids.has(key):
				weld_ids[key] = positions.size()
				positions.append(p)
			local_ids[i] = int(weld_ids[key])
		if weights is PackedFloat32Array and (weights as PackedFloat32Array).size() > 0:
			var w := weights as PackedFloat32Array
			var per := w.size() / maxi(verts.size(), 1)
			for i in verts.size():
				var sum := 0.0
				var used := 0
				for k in per:
					var x := w[i * per + k]
					sum += x
					if x > 0.0:
						used += 1
				max_influences = maxi(max_influences, used)
				if sum < 0.5:
					unweighted += 1
		var idx := PackedInt32Array()
		if index is PackedInt32Array and (index as PackedInt32Array).size() > 0:
			idx = index as PackedInt32Array
		else:
			for i in verts.size():
				idx.append(i)
		var has_normals: bool = normals is PackedVector3Array and (normals as PackedVector3Array).size() == verts.size()
		var has_uv: bool = uvs is PackedVector2Array and (uvs as PackedVector2Array).size() == verts.size()
		for t in range(0, idx.size() - 2, 3):
			var i0 := idx[t]
			var i1 := idx[t + 1]
			var i2 := idx[t + 2]
			var a := xf * verts[i0]
			var b := xf * verts[i1]
			var c := xf * verts[i2]
			var front := (c - a).cross(b - a)      # Godot front faces are clockwise
			var tri_area := front.length() * 0.5
			area += tri_area
			signed_volume += a.dot(front) / 6.0
			var w0 := local_ids[i0]
			var w1 := local_ids[i1]
			var w2 := local_ids[i2]
			if w0 == w1 or w1 == w2 or w0 == w2 or tri_area < 1e-10:
				tri_degenerate += 1
			else:
				tris.append(w0)
				tris.append(w1)
				tris.append(w2)
			if has_normals:
				var nn := (normals as PackedVector3Array)
				var avg := xf.basis * (nn[i0] + nn[i1] + nn[i2])
				if front.dot(avg) < 0.0:
					tri_flip += 1
			if has_uv:
				var uu := (uvs as PackedVector2Array)
				var e1 := uu[i1] - uu[i0]
				var e2 := uu[i2] - uu[i0]
				if absf(e1.x * e2.y - e1.y * e2.x) < 1e-10:
					tri_zero_uv += 1
				for uv in [uu[i0], uu[i1], uu[i2]]:
					var q: Vector2 = uv
					if q.x < -0.001 or q.x > 1.001 or q.y < -0.001 or q.y > 1.001:
						uv_outside += 1
		var mat := mesh.surface_get_material(s)
		if mi.get_surface_override_material(s) != null:
			mat = mi.get_surface_override_material(s)
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
			var tex := (mat as BaseMaterial3D).albedo_texture
			tex_info.append("%dx%d" % [tex.get_width(), tex.get_height()])
	var topo := _topology(positions, tris)
	var box := _bounds(positions)
	var tri_total := tris.size() / 3 + tri_degenerate
	print(("AUDIT %s %s MESH %s verts %d welded %d tris %d | open_edges %d (%.2f%%) nonmanifold %d | holes %d"
			+ " largest_hole %.2f m at %s | shells %d main %.1f%% small %d floating %d (largest floating %d tris %s)"
			+ " | flip_vs_normals %d (%.2f%%) signed_vol %.1f m3 | degenerate %d zero_uv %d uv_out %d"
			+ " | unweighted %d max_infl %d | albedo %s") % [kind, name, mi.name, verts_total,
			positions.size(), tri_total, topo["open"], 100.0 * float(topo["open"]) / maxf(float(topo["edges"]), 1.0),
			topo["nonmanifold"], topo["loops"], topo["largest_loop"], _v(topo["largest_loop_at"]),
			topo["shells"], topo["main_share"] * 100.0, topo["small"], topo["floating"],
			topo["floating_tris"], _v(topo["floating_at"]), tri_flip,
			100.0 * float(tri_flip) / maxf(float(tri_total), 1.0), signed_volume, tri_degenerate,
			tri_zero_uv, uv_outside, unweighted, max_influences, ",".join(tex_info)])
	return box


func _bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


func _find(parent: PackedInt32Array, i: int) -> int:
	var r := i
	while parent[r] != r:
		r = parent[r]
	var n := i
	while parent[n] != r:
		var nx := parent[n]
		parent[n] = r
		n = nx
	return r


func _topology(positions: PackedVector3Array, tris: PackedInt32Array) -> Dictionary:
	var count := positions.size()
	var edges: Dictionary = {}
	var parent := PackedInt32Array()
	parent.resize(count)
	for i in count:
		parent[i] = i
	for t in range(0, tris.size(), 3):
		var ids := [tris[t], tris[t + 1], tris[t + 2]]
		for e in 3:
			var a: int = ids[e]
			var b: int = ids[(e + 1) % 3]
			var key := mini(a, b) * count + maxi(a, b)
			edges[key] = int(edges.get(key, 0)) + 1
			var ra := _find(parent, a)
			var rb := _find(parent, b)
			if ra != rb:
				parent[ra] = rb
	var open := 0
	var nonmanifold := 0
	var boundary_adj: Dictionary = {}
	for key: int in edges:
		var c := int(edges[key])
		if c == 1:
			open += 1
			var a := key / count
			var b := key % count
			if not boundary_adj.has(a):
				boundary_adj[a] = PackedInt32Array()
			if not boundary_adj.has(b):
				boundary_adj[b] = PackedInt32Array()
			var la: PackedInt32Array = boundary_adj[a]
			la.append(b)
			boundary_adj[a] = la
			var lb: PackedInt32Array = boundary_adj[b]
			lb.append(a)
			boundary_adj[b] = lb
		elif c > 2:
			nonmanifold += 1
	# boundary loops: connected components of the boundary graph, perimeter in metres
	var seen: Dictionary = {}
	var loops := 0
	var largest := 0.0
	var largest_at := Vector3.ZERO
	for start: int in boundary_adj:
		if seen.has(start):
			continue
		loops += 1
		var perimeter := 0.0
		var centre := Vector3.ZERO
		var n := 0
		var stack: Array[int] = [start]
		seen[start] = true
		while not stack.is_empty():
			var v: int = stack.pop_back()
			centre += positions[v]
			n += 1
			for w: int in (boundary_adj[v] as PackedInt32Array):
				if v < w:
					perimeter += positions[v].distance_to(positions[w])
				if not seen.has(w):
					seen[w] = true
					stack.append(w)
		if perimeter > largest:
			largest = perimeter
			largest_at = centre / float(maxi(n, 1))
	# shells
	var shell_tris: Dictionary = {}
	var shell_box: Dictionary = {}
	for t in range(0, tris.size(), 3):
		var r := _find(parent, tris[t])
		shell_tris[r] = int(shell_tris.get(r, 0)) + 1
		for k in 3:
			var p := positions[tris[t + k]]
			if shell_box.has(r):
				shell_box[r] = (shell_box[r] as AABB).expand(p)
			else:
				shell_box[r] = AABB(p, Vector3.ZERO)
	var main := -1
	var main_tris := 0
	for r: int in shell_tris:
		if int(shell_tris[r]) > main_tris:
			main_tris = int(shell_tris[r])
			main = r
	var total := maxi(tris.size() / 3, 1)
	var small := 0
	var floating := 0
	var floating_tris := 0
	var floating_at := Vector3.ZERO
	var main_box: AABB = shell_box[main] if main >= 0 else AABB()
	var grown := main_box.grow(maxf(main_box.size.length() * 0.01, 0.05))
	for r: int in shell_tris:
		if r == main:
			continue
		var n := int(shell_tris[r])
		if float(n) < 0.005 * float(total):
			small += 1
		var b: AABB = shell_box[r]
		if not grown.intersects(b):
			floating += 1
			if n > floating_tris:
				floating_tris = n
				floating_at = b.get_center()
	return {"edges": edges.size(), "open": open, "nonmanifold": nonmanifold, "loops": loops,
			"largest_loop": largest, "largest_loop_at": largest_at, "shells": shell_tris.size(),
			"main_share": float(main_tris) / float(total), "small": small, "floating": floating,
			"floating_tris": floating_tris, "floating_at": floating_at}
