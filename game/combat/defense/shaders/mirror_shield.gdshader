shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

// Mirror Guard's energy surface (镜返盾) — the block panel and the catch dome share this one shader.
// r7: the panel used to be a flat, uniformly bright hexagon, which read as a mint-green tile pasted
// over the hero. What makes it read as ENERGY instead:
//
//   * the interior is nearly empty (`core_alpha`), so the mech and the thing it is blocking stay
//     visible straight through it — `blend_add` never occludes, ALPHA is the contribution;
//   * the brightness lives on the RIM, from two terms that agree with each other: the fresnel of the
//     curved cap and a radial band at the silhouette, so the hard outline of the old plate became a
//     soft glowing edge and the panel still reads when it is viewed dead-on;
//   * a hex cell pattern marks the surface as a constructed field rather than a painted decal, kept
//     faint enough that it never becomes the read;
//   * `ripple` is a ring travelling out of the point that was hit, and `flash` is the perfect parry.
//
// Every number here is pushed in from `MirrorShieldProfile` (GDScript), which is the single source of
// truth and the thing the headless tests measure. The defaults below only matter if a material is
// built by hand.

uniform vec4 core_color : source_color = vec4(0.30, 0.90, 1.00, 1.0);
uniform vec4 rim_color : source_color = vec4(0.72, 0.98, 1.00, 1.0);
uniform float core_alpha : hint_range(0.0, 1.0) = 0.12;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.95;
uniform float rim_power : hint_range(0.5, 8.0) = 2.4;
uniform float edge_soft : hint_range(0.01, 0.6) = 0.22;
uniform float hex_gain : hint_range(0.0, 1.0) = 0.30;
uniform float hex_scale = 7.0;
uniform float hex_spin = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float flash : hint_range(0.0, 4.0) = 0.0;
uniform vec3 ripple = vec3(0.0, 0.0, 0.0);
uniform float ripple_width : hint_range(0.01, 1.0) = 0.18;
uniform float ripple_gain : hint_range(0.0, 4.0) = 1.6;

// Distance to the nearest hex cell wall, 0 in the middle of a cell and 1 on the wall.
float hex_wall(vec2 p) {
	vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	float d = max(abs(g.x) * 0.8660254 + abs(g.y) * 0.5, abs(g.y));
	return smoothstep(0.34, 0.5, d);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float fres = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), rim_power);
	float edge = smoothstep(1.0 - edge_soft, 1.0, r);
	float rim = clamp(max(fres, edge), 0.0, 1.0);

	float spin = hex_spin;
	float ca = cos(spin);
	float sa = sin(spin);
	vec2 hp = mat2(vec2(ca, -sa), vec2(sa, ca)) * uv * hex_scale;
	float cells = hex_wall(hp);

	// Interior: a flat wash plus the cell walls. Bounded by core_alpha * (1.0 + hex_gain), which is
	// the number MirrorShieldProfile.center_alpha() reports and the test pins under 0.25.
	float body = core_alpha * (1.0 + hex_gain * cells);
	float a = mix(body, rim_alpha, rim);

	if (ripple.z > 0.0) {
		float d = length(uv - ripple.xy);
		float front = ripple.z * 1.6;
		a += (1.0 - smoothstep(0.0, ripple_width, abs(d - front))) * (1.0 - ripple.z) * ripple_gain;
	}

	a *= fade;
	a += flash * fade * (0.35 + 0.65 * rim);
	ALBEDO = mix(core_color.rgb, rim_color.rgb, rim) * (1.0 + flash * 1.5);
	ALPHA = clamp(a, 0.0, 1.0);
}
