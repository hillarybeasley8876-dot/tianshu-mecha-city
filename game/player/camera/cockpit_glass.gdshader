shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, specular_schlick_ggx;
// Canopy glass (camera-aim): a fresnel edge reflection plus faint dust specks, so the canopy reads as
// glass without hiding the world. SPEC §5 / lead review r1: the layer never goes over alpha 0.08 —
// the pilot must be able to see through it, it is a hint, not a tint.

uniform vec4 tint : source_color = vec4(0.31, 0.9, 1.0, 1.0);
uniform float max_alpha : hint_range(0.0, 0.2) = 0.08;
uniform float fresnel_power : hint_range(1.0, 8.0) = 3.2;
uniform float edge_gain : hint_range(0.0, 2.0) = 0.85;
uniform float dust : hint_range(0.0, 1.0) = 0.35;
uniform float dust_scale = 620.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);
	// Two decorrelated speck fields: fine dust plus a slow, very faint smear.
	vec2 cell = floor(UV * dust_scale);
	float speck = smoothstep(0.976, 1.0, hash21(cell));
	float smear = hash21(floor(UV * 5.0)) * 0.18;
	float dirt = (speck + smear) * dust;
	ALBEDO = tint.rgb;
	ALPHA = clamp(fresnel * edge_gain + dirt, 0.0, 1.0) * max_alpha;
	EMISSION = tint.rgb * fresnel * 0.35;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.9;
}
