extends Node
## city-art unit test (world/art/tests/test_art.gd). Headless: builds the environment scene, checks the
## CONTRACTS §7 hooks, the quality presets and the material library, and prints the live lighting
## numbers so a look-dev regression is visible in the log as well as in the captures.
## Run: tools/godot.sh test res://world/art/tests/test_art.gd

const ENV_SCENE := preload("res://world/art/environment.tscn")
const SH_ACCENT := preload("res://world/art/shaders/mc_up_accent.gdshader")
const SH_HOLOGRAM := preload("res://world/art/shaders/mc_hologram.gdshader")
const SH_STORM := preload("res://world/art/shaders/mc_storm.gdshader")
const SH_SURFACE := preload("res://world/art/shaders/mc_surface.gdshader")
const SH_WINDOW := preload("res://world/art/shaders/mc_window.gdshader")
const SH_KIT := preload("res://world/art/shaders/mc_kit.gdshader")
const SH_KIT_DS := preload("res://world/art/shaders/mc_kit_two_sided.gdshader")
const SH_KIT_BLEND := preload("res://world/art/shaders/mc_kit_blend.gdshader")
const KIT_BAKE := preload("res://world/art/tests/kit_bake.gd")
## The per-round look-review checks (r7, r8, r9, …). They grew the runner past 600 lines; the split is
## by review round because that is the axis they grow on.
const ROUND_CHECKS := preload("res://world/art/tests/round_checks.gd")

var _failures: int = 0
var _tod: TimeOfDay
var _infection: InfectionField


func _ready() -> void:
	_check_materials()
	_check_presets()
	await _check_environment()
	_check_infection()
	_check_r2_contracts()
	_check_r3_contracts()
	_check_kit()
	await _check_detail_layers()
	var rounds := ROUND_CHECKS.new(self)
	rounds.check_r7()
	rounds.check_r8()
	rounds.check_r9()
	print("ART TEST %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL ", what)


func _check_materials() -> void:
	for role in McMaterials.ROLE_NAMES:
		var mat := McMaterials.get_material(role)
		_expect(mat != null, "material %s exists" % role)
		if mat is ShaderMaterial:
			_expect((mat as ShaderMaterial).shader != null, "material %s has a shader" % role)
	_expect(McMaterials.get_material(&"mc_stone") == McMaterials.get_material(&"mc_stone"),
		"materials are cached, not rebuilt")
	# Every surface role must have found its CC0 set; tex_strength 0 means the library lookup failed.
	var untextured: Array[String] = []
	for role in McMaterials.SURFACES:
		var spec: Dictionary = McMaterials.SURFACES[role]
		var tex_id := String(spec.get("tex_id", ""))
		if not McSurface.has_textures(tex_id):
			untextured.append("%s(%s)" % [role, tex_id])
			continue
		var sm := McMaterials.get_material(role) as ShaderMaterial
		if sm == null or float(sm.get_shader_parameter(&"tex_strength")) < 0.5:
			untextured.append("%s(not bound)" % role)
	_expect(untextured.is_empty(), "every surface role has its CC0 texture set (bad: %s)"
		% ", ".join(untextured))
	var road := McMaterials.road_variant(&"street")
	_expect(road != McMaterials.road_variant(&"avenue"), "road variants are distinct materials")
	_expect(McMaterials.hologram() != null, "hologram material builds")
	# Regression: the push lists used to be filled by testing `get_shader_parameter(name) != null`,
	# which is only true for a uniform that has already been SET — so `haze` and `wet` were empty in
	# every build and the layered aerial perspective sat at its shader defaults for three rounds.
	var reg := McMaterials.registered()
	_expect(int(reg["haze"]) >= 10, "the haze push reaches the mc_* materials (%s)" % reg)
	_expect(int(reg["wet"]) >= 2, "the wetness push reaches road and deck (%s)" % reg)
	_expect(int(reg["facade"]) >= 2, "the facade-mask push reaches the facade materials (%s)" % reg)


func _check_presets() -> void:
	for name in [&"low", &"medium", &"high"]:
		_expect(ArtQuality.PRESETS.has(name), "preset %s exists" % name)
		var p: Dictionary = ArtQuality.PRESETS[name]
		var env := CityEnvironment.build(p)
		ArtQuality.apply(env, DirectionalLight3D.new(), p)
		_expect(env.ssao_enabled == bool(p["ssao"]), "preset %s applied ssao" % name)
		_expect(env.volumetric_fog_enabled == bool(p["volumetric"]), "preset %s applied volumetrics" % name)
		_expect(env.sky != null and env.sky.sky_material != null, "preset %s keeps a sky" % name)
	_expect(CityEnvironment.grade_lut() != null, "colour-grade LUT builds")


func _check_environment() -> void:
	var node := ENV_SCENE.instantiate()
	add_child(node)
	await get_tree().process_frame
	_tod = node as TimeOfDay
	_expect(_tod != null, "environment.tscn root is a TimeOfDay")
	if _tod == null:
		return
	_expect(_tod.is_in_group(&"time_of_day"), "TimeOfDay joins &\"time_of_day\"")
	var sun := _tod.get_node_or_null(^"Sun") as DirectionalLight3D
	_expect(sun != null and sun.light_energy > 0.5, "the sun is lit")
	if sun != null:
		var to_sun: Vector3 = sun.global_transform.basis.z
		print("ART sun dir=%.3f,%.3f,%.3f energy=%.2f colour=%s" %
			[to_sun.x, to_sun.y, to_sun.z, sun.light_energy, sun.light_color])
		_expect(to_sun.y > 0.05 and to_sun.y < 0.45, "sun elevation is 6-20 degrees")
		_expect(to_sun.x < 0.0 and to_sun.z < 0.0, "sun sits in the north-west quadrant")
	var we := _tod.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	var env := we.environment if we != null else null
	_expect(env != null, "WorldEnvironment has an Environment")
	# Lead 12:25: the post-render unit appends its CompositorEffects here, so the WorldEnvironment has
	# to carry the one shared stack and appending to it has to survive.
	_expect(we != null and we.compositor == CityEnvironment.compositor(),
		"WorldEnvironment carries the shared Compositor")
	var before := CityEnvironment.compositor().compositor_effects.size()
	var probe := CompositorEffect.new()
	probe.effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	CityEnvironment.add_compositor_effect(probe)
	CityEnvironment.add_compositor_effect(probe)   # idempotent
	_expect(CityEnvironment.compositor().compositor_effects.size() == before + 1,
		"a CompositorEffect appends once and only once")
	CityEnvironment.compositor().compositor_effects.remove_at(
		CityEnvironment.compositor().compositor_effects.size() - 1)
	if env != null:
		print("ART ambient=%.3f fog_begin=%.0f fog_end=%.0f glow=%s sdfgi=%s exposure=%.2f" %
			[env.ambient_light_energy, env.fog_depth_begin, env.fog_depth_end,
			env.glow_enabled, env.sdfgi_enabled, env.tonemap_exposure])

	# Progress ramp: sun drops, more windows light, the storm gathers.
	# Read the value TimeOfDay published, not the shader global: --headless uses the dummy rendering
	# server, where global_shader_parameter_get returns Nil.
	var lit_0 := _tod.lit_fraction
	_tod.set_progress_immediate(1.0)
	var lit_1 := _tod.lit_fraction
	var wet_1 := McMaterials.wetness()
	_expect(lit_1 > lit_0, "window lit fraction rises with progress (%.2f -> %.2f)" % [lit_0, lit_1])
	_expect(_tod.storm > 0.9, "storm gathers at progress 1")
	_expect(wet_1 > 0.8, "the storm leaves the streets wet (%.2f)" % wet_1)
	if sun != null:
		_expect(sun.global_transform.basis.z.y < 0.2, "sun is low at progress 1")
	_tod.set_progress(0.0)
	_expect(_tod.progress > 0.9, "set_progress does not jump: it tweens")
	_tod.lightning_at(Vector3(0.0, 240.0, -120.0))
	_tod.set_progress_immediate(0.0)
	_tod.set_storm(0.0, 0.01)
	var wet_0 := McMaterials.wetness()
	_expect(wet_0 < wet_1 and wet_0 > 0.1,
		"golden hour stays damp but drier than the storm (%.2f -> %.2f)" % [wet_0, wet_1])
	print("ART lit_fraction %.2f -> %.2f, storm %.2f, wet %.2f -> %.2f, wet mats %d"
		% [lit_0, lit_1, _tod.storm, wet_0, wet_1, int(McMaterials.registered()["wet"])])


func _check_infection() -> void:
	_infection = _tod.get_node_or_null(^"Infection") as InfectionField
	_expect(_infection != null, "environment.tscn carries an InfectionField")
	if _infection == null:
		return
	_expect(_infection.is_in_group(&"infection"), "InfectionField joins &\"infection\"")
	_infection.register_site(&"test_site", Vector3(100.0, 0.0, 100.0), 120.0)
	_infection.set_intensity(&"test_site", 1.0, 0.01)
	for i in range(20):
		await get_tree().process_frame
	_expect(_infection.site_level(&"test_site") > 0.9, "infection intensity reaches its target")
	_infection.set_intensity(&"nope", 1.0, 0.01)     ## unknown id must warn, never crash
	_infection.set_master(0.0, 0.01)
	for i in range(20):
		await get_tree().process_frame
	_expect(_infection.master < 0.05, "the master creep level recedes on demand")


## The r2 art-direction contracts, each of which a capture caught being wrong once:
## unshaded shaders must write ALBEDO (EMISSION alone renders black), the creep stain must stay inside
## its hive radius, and violet must belong to the storm rather than to dusk.
func _check_r2_contracts() -> void:
	for shader: Shader in [SH_ACCENT, SH_HOLOGRAM, SH_STORM]:
		var src: String = shader.code
		if not src.contains("unshaded"):
			continue
		var writes_albedo: bool = src.contains("ALBEDO =") and not src.contains("ALBEDO = vec3(0.0);")
		_expect(writes_albedo,
			"%s is unshaded, so its colour must go to ALBEDO" % shader.resource_path)
	# The gain is read out of the SOURCE, not the material: `get_shader_parameter` returns null for a
	# uniform the material never set explicitly, and `float(null)` is an engine error, not a failure.
	_expect(_declared_default(SH_ACCENT, "gain") <= 3.0,
		"the accent gain stays restrained (restrained neon, ART.md §2)")
	var strips := McMaterials.accent_variant(&"spire_strip", 2.2, 0.45, 1.8, 1)
	_expect(strips.get_shader_parameter(&"axis") == 1, "the Spire strips pulse upward")


	# Creep: the radius is clamped, so no site can be registered that would flood a whole district.
	_infection.register_site(&"huge", Vector3(0.0, 0.0, 0.0), 900.0)
	_expect(_infection.site_radius(&"huge") <= InfectionField.DEFAULT_RADIUS,
		"a hive radius is clamped to %d m" % int(InfectionField.DEFAULT_RADIUS))

	# Violet belongs to the storm: no storm before progress 0.66, full cover at the boss.
	_expect(is_zero_approx(TimeOfDay.storm_for(0.0)), "no storm at progress 0")
	_expect(is_zero_approx(TimeOfDay.storm_for(0.5)), "no storm at progress 0.5")
	_expect(TimeOfDay.storm_for(0.8) > 0.1 and TimeOfDay.storm_for(0.8) < 0.9,
		"the storm ramps in over the last third")
	_expect(TimeOfDay.storm_for(1.0) > 0.99, "full storm at the boss")

	# The water surface must be opaque: a blended surface never gets an SSR pass.
	var water := McMaterials.get_material(&"mc_water") as ShaderMaterial
	_expect(water != null and not water.shader.get_code().contains("ALPHA ="),
		"the canal is opaque, so SSR reflects the city in it")


## The r3 art-direction contracts: every city material has to carry the two-band haze itself (the
## built-in depth fog saturated at 1.3 km and flattened the distance), the facade window grid has to
## dissolve to its own mean before it aliases into static, and the signage layer has to actually place
## blades, shopfronts, parapet lines and billboards.
func _check_r3_contracts() -> void:
	for role in McMaterials.ROLE_NAMES:
		var mat := McMaterials.get_material(role) as ShaderMaterial
		if mat == null or not mat.shader.code.contains("mc_haze.gdshaderinc"):
			continue
		_expect(mat.shader.code.contains("fog_disabled"),
			"%s applies its own aerial perspective, so it must opt out of the built-in fog" % role)
	# The window grid is dissolved by `fwidth`, which is the only thing that knows the cell's size in
	# pixels; a hard-coded distance would alias at one resolution and not at another.
	for shader: Shader in [SH_SURFACE, SH_WINDOW]:
		_expect(shader.code.contains("fwidth("),
			"%s dissolves its window cells by pixel size" % shader.resource_path)
	# The far band must sit further out than the near band, or the two cross and the mid-ground goes
	# violet while the foreground is still warm. The numbers live in the include, not in the shaders
	# that include it, so they are read from the file.
	_expect(_file_default("haze_far_begin") > _file_default("haze_near_end"),
		"the cool far band starts beyond the warm near band (%.0f > %.0f m)"
		% [_file_default("haze_far_begin"), _file_default("haze_near_end")])
	_check_signs()


## city-kit's hand-off (lead 12:10 PRIORITY): `McMaterials.kit(src)` must wrap an imported glTF
## material in this unit's atmosphere without losing the model's own texture set, and must pick the
## shader variant the import asked for.
func _check_kit() -> void:
	var src := KIT_BAKE.material("test_kit", 7, Color(0.74, 0.72, 0.68), 1.0, Color(0.3, 0.9, 1.0))
	var kit := McMaterials.kit(src) as ShaderMaterial
	_expect(kit != null and kit.shader == SH_KIT, "kit() returns the mc_kit material")
	if kit == null:
		return
	_expect(kit.get_shader_parameter(&"tex_albedo") == src.albedo_texture,
		"the kit material keeps the model's own albedo")
	_expect(float(kit.get_shader_parameter(&"use_orm")) == 1.0,
		"one image shared by roughness and metallic is read as packed ORM")
	_expect(float(kit.get_shader_parameter(&"use_emission")) == 1.0,
		"the model's baked emissive survives the wrap")
	# `Shader.code` is the file as written — Godot resolves the includes at compile time — so the two
	# shared layers are checked in the body the three headers pull in.
	_expect(kit.shader.code.contains("fog_disabled"), "a kit building opts out of the built-in fog")
	var body := FileAccess.get_file_as_string("res://world/art/shaders/mc_kit_body.gdshaderinc")
	_expect(body.contains("#include \"mc_haze.gdshaderinc\"") and body.contains("layered_haze("),
		"a kit building applies the city's own two-band haze")
	_expect(body.contains("#include \"mc_creep.gdshaderinc\"") and body.contains("apply_creep("),
		"a kit building carries the infection creep like every other city surface")
	# The thresholds are compared against LINEAR luminance (the albedo is a source_color sampler); an
	# sRGB-shaped threshold finds no panes at all, which is a silent failure.
	_expect(float(kit.get_shader_parameter(&"win_dark_hi")) < 0.2,
		"the window threshold is in linear space, not sRGB")
	_expect(McMaterials.kit(src) == kit, "kit() caches per source material")
	var other := KIT_BAKE.material("test_kit_b", 9, Color(0.6, 0.6, 0.62), 2.0)
	_expect(McMaterials.kit(other) != kit, "a different source material gets its own skin")

	var ds := KIT_BAKE.material("test_kit_ds", 11, Color(0.7, 0.7, 0.7), 1.0, Color(0, 0, 0), true)
	_expect((McMaterials.kit(ds) as ShaderMaterial).shader == SH_KIT_DS,
		"a double-sided import gets the two-sided variant")
	var glass := KIT_BAKE.material("test_kit_glass", 13, Color(0.7, 0.7, 0.7), 1.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var gm := McMaterials.kit(glass) as ShaderMaterial
	_expect(gm.shader == SH_KIT_BLEND and float(gm.get_shader_parameter(&"use_alpha")) == 1.0,
		"a transparent import gets the blend variant and writes alpha")

	# `apply_kit` is the pass city-kit can call instead of walking the meshes: it must replace imported
	# surfaces and leave city-build's mc_* roles alone.
	var root := Node3D.new()
	add_child(root)
	for i in 2:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.material = src if i == 0 else McMaterials.get_material(&"mc_stone")
		mi.mesh = box
		root.add_child(mi)
	var changed := McMaterials.apply_kit(root)
	_expect(changed == 1, "apply_kit replaces the imported surface only (got %d)" % changed)
	var skinned := (root.get_child(0) as MeshInstance3D).get_surface_override_material(0)
	_expect(skinned is ShaderMaterial and (skinned as ShaderMaterial).shader == SH_KIT,
		"the imported surface now carries the kit skin")
	root.queue_free()
	_check_facade(kit)


## r11: the facade that replaces the Tripo atlas on a near wall. The band table is the contract with
## city-kit — a building band gets the facade, a pipe rack or an arena cover piece does not — and the
## shader body has to carry the metric grid the whole thing is built on.
func _check_facade(kit: ShaderMaterial) -> void:
	# A synthetic material has no `res://world/kit/<id>/…` albedo path, so it takes the safe default.
	_expect(float(kit.get_shader_parameter(&"facade_mix")) == 0.0,
		"a material that is not a kit model keeps the atlas (facade_mix 0)")
	_expect(float(kit.get_shader_parameter(&"facade_lines")) == 1.0,
		"the facade's structure is on by default")
	_expect(McKitSkin.FACADE_BANDS.has("tower") and McKitSkin.FACADE_BANDS.has("civic")
		and not McKitSkin.FACADE_BANDS.has("industrial")
		and not McKitSkin.FACADE_BANDS.has("cover") and not McKitSkin.FACADE_BANDS.has("tileable"),
		"the facade bands are the building bands only")
	# `facade_mix_for` is what reads kit.json, so it must find the band for a real model id and must
	# refuse anything outside `res://world/kit/`.
	var m04 := load("res://world/kit/m04/m04_m04_albedo.jpg") as Texture2D
	if m04 != null:
		var src := StandardMaterial3D.new()
		src.albedo_texture = m04
		_expect(McKitSkin.facade_mix_for(src) == 1.0,
			"m04 (band megablock) takes the facade")
	var stray := StandardMaterial3D.new()
	stray.albedo_texture = load("res://assets/textures/brushed_concrete/brushed_concrete_diff.jpg") as Texture2D
	_expect(McKitSkin.facade_mix_for(stray) == 0.0, "a texture outside world/kit keeps the atlas")

	var body := FileAccess.get_file_as_string("res://world/art/shaders/mc_kit_body.gdshaderinc")
	var facade := FileAccess.get_file_as_string("res://world/art/shaders/mc_facade.gdshaderinc")
	var style := FileAccess.get_file_as_string("res://world/art/shaders/mc_facade_style.gdshaderinc")
	_expect(body.contains("MODEL_MATRIX[0]") and body.contains("VERTEX * ms"),
		"v_local carries the instance scale, so a storey is 4.0 m on every building")
	_expect(body.contains("facade_curv_max"), "curved parts (domes, tanks, crowns) keep the atlas")
	# r12 §1: the slab / mullion / pane sizes moved out of uniforms and into the per-family STYLE, so the
	# three things to check are that the style still declares them, that the facade reads the style, and
	# that the family uniform is what selects it.
	_expect(style.contains("float slab_m") and style.contains("float mull_m")
		and style.contains("float pane_w") and style.contains("float cell_w"),
		"the facade draws a slab, a mullion and a pane on the metric grid")
	_expect(facade.contains("facade_style(facade_family"), "the facade reads its style from the family")
	_expect(facade.contains("uniform int facade_family"), "the family is a per-material uniform")
	_expect(facade.contains("mc_res("), "every fixed-width line fades out before it is one pixel wide")
	_expect(body.contains("pane = mix(pane, fpane, fac)"),
		"on a facade wall the pane REPLACES the atlas window mask")
	_check_facade_families(style)


## r12 §1: three families, three variants each, and the extras the brief names — a cornice on the
## punched wall, a balcony / plant line on one megablock variant in three.
func _check_facade_families(style: String) -> void:
	_expect(McKitSkin.FAMILY_BY_BAND.get("tower") == 0
		and McKitSkin.FAMILY_BY_BAND.get("megablock") == 1
		and McKitSkin.FAMILY_BY_BAND.get("midrise") == 1
		and McKitSkin.FAMILY_BY_BAND.get("oldtown") == 2
		and McKitSkin.FAMILY_BY_BAND.get("civic") == 2,
		"every building band maps to a facade family (tower/ribbon/punched)")
	_expect(not McKitSkin.FAMILY_BY_BAND.has("industrial")
		and not McKitSkin.FAMILY_BY_BAND.has("cover"),
		"plant and arena cover keep the atlas — they have no storeys")
	_expect(style.contains("s.cornice_m = 0.45"), "the punched wall carries a cornice line")
	_expect(style.contains("s.balc_m = 0.6") and style.contains("s.rail_m = 0.10"),
		"one megablock variant in three carries a balcony / plant line")
	_expect(style.contains("s.joint_m = vi == 0 ? 7.0"),
		"the ribbon block is jointed every 6-9 m, not only at the pane grid")
	_expect(style.contains("fam == 3"), "the r11 single skin is kept as the A/B arm")


## The signage layer against the design layout: the counts are the evidence that it landed.
func _check_signs() -> void:
	# r12 §3: the `res://` copy the Blender build writes, never a literal an absolute home path path.
	var path := ArtRepo.design_layout()
	if not FileAccess.file_exists(path):
		push_warning("test_art: no design layout — the signage check is skipped")
		return
	var design: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var node := FacadeSigns.new()
	node.build(design as Dictionary)
	add_child(node)
	_expect(node.blades >= 150, "blade signs on the tier B/C/D facades (got %d)" % node.blades)
	_expect(node.shopfronts >= 300, "a shopfront glow band on every podium (got %d)" % node.shopfronts)
	_expect(node.parapets >= 100, "parapet light lines on the tier C/D towers (got %d)" % node.parapets)
	_expect(node.billboards == FacadeSigns.BILLBOARD_ANCHORS.size(),
		"one holo billboard per anchor (got %d of %d)"
		% [node.billboards, FacadeSigns.BILLBOARD_ANCHORS.size()])
	print("ART signs blades=%d shopfronts=%d parapets=%d billboards=%d"
		% [node.blades, node.shopfronts, node.parapets, node.billboards])
	node.free()


## The default `mc_haze.gdshaderinc` declares for `uniform float <name>` — the shared haze numbers are in
## the include, so the shader-source reader below cannot see them.
static func _file_default(name: String) -> float:
	var path := "res://world/art/shaders/mc_haze.gdshaderinc"
	if not FileAccess.file_exists(path):
		return 0.0
	return _scan(FileAccess.get_file_as_string(path), name)


## The default value a shader declares for `uniform float <name>`, or 0.0 when it declares none.
static func _declared_default(shader: Shader, name: String) -> float:
	return _scan(shader.code, name)


## First `uniform float <name> = <value>;` in `src`, or 0.0 when there is none.
static func _scan(src: String, name: String) -> float:
	for line in src.split("\n"):
		var l := String(line).strip_edges()
		if not l.begins_with("uniform float %s" % name):
			continue
		var eq := l.find("=")
		if eq < 0:
			return 0.0
		return l.substr(eq + 1).split(";")[0].strip_edges().to_float()
	return 0.0

## The detail layers are geometry and emitters rather than materials, so they are checked for
## "actually built something" instead of by eye: an empty cable net or a silent emitter is the
## failure mode a screenshot hides.
func _check_detail_layers() -> void:
	var cables := CableNet.new()
	add_child(cables)
	cables.build([[Vector3(-50.0, 60.0, 0.0), Vector3(50.0, 66.0, 0.0), 12.0],
		[Vector3(-50.0, 40.0, 30.0), Vector3(50.0, 44.0, 30.0)]])
	_expect(cables.span_count == 2, "cable net built both spans")
	_expect(cables.mesh != null and cables.mesh.get_surface_count() == 1,
		"cables are one surface, so one draw call")
	_expect(cables.mesh.get_aabb().size.y > 1.0, "the catenary actually sags")
	cables.build([])
	_expect(cables.mesh == null, "an empty span list produces no mesh")

	var cloth := ClothLines.new()
	add_child(cloth)
	cloth.build([[Vector3(0.0, 20.0, 0.0), 0.0, 3.0, 7.0], [Vector3(6.0, 18.0, 0.0), 90.0, 2.5, 5.0]])
	_expect(cloth.multimesh != null and cloth.multimesh.instance_count == 2,
		"cloth lines built both banners")
	_expect(cloth.multimesh.use_custom_data, "banners carry per-instance seeds")

	var life := CityLife.new()
	add_child(life)
	await get_tree().process_frame
	_expect(life.emitters.size() == 3, "CityLife pre-instances one of each emitter at load")
	_expect(not life.emitters[0].emitting, "the warm-up emitters start silent")
	life.smoke_column(Vector3.ZERO, 120.0, 12.0).emitting = true
	life.steam_vent(Vector3(4.0, 0.0, 0.0)).emitting = true
	life.drone_flock(Vector3(0.0, 60.0, 0.0), 80.0, 24).emitting = true
	await get_tree().process_frame
	await get_tree().process_frame
	var live := 0
	for e in life.emitters:
		if e.emitting:
			live += 1
	_expect(live == 3, "the placed emitters are running (%d of 3)" % live)
	_expect(SoftTextures.radial() != null and SoftTextures.puff(3) != null,
		"the particle textures build")
	life.queue_free()

	# r4: the three new dressing layers. Each one is a MultiMesh batch, so the check that matters is
	# "did the plan produce instances AND did they become one draw call per kind".
	var greebles := RoofGreebles.new()
	add_child(greebles)
	var placed := greebles.build(_fake_layout(), 7)
	_expect(placed >= 16, "rooftop greebles placed on the fake roofs (%d)" % placed)
	_expect(greebles.get_child_count() > 0, "greebles are grouped per 600 m cell")
	for group in greebles.get_children():
		for batch in (group as Node3D).get_children():
			var mm := (batch as MultiMeshInstance3D).multimesh
			_expect(mm != null and mm.instance_count > 0, "every greeble batch drew something")
	# Masts are a 22 % roll per roof, so a four-roof fixture can legitimately have none: roll a few
	# seeds and require that the lamp batch appears together with the masts it belongs to.
	var lamp_seen := false
	for seed in range(1, 9):
		var more := RoofGreebles.new()
		add_child(more)
		more.build(_fake_layout(), seed)
		for group in more.get_children():
			for batch in (group as Node3D).get_children():
				if String(batch.name) == "mast_lamp":
					lamp_seen = true
		more.queue_free()
	_expect(lamp_seen, "a mast always brings its aviation lamp batch")

	var web := StreetWeb.new()
	add_child(web)
	var spans := web.build(_fake_layout(), 7)
	_expect(spans >= 0, "street web built without an error")
	# A layout with a single 12 m street cannot have two facing facades, so it must stay empty rather
	# than inventing anchors in mid-air.
	_expect(spans == 0 or web.get_node_or_null(^"Cables") != null,
		"a web with spans also produced the cable mesh")

	var scaffolds := Scaffolds.new()
	add_child(scaffolds)
	_expect(scaffolds.build(_fake_layout(), 7) == 2, "both construction sites were built")
	_expect(scaffolds.get_child_count() == 2, "each site is one MeshInstance3D, so one draw call")


## A minimal design layout: two facing blocks either side of a 40 m street, plus a low shed.
func _fake_layout() -> Dictionary:
	var blocks: Array = []
	for i in range(4):
		blocks.append({"id": "T_b%d" % i, "tier": "C", "district": "D3",
			"center": [-40.0 if i < 2 else 40.0, -30.0 + 60.0 * float(i % 2)],
			"size": [30.0, 30.0], "rot": 0.0, "base_z": 0.0, "height": 90.0})
	blocks.append({"id": "T_shed", "tier": "A", "district": "D3", "center": [0.0, 120.0],
		"size": [12.0, 12.0], "rot": 0.0, "base_z": 0.0, "height": 8.0})
	return {"buildings": blocks,
		"streets": [{"z": 0.0, "width": 40.0, "points": [[0.0, -60.0], [0.0, 60.0]]}]}
