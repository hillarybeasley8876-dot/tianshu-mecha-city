shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Expanding shockwave ring (feel unit). A single flat quad laid on the impact surface: the fragment
// draws a soft annulus at 0.85 of the quad radius and brightens at grazing angles, which reads as a
// fresnel shell without needing depth. `progress` is driven by shockwave_fx.gd from 0 to 1.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float thickness : hint_range(0.01, 0.5) = 0.1;
uniform vec4 ring_color : source_color = vec4(1.0, 0.54, 0.17, 1.0);
uniform float edge_gain : hint_range(0.0, 4.0) = 1.6;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float ring = 1.0 - smoothstep(0.0, thickness, abs(r - 0.86));
	// A short, weak core so the blast has a centre without turning a 30 m ring into a grey dome.
	float core = (1.0 - smoothstep(0.0, 0.55, r)) * (1.0 - smoothstep(0.0, 0.12, progress)) * 0.18;
	vec3 view_dir = normalize(-VERTEX);
	float grazing = 1.0 - abs(dot(normalize(NORMAL), view_dir));
	float fade = pow(1.0 - progress, 1.1);
	float a = (ring * 1.7 + core) * fade * (0.8 + edge_gain * grazing * 0.6);
	ALBEDO = ring_color.rgb * a;
	ALPHA = clamp(a * ring_color.a, 0.0, 1.0);
}
