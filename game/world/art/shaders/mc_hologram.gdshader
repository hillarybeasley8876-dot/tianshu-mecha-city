shader_type spatial;
render_mode blend_add, cull_disabled, depth_draw_never, unshaded, shadows_disabled, fog_disabled;
// mc_hologram (city-art): the Block 9 koi-dragon, the holo billboards and every projected sign.
// Additive cyan/magenta with scanlines, a fresnel rim, a slow vertical sweep and sparse glitch
// frames. `graphic` optionally multiplies a generated brand texture (billboards); the koi uses the
// mesh's own shape with graphic disabled.

uniform sampler2D graphic : source_color, hint_default_white, repeat_disable;
uniform float use_graphic : hint_range(0.0, 1.0) = 0.0;
uniform vec3 color_a : source_color = vec3(0.243, 0.902, 1.0);   // cyan  #3EE6FF
uniform vec3 color_b : source_color = vec3(1.0, 0.243, 0.647);   // magenta #FF3EA5
uniform float color_mix : hint_range(0.0, 1.0) = 0.25;
uniform float gain : hint_range(0.0, 12.0) = 2.2;
uniform float opacity : hint_range(0.0, 1.0) = 0.55;
uniform float scan_density = 90.0;      // lines per UV unit
uniform float scan_speed = 0.9;
uniform float scan_depth : hint_range(0.0, 1.0) = 0.45;
uniform float sweep_speed = 0.35;
uniform float sweep_width : hint_range(0.01, 0.6) = 0.12;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.4;
uniform float fresnel_gain : hint_range(0.0, 4.0) = 1.1;
uniform float flicker : hint_range(0.0, 1.0) = 0.12;
uniform float glitch : hint_range(0.0, 1.0) = 0.10;
uniform float project_range = 30.0;     // metres over which the beam fades from its projector

global uniform float mc_time;

varying vec3 v_local;
varying vec3 v_world;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract(p * (p + p));
}

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = mc_time;

	// Sparse glitch frames: a few times a second a band of the hologram shears and dims.
	float gframe = floor(t * 8.0);
	float gsel = step(1.0 - glitch, hash11(gframe));
	float band = step(1.0 - 0.18, hash11(gframe + floor(v_local.y * 3.0)));
	float g = gsel * band;

	float scan = 0.5 + 0.5 * sin((v_local.y * scan_density) - t * scan_speed * 6.2831853);
	scan = mix(1.0, scan, scan_depth);

	// A bright band travelling up the projection, the classic "refresh" read.
	float sweep = fract(t * sweep_speed - v_local.y * 0.02);
	float sweep_glow = pow(1.0 - clamp(sweep / sweep_width, 0.0, 1.0), 3.0);

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	float flick = 1.0 - flicker * hash11(floor(t * 24.0));

	vec3 tint = mix(color_a, color_b, clamp(color_mix + fres * 0.35, 0.0, 1.0));
	float body = mix(opacity, 1.0, fres * fresnel_gain) * scan * flick * (1.0 - g * 0.75);
	body += sweep_glow * 0.8;

	// city-art r14: the sweep was counted TWICE (once into `body`, once here), so a holo billboard
	// peaked at ~2.4 x gain on an ADDITIVE blend and every one of them clipped — 2.6 % of the A3st
	// street frame on a single sign.
	vec3 col = tint * gain * (body + sweep_glow * 0.15);
	if (use_graphic > 0.5) {
		vec4 g4 = texture(graphic, UV);
		col *= g4.rgb;
		col *= g4.a;
		body *= g4.a;
	}

	// Fade with distance from the projector so the beam reads as projected, not painted.
	float dist = length(v_local);
	col *= clamp(1.0 - dist / max(project_range, 0.01), 0.05, 1.0);

	// `unshaded` outputs ALBEDO, not EMISSION: with blend_add an EMISSION-only write adds black, which
	// is an invisible hologram (same bug as mc_up_accent).
	ALBEDO = col;
	EMISSION = vec3(0.0);
	ALPHA = clamp(body, 0.0, 1.0);
}
