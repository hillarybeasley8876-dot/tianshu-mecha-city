shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;

// Soft lit puff (feel unit): smoke columns, dust rings, steam. A camera-facing quad with a soft
// radial alpha, a cheap sun term so puffs read as volume rather than grey stickers, and a little
// noise breakup at the rim. Lit by shading (not unshaded) so the world's sun colour lands on it.

uniform vec4 puff_color : source_color = vec4(0.24, 0.24, 0.27, 0.55);
uniform vec4 rim_color : source_color = vec4(0.62, 0.6, 0.58, 0.0);
uniform float softness : hint_range(0.05, 1.0) = 0.55;
uniform float breakup : hint_range(0.0, 1.0) = 0.45;
uniform float alpha_mul : hint_range(0.0, 1.0) = 1.0;
// Direction the cheap sun term comes from, in view space (set once, world sun is static per scene).
uniform vec3 sun_dir = vec3(0.4, 0.7, -0.6);
uniform vec4 sun_color : source_color = vec4(1.0, 0.83, 0.63, 1.0);
uniform float sun_gain : hint_range(0.0, 2.0) = 0.5;
global uniform float fx_opacity;

varying vec2 v_uv;
varying float v_seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	// Per-particle yaw so a column of puffs does not read as one repeating sprite.
	float a = hash(vec2(origin.x, origin.z)) * 6.2831853;
	float c = cos(a);
	float s = sin(a);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(INV_VIEW_MATRIX[0].xyz * sx, 0.0),
			vec4(INV_VIEW_MATRIX[1].xyz * sy, 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz, 0.0),
			vec4(origin, 1.0));
	vec2 p = UV - vec2(0.5);
	v_uv = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	v_seed = hash(vec2(origin.y, origin.x + origin.z));
}

void fragment() {
	vec2 uv = v_uv;
	float r = length(uv) * 2.0;
	float n = vnoise(uv * 4.0 + vec2(v_seed * 31.0, v_seed * 17.0));
	float edge = 1.0 - breakup * (n - 0.5);
	float mask = smoothstep(edge, edge - softness, r);
	if (mask <= 0.003) {
		discard;
	}
	// Cheap lighting: the top-left of the puff catches the sun, the bottom sinks into shadow.
	float lit = clamp(0.5 + dot(normalize(vec3(uv, 1.0)), normalize(sun_dir)) * 0.9, 0.0, 1.0);
	vec3 col = mix(puff_color.rgb * 0.55, mix(puff_color.rgb, sun_color.rgb, sun_gain), lit);
	col = mix(col, rim_color.rgb, smoothstep(0.55, 1.0, r) * rim_color.a);
	ALBEDO = col;
	ALPHA = clamp(mask * COLOR.a * puff_color.a * alpha_mul * fx_opacity, 0.0, 1.0);
}
