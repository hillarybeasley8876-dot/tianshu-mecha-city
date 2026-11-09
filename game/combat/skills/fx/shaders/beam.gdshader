shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;
// The skills' beam: a glowing tube between two points. One shader serves the Corona Fin beams
// (0.6 m core inside a 2.5 m glow) and the three Zenith Lance layers (2.4 white / 8 gold / 16 red),
// which differ only in width, colour and how solid their middle is.
//
// The mesh is a unit CYLINDER (radius 0.5, height 1) laid along its local +Y, so every fragment sits
// ON the tube surface — a radial falloff taken from the local position is constant (and therefore
// invisible) on exactly the side faces the camera sees. The falloff comes from the view angle
// instead: the silhouette edges burn, the middle carries `solid`. `local_pos.y` is the beam axis, so
// that is what the energy flows along.

instance uniform vec4 color : source_color = vec4(0.6, 0.95, 1.0, 1.0);
instance uniform float strength : hint_range(0.0, 8.0) = 1.5;
instance uniform float solid : hint_range(0.0, 1.0) = 0.25;  // how lit the tube's middle is
// Fraction of the tube the beam stays bright over (1.0 = no fade, the default for short beams). The
// Zenith Lance needs it: seen almost end-on from the gameplay camera, every fragment of an 800 m tube
// has its normal perpendicular to the view, so the rim term is ~1 along the WHOLE length and the beam
// fills a sixth of the screen with a flat wedge however round the geometry is. Fading the far end —
// furthest on the widest layer, shortest on the white core — is what leaves concentric rings at the
// muzzle and a bright line to the horizon (r4 item 3).
instance uniform float reach : hint_range(0.0, 1.0) = 1.0;
uniform float scroll = 2.0;                                   // energy flowing along the beam

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float rim = pow(clamp(1.0 - abs(dot(n, v)), 0.0, 1.0), 2.2);
	float body = mix(solid, 1.0, rim);
	float flow = 0.78 + 0.22 * sin(local_pos.y * 26.0 + TIME * scroll * 6.28318);
	float t = clamp(local_pos.y + 0.5, 0.0, 1.0);   // 0 at the muzzle end, 1 at the far end
	float fade = reach >= 0.999 ? 1.0 : (1.0 - smoothstep(reach * 0.3, reach, t));
	float a = body * strength * flow * fade;
	ALBEDO = mix(color.rgb, vec3(1.0), rim * 0.6) * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
