shader_type spatial;
render_mode diffuse_burley, specular_disabled;

// 1 m minor / 10 m major grid on a neutral grey floor, so contact, sliding and scale read.
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 g1 = abs(fract(p - 0.5) - 0.5) / max(fwidth(p), vec2(1e-4));
	float l1 = 1.0 - clamp(min(g1.x, g1.y), 0.0, 1.0);
	vec2 p10 = p / 10.0;
	vec2 g10 = abs(fract(p10 - 0.5) - 0.5) / max(fwidth(p10), vec2(1e-4));
	float l10 = 1.0 - clamp(min(g10.x, g10.y) * 0.5, 0.0, 1.0);
	vec3 base = vec3(0.26);
	base = mix(base, vec3(0.19), l1 * 0.5);
	base = mix(base, vec3(0.10), l10);
	ALBEDO = base;
	ROUGHNESS = 0.92;
}
