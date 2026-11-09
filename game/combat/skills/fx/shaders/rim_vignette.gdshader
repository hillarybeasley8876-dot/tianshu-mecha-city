shader_type canvas_item;
// Gold rim vignette for the Zenith Overdrive and the Lance (the lead's note: gold, not the red
// damage edge). Drawn by the skills unit's own CanvasLayer so it never collides with the Feel
// Director's post stack.

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.32, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 0.5;
uniform float width : hint_range(0.05, 1.5) = 0.55;
uniform float pulse = 2.0;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * vec2(1.0, 0.62) * 2.0;
	float r = length(d);
	float edge = smoothstep(1.0 - width, 1.35, r);
	float beat = 0.85 + 0.15 * sin(TIME * pulse * 6.28318);
	COLOR = vec4(color.rgb, clamp(edge * strength * beat, 0.0, 1.0));
}
