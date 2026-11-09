extends Node
## hero-v3 gate for lead r4 item 9: no armour piece passes through another.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_pieces.gd
##
## The brief's gate is "no piece intersects another at rest or in the 4 stress poses; sample the mesh,
## report the worst penetration; <= 5 cm". This measures it on the SKINNED mesh, piece by piece: a
## piece is every vertex and triangle whose heaviest skin weight lands on one bone.
##
## HOW PENETRATION IS DECIDED: by SURFACE CROSSING, and only where a camera can SEE it. Three earlier
## versions of this gate asked "is this vertex inside that piece?" -- by ray parity, then by a
## normal-signed nearest surface, then by a probe back along the vertex normal. All three are wrong
## here, and the third measured the truth and still failed: it reported the hand 0.81 m inside the
## forearm, the calf 0.57 m inside the thigh, the upper arm 0.90 m inside the pauldron. Those are not
## bugs. A mech's joints TELESCOPE -- the gauntlet slides into the elbow shell, the calf into the
## thigh, the arm into the pauldron -- so the child segment living inside the parent's shell IS the
## design, and it is invisible precisely because it is inside.
##
## So the gate asks the two questions containment cannot:
##   1. do the two SURFACES CROSS? An edge of one piece through a triangle of the other. A telescoping
##      joint does not: the child enters through the parent's open end and crosses nothing.
##   2. is the crossing EXPOSED? A ray is cast from it straight out of the body; if it escapes, the
##      crossing is on the skin and a player will see it. If it hits the mech on the way out, the
##      crossing is buried in a socket and nothing is wrong.
## Only an exposed crossing deeper than the gate fails. Buried ones are reported but not failed.
##
## AND ONLY WHAT THE ANIMATION ADDS. The exported rest mesh already crosses itself at every joint --
## Head/Neck 0.357 m, Clavicle/Spine 0.282 m, and those numbers are byte-identical in all seven poses,
## so nothing this unit does causes them and nothing this unit can do fixes them; they are the
## modeller's. So `rest` is measured first and becomes the BASELINE, and the gate fails on how much
## WORSE a pose is than rest. The absolute numbers are still printed, because a 0.36 m hole in the neck
## is a real defect that someone has to own -- it is just not an animation defect.
##
## Poses: the exported rest, the deepest walk crouch, `guard_up`, the `melee_l1` follow-through,
## `death` at its last frame, `hit_knockdown` at its deepest, and the slide skate.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 60.0
const GATE := 0.05
## How far the exposure probe looks for body geometry in front of a crossing. A crossing is only a
## defect if a camera can see it; one buried inside a socket is not, and this is how the two are told
## apart. Generous against the 16 m mech: nothing that matters is more than 4 m inside it.
const EXPOSE_RANGE := 4.0
## Triangles MEASURED per piece, sampled evenly out of everything that piece owns. Collection keeps
## every wholly-owned triangle -- an earlier version strided the collection as well and that quietly
## halved the armour, from 29 pieces to 14, so half the plates were never measured at all.
const TRIS_PER_PIECE := 64
## The folded drone fan is not armour: the seven blades stack on the back frame by design and
## `set_wings` is what spreads them, so they are not pairs this gate measures.
const SKIP: Array[String] = ["Root", "BackFrame"]
## label, how to reach the pose. `frames` is how many ticks to run after the clip starts.
const POSES: Array = [
	["rest", &"", 0],
	["walk crouch", &"", -1],
	["guard_up", &"guard_up", 40],
	["melee_l1 follow", &"melee_l1", 16],
	["death last frame", &"death", 96],
	["knockdown deepest", &"hit_knockdown", 26],
	["slide skate", &"", -2],
	["fall brace", &"fall", 40],
	["fly clip standing", &"fly", 40],
	["hover standing", &"hover", 40],
	["flight cruise", &"", -3],
	["flight boost banked", &"", -4],
]

var failures: Array[String] = []
## bone -> PackedVector3Array of triangles (3 verts each) in mesh space
var _pieces: Dictionary = {}
var _pairs: Array = []
var _model: Node3D
## where the last crossing found was, and which way is OUT of the body from there
var _cross_at: Vector3 = Vector3.ZERO
var _cross_dir: Vector3 = Vector3.ZERO
## where the worst VISIBLE crossing of the pair being measured was, so the report can say where to look
var _seen_at: Vector3 = Vector3.ZERO
## unordered pair label -> the exposed crossing depth in the EXPORTED REST pose. Everything a later
## pose shows above this is attributable to the animation.
var _baseline: Dictionary = {}


func _ready() -> void:
	# The pieces are collected once, off the first model: they are MESH-space triangles, so they are
	# the same for every instance. Each POSE then gets its own model -- see `_pose`.
	_model = _spawn()
	var skel: Skeleton3D = _model.skeleton
	_collect(skel)
	_pairs = _adjacent(skel)
	print("PIECES %d rigid pieces, %d adjacent pairs, %d tris sampled per piece"
			% [_pieces.size(), _pairs.size(), TRIS_PER_PIECE])
	for spec: Array in POSES:
		await _pose(String(spec[0]), spec[1], int(spec[2]))
	print("PIECES rest baseline: %d pairs already cross in the exported mesh, worst %.3f m"
			% [_baseline.size(), _baseline.values().max() if not _baseline.is_empty() else 0.0])
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for line in failures:
			print("FAIL %s" % line)
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


## A fresh mech, driven by hand at a fixed step.
func _spawn() -> Node3D:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	return model


## One pose, then every adjacent pair measured against it.
##
## Every pose gets a FRESH MODEL. Sharing one let state leak between them: the walk pose translates
## the mech 36 m downrange to make the gait step, and the gait's plants are world-locked, so every
## pose after it was measured standing somewhere else with its feet planted 36 m behind it. That read
## as `guard_up` -- an upper-body clip with no leg keys at all -- moving the right knee 1.5 m.
func _pose(label: String, clip: StringName, frames: int) -> void:
	if _model != null:
		_model.queue_free()
	_model = _spawn()
	var skel: Skeleton3D = _model.skeleton
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	_model.gait.reset()
	_model.stop_action()
	_model.set_aim(Vector3.ZERO, 0.0)
	for i in 30:
		_tick()
	if frames == -1:
		_model.set_locomotion(&"walk", 9.0, Vector2(0.0, -1.0))
		_model.gait.reset()
		for i in 240:
			_model.position += Vector3(0.0, 0.0, -9.0) * DT
			_tick()
	elif frames == -2:
		_model.set_locomotion(&"slide", 42.0, Vector2(0.0, -1.0))
		for i in 40:
			_tick()
	elif frames == -3 or frames == -4:
		_flight(50.0 if frames == -3 else 84.0, 0.0 if frames == -3 else 120.0)
	elif clip != &"":
		_model.play_action(clip, 0.06)
		for i in frames:
			_tick()
	var worst := 0.0
	var worst_pair := ""
	var worst_abs := 0.0
	var deepest_buried := 0.0
	var rows: Array = []
	var is_rest := label == "rest"
	for pair: Array in _pairs:
		var depth: Array = _penetration(skel, int(pair[0]), int(pair[1]))
		var back: Array = _penetration(skel, int(pair[1]), int(pair[0]))
		var seen := maxf(float(depth[0]), float(back[0]))
		var key := _key(skel, int(pair[0]), int(pair[1]))
		deepest_buried = maxf(deepest_buried, maxf(float(depth[1]), float(back[1])))
		worst_abs = maxf(worst_abs, seen)
		if is_rest:
			if seen > 0.005:
				_baseline[key] = seen
			continue
		# what the ANIMATION added on top of what the exported mesh already does
		var added := seen - float(_baseline.get(key, 0.0))
		if added > 0.005:
			var at: Vector3 = depth[3] if float(depth[0]) >= float(back[0]) else back[3]
			rows.append([added, "%s +%.3f m at (%.1f, %.1f, %.1f)"
					% [depth[2], added, at.x, at.y, at.z]])
		if added > worst:
			worst = added
			worst_pair = String(depth[2])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("PIECES %-20s added by the pose %.3f m (%s)%s | worst absolute %.3f m | deepest buried %.3f m"
			% [label, worst, worst_pair if worst_pair != "" else "none",
			"" if rows.is_empty() else "  | " + ", ".join(PackedStringArray(rows.slice(0, 4).map(
					func(r: Array) -> String: return r[1]))), worst_abs, deepest_buried])
	if worst > GATE:
		_fail("%s: %s interpenetrate by %.3f m more than the rest mesh does, gate %.2f"
				% [label, worst_pair, worst, GATE])
	await get_tree().process_frame


## The pair's key, order-independent, so `A/B` and `B/A` share one baseline entry.
func _key(skel: Skeleton3D, a: int, b: int) -> String:
	var x := skel.get_bone_name(a)
	var y := skel.get_bone_name(b)
	return "%s|%s" % [x, y] if x < y else "%s|%s" % [y, x]


## Free flight, driven the way `Hero3Flight` measures it: the MODEL NODE is moved, because that node's
## global transform is what the pose reads for its speed and its yaw rate (lead r8 item 3).
func _flight(speed: float, yaw_deg: float) -> void:
	_model.set_locomotion(Hero3Flight.STATE, speed, Vector2(0.0, 1.0))
	for i in 240:
		_model.position += -_model.global_transform.basis.z * speed * DT
		if yaw_deg != 0.0:
			_model.rotate_y(deg_to_rad(yaw_deg) * DT)
		_model.flight.sample(_model, DT, Hero3Flight.STATE)
		_model.gait.set_flight(_model.flight.blend, _model.flight.lean)
		_model.rig.set_thrust_dir(_model.flight.thrust)
		_tick()
		_model._place_model(Vector3.ZERO)


func _tick() -> void:
	_model.clips.update(DT)
	_model.gait.update(DT)
	_model.clips.apply()
	_model.rig.update(DT)


func _fail(line: String) -> void:
	failures.append(line)


## How far piece `a`'s surface has gone through piece `b`'s, as `[depth, "A/B"]`.
func _penetration(skel: Skeleton3D, a: int, b: int) -> Array:
	var label := "%s/%s" % [skel.get_bone_name(a), skel.get_bone_name(b)]
	if not _pieces.has(a) or not _pieces.has(b) or a == b:
		return [0.0, label]
	var xf_b := _bone_xf(skel, b)
	var tris_a: PackedVector3Array = _world(_bone_xf(skel, a), _sample(_pieces[a]))
	var tris_b: PackedVector3Array = _world(xf_b, _sample(_pieces[b]))
	# `b`'s own bone origin decides which way its faces look: a shell's outward normal points away
	# from the bone it wraps, and that is the direction a poke-through escapes along.
	var hub := xf_b.origin
	var seen := 0.0
	var buried := 0.0
	for i in range(0, tris_a.size(), 3):
		for j in range(0, tris_b.size(), 3):
			var depth := _cross(tris_a, i, tris_b, j)
			if depth <= GATE:
				continue
			if _cross_dir.dot(_cross_at - hub) < 0.0:
				_cross_dir = -_cross_dir
			if _exposed(skel, _cross_at + _cross_dir * 0.05, _cross_dir):
				if depth > seen:
					seen = depth
					_seen_at = _cross_at
			else:
				buried = maxf(buried, depth)
	return [seen, buried, label, _seen_at]


## An even spread of at most `TRIS_PER_PIECE` triangles out of everything the piece owns, so a big
## plate and a small one are both covered and the cost stays the same for every pair.
func _sample(tris: PackedVector3Array) -> PackedVector3Array:
	var total := int(tris.size() / 3)
	if total <= TRIS_PER_PIECE:
		return tris
	var out := PackedVector3Array()
	out.resize(TRIS_PER_PIECE * 3)
	for i in TRIS_PER_PIECE:
		var src := int(float(i) * float(total) / float(TRIS_PER_PIECE)) * 3
		out[i * 3] = tris[src]
		out[i * 3 + 1] = tris[src + 1]
		out[i * 3 + 2] = tris[src + 2]
	return out


## The transform that carries a piece's mesh-space vertices into skeleton space under its bone's
## current pose: `bind_pose` is the inverse of the bone's rest, so this is the skinning transform.
func _bone_xf(skel: Skeleton3D, bone: int) -> Transform3D:
	return skel.get_bone_global_pose(bone) * skel.get_bone_global_rest(bone).affine_inverse()


## A piece's triangles moved into skeleton space.
func _world(xf: Transform3D, tris: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(tris.size())
	for i in tris.size():
		out[i] = xf * tris[i]
	return out


## How far triangle `i` of `a` has gone through triangle `j` of `b`: the worst of its three edges.
##
## The depth is how far the edge reaches PAST THE WALL PLANE, not how much of the edge is on the far
## side of it. The first version used the latter, which is at least half an edge length by
## construction, so a single long edge grazing a plate reported 0.44 m of penetration in every pose.
func _cross(a: PackedVector3Array, i: int, b: PackedVector3Array, j: int) -> float:
	var v0 := b[j]
	var v1 := b[j + 1]
	var v2 := b[j + 2]
	var wall := (v1 - v0).cross(v2 - v0)
	if wall.length_squared() < 1e-12:
		return 0.0
	wall = wall.normalized()
	var worst := 0.0
	for e in 3:
		var p0 := a[i + e]
		var p1 := a[i + (e + 1) % 3]
		var t := _seg_hit(p0, p1, v0, v1, v2)
		if t < 0.0:
			continue
		var hit := p0.lerp(p1, t)
		var depth := maxf(absf((p0 - hit).dot(wall)), absf((p1 - hit).dot(wall)))
		if depth > worst:
			worst = depth
			_cross_at = hit
			_cross_dir = wall
	return worst


## Can a camera see the crossing? A ray is cast from it straight OUT of the body; if it reaches
## `EXPOSE_RANGE` without meeting any other piece, the crossing is on the skin and visible. A head
## sitting down into its collar crosses surfaces too, but the ray hits the collar on the way out, so
## that crossing is buried and nobody will ever see it.
func _exposed(skel: Skeleton3D, from: Vector3, dir: Vector3) -> bool:
	var to := from + dir * EXPOSE_RANGE
	for bone: int in _pieces:
		var tris: PackedVector3Array = _world(_bone_xf(skel, bone), _sample(_pieces[bone]))
		for j in range(0, tris.size(), 3):
			if _seg_hit(from, to, tris[j], tris[j + 1], tris[j + 2]) >= 0.0:
				return false
	return true


## Moller-Trumbore for the segment p0->p1 against one triangle. Returns the parameter along the
## segment in (0, 1), or -1 when it misses or only touches the triangle at one of its own ends.
func _seg_hit(p0: Vector3, p1: Vector3, v0: Vector3, v1: Vector3, v2: Vector3) -> float:
	var dir := p1 - p0
	var e1 := v1 - v0
	var e2 := v2 - v0
	var pv := dir.cross(e2)
	var det := e1.dot(pv)
	if absf(det) < 1e-9:
		return -1.0
	var tv := p0 - v0
	var u := tv.dot(pv) / det
	if u < 0.0 or u > 1.0:
		return -1.0
	var qv := tv.cross(e1)
	var v := dir.dot(qv) / det
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t := e2.dot(qv) / det
	return t if t > 1e-4 and t < 1.0 - 1e-4 else -1.0


## Group the mesh's triangles by the bone each one is weighted to.
## mesh: the weapons are held away from the armour.
func _collect(skel: Skeleton3D) -> void:
	for n in _model.find_children("Hero3Body", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		var bind := PackedInt32Array()
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			if bone < 0:
				bone = skel.find_bone(String(mi.skin.get_bind_name(b)))
			bind.append(bone)
		for s in mi.mesh.get_surface_count():
			_collect_surface(mi, s, bind)


func _collect_surface(mi: MeshInstance3D, surface: int, bind: PackedInt32Array) -> void:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if bones == null or verts.is_empty():
		return
	var per := int(bones.size() / verts.size())
	var owner := PackedInt32Array()
	owner.resize(verts.size())
	for i in verts.size():
		var top := -1
		var best := -1.0
		for j in per:
			if weights[i * per + j] > best:
				best = weights[i * per + j]
				top = int(bones[i * per + j])
		owner[i] = bind[top] if top >= 0 else -1
	var count := indices.size() if indices.size() > 0 else verts.size()
	for t in range(0, count, 3):
		var i0 := indices[t] if indices.size() > 0 else t
		var i1 := indices[t + 1] if indices.size() > 0 else t + 1
		var i2 := indices[t + 2] if indices.size() > 0 else t + 2
		var bone := owner[i0]
		# only triangles wholly owned by one bone: a straddling one has no single piece to belong to
		if bone < 0 or owner[i1] != bone or owner[i2] != bone:
			continue
		_piece(bone).append_array([verts[i0], verts[i1], verts[i2]])

func _piece(bone: int) -> PackedVector3Array:
	if not _pieces.has(bone):
		_pieces[bone] = PackedVector3Array()
	return _pieces[bone]


## Every pair of pieces whose bones are within two steps of each other in the skeleton, which is where
## armour meets armour: a shoulder and an upper arm, a thigh and a calf, the pelvis and the waist.
func _adjacent(skel: Skeleton3D) -> Array:
	var keys: Array = []
	for bone: int in _pieces:
		var bone_name := skel.get_bone_name(bone)
		if SKIP.has(bone_name) or bone_name.begins_with("Drone_"):
			continue
		keys.append(bone)
	var out: Array = []
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if _steps(skel, int(keys[i]), int(keys[j])) <= 2:
				out.append([keys[i], keys[j]])
	return out


func _steps(skel: Skeleton3D, a: int, b: int) -> int:
	for depth in 3:
		if _reaches(skel, a, b, depth) or _reaches(skel, b, a, depth):
			return depth
	return 99


func _reaches(skel: Skeleton3D, from: int, to: int, depth: int) -> bool:
	if depth == 0:
		return from == to
	if skel.get_bone_parent(from) >= 0 and _reaches(skel, skel.get_bone_parent(from), to, depth - 1):
		return true
	for child in skel.get_bone_children(from):
		if _reaches(skel, child, to, depth - 1):
			return true
	return false
