shader_type spatial;
render_mode blend_mix, cull_front, depth_draw_never, unshaded, shadows_disabled, fog_disabled;
// mc_storm (city-art): the storm-violet cloud shell that gathers around the Spire crown as spires
// fall (ART.md §1, §3). Drawn on the inside of a large sphere with a cheap 3-octave value-noise
// cloud field, a slow rotation and a violet rim that brightens on lightning strikes.

uniform vec3 cloud_dark : source_color = vec3(0.141, 0.102, 0.227);   // #241A3A
uniform vec3 cloud_light : source_color = vec3(0.549, 0.357, 1.0);    // #8C5BFF
uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform float density : hint_range(0.0, 3.0) = 1.0;
uniform float scale = 2.4;
uniform float spin = 0.045;
uniform float rim_power : hint_range(0.5, 8.0) = 2.0;
uniform float flash : hint_range(0.0, 4.0) = 0.0;
uniform vec3 flash_pos = vec3(0.0, 300.0, -120.0);
uniform float flash_radius = 260.0;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.55;

varying vec3 v_dir;
varying vec3 v_world;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x),
				   mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x),
				   mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_dir = normalize(VERTEX);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (cover <= 0.002) {
		discard;
	}
	float t = TIME * spin;
	// Rotate the sample point around Y so the cell drifts instead of crawling.
	vec3 p = vec3(v_dir.x * cos(t) - v_dir.z * sin(t), v_dir.y, v_dir.x * sin(t) + v_dir.z * cos(t));
	float n = vnoise(p * scale) * 0.55 + vnoise(p * scale * 2.3 + 11.0) * 0.30
		+ vnoise(p * scale * 5.1 - 4.0) * 0.15;

	// Clouds pool overhead and thin out toward the horizon of the shell.
	float pool = smoothstep(-0.15, 0.85, v_dir.y);
	// r6: `cover` was added straight into the mass term, so at cover 1.0 `mass` clamped to 1.0 across the
	// entire 760 m shell and the storm became one flat lilac wall over every vista
	// (captures/r6p1_V1.jpg) — no cloud, no silhouette, no crown. Cover now thickens the deck without
	// erasing the noise contrast that makes it read as cloud.
	float mass = clamp((n * density - mix(0.42, 0.24, cover)) * mix(2.2, 1.6, cover), 0.0, 1.0)
		* mix(0.25, 1.0, pool);

	// Rim: the shell edge glows violet, brighter where a strike is playing. `v_dir` is object space, so
	// it has to be taken to world before it is dotted with the view vector or the "rim" lands wherever
	// the sphere happens to be oriented rather than at its silhouette.
	vec3 wdir = normalize(v_world - (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float rim = pow(1.0 - abs(dot(wdir, normalize(VIEW))), rim_power);
	float strike = flash * exp(-length(v_world - flash_pos) / max(flash_radius, 1.0));
	vec3 col = mix(cloud_dark, cloud_light, clamp(mass * 0.62 + rim * 0.34 + strike, 0.0, 1.0));
	col += cloud_light * strike * 2.5;

	ALBEDO = col;
	ALPHA = clamp(mass * base_alpha * cover + rim * 0.25 * cover + strike * 0.8, 0.0, 1.0);
}
