shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;
// Flat shock ring on the ground (Shockcore's ground ring, the Plunge dust wave, the Undertow rim).
// The mesh is a unit PlaneMesh scaled to the radius, so the bright band always sits on the expanding
// leading edge and the interior only carries a faint wash.

instance uniform vec4 color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
instance uniform float strength : hint_range(0.0, 8.0) = 1.8;
instance uniform float thickness : hint_range(0.01, 1.0) = 0.14;
instance uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float edge = 1.0 - smoothstep(0.0, thickness, abs(r - 1.0));
	float inner = (1.0 - smoothstep(0.0, 1.0, r)) * 0.12;
	float a = (edge + inner) * strength * (1.0 - progress);
	ALBEDO = color.rgb * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
