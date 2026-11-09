shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, fog_disabled, diffuse_burley, specular_schlick_ggx;
// mc_road (city-art): carriageway with lane markings and crossings, drawn in the shader from METRE
// UVs (city-build's convention). `width_m` is the full carriageway; the shader assumes the road
// quad's V axis runs ALONG the street and U across it, which is how the corridor builder lays it out.
// Everything is procedural, so no decal geometry is needed for markings.
#include "mc_haze.gdshaderinc"
#include "mc_sun.gdshaderinc"
#include "mc_wet.gdshaderinc"

uniform vec3 asphalt : source_color = vec3(0.180, 0.180, 0.190);
uniform vec3 paint : source_color = vec3(0.78, 0.76, 0.70);
uniform float width_m = 56.0;
uniform float lane_m = 7.0;
uniform int lane_count : hint_range(0, 8) = 4;      // 0 = unmarked (alleys, docks)
uniform float edge_line_w = 0.45;
uniform float dash_len = 6.0;
uniform float dash_gap = 6.0;
uniform float crossing_every = 0.0;                 // metres; 0 = no crossings
uniform float crossing_w = 5.0;
uniform float crossing_band = 26.0;                  // crosswalk covers the carriageway
uniform float paint_wear : hint_range(0.0, 1.0) = 0.45;
uniform float wet : hint_range(0.0, 1.0) = 0.25;   // city-wide amount (McMaterials.set_wetness)
uniform float wet_bias : hint_range(0.0, 2.0) = 1.0;  // per-kind: alleys hold water, avenues drain
uniform float tile_m = 6.0;
uniform float seed = 0.0;

varying vec3 v_world;
varying vec3 v_nrm;

float hash21(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
			   mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float u = UV.x;                       // metres across the carriageway
	float v = UV.y;                       // metres along the street
	float half_w = width_m * 0.5;

	// Asphalt grain + patches.
	float grain = vnoise2(v_world.xz / tile_m * 3.0 + seed);
	float patch = vnoise2(v_world.xz / 34.0 + seed * 7.0);
	vec3 base = asphalt * (0.82 + 0.30 * grain) * (0.9 + 0.2 * patch);

	// Markings: edge lines plus dashed lane dividers, all symmetric about the centre.
	float mark = 0.0;
	if (lane_count > 0) {
		mark = max(mark, step(abs(abs(u) - (half_w - 1.2)), edge_line_w * 0.5));
		float dash = step(fract(v / max(dash_len + dash_gap, 0.01)) * (dash_len + dash_gap), dash_len);
		for (int i = 1; i < lane_count; i++) {
			float at = half_w - lane_m * float(i);
			if (at <= edge_line_w) { continue; }
			mark = max(mark, step(abs(abs(u) - at), edge_line_w * 0.4) * dash);
		}
		// Solid double centre line on avenues.
		if (lane_count >= 4) {
			mark = max(mark, step(abs(abs(u) - 0.55), 0.22));
		}
	}

	// Crossings: zebra bars across the full carriageway at a fixed spacing.
	if (crossing_every > 0.0) {
		float cycle = abs(fract(v / crossing_every) - 0.5) * crossing_every;
		float band = step(cycle, crossing_w * 0.5) * step(abs(u), min(crossing_band, half_w - 0.6));
		float bars = step(fract(u / 2.4), 0.55);
		mark = max(mark, band * bars);
	}

	// Tyre wear polishes the wheel tracks; paint wears away unevenly.
	float tracks = smoothstep(2.6, 0.0, abs(fract(u / max(lane_m, 0.01)) * lane_m - lane_m * 0.5));
	float wear = clamp(paint_wear * (0.4 + 0.6 * vnoise2(v_world.xz * 0.12)) + tracks * 0.25, 0.0, 1.0);
	float paint_a = mark * (1.0 - wear);

	vec3 albedo = mix(base, paint * (0.85 + 0.3 * grain), paint_a);

	// Puddles, not a uniform wet film. Water pools in the gutters and in the low patches of the
	// asphalt, so the neon and the windows reflect in SHAPES at street level (key art v2, and what
	// post-render's SSR A/B needs — lead 12:25). `wet` is the city-wide amount the storm drives.
	float pool = smoothstep(0.40, 0.74, vnoise2(v_world.xz * 0.055 + seed * 3.0));
	float gutter = smoothstep(half_w - 5.0, half_w - 1.0, abs(u));
	float wetness = clamp(wet * wet_bias * (0.30 + 1.05 * pool + 0.75 * gutter), 0.0, 1.0);
	albedo *= 1.0 - 0.45 * wetness;          // standing water darkens what is under it
	float rough = mix(0.86 - 0.18 * tracks, 0.62, paint_a) - wetness * 0.55;

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.06, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.35, 0.85, wetness);

	// r15 §4: the street mirrors the sky and the sun's path — the single strongest read in key art v2,
	// where the whole canyon lies down in the wet asphalt. Analytic (mc_wet.gdshaderinc), because SSR
	// is off at shipping quality.
	vec3 mirror = wet_reflection(v_world, normalize(v_nrm), CAMERA_POSITION_WORLD, wetness);

	// Layered aerial perspective (mc_haze): the ground plane runs to the map edge, so it has to haze
	// with everything standing on it.
	vec3 alb = ALBEDO;
	EMISSION = apply_haze(alb, mirror, layered_haze(v_world, CAMERA_POSITION_WORLD));
	ALBEDO = alb;
}
