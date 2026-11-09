shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, fog_disabled, diffuse_lambert;
// mc_foliage (city-art, look review 2026-11-02 item 3) — the planting on the arena cover walls.
// A planter trough needs a leaf mass that still reads GREEN inside a golden-hour frame: a fully lit
// PBR shrub under a #ff9d66 sun goes brown. So the top of the mass takes a cool sky term of its own
// and the shade keeps the leaf colour rather than the sun's. COLOR.r is the per-instance hue jitter,
// so 200 bushes are not one bush.

uniform vec3 leaf_a : source_color = vec3(0.24, 0.42, 0.23);
uniform vec3 leaf_b : source_color = vec3(0.37, 0.55, 0.29);
uniform float sky_fill = 0.55;        // how much of the sky's own colour the mass picks up
uniform float clumping = 3.4;         // leaf-blob frequency, per metre

varying vec3 v_local;
varying vec3 v_world;
varying float v_hue;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash21(i.xy + i.z * 37.0);
	float n100 = hash21(i.xy + vec2(1.0, 0.0) + i.z * 37.0);
	float n010 = hash21(i.xy + vec2(0.0, 1.0) + i.z * 37.0);
	float n110 = hash21(i.xy + vec2(1.0, 1.0) + i.z * 37.0);
	float n001 = hash21(i.xy + (i.z + 1.0) * 37.0);
	float n101 = hash21(i.xy + vec2(1.0, 0.0) + (i.z + 1.0) * 37.0);
	float n011 = hash21(i.xy + vec2(0.0, 1.0) + (i.z + 1.0) * 37.0);
	float n111 = hash21(i.xy + vec2(1.0, 1.0) + (i.z + 1.0) * 37.0);
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	v_local = VERTEX * vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_hue = COLOR.r;
}

void fragment() {
	// Leaf blobs: the mass is a box, and the noise both breaks its value and pushes the normal around
	// so the silhouette edge is not a straight line.
	float n = vnoise(v_local * clumping + v_hue * 41.0);
	float n2 = vnoise(v_local * clumping * 2.7 + 13.0);
	vec3 leaf = mix(leaf_a, leaf_b, clamp(n * 0.7 + v_hue * 0.5, 0.0, 1.0));
	leaf *= 0.72 + 0.5 * n2;

	vec3 nrm = normalize(NORMAL + vec3(n2 - 0.5, 0.0, n - 0.5) * 0.85);
	NORMAL = nrm;

	ALBEDO = leaf;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	// The cool fill from above: what keeps a shrub green under an orange key.
	BACKLIGHT = vec3(0.0);
	EMISSION = leaf * sky_fill * clamp(nrm.y * 0.5 + 0.5, 0.0, 1.0) * 0.22;
}
