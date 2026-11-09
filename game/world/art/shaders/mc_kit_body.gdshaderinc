// mc_kit body (city-art, lead 12:10 PRIORITY) — the skin for city-kit's Tripo architecture.
//
// city-kit fits real modelled buildings over city-build's blockout and keeps the glTF texture sets
// Blender exported. A raw StandardMaterial3D in that scene is wrong in three ways, and this fixes all
// three with the mesh's own textures:
//   1. ATMOSPHERE — the rest of the city turns Godot's fog off and applies the two-band aerial
//      perspective of mc_haze.gdshaderinc itself. An imported material keeps the built-in fog, so kit
//      buildings sat in front of the haze instead of inside it.
//   2. WINDOWS — a baked albedo has no lit windows. The dark glass panes in it are found by luminance
//      (or read from a mask texture when the kit exports one) and lit at `mc_lit_fraction`, warm/cool
//      by a per-cell hash, so a kit tower joins the same dusk as the procedural ones.
//   3. INFECTION — the creep overlay in mc_creep.gdshaderinc, shared with mc_surface.
// The window cells live in OBJECT space, not world space: a kit model stores its native size and the
// placer scales it to its box, so the cell grid follows the building up onto a deck at +40 m instead of
// being keyed to absolute world height. The per-building SEED comes from world XZ, which is what makes
// two instances of one MultiMesh light up differently.
// Three thin shader files (mc_kit, mc_kit_two_sided, mc_kit_blend) share this body: `render_mode` is
// compile-time, so the cull/blend variants a glTF material asks for need their own header.

#include "mc_haze.gdshaderinc"
#include "mc_creep.gdshaderinc"
#include "mc_sun.gdshaderinc"

global uniform float mc_lit_fraction;

// --- the imported material's own set -------------------------------------------------------
uniform vec4 base_color : source_color = vec4(1.0);
// Anisotropic + mipmap filtering: these are triplanar/metre-UV architecture sets seen at grazing
// angles, and the imported textures are the detail the look lives on (look review 2026-11-02).
uniform sampler2D tex_albedo : source_color, hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_orm : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;      // r = AO, g = rough, b = metal
uniform sampler2D tex_rough : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_metal : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_emission : source_color, hint_default_black, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_gain : hint_range(0.0, 8.0) = 1.0;
uniform float roughness : hint_range(0.03, 1.0) = 0.7;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform int rough_channel : hint_range(0, 3) = 1;   // matches BaseMaterial3D.TextureChannel
uniform int metal_channel : hint_range(0, 3) = 2;
uniform float use_normal = 0.0;
uniform float use_orm = 0.0;
uniform float use_rough = 0.0;
uniform float use_metal = 0.0;
uniform float use_emission = 0.0;
uniform float use_alpha = 0.0;

// --- the window layer ------------------------------------------------------------------------
uniform sampler2D tex_win_mask : hint_default_black, repeat_enable;
uniform float win_mask_from : hint_range(0.0, 1.0) = 0.0;   // 0 = albedo darkness, 1 = mask texture
uniform float win_dark_lo : hint_range(0.0, 1.0) = 0.005;   // LINEAR luminance: below this, always glass
uniform float win_dark_hi : hint_range(0.0, 1.0) = 0.055;   // LINEAR: above this, never glass
uniform float win_gain : hint_range(0.0, 8.0) = 1.7;
uniform float win_cool : hint_range(0.0, 1.0) = 0.22;
uniform float win_cell_m = 3.4;      // bay spacing along the wall
uniform float win_floor_m = 4.0;     // city-build's floor module
uniform float win_podium_m = 6.0;    // no lit windows in the lowest floors (shopfronts, plant)
// The model's own base in OBJECT space, subtracted before the podium test and the floor grid. city-kit
// contracts to pivot at its footprint's base centre (0), but a model with a centred pivot would put
// its podium line halfway up the tower, so `McMaterials.apply_kit` passes the mesh AABB's min y.
uniform float win_base_y = 0.0;
uniform vec3 win_warm : source_color = vec3(1.0, 0.812, 0.541);
uniform vec3 win_cool_col : source_color = vec3(0.749, 0.890, 1.0);
uniform vec3 win_glass : source_color = vec3(0.075, 0.098, 0.133);
uniform float win_glass_mix : hint_range(0.0, 1.0) = 0.55;
// The same camera-distance dissolve as mc_window: past ~260 m the per-cell decision collapses to the
// lit fraction so a kit tower becomes a soft lit mass instead of a checkerboard.
uniform float win_fade_a = 210.0;
uniform float win_fade_b = 560.0;
uniform float creep_gain : hint_range(0.0, 1.0) = 1.0;
// city-art r14: how much of a Tripo bake's own albedo survives. The bakes are authored for a neutral
// studio light and land at 0.7-0.85 LINEAR reflectance, which under this city's 2.3-energy golden key
// puts every sunlit kit face over 248/255 — the Spire's crown cladding was 3.9 % of V3 on its own.
uniform float kit_albedo : hint_range(0.1, 1.0) = 1.0;
// A wall is flat; a dome, a tank or a moulded crown is not. Past this much normal change per metre
// (1 / radius) the part keeps the atlas, because a storey grid wrapped round a dome reads as a bug.
uniform float facade_curv_max = 0.25;
// city-art r13: past this distance the wall keeps its albedo, its dissolved window glow and its haze
// and drops everything sub-pixel (see mc_surface). Pushed by `McMaterials.set_detail_distance()`.
uniform float detail_m = 100000.0;

// mc_facade reads `base_color`, `tex_albedo`, `tex_orm`, `hash21` and the win_* metres, so it can only
// be included once they are all declared.
#include "mc_facade.gdshaderinc"

varying vec3 v_world;
varying vec3 v_local;
varying vec3 v_nrm;
varying vec3 v_lnrm;
varying float v_basey;

float pick_channel(vec4 t, int c) {
	return c == 0 ? t.r : (c == 1 ? t.g : (c == 2 ? t.b : t.a));
}

void vertex() {
	// The kit placer scales instances to their box (D4_p002's m04 is [1.336, 1.344, 1.0]), so the
	// facade grid has to be laid out in METRES: carry the instance scale out of MODEL_MATRIX and put
	// v_local in world metres measured from the instance origin. Without it a storey is 4.0 m on one
	// building and 5.4 m on its neighbour, and the two read as different architecture.
	vec3 ms = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX * ms;
	v_basey = win_base_y * ms.y;
	v_lnrm = NORMAL;
	v_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

// Where this texel is a window pane. The albedo route is the one that always works: city-kit's Blender
// pass keeps the glass dark in the colour map, so luminance finds it with no extra texture. A kit model
// that ships an explicit mask (in its emissive slot) sets `win_mask_from` to 1 and gets that instead.
float window_mask(vec2 uv, vec3 tex_a) {
	if (win_mask_from > 0.5) {
		vec3 m = texture(tex_win_mask, uv).rgb;
		return clamp(max(m.r, max(m.g, m.b)), 0.0, 1.0);
	}
	float lum = dot(tex_a, vec3(0.2126, 0.7152, 0.0722));
	return 1.0 - smoothstep(win_dark_lo, win_dark_hi, lum);
}

void fragment() {
	// city-art r13: the detail distance (see mc_surface). Past it the kit building keeps its albedo, its
	// dissolved window glow and its haze, and drops the ORM/normal fetches, the facade style pass and
	// the per-cell hashes — all of which are sub-pixel there and all of which are per-pixel work.
	float cam_d = distance(v_world, CAMERA_POSITION_WORLD);
	bool far_px = cam_d > detail_m;
	vec2 uv = UV * uv1_scale.xy + uv1_offset.xy;
	vec4 tex_a = texture(tex_albedo, uv);
	vec3 albedo = base_color.rgb * tex_a.rgb * kit_albedo;

	float rough = roughness;
	float metal = metallic;
	if (far_px) {
		// Nothing to do: the ORM islands and the normal map are below a pixel at this distance.
	} else if (use_orm > 0.5) {
		vec3 orm = texture(tex_orm, uv).rgb;
		rough *= orm.g;
		metal *= orm.b;
		AO = mix(1.0, orm.r, 0.9);
		AO_LIGHT_AFFECT = 0.35;
	} else {
		if (use_rough > 0.5) {
			rough *= pick_channel(texture(tex_rough, uv), rough_channel);
		}
		if (use_metal > 0.5) {
			metal *= pick_channel(texture(tex_metal, uv), metal_channel);
		}
	}

	vec3 emis = vec3(0.0);
	if (use_emission > 0.5 && !far_px) {
		// The model's own baked signage (city-kit's neon strips) — kept well under the window gain, so
		// a kit tower's shopfronts read as signage and its windows as the dusk coming on.
		emis += emission_color * texture(tex_emission, uv).rgb * emission_gain;
	}

	// Windows (see the header): dark panes found in the texture, lit per bay at `mc_lit_fraction`.
	// r11: on the walls the atlas is out and `mc_facade` builds the panes on a metric grid instead.
	vec3 ln = normalize(v_lnrm);
	float vert = 1.0 - abs(ln.y);
	float spec = specular;
	float wy = v_local.y - v_basey;
	if (vert > 0.35) {
		vec3 an = abs(ln);
		float u = an.x > an.z ? v_local.z : v_local.x;
		float y = wy;
		vec2 blk = floor(v_world.xz / 7.0);
		vec2 seed = vec2(hash21(blk) * 255.0, hash21(blk + 3.7) * 61.0);
		// The size of one pixel in metres along this wall, and the camera-distance dissolve. Both are
		// what the antialiasing of the facade is measured against.
		float px = max(fwidth(u), fwidth(y));
		float dist_fade = smoothstep(win_fade_a, win_fade_b, distance(v_world, CAMERA_POSITION_WORLD));
		// Per-BUILDING variation survives the dissolve (same block hash as mc_surface / mc_window), so a
		// kit tower does not converge on the same flat glow as every other far block.
		float b_var = hash21(floor(v_world.xz / 29.0) + seed);

		{
		float pane = window_mask(uv, tex_a.rgb);
		// Curvature: a flat wall's normal does not change across a pixel, a dome's does. Normal change
		// per metre is 1 / radius, so this is radius < 4 m at the default.
		float curv = length(vec2(fwidth(ln.x), fwidth(ln.y))) / max(px, 1e-4);
		float fac = facade_mix * (1.0 - smoothstep(facade_curv_max, facade_curv_max * 2.0, curv));
		// A facade pane is a pane by construction, so it takes the full dark glass; the atlas route
		// needs `win_glass_mix` < 1 because there a "pane" is only a dark patch in a colour map.
		float gmix = mix(win_glass_mix, 1.0, fac);
		float pane_v = 0.5;
		// r12 §1: the facade owns its grid, so it also owns the cell id the lit-window logic uses and
		// the colour of its own glass. On a curtain wall the lit cells are 1.5 m bays; on a punched wall
		// they are 3 m holes in a wall — the same `mc_lit_fraction` over very different areas.
		vec2 cid = vec2(floor(u / win_cell_m), floor((y - win_podium_m) / win_floor_m));
		vec3 glass_col = win_glass;
		if (fac > 0.0) {
			float fpane = 0.0;
			float fpane_v = 0.5;
			vec2 fcid = cid;
			vec3 fglass = win_glass;
			vec3 fcol = facade(uv, u, y, px, b_var, dist_fade, fpane, fpane_v, fcid, fglass);
			albedo = mix(albedo, fcol, fac);
			pane = mix(pane, fpane, fac);
			pane_v = mix(0.5, fpane_v, fac);
			cid = mix(cid, fcid, fac);
			glass_col = mix(win_glass, fglass, fac);
			// The atlas ORM carries its own islands; on a facade wall it is read coarse and flattened,
			// or the confetti comes straight back in the specular.
			rough = mix(rough, facade_rough, fac);
			metal = mix(metal, facade_metal, fac);
			if (use_orm > 0.5) {
				AO = mix(AO, mix(1.0, textureLod(tex_orm, uv, facade_mip).r, 0.9), fac);
			}
		}

		if (y > win_podium_m) {
			// Real towers light in runs — a whole floor or a stack of bays — not in per-cell noise: two
			// thirds of the decision is the cell, one third the floor it sits on.
			float h = mix(hash21(cid + seed), hash21(vec2(3.1, cid.y) + seed), 0.42);
			float lit = step(h, mc_lit_fraction);
			float tone = hash21(cid + seed + 17.3);
			float cool = step(1.0 - win_cool, hash21(cid + seed + 41.7));

			// The dissolve is the union of the pixel-size fade and the camera-distance one: a kit model's
			// UVs are per-model, so `fwidth` alone says nothing about how big a bay is on screen.
			float fade = max(smoothstep(0.18, 0.75, px), dist_fade);
			lit = mix(lit, mc_lit_fraction * mix(0.55, 1.30, b_var), fade);
			tone = mix(tone, mix(0.55, 0.88, hash21(floor(v_world.xz / 29.0) + seed + 3.1)), fade);

			// Only a strong mask on a wall becomes glass: dark grime and shadow in the albedo must not turn
			// a stone facade into a mirror.
			float glass = smoothstep(0.35, 0.80, pane) * (1.0 - fade * 0.6);
			albedo = mix(albedo, glass_col, glass * gmix);
			rough = mix(rough, 0.13, glass);
			metal = mix(metal, 0.70, glass);
			spec = mix(spec, 0.90, glass);
			emis += mix(win_warm, win_cool_col, cool) * win_gain * lit * pane
				* sun_face_dim(v_nrm)
				* mix(0.35, 1.0, tone) * mix(0.55, 1.25, pane_v);
		} else if (fac > 0.0) {
			// Shopfronts are lit all evening, but not in runs: one dim warm value under the sign band.
			float shop = smoothstep(0.35, 0.80, pane) * fac;
			albedo = mix(albedo, glass_col, shop * gmix);
			rough = mix(rough, 0.13, shop);
			metal = mix(metal, 0.70, shop);
			spec = mix(spec, 0.90, shop);
			emis += win_warm * win_gain * facade_shop_glow * shop;
		}
		}
	}

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = spec;
	NORMAL_MAP = far_px ? vec3(0.5, 0.5, 1.0)
		: mix(vec3(0.5, 0.5, 1.0), texture(tex_normal, uv).rgb, use_normal);
	NORMAL_MAP_DEPTH = normal_strength;
	if (use_alpha > 0.5) {
		ALPHA = base_color.a * tex_a.a;
	}

	// Aerial perspective first (mc_haze), then the creep overlay (mc_creep) — the same order mc_surface
	// uses, so a kit building and a blockout wall standing side by side haze and stain identically.
	vec3 hazed = ALBEDO;
	EMISSION = apply_haze(hazed, emis, layered_haze(v_world, CAMERA_POSITION_WORLD));
	ALBEDO = hazed;
	apply_creep(ALBEDO, ROUGHNESS, METALLIC, EMISSION, v_world, creep_gain);
}
