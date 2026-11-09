shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Contact flash (feel unit): the tiny white-hot billboard that sits on an impact point for two or
// three frames, and - with `star` raised - the 3-frame camera-facing cross flare that gives heavy
// melee hits their anime-mech flavour. Additive and HDR, so it blooms through AgX (ART.md §3).
// Driven by fx/vfx/flash_pop.gd: `progress` 0 -> 1 over the pop's life.

uniform vec4 pop_color : source_color = vec4(1.0, 0.96, 0.85, 1.0);
uniform float heat : hint_range(0.0, 16.0) = 4.0;
// 0 = round pop, 1 = four-point cross flare.
uniform float star : hint_range(0.0, 1.0) = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float min_pixels = 4.0;
// Registered by VfxLibrary; the camera rig drops it to 0.6 in first person (FEEL.md header).
global uniform float fx_opacity;
// World metres per pixel per metre of depth; VfxLibrary refreshes it from the active camera.
global uniform float fx_pixel_scale;

varying vec2 v_uv;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	// A pop a hundred metres away must still cover a few pixels, or the hit reads as nothing.
	float px = distance(INV_VIEW_MATRIX[3].xyz, origin) * fx_pixel_scale;
	s = max(s, min_pixels * px);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(INV_VIEW_MATRIX[0].xyz * s, 0.0),
			vec4(INV_VIEW_MATRIX[1].xyz * s, 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz, 0.0),
			vec4(origin, 1.0));
	v_uv = (UV - vec2(0.5)) * 2.0;
}

void fragment() {
	float r = length(v_uv);
	if (r > 1.0) {
		discard;
	}
	// Round core: a tight hot centre with a soft halo.
	float core = pow(max(1.0 - r, 0.0), 2.6) + pow(max(1.0 - r, 0.0), 12.0) * 1.4;
	// Cross flare: two thin spikes, tapering away from the centre.
	float sx = pow(max(1.0 - abs(v_uv.x), 0.0), 1.6) * pow(max(1.0 - abs(v_uv.y) * 9.0, 0.0), 2.0);
	float sy = pow(max(1.0 - abs(v_uv.y), 0.0), 1.6) * pow(max(1.0 - abs(v_uv.x) * 9.0, 0.0), 2.0);
	float a = mix(core, max(core * 0.7, (sx + sy) * 0.9), star);
	// Snap on, fade out: the pop is 2-3 frames of punch, not a lamp.
	a *= (1.0 - progress) * (1.0 - progress);
	if (a <= 0.003) {
		discard;
	}
	ALBEDO = pop_color.rgb * heat;
	ALPHA = clamp(a * fx_opacity, 0.0, 1.0);
}
