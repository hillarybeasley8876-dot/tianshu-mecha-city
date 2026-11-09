class_name McKitSkin
extends RefCounted
## city-art — the skin for city-kit's Tripo architecture (lead 12:10, user feedback "搭积木").
##
## city-kit fits modelled buildings over city-build's blockout and keeps the glTF texture set Blender
## exported, so what arrives here is a plain imported `BaseMaterial3D`. On its own that material is
## wrong three ways in this scene: it keeps Godot's built-in fog while every other city surface does
## its own two-band aerial perspective (`mc_haze`), it has no lit windows, and it cannot carry the
## infection creep. `McMaterials.kit(src)` wraps it in `mc_kit`, which adds exactly those three things
## and nothing else — the model's own albedo / normal / ORM / emissive stay untouched, because the
## detail the user is asking for IS that texture set.
##
## Contract for city-kit: call `McMaterials.kit(src)` once per imported material and use the result as
## the surface override (a MultiMesh per model per tile, so this is a handful of materials, not
## hundreds). Optional `opts` tune the window layer:
##   win_mask (Texture2D)  an explicit window mask from Blender; without it the dark panes are found
##                         in the albedo by luminance, which is what city-kit's albedo pass produces.
##   win_gain, win_cool, win_cell_m, win_floor_m, win_podium_m, win_dark_lo, win_dark_hi, creep_gain.

const SH_KIT := preload("res://world/art/shaders/mc_kit.gdshader")
const SH_KIT_DS := preload("res://world/art/shaders/mc_kit_two_sided.gdshader")
const SH_KIT_BLEND := preload("res://world/art/shaders/mc_kit_blend.gdshader")

## r11: the bands whose models are BUILDINGS. Their walls take the object-space facade
## (`mc_facade.gdshaderinc`) instead of the Tripo albedo atlas, which is what the crumpled foil was.
## The industrial, cover, street and tileable bands are plant, arena cover and trim — a pipe rack and
## a railing have no 4 m storeys, so they keep the atlas.
const FACADE_BANDS: PackedStringArray = ["tower", "megablock", "midrise", "oldtown", "civic"]
## r12 §1: which FAMILY each band wears (`mc_facade_style.gdshaderinc`). Architecture, not taste: a
## tower is glass dominant, a megablock is horizontal, an old-town block is wall dominant.
const FAMILY_BY_BAND: Dictionary = {
	"tower": 0, "megablock": 1, "midrise": 1, "oldtown": 2, "civic": 2,
}
const KIT_JSON := "res://world/kit/kit.json"

## sRGB -> linear, for the two luminance thresholds: the albedo is a `source_color` sampler, so the
## shader sees linear values and a threshold written as if it were sRGB finds nothing.
static func _lin(srgb: float) -> float:
	if srgb <= 0.04045:
		return srgb / 12.92
	return pow((srgb + 0.055) / 1.055, 2.4)

static var _cache: Dictionary = {}
static var _warned: Dictionary = {}
static var _bands: Dictionary = {}
static var _bands_loaded := false


## The `facade_mix` switch for a kit material: 1 on a building band, 0 on everything else. The model
## id is read out of the albedo texture's own path (`res://world/kit/<id>/…`), because city-kit calls
## `McMaterials.kit(src)` with a material and no model name, and its placer is not this unit's file.
## `--no-facade` forces the whole city back to the atlas, which is how the r11 cost and flatness A/Bs
## get an r10b arm on the same machine in the same session.
static func facade_mix_for(src: BaseMaterial3D) -> float:
	if Game.has_flag("no-facade"):
		return 0.0
	return 0.0 if facade_family_for(src) < 0 else 1.0


## r12 §1: the FAMILY index for a kit material — 0 curtain, 1 ribbon, 2 punched, -1 for a band that has
## no facade at all. Same path-into-the-albedo lookup as `facade_mix_for`, for the same reason.
static func facade_family_for(src: BaseMaterial3D) -> int:
	if Game.has_flag("no-facade"):
		return -1
	if Game.has_flag("facade-r11"):
		# The r11 A/B arm: every kit wall wears the one skin r11 shipped, so the "same frames, r11 ->
		# r12" sheet comes from ONE build on ONE machine rather than from two checkouts that also differ
		# in everything else that landed between them.
		return 3 if _is_building(src) else -1
	var id := _model_id(src)
	if id.is_empty():
		return -1
	if not _bands_loaded:
		_load_bands()
	return int(FAMILY_BY_BAND.get(String(_bands.get(id, "")), -1))


## True when this material belongs to a model on a BUILDING band — the same test `facade_mix_for` makes.
static func _is_building(src: BaseMaterial3D) -> bool:
	var id := _model_id(src)
	if id.is_empty():
		return false
	if not _bands_loaded:
		_load_bands()
	return FACADE_BANDS.has(String(_bands.get(id, "")))


## The kit model id, read out of the albedo texture's own path (`res://world/kit/<id>/…`).
static func _model_id(src: BaseMaterial3D) -> String:
	var tex := src.albedo_texture
	if tex == null:
		return ""
	var parts := tex.resource_path.split("/")
	var i := parts.rfind("kit")
	if i < 0 or i + 1 >= parts.size() or i == 0 or parts[i - 1] != "world":
		return ""
	var id := parts[i + 1]
	return id.substr(0, id.length() - 4) if id.ends_with("_far") else id


## `world/kit/kit.json` is city-kit's manifest; one `id -> band` map is enough here and it is read
## once. A missing or broken manifest is an error, not a silent fall back to the old atlas look.
static func _load_bands() -> void:
	_bands_loaded = true
	if not FileAccess.file_exists(KIT_JSON):
		push_error("McKitSkin: no %s — no kit wall can take the facade" % KIT_JSON)
		return
	var txt := FileAccess.get_file_as_string(KIT_JSON)
	var data: Variant = JSON.parse_string(txt)
	if not data is Dictionary or not (data as Dictionary).has("models"):
		push_error("McKitSkin: %s has no `models` array" % KIT_JSON)
		return
	for row in (data as Dictionary)["models"]:
		if row is Dictionary:
			_bands[String(row.get("id", ""))] = String(row.get("band", ""))


## The one entry point. Returns a cached ShaderMaterial per source material, so a kit model placed on
## twelve tiles still costs one material. A `null` or non-`BaseMaterial3D` source is reported and
## handed back unchanged rather than silently replaced with something grey.
static func skin(src: BaseMaterial3D, opts: Dictionary = {}) -> Material:
	if src == null:
		push_error("McKitSkin.skin: null material — city-kit handed us an empty surface")
		return StandardMaterial3D.new()
	var key := "%d_%d" % [src.get_instance_id(), int(round(float(opts.get("base_y", 0.0)) * 10.0))]
	if _cache.has(key):
		return _cache[key]
	var m := _build(src, opts)
	_cache[key] = m
	return m


## Picks the shader variant the imported material asks for. `render_mode` is compile-time in Godot, so
## double-sided and transparent glTF materials each need their own header over the shared body.
static func _shader_for(src: BaseMaterial3D) -> Shader:
	if src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return SH_KIT_BLEND
	if src.cull_mode == BaseMaterial3D.CULL_DISABLED:
		return SH_KIT_DS
	return SH_KIT


static func _build(src: BaseMaterial3D, opts: Dictionary) -> Material:
	var m := ShaderMaterial.new()
	m.shader = _shader_for(src)
	m.resource_name = "mc_kit_" + src.resource_name if src.resource_name != "" else "mc_kit"
	m.set_shader_parameter(&"base_color", src.albedo_color)
	m.set_shader_parameter(&"tex_albedo", src.albedo_texture)
	m.set_shader_parameter(&"roughness", src.roughness)
	m.set_shader_parameter(&"metallic", src.metallic)
	m.set_shader_parameter(&"specular", src.metallic_specular)
	m.set_shader_parameter(&"uv1_scale", src.uv1_scale)
	m.set_shader_parameter(&"uv1_offset", src.uv1_offset)
	if src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		m.set_shader_parameter(&"use_alpha", 1.0)
	_copy_maps(src, m)
	_copy_emission(src, m, opts)
	_copy_windows(src, m, opts)
	m.set_shader_parameter(&"creep_gain", float(opts.get("creep_gain", 1.0)))
	var family := int(opts.get("facade_family", facade_family_for(src)))
	m.set_shader_parameter(&"facade_family", family)
	m.set_shader_parameter(&"facade_mix",
		float(opts.get("facade_mix", 0.0 if family < 0 else 1.0)))
	m.set_shader_parameter(&"facade_lines", float(opts.get("facade_lines", 1.0)))
	return m


## Normal + roughness/metallic. glTF packs occlusion/roughness/metallic into one texture, which Godot
## imports as an ORMMaterial3D or as a StandardMaterial3D sharing one image across two slots — both
## take the packed path. Anything else keeps its own channel selection.
static func _copy_maps(src: BaseMaterial3D, m: ShaderMaterial) -> void:
	if src.normal_enabled and src.normal_texture != null:
		m.set_shader_parameter(&"tex_normal", src.normal_texture)
		m.set_shader_parameter(&"use_normal", 1.0)
		m.set_shader_parameter(&"normal_strength", src.normal_scale)
	var orm: Texture2D = null
	if src is ORMMaterial3D:
		orm = (src as ORMMaterial3D).orm_texture
	elif src.roughness_texture != null and src.roughness_texture == src.metallic_texture:
		orm = src.roughness_texture
	if orm != null:
		m.set_shader_parameter(&"tex_orm", orm)
		m.set_shader_parameter(&"use_orm", 1.0)
		return
	if src.roughness_texture != null:
		m.set_shader_parameter(&"tex_rough", src.roughness_texture)
		m.set_shader_parameter(&"use_rough", 1.0)
		m.set_shader_parameter(&"rough_channel", int(src.roughness_texture_channel))
	if src.metallic_texture != null:
		m.set_shader_parameter(&"tex_metal", src.metallic_texture)
		m.set_shader_parameter(&"use_metal", 1.0)
		m.set_shader_parameter(&"metal_channel", int(src.metallic_texture_channel))


## The model's baked emissive (city-kit's neon strips) stays, at a gain low enough that shopfront
## signage never outshines the lit windows. `emission_as_mask` hands the same texture to the window
## layer instead — that is the route for a kit model whose Blender pass wrote a window mask.
static func _copy_emission(src: BaseMaterial3D, m: ShaderMaterial, opts: Dictionary) -> void:
	if not src.emission_enabled:
		return
	if bool(opts.get("emission_as_mask", false)) and src.emission_texture != null:
		m.set_shader_parameter(&"tex_win_mask", src.emission_texture)
		m.set_shader_parameter(&"win_mask_from", 1.0)
		return
	m.set_shader_parameter(&"emission_color", src.emission)
	# city-art r14: an imported emissive is CLAMPED. A Tripo bake's `emission_energy_multiplier` is
	# whatever the exporter felt like, and one model at 8.0 put the Spire's crown cladding over
	# 248/255 across the whole structure in V3 and V7 — the frame's brightest thing has to be the sun,
	# the neon and the tether, not a texture's idea of a light strip.
	m.set_shader_parameter(&"emission_gain", minf(
		src.emission_energy_multiplier * float(opts.get("emission_scale", 0.6)),
		float(opts.get("emission_max", 1.2))))
	if src.emission_texture != null:
		m.set_shader_parameter(&"tex_emission", src.emission_texture)
		m.set_shader_parameter(&"use_emission", 1.0)


## The window layer's tuning. `win_gain` defaults under `mc_window`'s 2.6: a kit facade's panes are
## already the texture's own dark glass, so the same gain reads hotter here than on a flat quad.
static func _copy_windows(src: BaseMaterial3D, m: ShaderMaterial, opts: Dictionary) -> void:
	var mask: Texture2D = opts.get("win_mask", null)
	if mask != null:
		m.set_shader_parameter(&"tex_win_mask", mask)
		m.set_shader_parameter(&"win_mask_from", 1.0)
	m.set_shader_parameter(&"win_gain", float(opts.get("win_gain", 0.9)))
	m.set_shader_parameter(&"kit_albedo", float(opts.get("kit_albedo", 0.72)))
	m.set_shader_parameter(&"win_cool", float(opts.get("win_cool", 0.22)))
	m.set_shader_parameter(&"win_cell_m", float(opts.get("win_cell_m", 3.4)))
	m.set_shader_parameter(&"win_floor_m", float(opts.get("win_floor_m", 4.0)))
	m.set_shader_parameter(&"win_podium_m", float(opts.get("win_podium_m", 6.0)))
	m.set_shader_parameter(&"win_base_y", float(opts.get("base_y", 0.0)))
	m.set_shader_parameter(&"win_dark_lo", _lin(float(opts.get("win_dark_lo", 0.08))))
	m.set_shader_parameter(&"win_dark_hi", _lin(float(opts.get("win_dark_hi", 0.26))))
	if src.albedo_texture == null:
		_warn_once(src, "no albedo texture — the window layer has nothing to find panes in")


## A per-source warning, once: a kit batch is hundreds of surfaces and a repeated message is noise.
static func _warn_once(src: BaseMaterial3D, what: String) -> void:
	if _warned.has(what):
		return
	_warned[what] = true
	push_warning("McKitSkin: %s (%s)" % [what, src.resource_name])


## How many distinct source materials have been skinned (evidence for the status file).
static func count() -> int:
	return _cache.size()
