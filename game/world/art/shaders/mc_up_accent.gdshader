shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, unshaded;
// mc_up_accent (city-art): the reserved cyan-white "up" connector language (ART.md §2) — lift rails,
// catapult rings, vent mouths, anchor nodes. A slow bright pulse travels along the strip in metres;
// the pulse direction is chosen by `axis` so a horizontal ring and a vertical lift both read upward.

uniform vec3 accent : source_color = vec3(0.243, 0.902, 1.0);   // #3EE6FF
uniform vec3 core : source_color = vec3(0.86, 0.99, 1.0);
// r16b §4: the peak of this strip is `gain * (steady + pulse_gain + 0.18 + fresnel_gain)`, it is
// written as an unshaded ALBEDO, and the clip gate (a pixel at 248/255 through AgX at the shipping
// exposure) sits at about 1.66 LINEAR — measured, not guessed: the clip share falls 11.95 % -> 5.23 %
// on A3st when the peak comes 6.35 -> 3.71, which is 2.55 points per linear unit and puts the gate at
// 1.66. At `--tod=1.0` the "up" language was 11.6 of A3st's 11.95 clipped per cent, 6.0 of V7's 7.75
// and 3.1 of V8's 6.49 (measured by hiding every `up_accent` node). The three terms are now budgeted
// against that number: the base (steady + rhythm) reads 0.73, the travelling pulse peaks at 1.63 and
// the grazing fresnel at 1.08, so a strip is bright and cyan-white and never over the gate.
uniform float gain : hint_range(0.0, 24.0) = 1.0;
uniform float pulse_speed = 6.0;         // metres per second along the strip
uniform float pulse_width : hint_range(0.5, 40.0) = 8.0;
uniform float pulse_gain : hint_range(0.0, 6.0) = 0.9;   // r16b: 1.6 put the pulse band over the clip gate
uniform float band_m = 2.0;              // metres between repeating pulse slots
uniform int axis : hint_range(0, 2) = 1; // 0 = X, 1 = Y (up), 2 = Z
uniform float steady : hint_range(0.0, 1.0) = 0.55;
uniform float fresnel_gain : hint_range(0.0, 4.0) = 0.35;  // r16b: 1.2 blew out every grazing rail

global uniform float mc_time;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float axis_pos = axis == 0 ? v_world.x : (axis == 2 ? v_world.z : v_world.y);
	float travel = fract((axis_pos - mc_time * pulse_speed) / max(pulse_width, 0.01));
	float pulse = pow(1.0 - travel, 6.0);

	// A soft repeating rhythm so long rails never look like one lone travelling dot.
	float rhythm = 0.5 + 0.5 * sin(axis_pos * 6.2831853 / max(band_m, 0.01) - mc_time * 1.7);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);

	float level = steady + pulse_gain * pulse + 0.18 * rhythm + fresnel_gain * fres;
	vec3 col = mix(accent, core, clamp(pulse * 0.9 + fres * 0.4, 0.0, 1.0)) * gain * level;
	// `unshaded` outputs ALBEDO, not EMISSION: writing the glow to EMISSION alone renders the strip
	// BLACK (found against the Spire tether capture). The value stays above the glow threshold, so it
	// still blooms.
	ALBEDO = col;
	EMISSION = vec3(0.0);
	ALPHA = 1.0;
}
