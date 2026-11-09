shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, fog_disabled, diffuse_burley, specular_schlick_ggx;
// mc_glass (city-art): dark, sky-reflecting curtain wall. Reflection comes from the sky ambient +
// SSR (high preset) + the arena reflection probes; the shader only has to make the panes differ
// from each other (roughness variation on the 4 m module) so a tower is not one mirror.
#include "mc_haze.gdshaderinc"

uniform vec3 glass_color : source_color = vec3(0.110, 0.149, 0.200);   // #1C2633
uniform vec3 sheen_color : source_color = vec3(0.749, 0.890, 1.0);
uniform float base_rough : hint_range(0.02, 0.6) = 0.11;
uniform float rough_variation : hint_range(0.0, 0.4) = 0.09;
uniform float metallic : hint_range(0.0, 1.0) = 0.82;
uniform float cell_size = 4.0;
uniform float fresnel_gain : hint_range(0.0, 4.0) = 0.9;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.18;
uniform float seed = 0.0;

varying vec3 v_world;

float hash21(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cid = floor(UV / cell_size) + vec2(seed) + floor(v_world.xz / 31.0);
	float r = hash21(cid);
	float rough = clamp(base_rough + (r - 0.5) * 2.0 * rough_variation, 0.02, 0.6);

	// Dirt film collects toward the bottom of each pane and in horizontal streaks.
	vec2 local = (UV / cell_size - floor(UV / cell_size)) * cell_size;
	float dirt = dirt_amount * (1.0 - smoothstep(0.0, cell_size * 0.5, local.y))
		* (0.4 + 0.6 * hash21(cid + 3.7));

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	vec3 albedo = mix(glass_color, glass_color * 1.6 + sheen_color * 0.05, fres);
	albedo = mix(albedo, vec3(0.32, 0.30, 0.27), dirt);

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough + dirt * 0.5, 0.02, 1.0);
	METALLIC = metallic * (1.0 - dirt * 0.7);
	SPECULAR = 0.9;
	EMISSION = sheen_color * fres * fresnel_gain * 0.12;

	// Far aerial perspective (mc_haze): a tower two kilometres out is mostly air.
	vec3 alb = ALBEDO;
	EMISSION = apply_haze(alb, EMISSION, layered_haze(v_world, CAMERA_POSITION_WORLD));
	ALBEDO = alb;
}
