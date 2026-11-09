class_name CityArt
extends Node
## Art integration root (city-art, CONTRACTS §7 "Art integration"). `world/city.tscn` instances
## `world/art/environment.tscn` as a child and owns no sky, sun or WorldEnvironment of its own; this node
## is the other half of that contract: on ready it finds the city that instanced it, swaps every
## `mc_*` surface for this unit's material, dresses the districts (props, holograms, effects) and places
## one reflection probe per arena. city.gd calls its `_environment()` AFTER `_instance_tiles()`, so the
## tiles already exist when this runs and no deferred retry is needed.

## The runtime layout city-build exports. Everything positional comes from here.
const RUNTIME_LAYOUT := "res://world/city/layout.json"

## Counters other units and the vista harness read back after load.
signal spire_ready

var host: Node = null          ## the city node that instanced us (null in a bare look-dev scene)
var surfaces: int = 0          ## mc_* surfaces swapped for the real materials
var props: int = 0             ## prop instances scattered
var probes: int = 0            ## reflection probes placed
var spire_strips: int = 0      ## accent strips on the Spire shaft (set one frame after load)
var spire_rings: int = 0       ## glowing ring edges on the Spire
var mask_buildings: int = 0    ## footprints rasterised into the facade mask (review r3 §1)
var skyline_surfaces: int = 0  ## distant-ring surfaces given the silhouette material (review r3 §3)
var signs: int = 0             ## blade signs, shopfront bands, parapet lines and billboards (r3 §2)
var greebles: int = 0          ## procedural rooftop machinery instances (r4 §1)
var web_spans: int = 0         ## cable crossings strung between facades (r4 §1)
var scaffolds: int = 0         ## half-clad construction sites (r4 §1)
var cargo: int = 0             ## arena cover pieces dressed as container stacks (look review item 3)
var settle: CitySettle = null  ## the r10 settle pass; null when there is no kit to settle onto
var supports: int = 0          ## rendered surfaces in the settle index
var occluders: CityOcclusion = null  ## r13: the occluder set, or null when it is switched off

## Kit models the settle pass is allowed to MOVE (r10b): DRESSING with no collider and no structural
## role. Everything else the placer lays is either architecture (tier `detail`, never touched) or
## STRUCTURE — deck slabs, viaduct pylons, street skirts, market rows, railings, pipe racks and the
## arena cover — whose placement comes from the same layout data as city-build's colliders. Moving or
## dropping one of those leaves the collider behind: invisible walls, invisible floors and holes.
const KIT_DRESSING: Array[String] = ["s08"]
## Kit models that HANG off a slab's outer face — the deck and viaduct fasciae. Nothing is under them
## by design, so neither the settle pass nor the audit judges them.
const KIT_HANGING: Array[String] = ["u01", "u02"]
## Kit models that stand in for an arena cover box. They are STRUCTURE (the collider is the same box)
## AND they are the one structure whose copies stack, so the audit judges their bottom layer only.
const KIT_COVER: Array[String] = ["k01", "k02", "k03", "k04", "k05", "k06", "k07", "k08", "k09",
		"k10", "k11", "k12"]


## What a kit model IS, in one place, so the settle pass, the windowed audit and `test_float.gd` cannot
## disagree about which batches are dressing: "dressing" | "structure" | "cover" | "hanging".
static func kit_role(model: String) -> String:
	if model in KIT_DRESSING:
		return "dressing"
	if model in KIT_HANGING:
		return "hanging"
	return "cover" if model in KIT_COVER else "structure"


func _ready() -> void:
	McMaterials.ensure_globals()
	host = _find_city()
	if host == null:
		# A look-dev scene (street, prop row, GI check) has no city: the environment still works, it just
		# has nothing of city-build's to re-material. Not an error.
		return
	surfaces = McMaterials.apply_to(host)
	# The design layout keeps the streets and buildings the runtime one drops, so street furniture can
	# follow the kerb line. `ArtRepo.design_layout()` is a `res://` copy written by the same Blender step
	# that writes `world/city/layout.json` (city-art r12 §3 — this used to be an absolute
	# home path, which an exported build on any other machine could not open, so the roof dressing and
	# the cargo blocks silently vanished there).
	var design := _read_json(ArtRepo.design_layout())
	var layout := _read_json(RUNTIME_LAYOUT)
	mask_buildings = _facade_mask(design, layout)
	skyline_surfaces = _skyline() + _hlod_far()
	if layout.is_empty():
		push_error("CityArt: %s missing or unreadable — the city keeps its blockout dressing"
				% RUNTIME_LAYOUT)
		return
	# r10: everything below places RESTING dressing, so the surface it rests on has to exist first.
	settle = _settle_pass()
	props = _dress(layout)
	_occlusion(design)
	# The push lists only fill in on a real renderer (head-less uses the dummy one, where a shader's
	# uniform list is empty), so this line is the evidence that the facade / haze / wetness pushes
	# actually reached materials in a windowed run.
	print("ART materials registered %s" % McMaterials.registered())
	signs = _signs(design)
	greebles = _greebles(design)
	web_spans = _web(design)
	scaffolds = _scaffolds(design)
	probes = _probes(layout)
	cargo = _cargo(layout, design)
	_spire(layout, design)
	_shadows()
	if settle != null:
		settle.report()
		# 1 500 static bodies left in the world would be in every broadphase for the rest of the
		# session, so the index goes as soon as the last batch has been settled.
		if settle.surfaces != null:
			settle.surfaces.dispose()
		if settle.cache != null and settle.cache.dirty:
			settle.cache.save()
	_debug_hide()


## r13: the shadow-casting policy (see `ArtShadows`). Applied once, after every layer has placed its
## meshes, because the rule is about the mesh that ended up in the scene rather than about who placed
## it — and it covers city-kit's far LODs and city-build's HLOD merges without editing either placer.
func _shadows() -> void:
	var t0 := Time.get_ticks_msec()
	var counts := ArtShadows.apply(host)
	print("ART shadows off: %d small meshes, %d far-tier meshes (%d ms)"
			% [counts["small"], counts["far"], Time.get_ticks_msec() - t0])


## r13: the occluder set. `project.godot` has had occlusion culling on since the blockout days, but the
## game contained no occluders at all, so the setting cost a little and bought nothing. Built from the
## two files this unit already reads — the design layout and city-kit's roof map — so nothing is
## rebuilt and no tile is touched. `--no-occluders` is the A/B arm.
func _occlusion(design: Dictionary) -> void:
	if Game.has_flag("no-occluders"):
		print("ART occluders OFF (--no-occluders)")
		return
	var t0 := Time.get_ticks_msec()
	var roofs := settle.roof_map if settle != null else KitRoofMap.load()
	occluders = CityOcclusion.build(host as Node3D, design, roofs)
	if occluders == null:
		push_warning("CityArt: no occluders built — the design layout had nothing to build them from")
		return
	print("ART occluders %d boxes in %d tiles (%d capped by the roof map, %d uncapped) in %d ms"
			% [occluders.boxes, occluders.tiles, occluders.capped, occluders.uncapped,
			   Time.get_ticks_msec() - t0])


## r10: the settle pass. Builds the rendered-surface index (kit near meshes + tile render meshes) and
## hands it to the pass that settles city-kit's own resting pieces and then our dressing.
##
## The index is built ONCE. It does not have to be rebuilt after the kit pieces move, because the only
## supports a resting thing may stand on are `ArtSurfaces.ARCHITECTURE` — kit BUILDINGS and city-build's
## tile meshes, neither of which the pass ever moves. Rebuilding it cost 1.25 s of a 1.5 s budget for
## an answer that could not change.
func _settle_pass() -> CitySettle:
	if Game.has_flag("no-settle") or OS.get_environment("NO_SETTLE") == "1":
		# The r10 before/after A/B: with this flag the city is exactly what it was at 8f2bfd1, so the
		# two sheets are the same build with one pass switched off. The env var is here because
		# `tools/godot.sh run` has no pass-through for extra arguments and the wrapper is the lead's.
		print("ART settle pass OFF (--no-settle)")
		return null
	var t0 := Time.get_ticks_msec()
	var kit := host.get_node_or_null(^"KitPlacer")
	var baking := OS.get_environment("SETTLE_BAKE") == "1"
	var legacy := OS.get_environment("SETTLE_STRUCTURE") == "1"
	# r16a: recompute the pass from the RULES without writing a new bake. The float gate
	# (`world/art/tests/test_float.gd`) measures the replayed bake, so a rule change is invisible to it
	# until the next bake; this makes a rule change measurable head-lessly in one run.
	var recompute := OS.get_environment("SETTLE_RECOMPUTE") == "1"
	var pass_settle := CitySettle.new(null)
	# r12 §2: city-kit measured every kit building's real top surface into `kit.json`, so a roof unit is
	# aimed at the roof instead of at the design box top. Read once; it is a few hundred kB of bytes.
	# `--no-roofmap` is the r11 A/B arm: the pass behaves exactly as it did before r12, aiming every roof
	# unit at the design box top. Same build, same machine, one rule apart — which is the only way the
	# "1 099 dropped -> N" claim is worth anything.
	var off := Game.has_flag("no-roofmap") or OS.get_environment("ROOF_MAP") == "0"
	var roofs := KitRoofMap.new() if off else KitRoofMap.load()
	pass_settle.roof_map = null if roofs.is_empty() else roofs
	print("ART roof map %d models, %d kit buildings%s"
			% [roofs.models, roofs.buildings, "" if pass_settle.roof_map != null else " (OFF)"])
	var trace := OS.get_environment("SETTLE_TRACE")
	if not trace.is_empty():
		pass_settle.trace_m = float(trace)
	var verify := OS.get_environment("SETTLE_VERIFY_M")
	if not verify.is_empty():
		pass_settle.verify_m = float(verify)
	pass_settle.trace_miss = OS.get_environment("ROOF_TRACE") == "1"
	var replaying := false
	# The r10b A/B (`SETTLE_STRUCTURE=1`) settles batches the bake does not contain, so it has to
	# compute rather than replay — and it must never write what it computed over the real bake.
	if not baking and not legacy and not recompute:
		pass_settle.cache = SettleCache.load()
		replaying = pass_settle.cache != null
		if replaying:
			print("ART settle replaying %d baked batches (stamp %s)"
					% [pass_settle.cache.batches.size(), pass_settle.cache.stamp.substr(0, 8)])
		else:
			push_warning("CityArt: %s is missing or stale — the settle pass is recomputing at load "
					% SettleCache.PATH + "(~2.2 s). Re-bake: SETTLE_BAKE=1 tools/godot.sh run "
					+ "res://tools/float_audit.tscn 600")
	if not replaying:
		var index := ArtSurfaces.new()
		supports = index.build(host, kit)
		pass_settle.surfaces = index
		if baking:
			pass_settle.cache = SettleCache.new()
		print("ART surfaces %d supports in the physics world, indexed in %d ms (shapes %d ms, bodies "
				% [supports, index.built_ms, index.shape_ms] + "%d ms)" % index.body_ms)
	# The kit's own pieces settle in BOTH modes: replaying the cache still has to walk every batch, it
	# just does not cast a ray.
	if kit != null and kit.has_method(&"near_batches"):
		_settle_kit(kit, pass_settle)
	print("ART settle pass: %d ms so far" % (Time.get_ticks_msec() - t0))
	return pass_settle


## Settles the kit's own ROOF MACHINERY, and nothing else (r10b). Buildings (tier `detail`) are
## architecture and stand on their own footprint; every other kit model is structure whose collider
## city-build builds from the same layout box, so a settle that moved or dropped one would leave the
## collider behind. If one of those is off its surface, `float_audit`'s STRUCTURE section reports it by
## row id and the rule that placed it is what gets fixed.
##
## `SETTLE_STRUCTURE=1` puts the r10 rule back (every non-hanging kit batch settled) so the r10b
## before/after sheets are the same build with one rule switched. Debug only.
func _settle_kit(kit: Node, pass_settle: CitySettle) -> void:
	var legacy := OS.get_environment("SETTLE_STRUCTURE") == "1"
	if legacy:
		push_warning("CityArt: SETTLE_STRUCTURE=1 — settling kit STRUCTURE the way r10 did. This moves "
				+ "and drops deck slabs, pylons and arena cover whose colliders stay where they were.")
	for batch: Dictionary in kit.call(&"near_batches"):
		var model := String(batch["model"])
		var role := kit_role(model)
		if role == "hanging" or (not legacy and role != "dressing"):
			continue
		var rule := CitySettle.RULE_ROOF if role == "dressing" else CitySettle.RULE_STREET
		var kept := pass_settle.settle(batch["list"] as Array, batch["mesh"] as Mesh, rule,
				"kit:" + model, String(batch["name"]))
		kit.call(&"upload", batch, kept)


## Diagnostic (`--art-debug=hide=<name fragment>`): hides every mesh whose node name contains the
## fragment. Attributing a flat mass in a capture by raycasting only reaches the COLLISION geometry,
## and the things worth blaming (HLOD proxies, backdrop cards) have none — so the honest way to find
## out what a shape is, is to remove it and look again.
func _debug_hide() -> void:
	var what := Game.flag("art-debug")
	if not what.begins_with("hide="):
		return
	var needle := what.substr(5)
	var hidden := 0
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		# Node3D as well as MeshInstance3D: the things worth blaming are often a whole imported subtree
		# (city-build's ring is a glb root named "Skyline" whose children are the meshes), and matching
		# only the meshes silently hid nothing.
		if n is Node3D and String(n.name).contains(needle):
			(n as Node3D).visible = false
			hidden += 1
		stack.append_array(n.get_children())
	print("ART-DEBUG hid %d nodes matching '%s'" % [hidden, needle])


## Review r3 §1: rasterise the design layout's footprints once and hand the mask to every facade
## material. Without a design layout (an exported build) the facades stay blank rather than guessing.
func _facade_mask(design: Dictionary, runtime: Dictionary = {}) -> int:
	if design.is_empty():
		return 0
	var mask := FacadeMask.new()
	McMaterials.set_facade_mask(mask.build(design, runtime))
	return mask.buildings


## Review r3 §3: city.gd names its ring instance "Skyline" and ships it with one `mc_concrete` surface,
## which made it a lit wall across every vista. It gets the ring's own silhouette material instead.
func _skyline() -> int:
	var node := host.get_node_or_null(^"Skyline")
	if node == null:
		push_warning("CityArt: no 'Skyline' child on %s — the distant ring keeps its blockout material"
				% host.name)
		return 0
	return McMaterials.apply_skyline(node)


## Review r3 §3: the flat band that closed every vista is city-build's HLOD layer, not the ring.
## `--art-debug=hide=_hlod` removes it and the real skyline is behind it (captures/hide2__hlod_high.jpg).
## Some of the proxies also carry the map-edge backdrop: `t-1_3_hlod` is a planar 0 x 260 x 1,406 m
## card and `t0_3_hlod` merges one into 353 x 260 x 1,406 m of massing, both far larger than the 200 m
## tile they stand in for.
##
## All of it renders only past city-build's HLOD_BEGIN (430 m), which is exactly the band where a
## surface should be dissolving into haze anyway — so the whole layer takes the ring's silhouette
## material. That fixes the read without touching geometry that is not mine. The proper fix is
## city-build's (see `## Requests`): keep the backdrop cards out of the HLOD merge and push them to
## the ring radius, or give them their own role instead of `mc_concrete`.
func _hlod_far() -> int:
	var mat := McMaterials.skyline_hlod()
	var changed := 0
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and String(n.name).ends_with("_hlod"):
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				changed += McMaterials.apply_skyline(mi, mat)
		stack.append_array(n.get_children())
	return changed


## The Spire's shaft strips and ring edges (review r2 §5). It raycasts the built tower, so it needs the
## physics world: `build` awaits a physics frame, which makes this a coroutine — the counters land a
## frame after load and `await art.spire_ready` is how a test waits for them.
func _spire(layout: Dictionary, design: Dictionary) -> void:
	var height := 360.0
	for lm in design.get("landmarks", []):
		if String(lm.get("kind", "")) == "spire":
			height = float((lm.get("params", {}) as Dictionary).get("height", height))
	for lm in layout.get("landmarks", []):
		if String(lm.get("kind", "")) != "spire" or not lm.has("pos"):
			continue
		var p: Array = lm["pos"]
		var node := SpireLights.new()
		node.name = "SpireLights"
		add_child(node)
		await node.build(Vector3(float(p[0]), 0.0, -float(p[1])), height)
		spire_strips = node.strips
		spire_rings = node.rings
		spire_ready.emit()
		return
	push_warning("CityArt: no spire landmark in %s — the Spire keeps its tether only" % RUNTIME_LAYOUT)


## The city is either our parent's parent (`world/city.tscn`) or a sibling (the vista harness adds the
## environment next to the city). Both are found by the script contract, never by node name.
func _find_city() -> Node:
	var n: Node = get_parent()
	while n != null:
		if _is_city(n):
			return n
		for child in n.get_children():
			if _is_city(child):
				return child
		n = n.get_parent()
	return null


func _is_city(n: Node) -> bool:
	return n.get(&"layout") != null and n.has_method(&"to_godot")


func _dress(layout: Dictionary) -> int:
	var scatter := PropScatter.new()
	scatter.name = "Dressing"
	add_child(scatter)
	var n := scatter.dress(layout, _read_json(ArtRepo.design_layout()), 20261101, settle)
	print("ART roof props: %d slots had nowhere flat to stand" % scatter.no_roof)
	return n


## Review r3 §2: the signage layer needs the design layout's footprints, so it cannot live in
## PropScatter (which takes the runtime layout). One node, four batches, a handful of draw calls.
func _signs(design: Dictionary) -> int:
	if design.is_empty():
		return 0
	var node := FacadeSigns.new()
	node.name = "Signs"
	add_child(node)
	return node.build(design)


## Lead r4 §1: plant boxes, duct runs, vent stacks and aerial masts on every tier B-D roof. The big
## roof machines are city-build's slots (PropPlacer fills 844 of them); this is the layer under them.
func _greebles(design: Dictionary) -> int:
	if design.is_empty():
		return 0
	var node := RoofGreebles.new()
	node.name = "Greebles"
	add_child(node)
	var n := node.build(design, 20261102, settle, settle.roof_map if settle != null else null)
	print("ART greebles %d placed, %d roofs with nowhere flat, %d units with no flat cell"
			% [n, node.roofs_skipped, node.no_roof])
	return n


## Lead r4 §1: cable bundles and washing lines across the streets. Thin dark lines over a bright sky
## are most of what the key art has that a blockout does not, and they cost two draw calls.
func _web(design: Dictionary) -> int:
	if design.is_empty():
		return 0
	var node := StreetWeb.new()
	node.name = "StreetWeb"
	add_child(node)
	return node.build(design)


## Lead r4 §1: two half-clad construction sites. A scaffold lattice down a tower face is the most
## legible "this city is still being built" read there is, and it breaks a box silhouette for 100 m.
func _scaffolds(design: Dictionary) -> int:
	if design.is_empty():
		return 0
	var node := Scaffolds.new()
	node.name = "Scaffolds"
	add_child(node)
	return node.build(design)


## One reflection probe per arena (ART.md §3), created at load so the first probe never compiles a
## pipeline mid-game (godot-tech §4.6).
func _probes(layout: Dictionary) -> int:
	if not bool(ArtQuality.get_preset().get("reflection_probes", false)):
		return 0
	var node := ArenaProbes.new()
	node.name = "ArenaProbes"
	add_child(node)
	return node.build(layout.get("arenas", []))


## Look review 2026-11-02 item 3: the 360 arena cover pieces are the closest geometry to the camera and
## were bare kit boxes. This dresses each one as a stack of shipping containers — same footprint, same
## collider, a skin drawn 2 cm proud plus a few containers perched off-grid for silhouette.
func _cargo(layout: Dictionary, design: Dictionary) -> int:
	var node := CargoBlocks.new()
	node.name = "Cargo"
	add_child(node)
	var n := node.build(layout, design)
	# The skipped count is the evidence for the one-owner rule (lead r7): every piece in it is dressed by
	# city-kit's own Tripo cover model instead, so it must never be a container skin as well.
	print("ART cover dressed=%d soft=%d hard=%d low=%d kit-owned=%d"
			% [n, node.soft_n, node.hard_n, node.low_n, node.skipped_kit])
	return n


## Reads a JSON object, warning (not erroring) when the file is absent — the design layout is optional.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		if path == RUNTIME_LAYOUT:
			push_error("CityArt: cannot open %s" % path)
		else:
			push_warning("CityArt: no %s — street furniture will be skipped" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("CityArt: %s is not a JSON object" % path)
		return {}
	return parsed as Dictionary
