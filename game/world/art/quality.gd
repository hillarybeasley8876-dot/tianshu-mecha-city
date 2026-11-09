class_name ArtQuality
extends RefCounted
## Quality presets for the environment (city-art). Applied once at load: godot-tech §4.6 warns that
## toggling SDFGI, MSAA or adding the first ReflectionProbe mid-game triggers pipeline compiles, so
## presets are load-time only and never re-applied during play.
## Numbers: ART.md §3 (sun, fog) and godot-tech §4.3 (shadow splits, volumetric length).

const PRESETS: Dictionary = {
	&"low": {
		"ssao": false, "ssil": false, "ssr": false, "sdfgi": false,
		"volumetric": false, "vol_density": 0.0, "vol_length": 64.0, "glow": true, "glow_levels": 3,
		"shadow_distance": 220.0, "shadow_splits": 2, "shadow_size_scale": 0.75, "shadow_blur": 1.2,
		"sky_ambient": 1.60, "reflection_probes": false, "taa": false, "msaa": 0,
		"scale_3d": 0.5, "detail_m": 60.0, "tri_m": 20.0, "sun_specular": 0.15,
	},
	&"medium": {
		"ssao": true, "ssil": false, "ssr": false, "sdfgi": false,
		"volumetric": true, "vol_density": 0.0009, "vol_length": 130.0, "glow": true, "glow_levels": 5,
		"shadow_distance": 380.0, "shadow_splits": 4, "shadow_size_scale": 1.0, "shadow_blur": 1.2,
		"sky_ambient": 1.60, "reflection_probes": true, "taa": true, "msaa": 0,
		"scale_3d": 0.58, "detail_m": 120.0, "tri_m": 40.0, "sun_specular": 0.15,
	},
	&"high": {
		"ssao": true, "ssil": true, "ssr": false, "sdfgi": false,
		"volumetric": true, "vol_density": 0.0013, "vol_length": 180.0, "glow": true, "glow_levels": 7,
		"shadow_distance": 500.0, "shadow_splits": 4, "shadow_size_scale": 1.0, "shadow_blur": 1.2,
		# r14 cut the fill 0.40 -> 0.33 with the key and the shade went to black with it: at tod 0.6 the
		# shaded surfaces measured a median luma of 0.003-0.03 against a key-art floor of 0.09, and two
		# probe frames had HALF their pixels at exactly zero. r15 puts it back and then some — the sky
		# is the ambient source, so `sky_ambient` and the sky's own exposure move together; 1.90 here
		# with the sky at exposure 1.30 is the pair that lands `shd_p50` on 0.06-0.13 (target >= 0.09)
		# without moving the clip gate (0.04-0.48 % against 1.5 %).
		"sky_ambient": 1.60, "reflection_probes": true, "taa": true, "msaa": 0,
		"scale_3d": 0.60, "detail_m": 200.0, "tri_m": 60.0, "sun_specular": 0.15,
	},
}

## SDFGI is a separate opt-in (ART.md §3 A/B): `ArtQuality.sdfgi_enabled()` reads --gi=sdfgi.
const SDFGI := {
	"cascades": 4, "min_cell_size": 0.6, "energy": 1.0, "normal_bias": 1.1,
	"probe_bias": 1.1, "use_occlusion": true, "read_sky_light": true, "bounce_feedback": 0.5,
}


const MAX_GLOW_LEVELS := 7


static func preset() -> StringName:
	var q := String(Settings.get_value(&"quality"))
	return q if PRESETS.has(StringName(q)) else &"high"


static func get_preset(name: StringName = &"") -> Dictionary:
	return PRESETS[name if PRESETS.has(name) else preset()]


static func sdfgi_enabled() -> bool:
	return Game.flag("gi") == "sdfgi"


## Applies the preset to the Environment, the sun and the viewport. Load-time only.
static func apply(env: Environment, sun: DirectionalLight3D, p: Dictionary) -> void:
	env.ssao_enabled = bool(p["ssao"])
	env.ssao_radius = 2.2
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssil_enabled = bool(p["ssil"])
	env.ssil_radius = 6.0
	env.ssil_intensity = 1.45
	# r13: SSR is off on `high`. It measured 1.75 ms of a 28 ms street frame and what it buys in THIS
	# city is a mirror the art direction does not have: the surfaces it can reflect off are rough
	# concrete, glass and wet asphalt, and the wet read the key art sells is the deck shader's own
	# puddles plus the arena probes — shaded, not ray-marched. SSIL stays: it is the bounce that keeps
	# the shaded faces readable, which ART.md asks for by name.
	env.ssr_enabled = bool(p["ssr"])
	env.ssr_max_steps = 48
	env.ssr_fade_in = 2.0
	env.ssr_fade_out = 24.0

	env.volumetric_fog_enabled = bool(p["volumetric"])
	env.volumetric_fog_density = float(p["vol_density"])
	env.volumetric_fog_length = float(p["vol_length"])
	env.volumetric_fog_detail_spread = 2.0
	# Review r3 §3: volumetric fog exists for the god rays through the canyons, but a high ambient
	# inject plus a thick froxel slab lifted EVERY pixel and flattened the whole city (the A/B against
	# the low preset was unmistakable). Low inject = directional scattering = shafts, not milk.
	env.volumetric_fog_ambient_inject = 0.22
	env.volumetric_fog_sky_affect = 0.14
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9

	env.glow_enabled = bool(p["glow"])
	env.glow_intensity = 0.50
	env.glow_strength = 1.0
	env.glow_bloom = 0.09
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.45
	env.glow_hdr_scale = 2.0
	for i in range(MAX_GLOW_LEVELS):
		env.set_glow_level(i, 1.0 if i < int(p["glow_levels"]) else 0.0)

	if sdfgi_enabled():
		env.sdfgi_enabled = true
		env.sdfgi_cascades = int(SDFGI["cascades"])
		env.sdfgi_min_cell_size = float(SDFGI["min_cell_size"])
		env.sdfgi_energy = float(SDFGI["energy"])
		env.sdfgi_normal_bias = float(SDFGI["normal_bias"])
		env.sdfgi_probe_bias = float(SDFGI["probe_bias"])
		env.sdfgi_use_occlusion = bool(SDFGI["use_occlusion"])
		env.sdfgi_read_sky_light = bool(SDFGI["read_sky_light"])
		env.sdfgi_bounce_feedback = float(SDFGI["bounce_feedback"])
	else:
		env.sdfgi_enabled = false

	if sun != null:
		sun.directional_shadow_max_distance = float(p["shadow_distance"])
		sun.directional_shadow_mode = (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			if int(p["shadow_splits"]) == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
		sun.directional_shadow_split_1 = 0.05
		sun.directional_shadow_split_2 = 0.15
		sun.directional_shadow_split_3 = 0.40
		sun.directional_shadow_blend_splits = false
		sun.directional_shadow_fade_start = 0.85
		sun.shadow_bias = 0.06
		sun.shadow_normal_bias = 1.6
		# r13: `shadow_blur` is NOT a free saving. At 0 the sun's shadow term comes back ~0 over almost
		# the whole frame — the A5 deck wall loses two thirds of its value and the golden key with it
		# (`captures/r13mA_A5deck_base.jpg` against `..._shadow-blur.jpg`). 1.2 is the soft PCF the r12
		# look was approved on; it costs 3.4 ms and it is the only setting that puts the sun on the
		# walls at all, so it stays.
		sun.shadow_blur = float(p.get("shadow_blur", 1.2))
		# r14: the sun's specular was the single biggest clipper in the frame. A 2.3-energy key on a
		# 0.13-roughness glass pane threw a 14-degree white blob — 5.7 % of the T1fac street frame on its
		# own, more than the whole 1.5 % gate. 0.15 keeps the glint the wet decks and the key art's
		# reflections sell, without the blob.
		sun.light_specular = float(p.get("sun_specular", 0.15))

	# r13: the shader detail distances (see `McMaterials.set_detail_distance`). The mc_* shaders were the
	# single biggest item in the frame budget — more than the sun's shadows, more than SSIL and SSR
	# together — because every pixel paid nine anisotropic triplanar fetches and four 3D value noises
	# whether or not any of it was resolvable.
	McMaterials.set_detail_distance(float(p.get("detail_m", McMaterials.NO_DETAIL)),
		float(p.get("tri_m", McMaterials.NO_DETAIL)))

	var vp := Engine.get_main_loop()
	if vp is SceneTree and (vp as SceneTree).root != null:
		var rid: RID = (vp as SceneTree).root.get_viewport_rid()
		RenderingServer.viewport_set_msaa_3d(rid, int(p["msaa"]))
		_apply_scaling((vp as SceneTree).root, rid, p)


## 3D renders below the window's backing store and a temporal upscaler brings it back up. On a Retina
## Mac a 1600 x 900 window is a 3024 x 1898 framebuffer: native rendering held 23-24 fps at the A1yard
## and T1fac street cameras, MetalFX temporal at 0.67 held 35-40 with no visible softening in a 2x crop
## (lead probe, 11-04). A temporal upscaler is its own anti-aliasing, so TAA goes off with it (the
## engine disables it anyway and warns). `--render-scale=1` renders native, for art A/B captures.
static func _apply_scaling(root: Viewport, rid: RID, p: Dictionary) -> void:
	var scale := clampf(float(Game.flag("render-scale", str(p.get("scale_3d", 1.0)))), 0.25, 1.0)
	if scale > 0.999:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.scaling_3d_scale = 1.0
		RenderingServer.viewport_set_use_taa(rid, bool(p["taa"]))
		return
	var metal := RenderingServer.get_current_rendering_driver_name() == "metal"
	root.scaling_3d_mode = (Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if metal
		else Viewport.SCALING_3D_MODE_FSR2)
	root.scaling_3d_scale = scale
	RenderingServer.viewport_set_use_taa(rid, false)
