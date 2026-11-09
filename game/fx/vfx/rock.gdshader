shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Rubble chunk (feel unit). Procedural concrete/rock so the debris reads as broken city rather than
// the untextured grey boxes the r1 review rejected: 3-octave noise splits pale limestone from darker
// aggregate, the upward faces catch dust, and roughness varies so it is not uniformly matte.
// One material per pooled chunk, so `tint` can push a chunk toward concrete or scorched metal.

uniform vec4 tint : source_color = vec4(0.62, 0.6, 0.57, 1.0);
uniform vec4 grit_color : source_color = vec4(0.3, 0.28, 0.27, 1.0);
uniform float grain : hint_range(0.5, 12.0) = 3.5;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.82;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
global uniform float fx_opacity;

varying vec3 v_local;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i);
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 p = v_local * grain;
	float n = vnoise(p) * 0.6 + vnoise(p * 2.7) * 0.3 + vnoise(p * 6.1) * 0.1;
	// Aggregate: darker pebbles poking through the pale matrix.
	float grit = smoothstep(0.52, 0.72, n);
	vec3 col = mix(tint.rgb, grit_color.rgb, grit * 0.8);
	// Dust settles on the up-facing side; the broken faces stay darker.
	col = mix(col * 0.72, col, clamp(NORMAL.y * 0.5 + 0.6, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = clamp(roughness_base - grit * 0.25, 0.05, 1.0);
	SPECULAR = 0.25;
	ALPHA = fade * fx_opacity;
}
