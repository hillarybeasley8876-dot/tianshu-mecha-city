shader_type spatial;
// `fog_disabled`: the city's depth fog is one warm colour over one curve and it was turning the whole
// ring into a single flat orange band. The ring does its own aerial perspective instead (below), which
// is also why it is `unshaded` — a silhouette must not pick up the sun as a lit wall.
// mc_skyline (city-art, review r3 §3; retuned in r9): the blocks past the map edge, 430-1,400 m out,
// which is BOTH city-build's 96-box `Skyline` ring AND its `_hlod` proxies. The key art has them as
// stacked silhouettes dissolving upward into the horizon; with the city's own concrete on them they
// read as a wall that closes every vista.
render_mode unshaded, fog_disabled, cull_back, depth_draw_opaque;

uniform vec3 body : source_color = vec3(0.115, 0.098, 0.130);
uniform vec3 rim : source_color = vec3(0.72, 0.46, 0.30);
// Review r9: this is the SKY's own horizon colour, pushed every frame by `TimeOfDay._ring_band()`.
// It is a uniform and not a constant precisely because a fixed value detaches from the sky — the
// lavender it used to be stuck at is what made the far city read as periwinkle boxes on an amber sky.
uniform vec3 sky_band : source_color = vec3(0.46, 0.40, 0.44);
uniform float rim_gain : hint_range(0.0, 4.0) = 1.0;
uniform float haze_floor = 0.40;        // how much air even the nearest block's BASE sits in
uniform float haze_top = 0.92;          // and how nearly gone its roofline is
uniform float haze_curve : hint_range(0.3, 3.0) = 1.7;  // >1 keeps the lower mass dark, top dissolves
uniform float depth_lo = 0.88;          // how much nearer/further blocks differ in haze
uniform float depth_hi = 1.14;
uniform float top_m = 240.0;            // metres over which the mass dissolves upward
uniform float base_m = -40.0;
// The band is the SKY's colour, so a silhouette has to sit UNDER it — mixing to the sky value itself
// makes the far city read as white paper cut-outs against a slightly brighter sky.
uniform float band_gain : hint_range(0.0, 1.5) = 0.66;

// --- silhouette breakers (review r9 §3) -------------------------------------------------
// Roofs are dark and slightly cool. Half of what a high vista sees of the far city is roof planes,
// and giving them the same value as the walls is most of what makes a box read as a box.
uniform float roof_dark : hint_range(0.0, 1.0) = 0.42;
uniform vec3 roof_tint : source_color = vec3(0.86, 0.92, 1.06);
// A sun-side rim on the VERTICAL EDGES: grazing faces seen from outside are exactly a box's corners,
// so a fresnel weighted by the block's own azimuth lights the edges that face the sun and leaves the
// rest of the wall flat.
uniform float edge_gain : hint_range(0.0, 4.0) = 0.55;
uniform float edge_pow : hint_range(0.5, 8.0) = 3.0;

// --- lit windows (review r9 §2) ----------------------------------------------------------
// They are a SPARKLE, not a grid. The old cell grid was 2-4 px per cell at 450-1,000 m and read as a
// high-contrast checkerboard over every far mass in every vista. What is here now is a sparse hashed
// POINT pattern: ~2 % of cells carry one round dot, the dot is never smaller than a pixel, and the
// whole term dissolves into its own mean with `fwidth` so no cell structure survives at any distance.
uniform vec3 window_col : source_color = vec3(1.0, 0.78, 0.50);
uniform float window_gain : hint_range(0.0, 4.0) = 0.55;
uniform float spark_m = 3.2;            // metres between candidate window points
uniform float spark_density : hint_range(0.0, 0.25) = 0.030;
uniform float spark_r : hint_range(0.05, 3.0) = 0.55;   // dot radius in metres (floor)
uniform float spark_fade_a = 1.1;       // cell size in PIXELS: below this the sparkle is its own mean
uniform float spark_fade_b = 4.2;
uniform float block_m = 90.0;           // per-block seed, so one field does not run across the ring
// Floor bands, at most: the only horizontal structure left, and very low contrast.
uniform float floor_m = 4.2;
uniform float floor_contrast : hint_range(0.0, 0.4) = 0.055;

global uniform float mc_lit_fraction;

varying vec3 v_world;
varying vec3 v_nrm;

float hash21(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize((MODEL_NORMAL_MATRIX * NORMAL));
}

// The lit-window sparkle: sparse round points on the wall plane, dissolving into their own mean once
// a cell is only a pixel or two across. `u`/`fw` come from the caller because the same metres-per-pixel
// figure drives the floor bands.
float sparkle(float u, float fw, float lit, out float mean_out) {
	vec2 p = vec2(u, v_world.y) / spark_m;
	vec2 cid = floor(p) + floor(v_world.xz / block_m);
	float frac = clamp(spark_density * (0.35 + lit), 0.0, 1.0);
	mean_out = frac * 0.30;
	float px = spark_m / max(fw, 1e-5);           // cell size in pixels
	float fade = smoothstep(spark_fade_a, spark_fade_b, px);
	if (fade <= 0.0) {
		return mean_out;
	}
	float on = step(hash21(cid), frac);
	// Jitter the point inside its cell so the field does not read as a lattice even up close.
	vec2 jit = vec2(hash21(cid + 3.17), hash21(cid + 7.71));
	float r = max(spark_r, fw * 0.70);           // never thinner than a pixel, or it aliases
	float d = length((fract(p) - jit) * spark_m);
	return mix(mean_out, on * (1.0 - smoothstep(r * 0.45, r, d)), fade);
}

void fragment() {
	vec3 n = normalize(v_nrm);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - v_world);
	// Backlit at dusk: the mass is warm on the sun's side and flat dark away from it. Lead r4: that
	// warmth used to come from the FACE NORMAL, and the ring is stepped block massing — so every facet
	// of every setback took a different value and the whole far city read as a mosaic of pale
	// rectangles. The dominant term is the block's own azimuth around the ring, which varies smoothly.
	vec3 sun_h = normalize(vec3(-0.62, 0.0, 0.70));
	vec3 radial = normalize(vec3(v_world.x, 0.0, v_world.z) + vec3(1e-5));
	float side = pow(clamp(dot(radial, sun_h) * 0.5 + 0.5, 0.0, 1.0), 1.5);
	float up = clamp(n.y, 0.0, 1.0);
	float roof = smoothstep(0.55, 0.85, up);
	vec3 col = body + rim * (side * 0.62) * rim_gain;
	col *= mix(1.0, roof_dark, roof);
	col *= mix(vec3(1.0), roof_tint, roof);

	// One horizontal axis per wall, or the pattern runs diagonally across a rotated face.
	float u = abs(n.x) > abs(n.z) ? v_world.z : v_world.x;
	float fw = max(fwidth(u), fwidth(v_world.y));
	float mean;
	float sp = sparkle(u, fw, mc_lit_fraction, mean);
	// Floor bands: the only horizontal structure left, and they go before the cells are resolvable.
	float band_fade = 1.0 - smoothstep(2.0, 6.0, floor_m / max(fw, 1e-5));
	col *= 1.0 + (cos(v_world.y * TAU / floor_m) * 0.5) * floor_contrast * band_fade * (1.0 - roof);

	// Aerial perspective. Review r9 §3: the base has to stay DARK and the top has to go, or the mass is
	// a flat slab of sky-coloured paint — `haze_curve` > 1 holds the lower two thirds down and lets the
	// crown dissolve, which is the vertical gradient the key art's distance has.
	float d = distance(v_world, CAMERA_POSITION_WORLD);
	float h = clamp((v_world.y - base_m) / top_m, 0.0, 1.0);
	float t = mix(haze_floor, haze_top, pow(h, haze_curve));
	t = clamp(t * clamp(d / 1100.0, depth_lo, depth_hi), 0.0, 0.97);

	vec3 out_col = mix(col, sky_band * band_gain, t);
	// The sparkle and the sun-side edge rim are added AFTER the haze on purpose. Both are LIGHT seen
	// through air: the air adds to them, it does not replace them, so mixing them into the surface
	// first and then handing the surface to the haze erased every lit window past ~600 m — which is
	// the whole distance this layer exists at.
	out_col += window_col * window_gain * sp * (1.0 - roof) * (1.0 - t * 0.55);
	float graze = 1.0 - abs(dot(n, to_cam));
	float edge = pow(clamp(graze, 0.0, 1.0), edge_pow) * (1.0 - roof) * smoothstep(0.30, 0.85, side);
	out_col += rim * edge * edge_gain * (1.0 - t * 0.55);

	ALBEDO = out_col;
}
