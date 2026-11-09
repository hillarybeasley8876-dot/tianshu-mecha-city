extends RefCounted
## Per-round look-review checks for `test_art.gd` (city-art). Split out because the runner passed the
## 600-line limit; each `check_rN` is one lead review round's contracts, and they are the ones that
## grow every round. The runner (`test_art.gd`) owns the failure counter and the scene tree, so this
## file borrows both through `runner` rather than duplicating them.

const SH_SKYLINE := preload("res://world/art/shaders/mc_skyline.gdshader")

## The `test_art.gd` node: `_expect` records a failure, `add_child` is how a fixture layer gets a tree.
var runner: Node


func _init(host: Node) -> void:
	runner = host


func _expect(ok: bool, what: String) -> void:
	runner.call(&"_expect", ok, what)


## Look review 2026-11-02. Item 1 is a silent failure by construction — a tiling map imported without
## mipmaps still loads, still draws, and only fizzes — so it gets an assertion. Item 3 is the arena
## cover dressing: the check that matters is that every destructible piece got a skin, that the skin is
## one batch, and that the perched containers are stacked rather than floating.
func check_r7() -> void:
	# Item 1: every map in the CC0 library must carry a mip chain. `detect_3d` cannot upgrade them,
	# because surface_factory binds them to a ShaderMaterial at runtime and the editor never sees them
	# used in 3D — tools/textures/fetch.py now writes the .import itself.
	var missing: Array[String] = []
	var checked := 0
	for set_id in ["brushed_concrete", "metal_plate", "concrete_panels", "clay_plaster",
			"clay_roof_tiles_02"]:
		for map in ["diff", "nor_gl", "rough"]:
			var path := "res://assets/textures/%s/%s_%s.jpg" % [set_id, set_id, map]
			if not ResourceLoader.exists(path):
				continue
			checked += 1
			var img := (load(path) as Texture2D).get_image()
			if img == null or img.get_mipmap_count() < 2:
				missing.append(path)
	_expect(checked == 15, "all 15 library maps were found (%d)" % checked)
	_expect(missing.is_empty(), "every library map ships a mip chain (%s)" % str(missing))

	# Item 3: the cover dressing, on a fixture with both a destructible and a permanent piece.
	var cargo := CargoBlocks.new()
	runner.add_child(cargo)
	_no_kit_file(cargo)
	var design := _fake_cover_layout()
	var n := cargo.build({}, design, 11)
	_expect(n == 2, "both cover pieces were dressed (%d)" % n)
	_expect(cargo.soft_n == 1 and cargo.hard_n == 1, "one container stack and one landscaped wall")
	var skin_batches := 0
	var inst := 0
	for group in cargo.get_children():
		for batch in (group as Node3D).get_children():
			if String(batch.name) == "skin":
				skin_batches += 1
				inst += ((batch as MultiMeshInstance3D).multimesh as MultiMesh).instance_count
	_expect(skin_batches == 1 and inst == 1, "the skins are ONE batch of one instance per slot")
	# Every perched container must rest on something: its base cannot be above the stack's own top
	# (8 m of box + city-build's cap + the 2 cm of skin that stands proud on each side). The MultiMesh
	# cannot be read back head-less, so the layer records what it placed.
	var stack_top := 8.0 + CargoBlocks.CAP_H + 0.05
	var floating := 0
	for xf in cargo.placed.get(&"perch", []):
		var half: float = (xf as Transform3D).basis.y.length() * 0.5
		if (xf as Transform3D).origin.y - half > stack_top:
			floating += 1
	_expect(floating == 0, "no perched container hangs in mid-air (%d did)" % floating)
	# The design layout is the only source that says `soft`; with it absent the runtime slots are used.
	var runtime := {"prop_slots": [{"kind": "breakable_cover", "arena": "A1", "index": 0,
		"pos": [0.0, 0.0, 0.0], "size": [20.0, 20.0, 8.0]}]}
	var fallback := CargoBlocks.new()
	runner.add_child(fallback)
	_no_kit_file(fallback)
	_expect(fallback.build(runtime, {}, 11) == 1 and fallback.soft_n == 1,
		"without the design layout the runtime breakable_cover slots still dress")
	cargo.queue_free()
	fallback.queue_free()


## Lead r7. One owner per cover piece: where `kit_assign.json` (and the runtime `kit_skin.cover` that
## city-build bakes from it) gives a piece a Tripo model, CargoBlocks must leave it alone — a container
## skin drawn over city-kit's cluster is two owners fighting for the same volume. Plus the two polish
## items: a low soft piece must not be one flat slab, and the permanent wall must carry its pour marks.
func check_r8() -> void:
	# Ownership: the second piece ("A1#1") is claimed by the kit, so only the first one is dressed.
	var owned := {"kit_skin": {"cover": ["A1#1"]}}
	var cargo := CargoBlocks.new()
	runner.add_child(cargo)
	_no_kit_file(cargo)
	var n := cargo.build(owned, _fake_cover_layout(), 11)
	_expect(n == 1 and cargo.hard_n == 0, "the kit-owned piece was skipped (%d dressed)" % n)
	_expect(cargo.skipped_kit == 1, "one piece was left to city-kit (%d)" % cargo.skipped_kit)
	var drawn := 0
	for group in cargo.get_children():
		for batch in (group as Node3D).get_children():
			var mm := (batch as MultiMeshInstance3D).multimesh as MultiMesh
			drawn += mm.instance_count
	# Nothing may land near the kit-owned piece, which sits 60 m east in the fixture.
	var far := 0
	for kind in cargo.placed:
		for xf in cargo.placed[kind]:
			if absf((xf as Transform3D).origin.x - 60.0) < 20.0:
				far += 1
	_expect(drawn >= 3 and far == 0,
		"nothing was drawn on the kit-owned piece (%d instances, %d near it)" % [drawn, far])

	# The low soft piece: separate containers with daylight between them, not one slab.
	_expect(cargo.low_n == 1, "the 8 m soft piece took the low-stack path")
	var singles: Array[Vector2] = []
	for xf in cargo.placed.get(&"perch", []):
		var o := (xf as Transform3D).origin
		singles.append(Vector2(o.x, o.z))
	var closest := 1e9
	for i in range(singles.size()):
		for j in range(i + 1, singles.size()):
			closest = minf(closest, singles[i].distance_to(singles[j]))
	_expect(singles.size() >= 2 and closest > 2.0,
		"the low stack carries %d singles, nearest pair %.1f m apart" % [singles.size(), closest])

	# The permanent wall: a board-formed pour, not a flat value.
	var wall := cargo._material_for(&"wall") as ShaderMaterial
	_expect(float(wall.get_shader_parameter(&"board_m")) > 0.0
			and float(wall.get_shader_parameter(&"form_tie_m")) > 0.0
			and float(wall.get_shader_parameter(&"reveal_m")) > 0.0,
		"the wall material carries boards, form ties and a recessed reveal")
	cargo.queue_free()

	# The same rule from the FILE city-kit writes: `data/map/kit_assign.json` rows with kind `cover`.
	# A fixture stands in for it — the real file now claims every piece in the city, which is exactly
	# the behaviour this asserts, but on the fixture's own two pieces so the assertion has an edge.
	var fixture := "user://kit_assign_fixture.json"
	var f := FileAccess.open(fixture, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 2, "cover": [
		{"id": "A1#0", "kind": "cover", "arena": "A1", "index": 0, "model": "k01"},
		{"id": "A1#1", "kind": "far", "arena": "A1", "index": 1},
	]}))
	f.close()
	var from_file := CargoBlocks.new()
	runner.add_child(from_file)
	from_file.kit_assign_path = ProjectSettings.globalize_path(fixture)
	_expect(from_file.build({}, _fake_cover_layout(), 11) == 1 and from_file.skipped_kit == 1,
		"a `cover` row in kit_assign.json skips that piece, and only that piece")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	from_file.queue_free()


## Lead r9. The far field (city-build's `Skyline` ring and its `_hlod` proxies, both in `mc_skyline`)
## read as lavender pixel-checkerboard boxes in all eight vistas. Three causes, three assertions:
## (1) `mc_skyline` carries `sky_band` but NOT `haze_near_amount`, so it never joined the haze push list
## and the ring kept the lavender `ArtPalette.SKYLINE_HAZE` it was built with for every round since r3
## — the same shape of bug as the empty `_haze_mats` list in r6, on the one material nobody looked at.
## (2) The band has to be the sky's OWN horizon colour, desaturated. (3) The lit windows are a sparse
## hashed SPARKLE now, not a cell grid, so no cell structure can survive at any distance.
func check_r9() -> void:
	var ring := McMaterials.skyline()
	var hlod := McMaterials.skyline_hlod()
	_expect(int(McMaterials.registered()["band"]) >= 2,
		"the horizon-band push reaches both skyline variants (%s)" % McMaterials.registered())
	# The exact regression: push a known band and read it back off both skyline materials.
	var probe := Color(0.80, 0.55, 0.30)
	McMaterials.set_haze(ArtPalette.HAZE_WARM, 0.4, ArtPalette.HAZE_FAR, 0.6, probe, 0.6)
	for m in [ring, hlod]:
		var got: Color = m.get_shader_parameter(&"sky_band")
		_expect(got.is_equal_approx(probe),
			"mc_skyline took the pushed horizon colour, not the lavender constant (%s)" % got)
	# ...and it is not the constant it used to be stuck at.
	_expect(not probe.is_equal_approx(ArtPalette.SKYLINE_HAZE),
		"the probe band differs from the old constant (the test can tell them apart)")
	# The band TimeOfDay actually pushes is the sky's hue at a LOWER chroma, so distance takes the
	# masses into the sky instead of towards a foreign colour.
	var sky_avg := ArtPalette.srgb_mix(ArtPalette.SKY_HORIZON, ArtPalette.SKY_HORIZON_AWAY, 0.5)
	var band: Color = TimeOfDay._ring_band(0.0, 0.0)
	_expect(band.s < sky_avg.s * 0.85,
		"the ring band is desaturated against the sky horizon (%.2f vs %.2f)"
			% [band.s, sky_avg.s])
	var hue_gap := absf(band.h - sky_avg.h)
	_expect(minf(hue_gap, 1.0 - hue_gap) < 0.06,
		"the ring band keeps the sky's hue (%.3f vs %.3f turns)" % [band.h, sky_avg.h])
	# The window term: no cell grid left, and a sparse point field in its place.
	var names: PackedStringArray = []
	for u in SH_SKYLINE.get_shader_uniform_list(true):
		names.append(String((u as Dictionary).get("name", "")))
	_expect(not names.has("cell_m") and names.has("spark_m") and names.has("spark_density"),
		"mc_skyline has no window cell grid, and sparkles instead")
	for m in [ring, hlod]:
		_expect(_sky_uniform(m, &"spark_density") <= 0.06,
			"the sparkle is sparse (%.3f of cells)" % _sky_uniform(m, &"spark_density"))
		_expect(_sky_uniform(m, &"haze_floor") < 0.6,
			"the far mass keeps a dark base (haze floor %.2f)" % _sky_uniform(m, &"haze_floor"))
		_expect(_sky_uniform(m, &"edge_gain") > 0.0, "the sun-side edge rim is on")


## `get_shader_parameter` returns null for a uniform the material never set (the value is then the
## shader's own default), so a bare `float(...)` on it is a runtime error that would abort the rest of
## the check silently — and this test reports PASS from its failure counter alone.
func _sky_uniform(m: ShaderMaterial, name: StringName) -> float:
	var v: Variant = m.get_shader_parameter(name)
	return float(v) if v != null else 0.0


## A design layout with one destructible and one permanent cover piece, both on tier 0.
func _fake_cover_layout() -> Dictionary:
	return {"arenas": [{"id": "A1", "district": "D1", "cover": [
		{"center": [0.0, 0.0, 0.0], "size": [20.0, 20.0, 8.0], "soft": true, "rot": 0.0},
		{"center": [60.0, 0.0, 0.0], "size": [24.0, 24.0, 12.0], "soft": false, "rot": 15.0},
	]}]}


## Points a fixture's CargoBlocks at a kit_assign.json that does not exist. The real one now claims
## all 1 070 arena cover pieces (city-kit wave 2, `data/map/kit_assign.json`), and the fixture's arena
## is called "A1" like a real one — so without this every fixture piece reads as kit-owned and the
## dressing assertions below would all pass or all fail on a file that has nothing to do with them.
func _no_kit_file(cargo: CargoBlocks) -> void:
	cargo.kit_assign_path = ProjectSettings.globalize_path("user://no_such_kit_assign.json")

