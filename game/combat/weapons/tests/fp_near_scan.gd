class_name FpNearScan
extends RefCounted
## Headless answer to "what is that big orange thing in my canopy" (lead r6 item 1).
##
## Walks the live scene and lists every DRAWN primitive within `radius` of the first-person lens:
## which pool owns it, what shape it is, how big it is in metres, how much of the frame it covers and
## what colour it is. Nothing here is a guess — the identification table in status/weapons.md is this
## scan's own output, and the first-person gate is a filter over it.
##
## Two sources, because the headless dummy renderer `tools/godot.sh test` runs under does NOT keep
## MultiMesh instance transforms (`set_instance_transform` then `get_instance_transform` returns
## identity, and `buffer` is empty — measured):
##   * plain MeshInstance3D nodes are read straight off the tree, the way the renderer sees them;
##   * every pool that implements `begin_record()` / `drawn()` reports what it wrote into its
##     MultiMesh, one entry per instance, with the same transform / size / tint / material.
## Geometry that is parked off-screen or scaled to nothing never shows up in either.

## A box this many times longer than it is wide is a needle (a tracer), not a slab: it recedes from
## the lens instead of covering it, so it is reported but never counted as a slab.
const NEEDLE_RATIO := 8.0
const FLAT_KINDS: Array[String] = ["box", "quad"]


## Every drawn primitive within `radius` of `lens`, nearest first. `skip` and its children are left
## out — the suite passes the hero model, which camera-aim culls in first person
## (`player/camera/camera_hero_cull.gd`) but the test rig still draws.
static func scan(root: Node, lens: Vector3, radius: float, skip: Node = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == skip:
			continue
		for c in n.get_children():
			stack.append(c)
		if n.has_method(&"begin_record") and n.has_method(&"drawn"):
			_pool(n, lens, radius, out)
			continue
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		_add(out, {
			"label": String(mi.name),
			"pool": String(mi.get_parent().name) if mi.get_parent() != null else String(mi.name),
			"group": "%s %s" % [String(mi.get_parent().name) if mi.get_parent() != null
					else String(mi.name), _kind(mi.mesh)],
			"kind": _kind(mi.mesh),
			"xf": mi.global_transform,
			"box": mi.mesh.get_aabb(),
			"tint": Color.WHITE,
			"mat": mi.material_override,
		}, lens, radius)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["dist"]) < float(b["dist"]))
	return out


static func _pool(node: Node, lens: Vector3, radius: float, out: Array[Dictionary]) -> void:
	for e: Dictionary in node.call(&"drawn"):
		var mat := e["mat"] as Material
		_add(out, {
			"label": String(e["label"]),
			"pool": String(node.name),
			"group": String(e["label"]),
			"kind": String(e["kind"]),
			"xf": e["xf"] as Transform3D,
			"box": AABB(-(e["size"] as Vector3) * 0.5, e["size"] as Vector3),
			"tint": e["tint"] as Color,
			"mat": mat,
		}, lens, radius)


static func _add(out: Array[Dictionary], prim: Dictionary, lens: Vector3, radius: float) -> void:
	var xf: Transform3D = prim["xf"]
	var local: AABB = prim["box"]
	var box := xf * local
	if box.size.length_squared() < 1.0e-6:
		return
	# Distance is measured to the ENCLOSING box, which can only be nearer than the real primitive —
	# the conservative direction for a "within 8 m" gate. Coverage uses the eight real corners.
	var dist := _box_dist(box, lens)
	if dist > radius:
		return
	# Side lengths come from the ORIENTED box (basis scale x local size), not from the enclosing AABB:
	# a 42 m tracer tilted a degree off the view axis has an AABB cross-section of several metres, and
	# measuring that would report the stream as a wall.
	var scale := xf.basis.get_scale()
	var dims := [absf(local.size.x * scale.x), absf(local.size.y * scale.y),
			absf(local.size.z * scale.z)]
	dims.sort()
	dims.reverse()
	var mat := prim["mat"] as Material
	var col := _color_of(mat, prim["tint"] as Color)
	out.append({
		"owner": "%s/%s" % [prim["pool"], prim["label"]],
		"group": String(prim["group"]),
		"pool": String(prim["pool"]),
		"kind": String(prim["kind"]),
		"soft": _is_soft(mat),
		"dist": dist,
		"long_m": float(dims[0]),
		"mid_m": float(dims[1]),
		"thick_deg": _thick_deg(float(dims[1]), dist),
		"color": col,
		"orange": is_orange(col),
	})


## A textured alpha sprite (the soft disc every flare, smoke puff and dust cloud is drawn with) has
## no edges: its quad is twice the glow anyone sees. Those are reported and bounded by coverage, but
## they are not "slabs" — a slab is a hard-edged polygon, which is what the canopy showed.
static func _is_soft(mat: Material) -> bool:
	var bm := mat as BaseMaterial3D
	return bm != null and bm.albedo_texture != null



## Effective colour of a primitive: the material's albedo (already HDR for the additive pools) times
## the per-instance tint, plus its emission. A ShaderMaterial is reported as white — none of the
## weapon pools use one, and a shader's output colour cannot be read back from GDScript.
static func _color_of(mat: Material, tint: Color) -> Color:
	var sm := mat as StandardMaterial3D
	if sm == null:
		return tint
	var c := sm.albedo_color
	if sm.emission_enabled:
		var e := sm.emission * sm.emission_energy_multiplier
		c = Color(c.r + e.r, c.g + e.g, c.b + e.b, c.a)
	return Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, 1.0)


## Orange-dominant: the hue of a muzzle flash, a tracer, a casing or an engine flare — red on top,
## blue well under green. Normalised first, so an HDR additive albedo (5.0, 3.9, 1.7) reads the same
## as the (1.0, 0.78, 0.34) it was built from.
static func is_orange(c: Color) -> bool:
	var m := maxf(c.r, maxf(c.g, c.b))
	if m < 0.15:
		return false
	var r := c.r / m
	var g := c.g / m
	var b := c.b / m
	return r > 0.85 and g < r - 0.08 and b < g - 0.10


## The lead's r6 gate: orange-dominant SLABS — a hard-edged flat box or quad that is not a needle —
## longer than `max_long` metres inside `radius` of the lens. Anything that matches is a car door in
## the canopy.
static func slabs(hits: Array[Dictionary], radius: float, max_long: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hit in _hard_orange(hits, radius, max_long):
		if not FLAT_KINDS.has(String(hit["kind"])):
			continue
		if float(hit["long_m"]) > maxf(float(hit["mid_m"]), 0.001) * NEEDLE_RATIO:
			continue
		out.append(hit)
	return out


## The shape-agnostic backstop: no hard-edged orange primitive of any kind may be longer than
## `max_long` inside `radius`. The r5 muzzle flash (0.594 m in the cockpit) is what sets the ceiling.
static func hard_over(hits: Array[Dictionary], radius: float,
		max_long: float) -> Array[Dictionary]:
	return _hard_orange(hits, radius, max_long)


## How wide one orange primitive may read across the view, soft sprites included — the bound that says
## "nothing orange dominates the canopy", whatever it is drawn with.
static func thick_over(hits: Array[Dictionary], radius: float,
		max_deg: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hit in hits:
		if bool(hit["orange"]) and float(hit["dist"]) <= radius \
				and float(hit["thick_deg"]) > max_deg:
			out.append(hit)
	return out


static func _hard_orange(hits: Array[Dictionary], radius: float,
		max_long: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hit in hits:
		if not bool(hit["orange"]) or bool(hit["soft"]) or float(hit["dist"]) > radius:
			continue
		if float(hit["long_m"]) > max_long:
			out.append(hit)
	return out


## One identification-table row.
static func row(hit: Dictionary) -> String:
	var c: Color = hit["color"]
	return "%s [%s%s] %.1f m away, %.2f x %.2f m, %.0f deg wide, #%02X%02X%02X" % [
		hit["owner"], "soft " if bool(hit["soft"]) else "", hit["kind"], hit["dist"],
		hit["long_m"], hit["mid_m"], hit["thick_deg"],
		int(clampf(c.r, 0.0, 1.0) * 255.0), int(clampf(c.g, 0.0, 1.0) * 255.0),
		int(clampf(c.b, 0.0, 1.0) * 255.0)]


## Every row, for the log and for status/weapons.md.
static func table(hits: Array[Dictionary]) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for hit in hits:
		lines.append(row(hit))
	return "\n".join(lines)


static func _kind(mesh: Mesh) -> String:
	if mesh is BoxMesh:
		return "box"
	if mesh is QuadMesh:
		return "quad"
	if mesh is SphereMesh:
		return "sphere"
	if mesh is CylinderMesh:
		return "cylinder"
	if mesh is TorusMesh:
		return "torus"
	return mesh.get_class()


## Distance from `p` to the nearest point of `box` (0 inside it).
static func _box_dist(box: AABB, p: Vector3) -> float:
	var lo := box.position
	var hi := box.position + box.size
	return Vector3(maxf(maxf(lo.x - p.x, p.x - hi.x), 0.0),
			maxf(maxf(lo.y - p.y, p.y - hi.y), 0.0),
			maxf(maxf(lo.z - p.z, p.z - hi.z), 0.0)).length()


## How WIDE a primitive reads across the view, in degrees of the 62 deg frame: the angle its second
## largest dimension subtends at the lens. That is the right question for a needle (a 42 m tracer is
## 0.35 m wide and reads as a line, not as half the sky) and for a billboard sprite (both dimensions
## are the sprite size). A slab seen face-on is caught by the metre gate instead, which is why the
## lead's rule is stated in metres.
static func _thick_deg(mid_m: float, dist: float) -> float:
	return 2.0 * rad_to_deg(atan(0.5 * mid_m / maxf(dist, 0.01)))

