extends Node
## city-art r13: the shadow-casting policy gate. Two things are checked, both without a renderer:
##   1. the RULE — a mesh under 2 m in every axis stops casting, a 20 m banner does not, and a MultiMesh
##      is judged by its own mesh rather than by the batch's AABB;
##   2. the CITY — applied to a real city build, it turns off a large number of small meshes and a
##      handful of far-tier ones, and it never touches a near building.
##   tools/godot.sh test res://world/art/tests/test_shadows.gd

const CITY := "res://world/city.tscn"

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	_rule()
	await _city()
	print("SHADOWS %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _rule() -> void:
	_check(ArtShadows.is_small(Vector3(1.0, 0.8, 1.9)), "a 1.9 m crate is dressing")
	_check(not ArtShadows.is_small(Vector3(1.0, 0.8, 2.1)), "a 2.1 m crate is not")
	_check(not ArtShadows.is_small(Vector3(20.0, 0.05, 0.4)), "a 20 m banner is not dressing")
	_check(not ArtShadows.is_small(Vector3.INF), "a mesh-less node is left alone")
	# A MultiMesh is judged by its own mesh: one crate scattered over a district must still read small.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _box(Vector3(1.0, 1.0, 1.0))
	mm.instance_count = 2
	mm.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(400.0, 0.0, 400.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_check(ArtShadows.is_small(ArtShadows.size_of(mmi)),
			"a MultiMesh of 1 m crates is dressing even when the batch is 400 m across")
	var big := MeshInstance3D.new()
	big.mesh = _box(Vector3(30.0, 60.0, 30.0))
	_check(not ArtShadows.is_small(ArtShadows.size_of(big)), "a 30 x 60 m tower is not dressing")
	# The far tier is a name contract.
	var far := MeshInstance3D.new()
	far.name = "t01_far"
	var parent := Node3D.new()
	parent.name = "Kit"
	parent.add_child(far)
	_check(ArtShadows.is_far(far), "t01_far is the far tier")
	_check(not ArtShadows.is_far(big), "an unnamed mesh is not")
	big.queue_free()
	parent.queue_free()
	mmi.queue_free()


func _city() -> void:
	if not ResourceLoader.exists(CITY):
		push_warning("test_shadows: no %s — the city half of the gate is skipped" % CITY)
		return
	var city := (load(CITY) as PackedScene).instantiate()
	add_child(city)
	await get_tree().process_frame
	await get_tree().process_frame
	# The city's own `CityArt._ready` has already applied the policy, so the gate here is the SECOND
	# application: it must be a no-op, and nothing large may have been caught on the way.
	var before := _casting(city)
	var counts := ArtShadows.apply(city)
	var after := _casting(city)
	_check(int(counts["small"]) == 0 and int(counts["far"]) == 0,
			"a second pass changes nothing (small %d, far %d)" % [counts["small"], counts["far"]])
	_check(before.size() == after.size(),
			"the casting set is stable (%d -> %d)" % [before.size(), after.size()])
	# Nothing that still casts may be dressing: the policy ran on a real city and the survivors are the
	# architecture, the tiles and the big props.
	var small_left := 0
	for gi: GeometryInstance3D in after:
		if ArtShadows.is_small(ArtShadows.size_of(gi)) and not ArtShadows.is_far(gi):
			small_left += 1
	_check(small_left == 0, "no small dressing is left casting (%d)" % small_left)
	var far_left := 0
	for gi: GeometryInstance3D in after:
		if ArtShadows.is_far(gi):
			far_left += 1
	_check(far_left == 0, "no far-tier mesh is left casting (%d)" % far_left)
	_check(after.size() > 100, "%d meshes still cast the sun" % after.size())
	city.queue_free()


## Every GeometryInstance3D under `root` that still casts a shadow.
func _casting(root: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var gi := n as GeometryInstance3D
		if gi != null and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			out.append(gi)
		stack.append_array(n.get_children())
	return out


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
