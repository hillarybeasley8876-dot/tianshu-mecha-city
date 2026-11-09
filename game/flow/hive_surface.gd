class_name FlowHiveSurface
extends RefCounted
## Where the Hive Spire's shell is (look/flow.md item 1). The pods and the core have to sit ON the
## trunk; flow used to push them out to a guessed radius, and the guess was wider than the trunk at the
## top and narrower than its roots, so four spheres floated in the air beside the spire.
##
## Two meshes come out of monster-assets' GLB and they are not the same shape:
##
##   * `Hive` — 60,000 faces, the mesh the player sees. This is what the weak points are solved
##     against. It is a shell with a wide root mass and a thin spined crown, so the surface along a
##     given bearing can be anywhere between r = 1.8 m and r = 24 m.
##   * `HiveCollision` — 164 faces. It is fatter than the skin along most bearings (measured 4–17 m
##     out at the four pod heights), so it is used for COLLISION only: a shot that stops on the trunk
##     is a shot that connects, and solving pods on it would bury them inside the visible mesh.
##
## Both are flattened into the visual's local space. 60,000 faces is 2 MB, so the caller drops the
## skin once its five weak points are solved; a test that wants to re-measure pays for it again.

const RAY_START := 260.0            ## m out along the bearing the probe starts at
const SINK := 1.0                   ## m the anchor sits inside the surface
## m of vertex clustering for the shot collision (`skin_shape`). Half a cell is the most the surface
## can move, so a pod 1 m inside the skin still pokes out through it.
const GRID := 1.2

var hull: PackedVector3Array = PackedVector3Array()
var skin: PackedVector3Array = PackedVector3Array()
## The decimated skin the trunk's shot collision is built from. Computed once in `load_from`, because
## `drop_skin` throws the 60,000 raw faces away right after the weak-point solve.
var _skin_collision: PackedVector3Array = PackedVector3Array()


## Read both meshes out of `model` (duck-typed: `collision_mesh()`, `meshes`) relative to `space`.
func load_from(model: Node3D, space: Node3D) -> void:
	hull = PackedVector3Array()
	skin = PackedVector3Array()
	_skin_collision = PackedVector3Array()
	if model == null:
		return
	if model.has_method(&"collision_mesh"):
		var mesh := model.call(&"collision_mesh") as Mesh
		if mesh != null and not mesh.get_faces().is_empty():
			hull = _flatten(mesh.get_faces(), model.get(&"collision") as Node3D, space)
		elif mesh != null:
			push_warning("FlowHiveSurface: the hive hull has no faces — no hull collision")
	var meshes := model.get(&"meshes") as Dictionary
	var node := meshes.get(&"intact") as MeshInstance3D if meshes != null else null
	if node != null and node.mesh != null:
		skin = _flatten(node.mesh.get_faces(), node, space)
		_skin_collision = decimate(skin, GRID)


## The visible mesh, or empty when there is no model. Re-read on demand after `drop_skin`.
func skin_faces(model: Node3D, space: Node3D) -> PackedVector3Array:
	if skin.is_empty():
		skin = _read_skin(model, space)
	return skin


func _read_skin(model: Node3D, space: Node3D) -> PackedVector3Array:
	if model == null:
		return PackedVector3Array()
	var meshes := model.get(&"meshes") as Dictionary
	var node := meshes.get(&"intact") as MeshInstance3D if meshes != null else null
	if node == null or node.mesh == null:
		return PackedVector3Array()
	return _flatten(node.mesh.get_faces(), node, space)


func drop_skin() -> void:
	skin = PackedVector3Array()


## The trunk's hull as a collision shape, or null when there is no model.
func hull_shape() -> ConcavePolygonShape3D:
	if hull.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(hull)
	return shape


## The trunk's SHOT collision, which has to follow the skin (r5 brief item 7). `HiveCollision` is a
## convex hull of a concave, spined trunk: measured along the four pod bearings it stands 4–17 m
## outside the mesh the player sees, so a one-hit shot — a rifle tap, a gatling round — stopped on
## invisible air in front of the pod, and only a piercing charged shot got through. Three of every
## hive's four pods, and the core, were unreachable that way.
##
## 60,000 faces is far too much trimesh for three spires, so the skin is decimated by vertex
## clustering: every vertex snaps to a `GRID` lattice, duplicates weld, and triangles that collapse are
## dropped. The surface can move at most half a cell, which is well inside the 1 m the pods are sunk.
## Deterministic — the same GLB always produces the same shape.
func skin_shape() -> ConcavePolygonShape3D:
	if _skin_collision.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_skin_collision)
	# Two-sided: the GLB's winding is not ours to assume, and a shot must not pass through the shell
	# because a triangle happens to face the other way.
	shape.backface_collision = true
	return shape


## How many triangles the shot collision ended up with — a test prints it, because "a few thousand"
## is the whole reason this is not just the raw skin.
func skin_face_count() -> int:
	return _skin_collision.size() / 3


## Vertex clustering: every vertex snaps to a `grid` lattice, duplicates weld, and the triangles that
## collapse or repeat are dropped. Deterministic — the same mesh always gives the same shape.
static func decimate(faces: PackedVector3Array, grid: float) -> PackedVector3Array:
	var kept := {}
	var out := PackedVector3Array()
	var ids := PackedInt64Array([0, 0, 0])
	var cells := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for i in range(0, faces.size(), 3):
		for k in 3:
			cells[k] = _cell(faces[i + k], grid)
			ids[k] = _id(cells[k], grid)
		ids.sort()
		if ids[0] == ids[1] or ids[1] == ids[2]:
			continue
		var key := "%d|%d|%d" % [ids[0], ids[1], ids[2]]
		if kept.has(key):
			continue
		kept[key] = true
		out.append(cells[0])
		out.append(cells[1])
		out.append(cells[2])
	return out


static func _cell(v: Vector3, grid: float) -> Vector3:
	return Vector3(roundf(v.x / grid), roundf(v.y / grid), roundf(v.z / grid)) * grid


## A lattice cell as one integer: the hive is 60 m tall, so ±512 cells at a 1.2 m grid is 600 m of
## headroom on every axis and the packing cannot overflow.
static func _id(v: Vector3, grid: float) -> int:
	var x := clampi(roundi(v.x / grid) + 512, 0, 1023)
	var y := clampi(roundi(v.y / grid) + 512, 0, 1023)
	var z := clampi(roundi(v.z / grid) + 512, 0, 1023)
	return x | (y << 10) | (z << 20)


## Where the shell is along `bearing` at height `y`, and which way it faces — `[point, normal]`, with
## the point `SINK` metres inside the surface. Skin first, hull second, empty when neither has a face
## along that bearing (the caller falls back to its stand-in cone).
func solve(bearing: float, y: float) -> Array:
	var dir := Vector3(cos(bearing), 0.0, sin(bearing))
	var hit := _probe(skin, dir, y)
	if hit.is_empty():
		hit = _probe(hull, dir, y)
	if hit.is_empty():
		return []
	return [(hit[0] as Vector3) - dir * SINK, hit[1]]


## How the shell's radius changes with height along `bearing` — dr/dy, clamped to a 45° face. A boil
## laid on a tapering trunk with a purely horizontal normal sinks into the shell on one side and
## floats off it on the other, so `FlowHiveCore` tilts its collar by this.
func slope(bearing: float, y: float, span: float = 6.0) -> float:
	var lo := _hit(bearing, y - span)
	var hi := _hit(bearing, y + span)
	if lo == Vector3.INF or hi == Vector3.INF:
		return 0.0
	var r_lo := Vector2(lo.x, lo.z).length()
	var r_hi := Vector2(hi.x, hi.z).length()
	return clampf((r_hi - r_lo) / (2.0 * span), -1.0, 1.0)


## The shell's local radius of curvature across `bearing` at height `y` — how fast the trunk falls
## away from its own tangent plane. `FlowHiveCore` needs it: a 5 m collar laid on the tangent plane of
## a trunk that curves with ρ = 10 m would float 1.4 m off the shell at its outer edge. INF when the
## shell is flat along that line or there is no face to measure.
func curvature(bearing: float, y: float, span: float = 0.26) -> float:
	var p0 := _hit(bearing - span, y)
	var p1 := _hit(bearing, y)
	var p2 := _hit(bearing + span, y)
	if p0 == Vector3.INF or p1 == Vector3.INF or p2 == Vector3.INF:
		return INF
	# Circle geometry: a chord of half-length h over a sagitta s belongs to a circle of radius h²/2s.
	var sag := (p1 - (p0 + p2) * 0.5).length()
	var half := p0.distance_to(p2) * 0.5
	if sag < 0.05 or half < 0.5:
		return INF
	return half * half / (2.0 * sag)


## The raw skin point along `bearing` at height `y`, or `Vector3.INF` when no face is crossed.
func _hit(bearing: float, y: float) -> Vector3:
	var found := _probe(skin, Vector3(cos(bearing), 0.0, sin(bearing)), y)
	if found.is_empty():
		found = _probe(hull, Vector3(cos(bearing), 0.0, sin(bearing)), y)
	return found[0] as Vector3 if not found.is_empty() else Vector3.INF


## The first face the ray crosses walking in from `RAY_START` to the axis, and its outward normal.
func _probe(faces: PackedVector3Array, dir: Vector3, y: float) -> Array:
	if faces.is_empty():
		return []
	var from := dir * RAY_START + Vector3.UP * y
	var to := Vector3.UP * y
	var best := INF
	var at := Vector3.INF
	var normal := dir
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, a, b, c)
		if hit == null:
			continue
		var d := from.distance_squared_to(hit)
		if d >= best:
			continue
		best = d
		at = hit
		var face := Plane(a, b, c).normal
		normal = face if face.length_squared() > 0.01 else dir
	if is_inf(best):
		return []
	if normal.dot(dir) < 0.0:
		normal = -normal
	return [at, normal]


## A mesh's faces moved into `space`'s local space. The GLB's nodes are at identity today, but a model
## scaled to the spire's height has to come out exact.
func _flatten(faces: PackedVector3Array, node: Node3D, space: Node3D) -> PackedVector3Array:
	if node == null or space == null or not space.is_inside_tree():
		return faces
	var rel := space.global_transform.affine_inverse() * node.global_transform
	if rel == Transform3D.IDENTITY:
		return faces
	var out := PackedVector3Array()
	out.resize(faces.size())
	for i in faces.size():
		out[i] = rel * faces[i]
	return out
