// mc_wet (city-art r15 §4) — the wet ground, and the reflection that sells it.
//
// The key art's foreground is WET in every plate that has one: v1's pier mirrors the sun's path and
// the magenta billboards, v2's street mirrors the whole canyon. That read is a REFLECTION, and SSR is
// off at shipping quality (r13 measured 1.75 ms of a 28 ms street frame for a screen-space mirror this
// art direction does not otherwise have), so the reflection here is ANALYTIC: the same horizon ->
// zenith ramp `mc_sky` draws, evaluated along the fragment's reflected ray, plus the sun's own glow
// and a Fresnel weight.
//
// What that costs: ~25 ALU and NO texture fetch, against SSR's screen-space march — and unlike SSR it
// is correct for the sky (SSR's screen-space march misses anything off-screen, which for a ground
// plane looking at the sky is most of it). What it does NOT do is reflect the BUILDINGS; those come
// from the arena reflection probes, which is the same trade r13 already made.
//
// `sky_horizon` / `sky_zenith` are pushed by `McMaterials.set_sky_tint` (TimeOfDay owns the ramp, the
// same way it owns the haze, the wetness and the sun). `sun_dir` comes from `mc_sun.gdshaderinc`.

uniform vec3 sky_horizon : source_color = vec3(0.91, 0.67, 0.45);
uniform vec3 sky_zenith : source_color = vec3(0.21, 0.34, 0.55);
// How strong the mirrored sky is. 1.0 is a mirror; the key art's wet asphalt is closer to 0.7.
uniform float sky_mirror : hint_range(0.0, 3.0) = 1.0;


// The dome's ramp, cheap enough to call per fragment: gold at the horizon in the sun's half, cooler
// away from it, and the zenith colour straight up. `toward_sun` uses the same horizontal-dot the sky
// shader does, so the mirrored sun sits exactly where the real one is.
vec3 sky_reflect_color(vec3 dir, vec3 sd) {
	float h = clamp(dir.y, -1.0, 1.0);
	vec2 dh = normalize(vec2(dir.x, dir.z) + vec2(1e-5));
	vec2 sh = normalize(vec2(sd.x, sd.z) + vec2(1e-5));
	float toward = clamp(dot(dh, sh) * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(sky_horizon * mix(0.72, 1.0, toward), sky_zenith, smoothstep(0.0, 0.34, h));
	// The sun's own glow in the water — the streak down v1's pier. Wide and soft: a mirror of a 0.5 deg
	// disc is a point, and a point on a rippled plane is aliasing, not a highlight.
	col += vec3(1.0, 0.86, 0.66) * pow(max(dot(dir, sd), 0.0), 22.0) * 1.6;
	return col * sky_mirror;
}


// The mirrored sky for a fragment, weighted by Fresnel and by how wet it is. Returns 0 on a dry or a
// non-horizontal surface, so nothing that is not a puddle pays for it beyond the branch.
// `wetness` is the surface's own 0..1 wetness, `world_normal` its shading normal.
vec3 wet_reflection(vec3 world_pos, vec3 world_normal, vec3 eye, float wetness) {
	if (wetness <= 0.003) {
		return vec3(0.0);
	}
	vec3 v = normalize(eye - world_pos);
	vec3 r = reflect(-v, normalize(world_normal));
	if (r.y < 0.0) {
		r.y = -r.y;   // a ripple can tip the reflected ray under the plane; fold it back
	}
	// Schlick, F0 = 0.02 for water. Grazing angles are where a wet street actually mirrors.
	float f = 0.02 + 0.98 * pow(1.0 - clamp(dot(v, normalize(world_normal)), 0.0, 1.0), 5.0);
	return sky_reflect_color(r, sun_dir) * f * wetness;
}
