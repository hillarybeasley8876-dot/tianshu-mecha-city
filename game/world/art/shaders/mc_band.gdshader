shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, unshaded;
// mc_band (city-art, review r3 §2): a flat emissive strip — the shopfront glow along L1 podiums and
// the parapet light lines on tower roofs. Both need a soft falloff across their short axis, otherwise
// a 1.5 m quad seen edge-on aliases into a dashed line at distance.

uniform vec3 tint : source_color = vec3(1.0, 0.624, 0.271);   // #FF9F45 street sodium
uniform float gain : hint_range(0.0, 8.0) = 2.1;
uniform float softness : hint_range(0.0, 0.5) = 0.22;         // falloff at the strip's long edges

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	// Bright in the middle of the strip, falling off toward both long edges.
	float across = min(v_uv.y, 1.0 - v_uv.y);
	float ends = min(v_uv.x, 1.0 - v_uv.x);
	float shape = smoothstep(0.0, softness, across) * smoothstep(0.0, 0.03, ends);
	ALBEDO = tint * gain * shape;
}
