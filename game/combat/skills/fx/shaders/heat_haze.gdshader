shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;
// Heat distortion in the air around the Zenith Lance and along the Plunge dive column: the mesh is a
// transparent volume that re-reads the screen behind it with a scrolling sine warp. Drawn late
// (render_priority) so the scene behind it is already resolved.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.35;
uniform float scale = 8.0;
uniform float speed = 1.6;

void fragment() {
	vec2 uv = SCREEN_UV;
	float w1 = sin(uv.y * scale * 34.0 + TIME * speed * 6.0);
	float w2 = sin(uv.x * scale * 26.0 - TIME * speed * 4.2);
	vec2 off = vec2(w1, w2) * strength * 0.012;
	ALBEDO = texture(screen_tex, uv + off).rgb;
	// the mesh is a box stretched along the beam, so every fragment is on its surface: fade by view
	// angle (face-on distorts most) instead of by a local radius that is constant on the side faces
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALPHA = strength * (0.25 + 0.75 * face);
}
