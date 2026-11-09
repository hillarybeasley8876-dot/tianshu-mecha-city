class_name RoofGreebles
extends Node3D
## Fine rooftop machinery on every tier B-D roof (city-art, lead r4 §1).
##
## city-build's `roof_machine` slots already carry the big Tripo props (844 of them). What was missing
## is the layer below them — plant boxes, duct runs, vent stacks, aerial masts and the red aircraft
## warning lights that a dusk skyline is made of. Those are what break a roof's silhouette against the
## sky, and the key art has them on every single roof.
##
## Everything is procedural boxes and cylinders in one MultiMesh per kind per 3x3 tile group, so the
## whole layer is a few dozen draw calls and nothing has to be authored or imported.

const GROUP_TILES := 3            ## 3 x 3 city tiles (600 m) share one MultiMesh per kind
const VISIBILITY_M := 900.0
const AREA_PER_GREEBLE := 130.0   ## m^2 of roof per greeble
const MAX_PER_ROOF := 26
const MAST_CHANCE := 0.22         ## share of roofs that carry an aerial mast with a warning light
const MARGIN := 3.5               ## keep clear of the parapet

## kind -> the prototype each one draws. A mast is two MultiMeshes on the same transforms, because a
## MultiMeshInstance3D has only `material_override`: the steel pole cannot share an instance with the
## aviation lamp on top of it.
const KINDS: Array[StringName] = [&"plant", &"duct", &"vent", &"mast", &"dish", &"mast_lamp"]
## What the per-roof scatter picks from. NOT `KINDS[:4]`: a `mast` drawn by the scatter has no lamp
## over it, so the mast and mast_lamp lists stop being the same length and the lamp batch cannot
## follow the pole it belongs to.
const SCATTER_KINDS: Array[StringName] = [&"plant", &"duct", &"vent", &"dish"]

var placed: int = 0
var groups: int = 0
var dropped: int = 0          ## r10: greebles with no kit roof under them, thrown away
## r12 §2: roofs the map says have nowhere flat to stand (an old-town pitched tile roof, a spire
## crown). Nothing is scattered on them at all, which is why they no longer arrive at the settle pass
## only to be thrown away — a greeble the placement knows cannot stand is never placed.
var roofs_skipped: int = 0
var no_roof: int = 0
## kind -> the transforms actually drawn. The float gate reads this instead of the MultiMesh, whose
## instance transforms are identity under the dummy renderer a head-less test runs on.
var emitted: Dictionary = {}


## `design` supplies the buildings; `decks` (optional) adds the arena podium tops, which carry no
## `roof_machine` slots and were reading as bare slabs in every vista.
##
## `settle` (r10) is the settle pass. `roof_map` (r12) is city-kit's measured roof surface: a greeble is
## AIMED at it rather than at the DESIGN box top, which a Tripo building only reaches somewhere on its
## footprint. Without it every unit over a podium, a setback or a crown hung in the air — 122 m of air
## in the worst case — and 1 099 of them were thrown away.
func build(design: Dictionary, seed: int = 20261102, settle: CitySettle = null,
		roof_map: KitRoofMap = null) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var by_group: Dictionary = {}     # group key -> kind -> Array[Transform3D]
	for b in design.get("buildings", []):
		var row := b as Dictionary
		var tier := String(row.get("tier", "B"))
		if tier == "A" and not bool(row.get("roof_walkable", false)):
			continue
		var size: Array = row.get("size", [20.0, 20.0])
		var w := float(size[0]) - MARGIN * 2.0
		var d := float(size[1]) - MARGIN * 2.0
		if w < 6.0 or d < 6.0:
			continue
		var centre: Array = row.get("center", [0.0, 0.0])
		var top := float(row.get("base_z", 0.0)) + float(row.get("height", 0.0))
		var org := Vector2(float(centre[0]), -float(centre[1]))
		var rot := -deg_to_rad(float(row.get("rot", 0.0)))
		# One probe for the whole roof: a roof with nowhere flat to stand gets no machinery at all,
		# rather than 26 units that the settle pass then throws away one at a time.
		if roof_map != null and roof_map.roof_at(Vector3(org.x, top, org.y), top).is_empty():
			roofs_skipped += 1
			continue
		var count := clampi(int(w * d / AREA_PER_GREEBLE), 3, MAX_PER_ROOF)
		if rng.randf() < MAST_CHANCE:
			var mast := _aimed(roof_map, org, 0.0, 0.0, top, rot, 0.0,
					rng.randf_range(0.6, 1.5))
			if not mast.is_empty():
				_push(by_group, _key(org), &"mast", mast["xf"])
				_push(by_group, _key(org), &"mast_lamp", mast["xf"], false)
		for i in range(count):
			var local := Vector2(rng.randf_range(-w * 0.5, w * 0.5), rng.randf_range(-d * 0.5, d * 0.5))
			var kind: StringName = SCATTER_KINDS[rng.randi_range(0, SCATTER_KINDS.size() - 1)]
			var unit := _aimed(roof_map, org, local.x, local.y, top, rot,
					rng.randf_range(0.0, 360.0), rng.randf_range(0.7, 1.6))
			if unit.is_empty():
				no_roof += 1
				continue
			_push(by_group, _key(org), kind, unit["xf"])
	for key in by_group:
		var node := Node3D.new()
		node.name = "Greebles_" + String(key).replace(",", "_")
		add_child(node)
		groups += 1
		var group := by_group[key] as Dictionary
		for kind in group:
			if kind == &"mast_lamp":
				continue          # emitted with the mast it rides on, below
			var list: Array = group[kind]
			if settle != null:
				var before := list.size()
				list = settle.settle(list, _mesh_for(kind), CitySettle.RULE_ROOF,
						"greeble:" + String(kind), "%s|%s" % [key, kind])
				dropped += before - list.size()
				placed -= before - list.size()
				if kind == &"mast" and group.has(&"mast_lamp"):
					# The lamp is the same transform list 9.3 m up the pole, so it follows the mast
					# instead of being settled on its own (much smaller) mesh.
					group[&"mast_lamp"] = CitySettle.follow(group[&"mast_lamp"] as Array,
							settle.last_kept, settle.last_delta)
			if not list.is_empty():
				_emit(node, kind, list)
		if group.has(&"mast_lamp") and not (group[&"mast_lamp"] as Array).is_empty():
			_emit(node, &"mast_lamp", group[&"mast_lamp"] as Array)
	return placed


func _push(by_group: Dictionary, key: StringName, kind: StringName, xf: Transform3D,
		count_it: bool = true) -> void:
	if not by_group.has(key):
		by_group[key] = {}
	var group := by_group[key] as Dictionary
	if not group.has(kind):
		group[kind] = [] as Array[Transform3D]
	(group[kind] as Array).append(xf)
	if count_it:
		placed += 1


## Roofs are grouped by a 600 m cell so a MultiMesh can be culled by distance without one node per roof.
static func _key(org: Vector2) -> StringName:
	var gx := int(floor(org.x / (200.0 * float(GROUP_TILES))))
	var gz := int(floor(org.y / (200.0 * float(GROUP_TILES))))
	return StringName("%d_%d" % [gx, gz])


## One unit, aimed at the roof map. Returns `{"xf": Transform3D}` or `{}` when there is nowhere to
## stand. Without a map this is exactly the old rule: the design box top.
func _aimed(roof_map: KitRoofMap, org: Vector2, lx: float, lz: float, top: float, rot: float,
		yaw_deg: float, scale: float) -> Dictionary:
	var local := Vector2(lx, lz).rotated(rot)
	var at := Vector3(org.x + local.x, top, org.y + local.y)
	if roof_map != null:
		var hit := roof_map.roof_at(at, top)
		if hit.is_empty():
			return {}
		at = hit["at"]
	return {"xf": Transform3D(Basis(Vector3.UP, rot + deg_to_rad(yaw_deg))
			.scaled(Vector3(scale, scale, scale)), at)}


func _emit(parent: Node3D, kind: StringName, xforms: Array) -> void:
	# r16a: the transforms actually drawn, accumulated across every 600 m group. The float gate reads
	# this instead of the MultiMesh, whose instance transforms are identity under the dummy renderer a
	# head-less test runs on — and it was declared and never filled, so `test_float` measured the whole
	# greeble layer as zero instances while the windowed audit was reporting it.
	var list: Array = emitted.get(kind, [])
	list.append_array(xforms)
	emitted[kind] = list
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh_for(kind)
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var node := MultiMeshInstance3D.new()
	# The raw kind, not `capitalize()`: that turns "mast_lamp" into "Mast Lamp" and breaks any
	# name-based lookup (`--art-debug=hide=`, tests).
	node.name = String(kind)
	node.multimesh = mm
	# A MultiMeshInstance3D has only `material_override`, so the aviation lamp on top of a mast is its
	# own MultiMesh over the same transforms rather than a second surface of the pole.
	node.material_override = McMaterials.glow_band(ArtPalette.AVIATION_RED, 3.4) if kind == &"mast_lamp" \
		else McMaterials.get_material(&"mc_metal")
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = VISIBILITY_M
	node.visibility_range_end_margin = 60.0
	parent.add_child(node)


## One unit-sized prototype per kind, built once and shared by every instance in the map.
func _mesh_for(kind: StringName) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		&"plant":
			McMeshKit.box(st, Vector3(0.0, 1.2, 0.0), Vector3(4.0, 2.4, 3.0))
			McMeshKit.box(st, Vector3(0.6, 2.7, 0.0), Vector3(1.8, 0.6, 1.6))
			McMeshKit.box(st, Vector3(-1.2, 2.55, 0.4), Vector3(0.8, 0.3, 0.8))
		&"duct":
			McMeshKit.box(st, Vector3(0.0, 1.1, 0.0), Vector3(8.0, 0.9, 1.1))
			McMeshKit.box(st, Vector3(-2.6, 0.35, 0.0), Vector3(0.3, 0.7, 0.3))
			McMeshKit.box(st, Vector3(2.6, 0.35, 0.0), Vector3(0.3, 0.7, 0.3))
		&"vent":
			McMeshKit.cyl(st, Vector3.ZERO, 0.75, 1.7, 8)
			McMeshKit.cyl(st, Vector3(0.0, 1.7, 0.0), 0.95, 0.28, 8)
		&"dish":
			McMeshKit.cyl(st, Vector3.ZERO, 0.22, 1.6, 6)
			McMeshKit.box(st, Vector3(0.0, 1.9, 0.0), Vector3(2.2, 0.25, 2.2))
			McMeshKit.box(st, Vector3(0.0, 2.2, 0.0), Vector3(0.5, 0.5, 0.5))
		&"mast":
			McMeshKit.cyl(st, Vector3.ZERO, 0.20, 9.0, 6)
			McMeshKit.box(st, Vector3(0.0, 6.2, 0.0), Vector3(2.4, 0.16, 0.16))
			McMeshKit.box(st, Vector3(0.0, 7.4, 0.0), Vector3(1.6, 0.14, 0.14))
		&"mast_lamp":
			McMeshKit.lamp(st, Vector3(0.0, 9.3, 0.0), 0.7)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	return mesh
