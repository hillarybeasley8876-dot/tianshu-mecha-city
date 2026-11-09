shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;
// The Rift Step decoy: a hologram of the mech left standing where the blink started, so Rippers keep
// biting at empty air. Scanlines + a vertical sweep + a hard fresnel edge read as "projected light"
// rather than "a copy of the mech".

instance uniform vec4 tint : source_color = vec4(0.45, 0.85, 1.0, 1.0);
instance uniform float strength : hint_range(0.0, 6.0) = 1.4;
uniform float lines = 46.0;       // scanline density across the model's height
uniform float sweep_speed = 0.7;
uniform float flicker : hint_range(0.0, 1.0) = 0.18;
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;   // driven down over the decoy's life

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;   // model space, so the scanlines stick to the silhouette while it stands
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float fres = pow(clamp(1.0 - abs(dot(n, v)), 0.0, 1.0), 1.6);
	float scan = 0.55 + 0.45 * sin((local_pos.y * lines + TIME * 6.0));
	float sweep = smoothstep(0.86, 1.0, sin(local_pos.y * 0.35 - TIME * sweep_speed * 6.28318));
	float noise = fract(sin(TIME * 43.0 + local_pos.x * 12.9) * 43758.5453);
	float a = (0.22 + fres * 0.9) * scan * strength * fade;
	a *= 1.0 - flicker * noise;
	a += sweep * 0.5 * fade;
	ALBEDO = tint.rgb * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
