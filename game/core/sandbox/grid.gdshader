shader_type spatial;
// Sandbox scale grid (core-owned): faint 2 m lines, strong 10 m lines, world-space so every box reads
// its size. Tint per instance via albedo.
uniform vec4 albedo : source_color = vec4(0.55, 0.57, 0.6, 1.0);
uniform vec4 line_color : source_color = vec4(0.12, 0.13, 0.15, 1.0);
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid(vec2 p, float step, float width) {
	vec2 g = abs(fract(p / step - 0.5) - 0.5) * step;
	vec2 fw = fwidth(p);
	vec2 l = 1.0 - smoothstep(vec2(width) - fw, vec2(width) + fw, g);
	return max(l.x, l.y);
}

void fragment() {
	vec3 n = abs(wnrm);
	vec2 p = n.y > 0.5 ? wpos.xz : (n.x > 0.5 ? wpos.zy : wpos.xy);
	float lines = max(grid(p, 2.0, 0.04) * 0.35, grid(p, 10.0, 0.12));
	ALBEDO = mix(albedo.rgb, line_color.rgb, lines);
	ROUGHNESS = 0.85;
}
