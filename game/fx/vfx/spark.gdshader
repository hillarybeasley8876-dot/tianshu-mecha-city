shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Spark streak (feel unit), emitted by fx/vfx/spark_process.gdshader. One quad per particle, stretched
// along its own velocity and turned edge-on to the camera around that axis, so the streak always faces
// the viewer however the spark flies. Additive, with the core above 1.0 so it blooms (ART.md §3).
// The age comes from INSTANCE_CUSTOM.y (written by the process shader) rather than COLOR, so the fade
// cannot be lost if a particle colour is not forwarded.

global uniform float fx_opacity;
// World metres per pixel per metre of depth; VfxLibrary refreshes it from the active camera.
global uniform float fx_pixel_scale;
uniform vec4 color_hot : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec4 color_cool : source_color = vec4(1.0, 0.5, 0.12, 1.0);
// Fraction of the life the streak stays white-hot; must match spark_process.gdshader's `hold`.
uniform float hold : hint_range(0.0, 0.95) = 0.5;
// Screen-space floor for the streak (r2 MUST-FIX 3): a hit 150 m away still draws a 2.5 px wide,
// 25 px long tracer instead of vanishing into a sub-pixel dot. The length floor shrinks with age so
// a dying spark does not turn into a long cold line.
uniform float min_width_px = 2.5;
uniform float min_length_px = 25.0;

varying vec2 v_uv;
varying float v_age;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	// World size of one pixel at this depth, from the fx_pixel_scale global VfxLibrary keeps up to
	// date from the active camera (VIEWPORT_SIZE reads 0 in an offscreen capture).
	float px = distance(INV_VIEW_MATRIX[3].xyz, origin) * fx_pixel_scale;
	float wid = max(length(MODEL_MATRIX[0].xyz), min_width_px * px);
	float slen = max(length(MODEL_MATRIX[1].xyz), min_length_px * px * (1.0 - v_age));
	vec3 axis = MODEL_MATRIX[1].xyz;
	float al = length(axis);
	vec3 ydir = al > 1e-5 ? axis / al : INV_VIEW_MATRIX[1].xyz;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - origin;
	vec3 xdir = cross(ydir, to_cam);
	float xl = length(xdir);
	xdir = xl > 1e-5 ? xdir / xl : INV_VIEW_MATRIX[0].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(xdir * wid, 0.0),
			vec4(ydir * slen, 0.0),
			vec4(cross(xdir, ydir), 0.0),
			vec4(origin, 1.0));
	v_uv = UV;
}

void fragment() {
	vec2 p = (v_uv - vec2(0.5)) * 2.0;
	float across = clamp(1.0 - abs(p.x), 0.0, 1.0);
	float along = clamp(1.0 - abs(p.y), 0.0, 1.0);
	// Thin body, tapered ends, brighter towards the leading tip.
	float body = pow(across, 2.4) * pow(along, 0.7) * mix(0.45, 1.0, smoothstep(-1.0, 1.0, p.y));
	float fade = 1.0 - smoothstep(hold, 1.0, v_age);
	if (body * fade <= 0.002) {
		discard;
	}
	// White-hot filament down the middle of the streak, cooling to orange over the life.
	vec3 col = mix(color_hot.rgb, color_cool.rgb, smoothstep(0.0, 1.0, v_age / max(hold + 0.4, 0.01)));
	col = mix(col, vec3(1.0), pow(across, 6.0) * 0.85);
	ALBEDO = col * 1.6;
	ALPHA = clamp(body * fade * fx_opacity, 0.0, 1.0);
}
