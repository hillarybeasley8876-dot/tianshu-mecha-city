shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, fog_disabled, diffuse_burley, specular_schlick_ggx;
// mc_window (city-art): randomised lit window cells for tower facades.
// city-build writes METRE UVs on a 4 m floor module; a window band is a 3.2 m x 2.6 m quad on a
// floor line (multiples of 4 m), so the cell index is floor(UV / 4) and no per-quad UV is needed.
// `mc_lit_fraction` is a global uniform owned by TimeOfDay (0.40 at the start -> 0.75 at the boss).
#include "mc_haze.gdshaderinc"
#include "mc_sun.gdshaderinc"

global uniform float mc_lit_fraction;
global uniform float mc_time;

uniform vec3 warm : source_color = vec3(1.0, 0.812, 0.541);   // #FFCF8A
uniform vec3 cool : source_color = vec3(0.749, 0.890, 1.0);   // #BFE3FF
uniform vec3 dark_glass : source_color = vec3(0.110, 0.149, 0.200);
uniform vec3 frame_col : source_color = vec3(0.075, 0.085, 0.100);
uniform float cell_size = 4.0;
uniform float win_w = 3.2;
uniform float win_h = 2.6;
uniform float cool_chance : hint_range(0.0, 1.0) = 0.16;
uniform float flicker_rate : hint_range(0.0, 0.2) = 0.012;
uniform float interior_depth : hint_range(0.0, 1.0) = 0.65;
uniform float emission_gain : hint_range(0.0, 16.0) = 5.0;
uniform float win_seed = 0.0;
uniform float glass_rough : hint_range(0.02, 1.0) = 0.16;

varying vec3 v_world;
varying vec3 v_nrm;

float hash21(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 cs = vec2(cell_size);
	vec2 cid = floor(UV / cs);
	vec2 local = (UV / cs - cid) * cs;   // 0..4 m in both axes, origin = cell corner
	// Per-building offset so one merged tile does not light up in a single repeating pattern.
	vec2 seed = vec2(win_seed) + floor(v_world.xz / 31.0) + vec2(0.0, floor(v_world.y / 24.0) * 5.0);

	float r_lit = hash21(cid + seed);
	float r_tone = hash21(cid + seed + 17.3);
	float r_cool = hash21(cid + seed + 41.7);
	float r_flick = hash21(cid + seed + 73.1);

	float lit = step(r_lit, mc_lit_fraction);
	// Rare, slow flicker (failing ballast): a small minority of cells breathe.
	float flick_phase = floor(mc_time * 3.0 + r_flick * 40.0);
	float flicker = 1.0 - step(1.0 - flicker_rate, r_flick) * 0.55
		* (0.5 + 0.5 * sin(flick_phase * 12.7 + r_flick * 30.0));

	// Window pane mask inside the cell, with a mullion at mid-width and a transom near the head.
	float pane = step(0.06, local.x) * step(local.x, win_w - 0.06)
		* step(0.08, local.y) * step(local.y, win_h - 0.08);
	float mullion = step(abs(local.x - win_w * 0.5), 0.045) + step(abs(local.y - win_h * 0.74), 0.035);
	pane *= 1.0 - clamp(mullion, 0.0, 1.0);

	// Fake interior depth: vertical falloff plus a couple of furniture silhouettes.
	float depth = mix(1.0, 0.35 + 0.65 * smoothstep(win_h, 0.0, local.y), interior_depth);
	depth *= 1.0 - interior_depth * 0.35 * step(0.55, hash21(floor(vec2(local.x, local.y) * 1.7) + cid));
	float room_gain = mix(0.30, 1.0, r_tone);

	// Lead (boss r2, r4): once a cell is a few pixels across, the tower turns to static and reads as a
	// coarse checkerboard — which is exactly what the 300-900 m towers were doing. The dissolve is keyed
	// on CAMERA DISTANCE, not on `fwidth(UV)`: these quads do not all carry city-build's metre UVs, and
	// where the UV is per-quad the derivative is tiny at any distance, so the fade never fired and the
	// lit cells stayed at full contrast as 4-10 px blobs. Every per-cell term collapses to its own mean.
	// Boss r2 wants it gone by ~400 m (the city under the Crown), hence the tighter range than r4's.
	float fade = smoothstep(210.0, 560.0, distance(v_world, CAMERA_POSITION_WORLD));
	float coverage = (win_w * win_h) / (cell_size * cell_size);
	// Per-BUILDING variation survives the dissolve, so the far towers stay a field of separate values.
	float b_var = hash21(floor(v_world.xz / 29.0) + vec2(win_seed));
	pane = mix(pane, coverage, fade);
	lit = mix(lit, mc_lit_fraction * mix(0.55, 1.30, b_var), fade);
	depth = mix(depth, 0.68, fade);
	room_gain = mix(room_gain, mix(0.55, 0.88, hash21(floor(v_world.xz / 29.0) + vec2(win_seed) + 3.1)), fade);

	vec3 lamp = mix(warm, cool, step(1.0 - cool_chance, r_cool));
	// r14 §2: a wall the low sun is on is a hundred times brighter than the lamp behind its glass, so
	// the lit cells there have to all but vanish; the shaded faces are where the city's lights read.
	vec3 emis = lamp * emission_gain * room_gain * lit * pane * depth * flicker
		* sun_face_dim(v_nrm);

	float is_frame = 1.0 - step(0.5, pane);
	ALBEDO = mix(dark_glass, frame_col, is_frame);
	ROUGHNESS = mix(glass_rough, 0.62, is_frame);
	METALLIC = mix(0.65, 0.15, is_frame);
	SPECULAR = mix(0.85, 0.25, is_frame);
	EMISSION = emis;

	// Far aerial perspective (mc_haze): the lit cells of a distant tower dim into the cool band.
	vec3 alb = ALBEDO;
	EMISSION = apply_haze(alb, EMISSION, layered_haze(v_world, CAMERA_POSITION_WORLD));
	ALBEDO = alb;
}
