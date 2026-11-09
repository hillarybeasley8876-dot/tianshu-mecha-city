class_name McMaterialRoles
extends RefCounted
## The city material library's DATA (city-art r16 §6): the 12 `mc_*` role names city-build's blockout
## references by name (blender/city/kit/roles.py), the procedural surface spec of each role, the shader
## each non-procedural role uses, and the load-time defaults of every global shader parameter.
## Split out of `material_library.gd` so the state (McMaterialState) and the builders
## (McMaterialBuilders) can both read it without referencing each other.

const ROLE_NAMES: Array[StringName] = [
	&"mc_stone", &"mc_concrete", &"mc_panel_white", &"mc_metal", &"mc_bronze", &"mc_terracotta",
	&"mc_deck", &"mc_glass", &"mc_road", &"mc_window", &"mc_up_accent", &"mc_water",
]

const SH_WINDOW := preload("res://world/art/shaders/mc_window.gdshader")
const SH_GLASS := preload("res://world/art/shaders/mc_glass.gdshader")
const SH_ROAD := preload("res://world/art/shaders/mc_road.gdshader")
const SH_WATER := preload("res://world/art/shaders/mc_water.gdshader")
const SH_ACCENT := preload("res://world/art/shaders/mc_up_accent.gdshader")
const SH_HOLOGRAM := preload("res://world/art/shaders/mc_hologram.gdshader")
const SH_SKYLINE := preload("res://world/art/shaders/mc_skyline.gdshader")
const SH_SIGN := preload("res://world/art/shaders/mc_sign.gdshader")
const SH_BAND := preload("res://world/art/shaders/mc_band.gdshader")
const SH_FOLIAGE := preload("res://world/art/shaders/mc_foliage.gdshader")

## city-art r13: the "no detail distance" sentinel — past this, nothing in the city is far enough to
## take a shader's cheap path, which is the same as the feature being off.
const NO_DETAIL := 100000.0

## Procedural surface roles: name -> McSurface spec. `tile_m` is the texture's real-world size from
## game/assets/textures/manifest.json, so a 2.5 m concrete slab tiles every 2.5 m and never stretches.
## Review r2: macro variation is ±8 % of value (it was reading as a blotch at close range) and the
## facade roles carry panel joints on city-build's 4 m module.
const SURFACES: Dictionary = {
	&"mc_stone": {"color": ArtPalette.STONE, "rough": 0.62, "tile_m": 2.0, "macro": 0.16,
		"grime": 0.26, "grime_height": 8.0, "streak": 0.22, "panel_m": 4.0, "panel_depth": 0.30,
		"tex_id": "clay_plaster", "facade": 1.0, "facade_podium_m": 5.0, "facade_gain": 1.0},
	&"mc_concrete": {"color": ArtPalette.CONCRETE, "rough": 0.78, "tile_m": 2.5, "macro": 0.18,
		"grime": 0.34, "grime_height": 10.0, "streak": 0.30, "panel_m": 4.0, "panel_depth": 0.38,
		"tex_id": "brushed_concrete", "facade": 1.0, "facade_podium_m": 6.0, "facade_gain": 1.2},
	&"mc_panel_white": {"color": ArtPalette.PANEL_WHITE, "rough": 0.35, "spec": 0.6, "tile_m": 8.0,
		"macro": 0.10, "grime": 0.18, "grime_height": 5.0, "streak": 0.24,
		"panel_m": 4.0, "panel_depth": 0.45, "tex_id": "concrete_panels",
		"facade": 1.0, "facade_podium_m": 6.0, "facade_gain": 1.3},
	&"mc_metal": {"color": ArtPalette.STEEL, "rough": 0.34, "metal": 0.9, "tile_m": 1.0,
		"macro": 0.14, "grime": 0.26, "streak": 0.28, "panel_m": 2.0, "panel_depth": 0.30,
		"tex_id": "metal_plate"},
	&"mc_bronze": {"color": ArtPalette.BRONZE, "rough": 0.30, "metal": 0.85, "tile_m": 1.0,
		"macro": 0.14, "grime": 0.22, "streak": 0.18, "panel_m": 2.0, "panel_depth": 0.22,
		"grime_color": Color(0.20, 0.26, 0.22), "tex_id": "metal_plate"},
	&"mc_terracotta": {"color": ArtPalette.TERRACOTTA, "rough": 0.72, "tile_m": 2.5,
		"macro": 0.22, "grime": 0.38, "grime_height": 4.0, "streak": 0.18,
		"tex_id": "clay_roof_tiles_02"},
	&"mc_deck": {"color": ArtPalette.DECK, "rough": 0.70, "tile_m": 2.5, "macro": 0.18,
		"grime": 0.34, "grime_height": 3.0, "streak": 0.12, "panel_m": 8.0, "panel_depth": 0.25,
		"tex_id": "brushed_concrete", "deck": 1.0, "deck_paver_m": 2.2},
}

## Every global shader parameter the art shaders read. The DECLARATIONS live in project.godot
## [shader_globals] (lead-owned): a shader compiled before a runtime `global_shader_parameter_add`
## does not see the new name, and re-adding an existing one errors. This table only carries the
## default this unit wants at load; needing a new global means asking the lead, not adding one here.
const GLOBALS: Dictionary = {
	&"mc_time": 0.0,
	&"mc_lit_fraction": 0.42,
	&"mc_infection": 1.0,
	&"mc_hive0": Vector4.ZERO,
	&"mc_hive1": Vector4.ZERO,
	&"mc_hive2": Vector4.ZERO,
	&"mc_hive3": Vector4.ZERO,
	&"mc_hive_levels": Vector4.ZERO,
}
