shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_lambert, shadows_disabled;
// mc_cloth (city-art): Old Town banners, laundry and awnings. A hanging quad that swings and ripples
// in the vertex stage (no physics, no bones) and takes its colour from a per-instance tint, so one
// material dresses a whole terrace. `hang` is 0 at the top edge and 1 at the free edge.

uniform vec3 cloth_a : source_color = vec3(0.72, 0.16, 0.18);   // Old Town red
uniform vec3 cloth_b : source_color = vec3(0.92, 0.72, 0.36);   // gold trim
uniform float trim : hint_range(0.0, 0.5) = 0.09;
uniform float wind = 1.0;
uniform float wave_len = 3.2;
uniform float wave_speed = 2.4;
uniform float swing = 0.16;
uniform float seed = 0.0;

global uniform float mc_time;

varying vec2 v_uv;
varying float v_hang;
varying vec3 v_tint;

void vertex() {
	v_uv = UV;
	v_hang = 1.0 - UV.y;
	// MultiMesh custom data carries (seed, tint index, spare) so one mesh dresses a whole terrace.
	v_tint = vec3(seed + INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.z);
	float t = mc_time * wave_speed + v_tint.x * 12.0;
	float phase = VERTEX.x * 6.2831853 / max(wave_len, 0.01) + t;
	// The free edge moves most; the hung edge barely moves at all.
	VERTEX.z += sin(phase) * wind * v_hang * v_hang * 0.55;
	VERTEX.x += sin(phase * 0.5 + 1.7) * swing * v_hang;
	NORMAL = normalize(vec3(-cos(phase) * wind * v_hang * 0.4, 0.0, 1.0));
}

void fragment() {
	float edge = step(v_uv.y, trim) + step(1.0 - trim, v_uv.y);
	float stripe = step(0.5, fract(v_uv.y * 6.0 + v_tint.x));
	vec3 base = mix(cloth_a, cloth_b, v_tint.y);
	ALBEDO = mix(base, cloth_b, clamp(edge + stripe * 0.35, 0.0, 1.0));
	ROUGHNESS = 0.86;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.35);
}
