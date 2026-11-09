shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;
// Skills' signature shell: the cyan-white fresnel sphere the Shockcore Burst snaps out to 32 m, the
// refraction ripple at both ends of a Rift Step and the plasma sheath of a Plunge dive.
// `progress` is driven per instance by the owning script (0 = just fired, 1 = end of life).

instance uniform vec4 core_color : source_color = vec4(0.55, 0.92, 1.0, 1.0);
instance uniform vec4 rim_color : source_color = vec4(0.9, 1.0, 1.0, 1.0);
instance uniform float strength : hint_range(0.0, 8.0) = 1.6;
instance uniform float power : hint_range(0.5, 8.0) = 2.6;
uniform float bands = 5.0;        // interference rings travelling up the shell
uniform float band_depth : hint_range(0.0, 1.0) = 0.35;
uniform float scroll = 1.2;
instance uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float fres = pow(clamp(1.0 - abs(dot(n, v)), 0.0, 1.0), power);
	// thin leading edge: the shell is a travelling front, not a growing ball of light
	float front = 1.0 - smoothstep(0.0, 1.0, progress);
	float rim = smoothstep(0.2, 1.0, fres);
	float band = mix(1.0, 0.5 + 0.5 * sin((UV.y * bands - TIME * scroll) * 6.28318), band_depth);
	float a = clamp(rim * band * strength * front, 0.0, 3.0);
	vec3 c = mix(core_color.rgb, rim_color.rgb, rim);
	ALBEDO = c * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
