extends Node
## city-kit props mesh audit (headless). For every prop GLB as SHIPPED -- the mesh `PropScatter`
## really loads, not the Tripo source -- it reports position-welded topology: open / non-manifold
## edges, open-boundary loops (holes, with perimeter and centre), connected shells (detached parts),
## winding against the vertex normals and the signed volume (inverted normals), degenerate and
## zero-UV-area triangles (smears), bounds against `PropPlacer.PROP_SIZE_M` and the albedo size.
## Ported from the lead's acceptance `probe_mesh.gd` so the numbers are comparable with theirs.
##   tools/godot.sh test res://world/kit/tests/probe_props.gd -- --qa-only=crane,ac_cluster
## `tools/citykit/prop_audit.py <log>` joins this output with `blender/props/prop_table.py`'s
## budgets and prints the markdown table the brief asks for.

const WELD := 0.0001

var _only: PackedStringArray = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-only="):
			_only = arg.trim_prefix("--qa-only=").split(",", false)
	var props: Array = PropPlacer.PROP_SIZE_M.keys()
	props.sort()
	for prop: Variant in props:
		if not _only.is_empty() and not _only.has(String(prop)):
			continue
		_audit(StringName(prop))
	print("PROBE done")
	get_tree().quit(0)


func _audit(name: StringName) -> void:
	var path := "res://world/props/meshes/%s.glb" % name
	var mesh := PropScatter.load_mesh(name)
	if mesh == null:
		print("PROBE %s FAIL cannot load %s" % [name, path])
		return
	var weld_ids: Dictionary = {}
	var positions := PackedVector3Array()
	var tris := PackedInt32Array()
	var tri_flip := 0
	var tri_degenerate := 0
	var tri_zero_uv := 0
	var verts_total := 0
	var signed_volume := 0.0
	var tex_info: PackedStringArray = []
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		verts_total += verts.size()
		var local_ids := PackedInt32Array()
		local_ids.resize(verts.size())
		for i in verts.size():
			var p := verts[i]
			var key := Vector3i(roundi(p.x / WELD), roundi(p.y / WELD), roundi(p.z / WELD))
			if not weld_ids.has(key):
				weld_ids[key] = positions.size()
				positions.append(p)
			local_ids[i] = int(weld_ids[key])
		var idx := PackedInt32Array()
		if index is PackedInt32Array and (index as PackedInt32Array).size() > 0:
			idx = index as PackedInt32Array
		else:
			for i in verts.size():
				idx.append(i)
		var has_normals: bool = normals is PackedVector3Array \
				and (normals as PackedVector3Array).size() == verts.size()
		var has_uv: bool = uvs is PackedVector2Array \
				and (uvs as PackedVector2Array).size() == verts.size()
		for t in range(0, idx.size() - 2, 3):
			var a := verts[idx[t]]
			var b := verts[idx[t + 1]]
			var c := verts[idx[t + 2]]
			var front := (c - a).cross(b - a)      # Godot front faces are clockwise
			var tri_area := front.length() * 0.5
			signed_volume += a.dot(front) / 6.0
			var w0 := local_ids[idx[t]]
			var w1 := local_ids[idx[t + 1]]
			var w2 := local_ids[idx[t + 2]]
			if w0 == w1 or w1 == w2 or w0 == w2 or tri_area < 1e-10:
				tri_degenerate += 1
			else:
				tris.append(w0)
				tris.append(w1)
				tris.append(w2)
			if has_normals:
				var nn := normals as PackedVector3Array
				if front.dot(nn[idx[t]] + nn[idx[t + 1]] + nn[idx[t + 2]]) < 0.0:
					tri_flip += 1
			if has_uv:
				var uu := uvs as PackedVector2Array
				var e1 := uu[idx[t + 1]] - uu[idx[t]]
				var e2 := uu[idx[t + 2]] - uu[idx[t]]
				if absf(e1.x * e2.y - e1.y * e2.x) < 1e-10:
					tri_zero_uv += 1
		var mat := mesh.surface_get_material(s)
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
			var tex := (mat as BaseMaterial3D).albedo_texture
			tex_info.append("%dx%d" % [tex.get_width(), tex.get_height()])
	var topo := _topology(positions, tris)
	var box := _bounds(positions)
	var size := box.size
	var target := float(PropPlacer.PROP_SIZE_M.get(name, 0.0))
	var longest := maxf(size.x, maxf(size.y, size.z))
	var tri_total := tris.size() / 3 + tri_degenerate
	print(("PROBE %s tris %d verts %d welded %d | longest %.2f target %.1f (%+.0f%%) base_y %.3f"
			+ " size %.2f,%.2f,%.2f | open %d (%.2f%%) nonmanifold %d holes %d largest_hole %.3f m at %s"
			+ " | shells %d small %d floating %d (largest %d tris) | flip %d (%.2f%%) vol %.1f m3"
			+ " | degenerate %d zero_uv %d | albedo %s")
			% [name, tri_total, verts_total, positions.size(), longest, target,
			(longest / maxf(target, 0.001) - 1.0) * 100.0, box.position.y, size.x, size.y, size.z,
			topo["open"], 100.0 * float(topo["open"]) / maxf(float(topo["edges"]), 1.0),
			topo["nonmanifold"], topo["loops"], topo["largest_loop"], _v(topo["largest_loop_at"]),
			topo["shells"], topo["small"], topo["floating"], topo["floating_tris"], tri_flip,
			100.0 * float(tri_flip) / maxf(float(tri_total), 1.0), signed_volume,
			tri_degenerate, tri_zero_uv, ",".join(tex_info)])


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


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
			for pair in [[a, b], [b, a]]:
				var u: int = pair[0]
				var v: int = pair[1]
				if not boundary_adj.has(u):
					boundary_adj[u] = PackedInt32Array()
				var la: PackedInt32Array = boundary_adj[u]
				la.append(v)
				boundary_adj[u] = la
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
	var main_box: AABB = shell_box[main] if main >= 0 else AABB()
	var grown := main_box.grow(maxf(main_box.size.length() * 0.01, 0.05))
	for r: int in shell_tris:
		if r == main:
			continue
		var n := int(shell_tris[r])
		if float(n) < 0.005 * float(total):
			small += 1
		if not grown.intersects(shell_box[r] as AABB):
			floating += 1
			floating_tris = maxi(floating_tris, n)
	return {"edges": edges.size(), "open": open, "nonmanifold": nonmanifold, "loops": loops,
			"largest_loop": largest, "largest_loop_at": largest_at, "shells": shell_tris.size(),
			"small": small, "floating": floating, "floating_tris": floating_tris}
