class_name PropScatter
extends Node3D
## Turns a PropPlacer plan into MultiMeshes (city-art). One MultiMeshInstance3D per prop per 200 m
## tile: godot-tech §4.4 — a MultiMesh spread over the whole map is never culled, so it must be split
## per region. Holograms are single MeshInstance3Ds with the additive hologram material instead.
## Phase 2: `world/city.tscn` adds one of these and calls `dress(layout)`.

const MESH_DIR := "res://world/props/meshes"
const PLACER := preload("res://world/props/prop_placer.gd")
const KOI_RADIUS := 90.0          ## the koi hologram circles Block 9 on this radius
const KOI_PERIOD := 42.0          ## seconds per lap
const TETHER_HEIGHT := 600.0      ## the Spire's light tether, matching layout landmark tether_length
const HIVE_RADIUS := 120.0        ## creep radius (review r2: the stain stays with the nest)
const DETAIL_END := 450.0          ## city-build's detail-chunk range; props are detail, so they match it

var counts: Dictionary = {}       ## prop name -> instances placed (evidence + perf checks)
## prop name -> the transforms actually drawn, for the head-less float gate (a MultiMesh read-back is
## identity on the dummy renderer).
var emitted: Dictionary = {}
## r12 §2: rooftop slots the roof map had nowhere flat for, so nothing was placed on them.
var no_roof: int = 0

var _placer := PLACER.new()
var _koi: Node3D
var _koi_angle: float = 0.0
var _koi_centre := Vector3.ZERO


## Builds the whole dressing from the map layout. Returns the number of prop instances placed.
## `design` is the optional design-time layout (streets/buildings); see PropPlacer.build.
## `settle` (r10) drops every instance onto the surface the player sees before it is drawn.
func dress(layout: Dictionary, design: Dictionary = {}, seed: int = 20261101,
		settle: CitySettle = null) -> int:
	var plan := _placer.build(layout, seed, design)
	counts = {}
	var total := 0
	for prop in plan:
		var mesh := load_mesh(prop)
		if mesh == null:
			continue
		var list: Array = plan[prop]
		if settle != null:
			list = _settled(settle, prop, mesh, list, _placer.rules.get(prop, []))
		total += _scatter(prop, mesh, list)
	_spawn_holograms()
	_spawn_signs()
	_spawn_effects()
	_apply_hive_sites()
	return total


## r10: settles one prop's instances. They can carry BOTH rules — `container_stack`, `pipe_cluster`
## and `storage_tank` are street furniture in one district and rooftop plant in another — so the list
## is split by rule and each half is settled on its own terms.
func _settled(settle: CitySettle, prop: StringName, mesh: Mesh, list: Array,
		rules: Array) -> Array[Transform3D]:
	var halves: Dictionary = {CitySettle.RULE_ROOF: [], CitySettle.RULE_STREET: []}
	for i in list.size():
		var rule: int = int(rules[i]) if i < rules.size() else CitySettle.RULE_STREET
		(halves[rule] as Array).append(list[i])
	var out: Array[Transform3D] = []
	for rule: int in [CitySettle.RULE_ROOF, CitySettle.RULE_STREET]:
		var half: Array = halves[rule]
		if half.is_empty():
			continue
		if rule == CitySettle.RULE_ROOF and settle.roof_map != null:
			half = _aimed(settle.roof_map, half, mesh)
			if half.is_empty():
				continue
		out.append_array(settle.settle(half, mesh, rule, "prop:" + String(prop),
				"%s|%d" % [prop, rule]))
	return out


## r12 §2: aims every rooftop prop at city-kit's measured roof surface instead of at the slot's own z,
## which is the design box top and only right somewhere on the footprint. A slot with nowhere flat to
## stand is not placed at all — the settle pass would only throw it away a moment later.
func _aimed(map: KitRoofMap, list: Array, mesh: Mesh) -> Array[Transform3D]:
	var bb := mesh.get_aabb()
	var c := bb.get_center()
	var out: Array[Transform3D] = []
	for xf: Transform3D in list:
		var top := (xf * Vector3(c.x, bb.end.y, c.z)).y
		var hit := map.roof_at(xf.origin, top)
		if hit.is_empty():
			no_roof += 1
			continue
		var moved: Transform3D = xf
		moved.origin = hit["at"]
		out.append(moved)
	return out


## Loads a processed prop mesh. Missing meshes are a loud warning, never a silent skip.
static func load_mesh(prop: StringName) -> Mesh:
	var path := "%s/%s.glb" % [MESH_DIR, prop]
	if not ResourceLoader.exists(path):
		push_warning("PropScatter: no processed mesh for '%s' (%s) — run "
			% [prop, path] + "tools/blender.sh run blender/props/process_prop.py -- --name " + String(prop))
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("PropScatter: %s did not load as a scene" % path)
		return null
	var instance := scene.instantiate()
	var found := _first_mesh(instance)
	instance.free()          ## the mesh is refcounted; the throwaway instance is not needed
	if found == null:
		push_error("PropScatter: %s contains no MeshInstance3D" % path)
	return found


static func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var m := _first_mesh(child)
		if m != null:
			return m
	return null


## The prop keeps the material its glb ships (albedo + ORM + emissive mask); overriding it here
## would throw away the light strips, so no material_override is set.
func _scatter(prop: StringName, mesh: Mesh, xforms: Array) -> int:
	var by_tile: Dictionary = {}
	for xf: Transform3D in xforms:
		var key: Vector2i = _placer.tile_of(xf.origin)
		if not by_tile.has(key):
			by_tile[key] = [] as Array[Transform3D]
		(by_tile[key] as Array).append(xf)
	for key in by_tile:
		var list: Array = by_tile[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in range(list.size()):
			mm.set_instance_transform(i, list[i])
		var node := MultiMeshInstance3D.new()
		node.name = "%s_%d_%d" % [prop, key.x, key.y]
		node.multimesh = mm
		node.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if PropPlacer.SHADOW_CASTERS.has(prop)
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		# Props are detail scale, so they end with city-build's detail chunks (DETAIL_END = 450 m)
		# rather than running to the horizon and costing a shadow pass each.
		node.visibility_range_end = DETAIL_END
		node.visibility_range_end_margin = 40.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		add_child(node)
	counts[prop] = xforms.size()
	emitted[prop] = xforms
	return xforms.size()


func _spawn_holograms() -> void:
	for key in _placer.hologram_plan:
		var mesh := _hologram_mesh(key)
		if mesh == null:
			continue
		for xf: Transform3D in _placer.hologram_plan[key]:
			var node := MeshInstance3D.new()
			node.name = "holo_" + String(key)
			node.mesh = mesh
			node.material_override = McMaterials.hologram()
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.position = xf.origin
			node.rotation.y = xf.basis.get_euler().y
			add_child(node)
			counts[key] = 1
			if key == &"koi_dragon":
				_koi_centre = xf.origin
				_koi = node


## The koi is a prop mesh; the traffic hologram is a generated brand billboard. The Spire's light
## tether is an effect, not a hologram — see `_spawn_tethers`.
func _hologram_mesh(key: StringName) -> Mesh:
	match key:
		&"koi_dragon":
			return load_mesh(&"koi_dragon")
		&"traffic":
			return _sign_quad(36.0, 18.0, HoloGraphics.billboard(3001, ArtPalette.NEON_CYAN))
	push_warning("PropScatter: no hologram mesh for '%s'" % key)
	return null


## The Spire's light tether: a thin tapering column reaching from the crown into the sky.
func _tether_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 2.0
	m.bottom_radius = 7.0
	m.height = TETHER_HEIGHT
	m.radial_segments = 10
	m.rings = 1
	return m


## A textured, unshaded quad for a generated sign.
func _sign_quad(w: float, h: float, graphic: Texture2D) -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var mat := McMaterials.hologram(ArtPalette.NEON_MAGENTA, graphic)
	q.material = mat
	return q


## city-build's `passage_sign` slots: small holographic signs over the corridor entrances.
func _spawn_signs() -> void:
	if _placer.sign_plan.is_empty():
		return
	var mat := McMaterials.hologram(ArtPalette.NEON_CYAN, HoloGraphics.shop_sign(77))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = _placer.sign_plan.size()
	for i in range(_placer.sign_plan.size()):
		var row: Array = _placer.sign_plan[i]
		var basis := Basis(Vector3.UP, deg_to_rad(float(row[1])))
		basis = basis * Basis.from_scale(Vector3(float(row[2]), float(row[3]), 1.0))
		mm.set_instance_transform(i, Transform3D(basis, row[0]))
	var node := MultiMeshInstance3D.new()
	node.name = "passage_signs"
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 400.0
	add_child(node)
	counts[&"passage_sign"] = _placer.sign_plan.size()


## Reactor plumes from city-build's `smoke_plume` slots, and the Spire's light tether from its
## `spire_beacon` slot (both arrive through `effect_plan`; the tether used to be planned here and never
## spawned, because only `hologram_plan` was walked).
func _spawn_effects() -> void:
	var plumes: Array = _placer.effect_plan.get(&"smoke_column", [])
	var tethers: Array = _placer.effect_plan.get(&"tether", [])
	if plumes.is_empty() and tethers.is_empty():
		return
	var life := CityLife.new()
	life.name = "Life"
	add_child(life)
	for at: Vector3 in plumes:
		life.smoke_column(at, 150.0, 16.0).emitting = true
	counts[&"smoke_plume"] = plumes.size()
	_spawn_tethers(tethers)


## The Spire's light tether: a tapering column standing on the beacon, bright enough to read from V1.
func _spawn_tethers(tethers: Array) -> void:
	if tethers.is_empty():
		return
	for at: Vector3 in tethers:
		var node := MeshInstance3D.new()
		node.name = "tether"
		node.mesh = _tether_mesh()
		# r16b §4: gain 3.0 peaked at 8.2 linear — over the clip gate. 1.7 peaks at 4.1 and still
		# blooms (threshold 2.6).
		node.material_override = McMaterials.accent_variant(&"tether", 1.7, 0.85, 0.5, 1)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A CylinderMesh is centred on its origin, so its base has to be lifted onto the beacon.
		node.position = at + Vector3.UP * TETHER_HEIGHT * 0.5
		node.extra_cull_margin = TETHER_HEIGHT
		add_child(node)
	counts[&"tether"] = tethers.size()


## Hand the hive positions to the infection field so creep and props agree on where a hive is.
func _apply_hive_sites() -> void:
	if _placer.hive_sites.is_empty():
		return
	var field := get_tree().get_first_node_in_group(&"infection")
	if field == null:
		return
	for id in _placer.hive_sites:
		field.call(&"register_site", id, _placer.hive_sites[id], HIVE_RADIUS)
		field.call(&"set_intensity", id, 1.0, 0.01)


func _process(delta: float) -> void:
	if _koi == null:
		return
	# The koi circles Block 9 on the real clock, so it keeps its lap through hit-stop and witch time.
	_koi_angle += TAU * Feel.real_delta(delta) / KOI_PERIOD
	_koi.position = _koi_centre + Vector3(cos(_koi_angle), 0.0, sin(_koi_angle)) * KOI_RADIUS
	_koi.rotation.y = -_koi_angle + PI * 0.5
