shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Fireball (feel unit). One camera-facing quad of boiling noise, driven by fireball_fx.gd:
// `age` 0 -> 1 erodes the ball away, `heat` pushes the core to 6-8 HDR so it blooms hard through
// AgX (ART.md §3), `noise_scale` keeps the flame cells about a metre wide whatever the blast radius.
// The ramp is white-yellow core -> orange body -> sooty near-black rim, and the silhouette is chewed
// by a domain-warped fbm, which is what separates fire from the soft orange ball the r2 review
// rejected. Reference: Battlefield / Titanfall explosion sprites.
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.78, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.42, 0.09, 1.0);
uniform vec4 edge_color : source_color = vec4(0.45, 0.05, 0.01, 1.0);
uniform vec4 soot_color : source_color = vec4(0.05, 0.04, 0.04, 1.0);
uniform float age : hint_range(0.0, 1.0) = 0.0;
uniform float heat : hint_range(0.0, 24.0) = 8.0;
uniform float seed = 0.0;
uniform float spin = 0.0;
uniform float alpha_mul : hint_range(0.0, 1.0) = 1.0;
uniform float erosion : hint_range(0.0, 1.5) = 0.55;
// Noise cells across the quad; set from the blast radius so cells stay ~1 m at any size.
uniform float noise_scale = 7.0;
// Silhouette radius in quad units (the quad is overscanned so the eroded rim never shows a corner).
uniform float shell : hint_range(0.2, 1.2) = 0.86;
// Registered by VfxLibrary; the camera rig drops it to 0.6 in first person (FEEL.md header).
global uniform float fx_opacity;

varying vec2 v_uv;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * amp;
		p = p * 2.07 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	// Camera-facing quad: keep the instance position and size, take the axes from the camera.
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(INV_VIEW_MATRIX[0].xyz * sx, 0.0),
			vec4(INV_VIEW_MATRIX[1].xyz * sy, 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz * 1.0, 0.0),
			vec4(origin, 1.0));
	float c = cos(spin);
	float s = sin(spin);
	vec2 p = UV - vec2(0.5);
	v_uv = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void fragment() {
	float r = length(v_uv) * 2.0;

	// Domain-warped fbm: the flame domain rises with time and is displaced by itself, so the
	// silhouette boils and licks upwards instead of pulsing like a lamp.
	vec2 q = v_uv * noise_scale + vec2(seed * 7.31, seed * 3.77);
	float rise = TIME * 1.35 + age * 2.6;
	vec2 warp = vec2(fbm(q + vec2(0.0, -rise * 0.7)), fbm(q + vec2(5.2, 1.3) - rise * 0.45));
	float n = fbm(q + (warp - 0.5) * 2.4 + vec2(0.0, -rise));
	n = clamp((n - 0.5) * 2.3 + 0.5, 0.0, 1.0);

	// The noise chews the silhouette; erosion accelerates with age so the ball burns out from the
	// outside in. The disc never reaches the quad border, so a 28 m blast shows no square corners.
	float edge = clamp(shell + 0.20 * n - 0.10 - age * erosion * 1.9, 0.04, 1.0);
	float mask = smoothstep(edge, edge * 0.52, r);
	if (mask <= 0.003) {
		discard;
	}

	// 0 at the burning surface, 1 in the middle: drives the colour ramp and the core heat.
	float t = clamp(1.0 - r / max(edge, 0.001) + (n - 0.5) * 0.42, 0.0, 1.0);
	vec3 col = mix(edge_color.rgb, mid_color.rgb, smoothstep(0.0, 0.42, t));
	col = mix(col, core_color.rgb, smoothstep(0.5, 0.95, t));
	// Sooty rim: the outer shell darkens towards black as it cools, then reads as smoke.
	col = mix(col, soot_color.rgb, (1.0 - smoothstep(0.0, 0.3, t)) * (0.45 + 0.55 * age));
	// Flame cells: the same noise darkens the body, so the ball is not a uniform lamp.
	col *= 0.45 + 1.05 * n;

	// HDR core only: the rim stays near 1 so the ball blooms from the middle like real fire.
	float core = pow(clamp((t - 0.35) / 0.65, 0.0, 1.0), 2.0);
	ALBEDO = col * mix(1.15, heat * (1.0 - age * 0.75), core);
	ALPHA = clamp(mask * (1.0 - age * age * age) * alpha_mul * fx_opacity, 0.0, 1.0);
}
