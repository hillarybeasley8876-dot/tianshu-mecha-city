class_name Hero3Panel
extends RefCounted
## The conformed glow sheet for one opening on the Tianshu (hero-v3, lead r8 item 2).
##
## r7 built the visor and the chest grille as FLAT quads placed at the frontmost point under their own
## footprint. On a domed helm that is a tangent plane: measured, the visor touched the armour at the
## midline and floated 0.40 m in front of it at both ends, which is the glowing rod the lead saw
## sticking out of the side of the helmet. Every vertex here is a sample of the real surface plus
## `PROUD`, so the sheet's silhouette IS the armour's.
##
## `Hero3Glow` owns the material and the placement on the skeleton; this file owns the geometry.

## Panel grid resolution. The visor is 1.1 x 0.25 m and the chest 0.8 x 0.7 m, so 13 x 7 samples put
## a vertex every 5-10 cm -- fine enough that the chord between two of them cannot leave the armour's
## silhouette by a visible amount, coarse enough that the whole panel is 144 triangles.
const GRID := Vector2i(13, 7)
## How far in front of the measured surface a panel sits. 3 cm of protrusion on a 16 m mech is
## invisible and it guarantees the panel is never z-fought into the armour.
const PROUD := 0.03
## How much of its nominal width a panel gives up before it is declared unplaceable: the plate under
## it has to reach both ends, and a panel that hangs off the edge of the helm is the rod the lead saw.
const SHRINK_STEPS := 6
## How far behind the sheet's own median a sample may sit before it is treated as a miss. The armour
## is a set of plates with gaps between them, and a sample in a gap finds whatever is behind.
const CLAMP_BAND := 0.30
## One opening's sheet, as `{"mesh": ArrayMesh, "at": Vector3}` in SKELETON space, or `{}` when the
## plate underneath will not carry one. `axis_x` is the bone's own x: both openings are on the body's
## MIDLINE, so the panel is centred on the bone and not on the midpoint of the patch -- the helm's
## bounding box runs x -1.18..1.48 because of the crest, and centring on the midpoint put the visor
## 50 cm off the face.
static func build(pts: Array[Vector3], spec: Dictionary, axis_x: float) -> Dictionary:
	if pts.size() < 8:
		return {}
	var surface := Hero3Surface.new()
	surface.build(pts)
	var place := _place(pts, spec, axis_x, surface)
	if place.is_empty():
		return {}
	var half_w: float = place["half_w"]
	var panel_h: float = place["panel_h"]
	var centre_y: float = place["centre_y"]
	var mesh := _conform(surface, axis_x, centre_y, half_w, panel_h)
	if mesh == null:
		return {}
	return {"mesh": mesh, "at": Vector3(axis_x, centre_y, place["front"])}


## Where the opening sits and how wide it may be. The nominal width comes off the front patch exactly
## as it did in r7; what is new is that it is then SHRUNK until the plate underneath actually covers
## every corner, because a panel that overhangs the helm is the artefact the lead reported.
static func _place(pts: Array[Vector3], spec: Dictionary, axis_x: float, surface: Hero3Surface) -> Dictionary:
	var lo := Vector3(INF, INF, INF)
	for p in pts:
		lo = lo.min(p)
	# the front face: everything within `depth` of the frontmost point
	var flo := Vector3(INF, INF, INF)
	var fhi := -flo
	var seen := 0
	for p in pts:
		if p.z > lo.z + float(spec["depth"]):
			continue
		flo = flo.min(p)
		fhi = fhi.max(p)
		seen += 1
	if seen < 4:
		return {}
	var height: float = maxf(fhi.y - flo.y, 0.01)
	var panel_h: float = height * float(spec["span"])
	var centre_y: float = flo.y + height * float(spec["drop"]) + panel_h * 0.5
	# the widest panel that still fits inside the patch on BOTH sides of the midline
	var half_w: float = minf(fhi.x - axis_x, axis_x - flo.x) * float(spec["width"])
	var front := INF
	for step in SHRINK_STEPS:
		front = INF
		var covered := true
		var radius := _cell_radius(half_w, panel_h)
		for corner in [Vector2(-half_w, -panel_h), Vector2(half_w, -panel_h),
				Vector2(-half_w, panel_h), Vector2(half_w, panel_h), Vector2(0.0, 0.0)]:
			var hit := surface.front(axis_x + corner.x, centre_y + corner.y * 0.5, radius)
			if hit.z == INF:
				covered = false
				break
			front = minf(front, hit.z)
		if covered:
			return {"half_w": maxf(half_w, 0.05), "panel_h": panel_h, "centre_y": centre_y,
					"front": front}
		half_w *= 0.75
		panel_h *= 0.90
	return {}


## The radius a sheet sample has to look over to be provably in front of the mesh: the panel's own
## cell diagonal. Every surface point lies inside the disc of every corner of its cell, so a corner
## placed at `front(x, y, r) - PROUD` is in front of all of them and so is the triangle between.
static func _cell_radius(half_w: float, panel_h: float) -> float:
	var dx := half_w * 2.0 / float(GRID.x - 1)
	var dy := panel_h / float(GRID.y - 1)
	return sqrt(dx * dx + dy * dy) * 1.15


## A GRID x GRID sheet whose every vertex is a sample of the armour surface pushed `PROUD` along -Z,
## with normals taken from the sheet itself so the gold bars light like the trim they sit beside.
##
## The armour is a set of separate PLATES, so there are gaps in it, and a sample that lands in a gap
## finds whatever is behind -- measured, a visor vertex came back 1.4 m further back than its
## neighbours, which would fold the sheet through the helmet. Samples more than `CLAMP` behind the
## sheet's own median are therefore treated as misses and filled from their neighbours, so the sheet
## stays a smooth cap on the front of the plate no matter what the mesh has underneath it.
static func _conform(surface: Hero3Surface, axis_x: float, centre_y: float, half_w: float,
		panel_h: float) -> ArrayMesh:
	var nx := GRID.x
	var ny := GRID.y
	var radius := _cell_radius(half_w, panel_h)
	var count := nx * ny
	var pos := PackedVector3Array()
	pos.resize(count)
	var uv := PackedVector2Array()
	uv.resize(count)
	var z := PackedFloat32Array()
	z.resize(count)
	var good := PackedByteArray()
	good.resize(count)
	var hits := PackedFloat32Array()
	for j in ny:
		for i in nx:
			var k := j * nx + i
			var u := float(i) / float(nx - 1)
			var v := float(j) / float(ny - 1)
			var x := axis_x + (u - 0.5) * half_w * 2.0
			var y := centre_y + (v - 0.5) * panel_h
			pos[k] = Vector3(x, y, 0.0)
			uv[k] = Vector2(u, v)
			var hit := surface.front(x, y, radius)
			if hit.z < INF:
				z[k] = hit.z
				good[k] = 1
				hits.append(hit.z)
			else:
				z[k] = INF
	if hits.is_empty():
		return null
	var med := _median(hits)
	for k in count:
		if good[k] == 1 and z[k] > med + CLAMP_BAND:
			good[k] = 0
	z = _fill(z, good, nx, ny, med)
	for k in count:
		pos[k].z = z[k] - PROUD
	var nrm := PackedVector3Array()
	nrm.resize(count)
	for j in ny:
		for i in nx:
			var a: Vector3 = pos[j * nx + mini(i + 1, nx - 1)] - pos[j * nx + maxi(i - 1, 0)]
			var b: Vector3 = pos[mini(j + 1, ny - 1) * nx + i] - pos[maxi(j - 1, 0) * nx + i]
			var n := b.cross(a)
			# the sheet is built left-to-right and bottom-to-top, so its natural normal faces +Z; the
			# mech faces -Z, so the outward one is the other way round
			nrm[j * nx + i] = (-n).normalized() if n.length_squared() > 1e-9 else Vector3.BACK
	var idx := PackedInt32Array()
	for j in ny - 1:
		for i in nx - 1:
			var k := j * nx + i
			idx.append_array(PackedInt32Array([k, k + 1, k + nx, k + 1, k + nx + 1, k + nx]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Replace every rejected sample with the mean of the valid ones around it, sweeping until the sheet
## is closed. Three passes cover a hole three samples wide, which is larger than any plate gap.
## Returns the corrected depths: a Packed array is a value type, so this cannot write through.
static func _fill(z: PackedFloat32Array, good: PackedByteArray, nx: int, ny: int,
		fallback: float) -> PackedFloat32Array:
	var out := z.duplicate()
	var live := good.duplicate()
	for sweep in 3:
		var next := out.duplicate()
		var next_live := live.duplicate()
		var changed := false
		for j in ny:
			for i in nx:
				var k := j * nx + i
				if live[k] == 1:
					continue
				var sum := 0.0
				var n := 0
				for dj: int in [-1, 0, 1]:
					for di: int in [-1, 0, 1]:
						var jj: int = j + dj
						var ii: int = i + di
						if jj < 0 or ii < 0 or jj >= ny or ii >= nx:
							continue
						var kk: int = jj * nx + ii
						if live[kk] == 0:
							continue
						sum += out[kk]
						n += 1
				if n > 0:
					next[k] = sum / float(n)
					next_live[k] = 1
					changed = true
		out = next
		live = next_live
		if not changed:
			break
	for k in out.size():
		if live[k] == 0:
			out[k] = fallback
	return out


static func _median(values: PackedFloat32Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]

