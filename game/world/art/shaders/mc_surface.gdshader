shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, fog_disabled, diffuse_burley, specular_schlick_ggx;
// mc_surface (city-art): the workhorse PBR for every opaque city role (stone, concrete, panel,
// metal, bronze, terracotta, deck, road base). Works with NO textures (procedural macro variation,
// grime and rain streaks only) and refines itself when a CC0 texture set is supplied, so the city
// never looks untextured while the library is still being fetched.
// UV_MODE: 0 = metre UV scaled by tile_m, 1 = world triplanar, 2 = raw UV (0..1 per face).
#include "mc_haze.gdshaderinc"
#include "mc_creep.gdshaderinc"
#include "mc_sun.gdshaderinc"
#include "mc_wet.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.7);
uniform float roughness : hint_range(0.03, 1.0) = 0.7;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform vec3 tint_a : source_color = vec3(1.0);
uniform vec3 tint_b : source_color = vec3(0.88, 0.86, 0.82);
uniform int uv_mode : hint_range(0, 2) = 1;
uniform float tile_m = 4.0;
// Mipmaps are generated on every library map (tools/textures/fetch.py writes the .import) and the
// decks/roofs are seen at grazing angles, so the minification filter is what keeps them crisp
// instead of fizzing. Look review 2026-11-02 item 1.
uniform sampler2D tex_albedo : source_color, hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_rough : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float tex_strength : hint_range(0.0, 1.0) = 1.0;
uniform float tex_gain = 1.0;  // 1 / mean(albedo): keeps the texture a modulation, not a darkening
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float macro_scale = 0.035;         // world metres -> macro-noise frequency (1/28 m)
uniform float macro_amount : hint_range(0.0, 1.0) = 0.45;
uniform float grime_amount : hint_range(0.0, 1.0) = 0.35;
uniform float grime_height = 6.0;          // metres of splash grime above the base
uniform float streak_amount : hint_range(0.0, 1.0) = 0.30;
uniform float streak_scale = 0.5;
uniform vec3 grime_color : source_color = vec3(0.22, 0.20, 0.19);
uniform float creep_gain : hint_range(0.0, 1.0) = 1.0;
// Review r2: panel joints on the 4 m facade module. 0 = no joints (roads, water, organic surfaces).
uniform float panel_m = 0.0;
uniform float panel_depth : hint_range(0.0, 1.0) = 0.35;
// Lead r7 (polish): the arena's permanent cover is board-formed concrete, and a 24 m wall of it is the
// largest flat value in the frame. `board_m` draws the shutter boards (a line every board, each board a
// slightly different batch), `form_tie_m` the cone holes the ties leave on their grid, and `reveal_m`
// the recessed shadow gap that divides the pour into panels. All 0 = off, so every other role is
// untouched.
uniform float board_m = 0.0;
uniform float form_tie_m = 0.0;
uniform float reveal_m = 0.0;
uniform float reveal_depth : hint_range(0.0, 1.0) = 0.6;
// Lead r4: the decks and podium tops are the biggest unbroken planes in every vista and they were the
// flattest thing in the frame. 1 = paver grid + patch repairs + standing water (mc_deck).
uniform float deck_on = 0.0;
uniform float deck_paver_m = 2.2;
uniform float deck_patch_m = 7.0;
// City-wide wetness (lead 12:25, post-render's SSR A/B): how much of the deck the puddles cover.
// 0 = bone dry, 1 = every basin full. Pushed by `McMaterials.set_wetness()`, like the haze bands.
uniform float wet : hint_range(0.0, 1.0) = 0.55;

// city-art r13: past this distance the pixel takes the cheap path (one texture fetch, no procedural
// detail, the dissolved window grid). `McMaterials.set_detail_distance()` pushes it; the default is
// far enough that the cheap path is off, so an A/B is one call and a missing push changes nothing.
uniform float detail_m = 100000.0;
// city-art r13: past this distance a triplanar surface is sampled on its dominant axis instead of on
// all three — a third of the texture fetches for a projection change only a diagonal face can show.
uniform float tri_m = 100000.0;

// Review r3 §1 "Facades": the blocks that carry no `mc_window` surface of their own still have to read
// as buildings, so this punches a lit window grid straight into the wall. `facade_mask` (FacadeMask) is
// what separates a tower facade from a viaduct parapet — both are mc_concrete.
uniform float facade_on = 0.0;              // 0 = never (roads, decks, roofs), 1 = auto by the mask
uniform sampler2D facade_mask : filter_nearest, repeat_disable;
uniform float facade_podium_m = 15.0;       // no punched windows below this height above base_z
uniform float facade_curtain_m = 40.0;      // tier C/D turns into curtain wall above this
uniform float facade_module = 4.0;          // city-build's floor module
uniform float facade_gain = 2.9;
uniform float facade_cool : hint_range(0.0, 1.0) = 0.22;
uniform vec3 facade_warm : source_color = vec3(1.0, 0.812, 0.541);
uniform vec3 facade_cool_col : source_color = vec3(0.749, 0.890, 1.0);
uniform vec3 facade_glass : source_color = vec3(0.075, 0.098, 0.133);

global uniform float mc_lit_fraction;

varying vec3 v_world;
varying vec3 v_nrm;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize((MODEL_NORMAL_MATRIX * NORMAL));
}

vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 1e-4);
}

vec3 tri_sample(sampler2D t, vec3 p, vec3 w, float s) {
	return texture(t, p.zy * s).rgb * w.x + texture(t, p.xz * s).rgb * w.y + texture(t, p.xy * s).rgb * w.z;
}

// Panel joints: a groove every `m` metres on the two axes the face actually spans, so a facade reads as
// assembled panels instead of one flat field at close range (review r2). Returns 1 in the groove.
float panel_joint(vec3 p, vec3 n, float m) {
	if (m <= 0.01) {
		return 0.0;
	}
	vec3 an = abs(n);
	vec2 q = an.y > 0.7 ? p.xz : (an.x > an.z ? p.zy : p.xy);
	vec2 g = abs(fract(q / m + 0.5) - 0.5) * m;
	float groove = 1.0 - smoothstep(0.025, 0.085, min(g.x, g.y));
	// A fixed-metre smoothstep is a sub-pixel step once the surface is far away, which is exactly
	// the crawling shimmer the key art does not have. Fade the groove out as it stops being
	// resolvable, the same way the facade grid does (look review 2026-11-02 item 1).
	float aa = clamp(max(fwidth(q.x), fwidth(q.y)) / 0.12, 0.0, 1.0);
	return groove * (1.0 - aa);
}

// The window grid on a facade (review r3 §1). `curtain` blends a punched masonry grid into a mullioned
// curtain wall. Outputs are masks, not colours, so the caller keeps control of the palette.
void facade_cells(vec2 seed, float curtain, float y, out float pane, out float frame,
		out float lit, out float tone, out float cool) {
	vec3 an = abs(normalize(v_nrm));
	float u = an.x > an.z ? v_world.z : v_world.x;
	float m = facade_module;

	// Punched: a 2.6 x 2.2 m window with a 0.9 m sill inside the 4 m floor module.
	vec2 pid = vec2(floor(u / m), floor((y - facade_podium_m) / m));
	vec2 pl = vec2(u - pid.x * m, (y - facade_podium_m) - pid.y * m);
	float punched = step(0.7, pl.x) * step(pl.x, 3.3) * step(0.9, pl.y) * step(pl.y, 3.1);
	float reveal = 1.0 - step(0.55, pl.x) * step(pl.x, 3.45) * step(0.75, pl.y) * step(pl.y, 3.25);

	// Curtain wall: glass everywhere, a mullion every 1.35 m and a spandrel every floor.
	float mx = abs(fract(u / 1.35 + 0.5) - 0.5) * 1.35;
	float my = abs(fract(y / m + 0.5) - 0.5) * m;
	float mull = 1.0 - smoothstep(0.05, 0.13, min(mx, my));

	pane = mix(punched, 1.0, curtain);
	frame = mix(reveal, mull, curtain);

	// Real towers light up in runs — a whole floor, or a whole stack of bays — not in per-cell noise.
	// Two thirds of the decision comes from the cell and one third from the floor it is on, which is
	// what turns a random field into horizontal banding at distance.
	vec2 cid = mix(pid, vec2(floor(u / 2.7), floor(y / m)), curtain);
	float h = mix(hash21(cid + seed), hash21(vec2(3.1, cid.y) + seed), 0.42);
	lit = step(h, mc_lit_fraction);
	tone = hash21(cid + seed + 17.3);
	cool = step(1.0 - facade_cool, hash21(cid + seed + 41.7));

	// Lead (boss r2, r4): once a 4 m window cell is a few pixels across, the whole facade turns into
	// static. `fwidth` gives the cell's size in pixels-of-world, so the grid can be dissolved into its
	// own AVERAGE exactly when it stops being resolvable — the far city becomes a smooth lit glow
	// carrying the lit fraction instead of a shimmering checkerboard. The range is early on purpose:
	// the mid-distance towers (300-900 m) were the ones reading as a checkerboard.
	float px = max(fwidth(u), fwidth(y));
	float fade = smoothstep(0.18, 0.75, px);
	pane = mix(pane, mix(0.36, 1.0, curtain), fade);
	frame = mix(frame, 0.12, fade);
	// The far city must not converge on ONE value: a block hash (not a cell hash) keeps neighbouring
	// towers a stop apart after the grid has dissolved, which is what leaves the skyline reading as a
	// field of separate buildings rather than one lit wall.
	float b_var = hash21(floor(v_world.xz / 29.0) + seed);
	lit = mix(lit, mc_lit_fraction * mix(0.55, 1.30, b_var), fade);
	tone = mix(tone, mix(0.55, 0.88, hash21(floor(v_world.xz / 29.0) + seed + 3.1)), fade);
}

// Structural relief on the wall itself (lead, r4 "detail energy"). The key art's facades are not
// flat fields with windows drawn on them: every floor has a slab edge that catches the sky and a
// shadow line under it, every second bay has a pier, and every few floors a ledge runs the whole way
// round. None of that is geometry — at the distance a vista is judged from, the shading of a slab
// edge is what makes a wall read as built, and it costs three fract() calls.
float facade_relief(float u, float y, vec2 seed, float fade, out float shade) {
	float m = facade_module;
	float bay = m * 2.0;
	float ly = fract(y / m) * m;              // 0..m, measured up from the floor line
	float pu = abs(fract(u / bay + 0.5) - 0.5) * bay;   // distance to the nearest pier centre

	// Slab edge: a lit lip on the floor line, a shadow line immediately under it.
	float lip = 1.0 - smoothstep(0.16, 0.46, ly);
	float under = smoothstep(0.46, 0.62, ly) * (1.0 - smoothstep(0.72, 1.15, ly));
	// Ledge every fourth floor: deeper, and it throws a wider shadow.
	float ledge_row = abs(fract(y / (m * 4.0) + 0.5) - 0.5) * m * 4.0;
	float ledge = 1.0 - smoothstep(0.55, 0.95, ledge_row);
	float ledge_shadow = smoothstep(0.95, 1.25, ledge_row) * (1.0 - smoothstep(1.7, 2.4, ledge_row));
	// Pier: proud of the wall, with a shadow line down each side.
	float pier = 1.0 - smoothstep(0.36, 0.52, pu);
	float pier_edge = smoothstep(0.52, 0.60, pu) * (1.0 - smoothstep(0.68, 0.82, pu));
	// Plinth: the lowest 3 m is a darker stone base course on every building.
	float plinth = 1.0 - smoothstep(2.6, 3.2, y);
	// One bay in three is a slightly different batch of panel — the thing that stops a long wall from
	// reading as one repeated stamp.
	float bay_tone = mix(0.93, 1.07, hash21(floor(vec2(u / bay, y / (m * 4.0))) + seed));

	float v = bay_tone;
	v *= mix(1.0, 1.22, lip) * mix(1.0, 0.74, under);
	v *= mix(1.0, 1.16, ledge) * mix(1.0, 0.66, ledge_shadow);
	v *= mix(1.0, 1.10, pier) * mix(1.0, 0.82, pier_edge);
	v = mix(v, v * 0.78, plinth);
	shade = max(max(under, ledge_shadow), pier_edge);
	// Past the point where a 4 m floor is a couple of pixels, the relief is noise: dissolve it.
	return mix(v, 1.0, fade);
}



// Board-formed concrete (lead r7). One function, three marks, all in metres on the face's own two
// axes, all faded by `fwidth` like every other line in this shader: a board line every `board_m` with
// its own batch tone, the form-tie cone holes on a `form_tie_m` grid, and a recessed reveal on the
// larger `reveal_m` module. `shade` is the part that should also roughen the surface.
void board_form(vec2 q, out float tone, out float shade) {
	tone = 1.0;
	shade = 0.0;
	float px = max(fwidth(q.x), fwidth(q.y));
	// Metres per pixel. A 3 cm board line and a 7 cm tie hole are gone by ~30 m, but that is well
	// inside the range an arena wall is judged at, so the cut-offs are set where the mark is about two
	// pixels wide — not where it is mathematically resolvable.
	float fine = 1.0 - clamp(px / 0.12, 0.0, 1.0);
	float coarse = 1.0 - clamp(px / 0.32, 0.0, 1.0);

	if (board_m > 0.01) {
		float ly = abs(fract(q.y / board_m + 0.5) - 0.5) * board_m;
		float line = (1.0 - smoothstep(0.015, 0.06, ly)) * fine;
		// Every board is a separate length of timber: the tone drift is what stops a big wall reading as
		// one printed texture, and it survives long after the lines themselves have gone.
		tone *= mix(1.0, 0.76, line);
		tone *= mix(0.90, 1.10, hash21(vec2(floor(q.x / 1.6), floor(q.y / board_m))));
		shade = max(shade, line * 0.7);
	}
	if (form_tie_m > 0.01) {
		vec2 t = (fract(q / form_tie_m + 0.5) - 0.5) * form_tie_m;
		float d = length(t * vec2(1.0, 1.35));
		float hole = (1.0 - smoothstep(0.035, 0.075, d)) * fine;
		float ring = smoothstep(0.06, 0.09, d) * (1.0 - smoothstep(0.09, 0.14, d)) * fine;
		tone *= mix(1.0, 0.55, hole);
		tone *= mix(1.0, 1.10, ring);
		shade = max(shade, hole);
	}
	if (reveal_m > 0.01) {
		vec2 rv = abs(fract(q / reveal_m + 0.5) - 0.5) * reveal_m;
		float groove = 1.0 - smoothstep(0.05, 0.13, min(rv.x, rv.y));
		// The lip above a recessed reveal catches the light; the groove itself is a hard shadow line.
		float lip = smoothstep(0.13, 0.17, min(rv.x, rv.y)) * (1.0 - smoothstep(0.17, 0.30, min(rv.x, rv.y)));
		tone *= mix(1.0, 0.42, groove * coarse * reveal_depth);
		tone *= mix(1.0, 1.14, lip * coarse);
		shade = max(shade, groove * coarse * reveal_depth);
	}
}

void fragment() {
	vec3 wn = normalize(v_nrm);
	// city-art r13: the detail distance. Everything below `detail_m` is the full material; past it the
	// pixel takes one texture fetch and the flat base colour, because that is all that survives
	// minification anyway — the macro noise, the grime, the rain streaks, the panel grooves, the board
	// marks and the paver grid are all sub-pixel there, and each one is a 3D value noise (8 hashes) or
	// a triplanar fetch (3 taps per map). The mc_* shaders measured 6.3 ms of a 28 ms street frame;
	// this is where that goes. `McMaterials.set_detail_distance()` pushes the number.
	float cam_d = distance(v_world, CAMERA_POSITION_WORLD);
	bool far_px = cam_d > detail_m;
	vec2 uv;
	vec3 tw = vec3(1.0, 0.0, 0.0);
	float s = 1.0 / max(tile_m, 0.01);
	if (uv_mode == 1) {
		tw = triplanar_weights(wn);
		uv = UV * s;
	} else if (uv_mode == 0) {
		uv = UV * s;
	} else {
		uv = UV;
	}

	vec3 tex_a = vec3(1.0);
	vec3 tex_n = vec3(0.5, 0.5, 1.0);
	float tex_r = 1.0;
	if (tex_strength > 0.0) {
		if (far_px) {
			// One fetch, on the axis the face actually points along: nine anisotropic taps for a
			// surface that is ten pixels across is the whole cost.
			vec2 duv = uv_mode == 1 ? (abs(wn).y > 0.7 ? v_world.xz : (abs(wn.x) > abs(wn.z)
				? v_world.zy : v_world.xy)) * s : uv;
			tex_a = texture(tex_albedo, duv).rgb;
		} else if (uv_mode == 1 && cam_d > tri_m) {
			// Triplanar is three anisotropic fetches per map — nine per pixel — and what it buys is a
			// seam-free projection on faces that are not axis-aligned. A city is boxes: past `tri_m` the
			// dominant axis IS the wall's own plane, so the same three maps cost three fetches instead
			// of nine and the only thing that changes is a diagonal face's texture direction.
			vec2 duv = (abs(wn).y > 0.7 ? v_world.xz : (abs(wn.x) > abs(wn.z)
				? v_world.zy : v_world.xy)) * s;
			tex_a = texture(tex_albedo, duv).rgb;
			tex_n = texture(tex_normal, duv).rgb;
			tex_r = texture(tex_rough, duv).g;
		} else if (uv_mode == 1) {
			tex_a = tri_sample(tex_albedo, v_world, tw, s);
			tex_n = tri_sample(tex_normal, v_world, tw, s);
			tex_r = tri_sample(tex_rough, v_world, tw, s).g;
		} else {
			tex_a = texture(tex_albedo, uv).rgb;
			tex_n = texture(tex_normal, uv).rgb;
			tex_r = texture(tex_rough, uv).g;
		}
	}

	// Macro variation: broad tint drift so large facades never read as one flat colour.
	float macro = far_px ? 0.5
		: vnoise(v_world * macro_scale) * 0.65 + vnoise(v_world * macro_scale * 3.1) * 0.35;
	vec3 albedo = base_color * mix(tint_a, tint_b, macro * macro_amount + (1.0 - macro_amount) * 0.5);
	albedo *= mix(vec3(1.0), tex_a * tex_gain, tex_strength);

	// Grime: splash dirt near the base, plus a cavity-ish term on downward faces.
	float vert = 1.0 - abs(wn.y);
	float grime = 0.0;
	float streak = 0.0;
	float joint = 0.0;
	float form_shade = 0.0;
	if (!far_px) {
		float base_t = 1.0 - clamp((v_world.y - 0.0) / max(grime_height, 0.01), 0.0, 1.0);
		float down = clamp(-wn.y, 0.0, 1.0);
		grime = grime_amount * clamp(base_t * base_t * 0.8 + down * 0.5, 0.0, 1.0)
			* (0.55 + 0.45 * vnoise(v_world * 0.35));
		albedo = mix(albedo, grime_color * (0.6 + 0.4 * albedo), grime);

		// Rain streaks: vertical smears on near-vertical faces only.
		streak = vnoise(vec3(v_world.x * streak_scale, v_world.y * 0.02, v_world.z * streak_scale));
		streak = smoothstep(0.62, 0.95, streak) * vert * streak_amount;
		albedo *= 1.0 - streak * 0.45;

		// Panel joints on the module grid: a shadow line with a highlight lip on the up-sun side.
		joint = panel_joint(v_world, wn, panel_m) * panel_depth;
		albedo *= 1.0 - joint * 0.55;

		// Board-formed concrete (lead r7): only on near-vertical faces, and only for the roles that ask
		// for it. `board_form` works on the face's own two world axes, so the marks stay square to the
		// wall.
		if (board_m > 0.01 && vert > 0.5) {
			vec3 an0 = abs(wn);
			vec2 fq = an0.x > an0.z ? v_world.zy : v_world.xy;
			float tone = 1.0;
			board_form(fq, tone, form_shade);
			albedo *= tone;
		}
	}

	float rough = clamp(roughness * mix(1.0, tex_r * 2.0, tex_strength) + grime * 0.25 + streak * 0.2
		+ joint * 0.25 + form_shade * 0.30, 0.03, 1.0);

	// Deck surfaces (lead r4): a paver grid at walking scale, patch repairs where the slab has been
	// cut and re-laid, and standing water in the low spots — the wet deck is what puts the dusk sky
	// back into the floor of the frame, and it is in every one of the key art plates.
	float spec_wet = specular;
	// r15 §4: how wet this fragment is, so the analytic sky reflection below knows what to mirror.
	float deck_wet = 0.0;
	if (deck_on > 0.5 && wn.y > 0.55 && !far_px) {
		vec2 g = abs(fract(v_world.xz / deck_paver_m + 0.5) - 0.5) * deck_paver_m;
		float groove = 1.0 - smoothstep(0.03, 0.10, min(g.x, g.y));
		// Paver grooves are ~7 cm: past a few tens of metres they are far below a pixel and a hard
		// step there crawls. Fade with the same fwidth rule the panel joints use.
		float gaa = clamp(max(fwidth(v_world.x), fwidth(v_world.z)) / 0.10, 0.0, 1.0);
		groove *= 1.0 - gaa;
		vec2 pid = floor(v_world.xz / deck_patch_m);
		float patch = hash21(pid);
		albedo *= (1.0 - groove * 0.45) * mix(0.86, 1.14, patch);
		albedo = mix(albedo, albedo * vec3(0.82, 0.83, 0.88), step(0.78, patch) * 0.7);
		// Puddles: broad low-frequency basins, glossy and darker, so the sky lands in them. `wet` slides
		// the waterline, so one number drives how much of the deck is reflecting.
		float basin = vnoise(v_world * 0.055) * 0.7 + vnoise(v_world * 0.17) * 0.3;
		float line = mix(0.82, 0.42, wet);
		float wetness = smoothstep(line, line + 0.18, basin) * (1.0 - groove);
		// r15 §4: and a FILM everywhere, not just in the basins. The key art's decks are damp across
		// their whole width — v1's pier and v2's street both carry the sky end to end — and a deck that
		// is dry between its puddles reads as plastic. `film` is the "a little everywhere" the brief
		// asks for; the basins then go the rest of the way to a mirror.
		float film = wet * 0.34;
		wetness = clamp(wetness + film, 0.0, 1.0);
		albedo *= mix(1.0, 0.42, wetness);
		rough = mix(rough, 0.07, wetness);
		spec_wet = mix(specular, 0.9, wetness);
		deck_wet = wetness;
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metallic;
	SPECULAR = spec_wet;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), tex_n, tex_strength);
	NORMAL_MAP_DEPTH = normal_strength;

	vec3 emis = vec3(0.0);
	// Facade windows (review r3 §1). Only near-vertical faces of a masked building footprint, above the
	// podium: everything else on this material is road, deck, parapet or roof.
	if (facade_on > 0.5 && vert > 0.55) {
		vec2 muv = (v_world.xz + vec2(700.0)) / 1400.0;
		vec4 fm = texture(facade_mask, clamp(muv, vec2(0.0), vec2(1.0)));
		float y = v_world.y - fm.b * 64.0;
		vec2 seed = vec2(fm.a * 255.0, fm.a * 61.0);
		vec3 an = abs(wn);
		float u = an.x > an.z ? v_world.z : v_world.x;
		float fade = smoothstep(0.18, 0.75, max(fwidth(u), fwidth(y)));
		if (fm.r > 0.5) {
			// The relief runs at every distance: it is ALU, not texture work, and the far city's slab
			// lines are most of what makes it read as built. Only the FETCHES and the 3D value noise go
			// away past `detail_m`.
			float shade = 0.0;
			float relief = facade_relief(u, y, seed, fade, shade);
			ALBEDO *= relief;
			ROUGHNESS = clamp(ROUGHNESS + shade * 0.18 - (relief - 1.0) * 0.10, 0.05, 1.0);
		}
		if (fm.r > 0.5 && y > facade_podium_m) {
			// Tier C/D above `facade_curtain_m` is a glass curtain wall; everything else is a punched
			// grid in the masonry. The blend is soft so a setback tower does not switch language mid-wall.
			float curtain = smoothstep(facade_curtain_m, facade_curtain_m + 14.0, y) * fm.g;
			float pane = 0.0;
			float frame = 0.0;
			float lit = 0.0;
			float tone = 0.0;
			float cool = 0.0;
			facade_cells(seed, curtain, y, pane, frame, lit, tone, cool);
			// A window is glass: dark, glossy, and it reflects the dusk sky through the ambient probe.
			ALBEDO = mix(ALBEDO, facade_glass, pane * (1.0 - frame));
			ALBEDO = mix(ALBEDO, ALBEDO * 0.72, frame * 0.8);      // mullion / reveal shadow
			ROUGHNESS = mix(ROUGHNESS, 0.13, pane * (1.0 - frame));
			METALLIC = mix(METALLIC, 0.70, pane * (1.0 - frame));
			SPECULAR = mix(SPECULAR, 0.9, pane * (1.0 - frame));
			// Interiors are not one lamp: `tone` spreads them from a dim back room to a lit office.
			vec3 lamp = mix(facade_warm, facade_cool_col, cool);
			emis += lamp * facade_gain * lit * pane * (1.0 - frame) * mix(0.35, 1.0, tone)
				* sun_face_dim(wn);
		}
	}

	// Far aerial perspective (review r3 §3): past ~700 m the air goes cool violet-blue.
	// r15 §4: the wet deck mirrors the sky (mc_wet.gdshaderinc). SSR is off at shipping quality, so
	// this is the reflection the key art's pier and street sell — analytic, ~25 ALU, no texture fetch.
	emis += wet_reflection(v_world, wn, CAMERA_POSITION_WORLD, deck_wet);

	vec3 alb = ALBEDO;
	emis = apply_haze(alb, emis, layered_haze(v_world, CAMERA_POSITION_WORLD));
	ALBEDO = alb;
	EMISSION = emis;

	// Infection creep (review r2) — the shared overlay in mc_creep.gdshaderinc, which the Tripo kit
	// buildings also carry so a nest stains real architecture the same way it stains the blockout.
	apply_creep(ALBEDO, ROUGHNESS, METALLIC, EMISSION, v_world, creep_gain);
}
