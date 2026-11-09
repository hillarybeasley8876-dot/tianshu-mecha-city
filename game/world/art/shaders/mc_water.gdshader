shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, fog_disabled, diffuse_burley, specular_schlick_ggx;
// mc_water (city-art): the canal and the reflecting pools. Sky and city reflection comes from SSR
// (high preset) and the arena probes; this shader adds slow directional swell, a fine chop normal, and
// shoreline foam derived from the scene depth behind the surface, so foam follows the real banks and
// the pier legs.
// The surface is OPAQUE on purpose: a blended surface is drawn in the transparent pass, where SSR does
// not run, and the pier shot then has a flat navy canal instead of a city reflected in the water
// (review r2 §4). Depth is read from the depth buffer instead, which the foam already does.
#include "mc_haze.gdshaderinc"

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform vec3 deep_color : source_color = vec3(0.180, 0.353, 0.431);   // #2E5A6E
uniform vec3 shallow_color : source_color = vec3(0.35, 0.52, 0.55);
uniform vec3 foam_color : source_color = vec3(0.86, 0.88, 0.88);
uniform float wave_height = 0.28;
uniform float wave_len = 26.0;
uniform float wave_speed = 0.55;
uniform float chop_scale = 0.9;
uniform float chop_speed = 1.4;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float foam_width = 2.2;          // metres of shoreline foam
uniform float foam_noise = 0.55;
uniform float roughness_base : hint_range(0.01, 0.5) = 0.06;
uniform float metallic : hint_range(0.0, 1.0) = 0.25;

global uniform float mc_time;

varying vec3 v_world;

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

// Height field: one long swell train plus two crossing chops.
float wave_h(vec2 p, float t) {
	float h = sin(dot(p, vec2(0.92, 0.38)) * 6.2831853 / wave_len - t * wave_speed) * wave_height;
	h += sin(dot(p, vec2(-0.42, 0.91)) * 6.2831853 / (wave_len * 0.45) + t * wave_speed * 1.7) * wave_height * 0.45;
	h += (vnoise2(p * chop_scale * 0.35 + vec2(t * chop_speed * 0.2, 0.0)) - 0.5) * wave_height * 0.8;
	return h;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float e = 0.6;
	float h = wave_h(p, mc_time);
	float hx = wave_h(p + vec2(e, 0.0), mc_time);
	float hz = wave_h(p + vec2(0.0, e), mc_time);
	vec3 n = normalize(vec3(-(hx - h) / e, 1.0, -(hz - h) / e));
	NORMAL = normalize(mix(vec3(0.0, 1.0, 0.0), n, normal_strength));

	// Shoreline: compare this fragment's view depth with what the depth buffer holds behind it.
	float raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	view_pos.xyz /= view_pos.w;
	float water_col = max(-view_pos.z - (-VERTEX.z), 0.0);
	float shore = 1.0 - smoothstep(0.0, foam_width, water_col);
	float foam = shore * (0.55 + foam_noise * vnoise2(p * 1.6 + vec2(mc_time * 0.5, 0.0)));
	foam += smoothstep(0.75, 1.0, vnoise2(p * 0.7 - vec2(0.0, mc_time * 0.3))) * 0.06;

	float shallow = 1.0 - smoothstep(0.0, foam_width * 2.5, water_col);
	vec3 albedo = mix(deep_color, shallow_color, shallow * 0.7);
	albedo = mix(albedo, foam_color, clamp(foam, 0.0, 1.0));

	ALBEDO = albedo;
	// Smoother where the water is deep and still, rougher over the chop and the foam.
	ROUGHNESS = clamp(roughness_base + foam * 0.5 + shallow * 0.05, 0.01, 1.0);
	METALLIC = metallic * (1.0 - foam);
	SPECULAR = 0.95;

	vec3 alb = ALBEDO;
	EMISSION = apply_haze(alb, vec3(0.0), layered_haze(v_world, CAMERA_POSITION_WORLD));
	ALBEDO = alb;
}
