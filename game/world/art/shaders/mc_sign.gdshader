shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, unshaded;
// mc_sign (city-art, review r3 §2): a vertical neon blade sign. The generated glyph strip
// (HoloGraphics — fictional brands only) reads as self-luminous signage on a near-black backing plate,
// with a thin lit edge around the plate so the blade has a silhouette even against a bright sky.
// `unshaded` writes ALBEDO (Godot 4.7), which is the whole output here — see review r2.

uniform sampler2D graphic : source_color, filter_linear, repeat_disable;
uniform vec3 tint : source_color = vec3(0.243, 0.902, 1.0);   // #3EE6FF
uniform vec3 plate : source_color = vec3(0.035, 0.038, 0.050);
uniform float gain : hint_range(0.0, 8.0) = 1.6;
uniform float edge_gain : hint_range(0.0, 8.0) = 0.7;
uniform float edge_m : hint_range(0.0, 0.5) = 0.06;           // border width, in UV

global uniform float mc_time;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec4 g = texture(graphic, v_uv);
	// A slow neon flutter: cheap, and it keeps the blades from reading as decals.
	float flutter = 0.88 + 0.12 * sin(mc_time * 2.3 + v_uv.y * 9.0);
	float edge = 1.0 - step(edge_m, min(min(v_uv.x, 1.0 - v_uv.x),
		min(v_uv.y, 1.0 - v_uv.y)));
	vec3 col = plate + tint * gain * g.a * flutter + tint * edge_gain * edge;
	ALBEDO = col;
}
