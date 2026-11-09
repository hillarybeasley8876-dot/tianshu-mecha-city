class_name McSurface
extends RefCounted
## Builds one `mc_surface` ShaderMaterial from a role spec (city-art). A role upgrades itself
## automatically once its CC0 texture set exists in res://assets/textures/<id>/ — until then
## tex_strength is 0 and the surface is pure procedural macro variation, grime and rain streaks.
## Spec keys (all optional except `color`):
##   color Color, rough float, metal float, spec float, uv_mode int (0 metre UV, 1 triplanar,
##   2 raw UV), tile_m float, tint_a/tint_b Color, macro float, grime float, grime_height float,
##   streak float, grime_color Color, tex_id String, creep float.

const SHADER := preload("res://world/art/shaders/mc_surface.gdshader")
const TEX_DIR := "res://assets/textures"


## True when the library holds a usable diffuse map for this texture id.
static func has_textures(tex_id: String) -> bool:
	return not tex_id.is_empty() and ResourceLoader.exists("%s/%s/%s_diff.jpg" % [TEX_DIR, tex_id, tex_id])


static func build(spec: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var col: Color = spec.get("color", Color(0.7, 0.7, 0.7))
	mat.set_shader_parameter(&"base_color", col)
	mat.set_shader_parameter(&"roughness", float(spec.get("rough", 0.7)))
	mat.set_shader_parameter(&"metallic", float(spec.get("metal", 0.0)))
	mat.set_shader_parameter(&"specular", float(spec.get("spec", 0.5)))
	mat.set_shader_parameter(&"uv_mode", int(spec.get("uv_mode", 1)))
	mat.set_shader_parameter(&"tile_m", float(spec.get("tile_m", 4.0)))
	mat.set_shader_parameter(&"tint_a", spec.get("tint_a", Color(1, 1, 1)) as Color)
	mat.set_shader_parameter(&"tint_b", spec.get("tint_b", Color(0.88, 0.86, 0.82)) as Color)
	mat.set_shader_parameter(&"macro_scale", float(spec.get("macro_scale", 0.035)))
	mat.set_shader_parameter(&"macro_amount", float(spec.get("macro", 0.45)))
	mat.set_shader_parameter(&"grime_amount", float(spec.get("grime", 0.35)))
	mat.set_shader_parameter(&"grime_height", float(spec.get("grime_height", 6.0)))
	mat.set_shader_parameter(&"streak_amount", float(spec.get("streak", 0.30)))
	mat.set_shader_parameter(&"grime_color", spec.get("grime_color", Color(0.22, 0.20, 0.19)) as Color)
	mat.set_shader_parameter(&"creep_gain", float(spec.get("creep", 1.0)))
	mat.set_shader_parameter(&"panel_m", float(spec.get("panel_m", 0.0)))
	mat.set_shader_parameter(&"panel_depth", float(spec.get("panel_depth", 0.35)))
	# Lead r7: board-formed concrete (shutter boards, form-tie holes, recessed reveal). Off by default.
	mat.set_shader_parameter(&"board_m", float(spec.get("board_m", 0.0)))
	mat.set_shader_parameter(&"form_tie_m", float(spec.get("form_tie_m", 0.0)))
	mat.set_shader_parameter(&"reveal_m", float(spec.get("reveal_m", 0.0)))
	if spec.has("reveal_depth"):
		mat.set_shader_parameter(&"reveal_depth", float(spec["reveal_depth"]))
	# Lead r4: decks get pavers, patch repairs and standing water (see mc_surface `deck_on`).
	mat.set_shader_parameter(&"deck_on", float(spec.get("deck", 0.0)))
	if spec.has("deck_paver_m"):
		mat.set_shader_parameter(&"deck_paver_m", float(spec["deck_paver_m"]))
	# Review r3 §1: roles that are mostly building wall carry a procedural lit window grid; the mask
	# (McMaterials.set_facade_mask) keeps it off viaducts, decks and roofs that share the same role.
	mat.set_shader_parameter(&"facade_on", float(spec.get("facade", 0.0)))
	if spec.has("facade_gain"):
		mat.set_shader_parameter(&"facade_gain", float(spec["facade_gain"]))
	if spec.has("facade_podium_m"):
		mat.set_shader_parameter(&"facade_podium_m", float(spec["facade_podium_m"]))
	mat.set_shader_parameter(&"facade_warm", ArtPalette.WINDOW_WARM)
	mat.set_shader_parameter(&"facade_cool_col", ArtPalette.WINDOW_COOL)
	mat.set_shader_parameter(&"facade_glass", ArtPalette.GLASS)
	_apply_textures(mat, String(spec.get("tex_id", "")))
	return mat


## Loads whatever maps the library has for `tex_id`; leaves tex_strength at 0 when there are none.
static func _apply_textures(mat: ShaderMaterial, tex_id: String) -> void:
	mat.set_shader_parameter(&"tex_strength", 0.0)
	if tex_id.is_empty():
		return
	var base := "%s/%s/%s" % [TEX_DIR, tex_id, tex_id]
	var diff := _try_load(base + "_diff.jpg")
	if diff == null:
		return
	mat.set_shader_parameter(&"tex_albedo", diff)
	mat.set_shader_parameter(&"tex_strength", 1.0)
	mat.set_shader_parameter(&"tex_gain", 1.0 / clampf(_mean_luminance(diff), 0.15, 1.0))
	var nor := _try_load(base + "_nor_gl.jpg")
	if nor != null:
		mat.set_shader_parameter(&"tex_normal", nor)
	var rgh := _try_load(base + "_rough.jpg")
	if rgh != null:
		mat.set_shader_parameter(&"tex_rough", rgh)


## Mean luminance of a texture, measured on a 32x32 copy so a 1K map does not cost a full read.
static func _mean_luminance(tex: Texture2D) -> float:
	var img := tex.get_image()
	if img == null:
		return 0.5
	if img.is_compressed():
		if img.decompress() != OK:
			return 0.5
	img.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	for y in range(32):
		for x in range(32):
			var c := img.get_pixel(x, y).srgb_to_linear()
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	return total / 1024.0


static func _try_load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		push_warning("McSurface: %s exists but did not load as Texture2D" % path)
	return tex
