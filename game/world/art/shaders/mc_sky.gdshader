shader_type sky;
render_mode use_half_res_pass;
// mc_sky (city-art): the 云阙城 dusk dome, hand-built instead of PhysicalSkyMaterial because ART.md §2
// fixes an exact sRGB ramp (zenith #2B4C7E -> mid #6F86B0 -> horizon #F2B880) plus a warm cloud band
// and a storm tint that the physical model cannot express. TimeOfDay pushes sun_dir, the dusk ramp
// and the storm cover here; the sky is also the ambient and reflection source for the whole city.

uniform vec3 zenith : source_color = vec3(0.169, 0.298, 0.494);   // #2B4C7E
uniform vec3 mid_sky : source_color = vec3(0.769, 0.604, 0.525);  // #C49A86
uniform vec3 horizon : source_color = vec3(0.969, 0.757, 0.537);  // #F7C189 gold, sun side
uniform vec3 horizon_away : source_color = vec3(0.827, 0.671, 0.576); // #D3AB93 peach, anti-sun side
uniform vec3 ground : source_color = vec3(0.227, 0.204, 0.251);   // #3A3440
uniform vec3 sun_color : source_color = vec3(1.0, 0.941, 0.812);  // #FFF0CF
uniform vec3 cloud_warm : source_color = vec3(1.0, 0.753, 0.541); // #FFC08A
uniform vec3 cloud_dusk : source_color = vec3(0.420, 0.290, 0.561); // #6B4A8F
// r15: the cloud BODY. It used to be `cloud_warm * 0.20` — one warm brown — and because the deck
// saturated to full coverage the whole dome rendered as that one colour (measured on the bare-sky
// pass: hue 52 deg at EVERY elevation from -2 to 35, against a key-art zenith 100-130 deg away from
// its horizon). The key art's cloud bodies are violet-grey and only their sunward edges are warm.
uniform vec3 cloud_body : source_color = vec3(0.357, 0.333, 0.439);  // #5B5570 violet-grey
uniform float cloud_body_gain : hint_range(0.0, 2.0) = 1.05;
uniform vec3 sun_dir = vec3(-0.5, 0.30, 0.5);
uniform float sun_intensity = 14.0;   // TimeOfDay pushes 4.5 -> 3.0 (r14, was 9 -> 6)
uniform float sun_size_deg : hint_range(0.1, 8.0) = 0.9;   // r14: 1.4 made a 5x-life-size disc
uniform float halo_power : hint_range(1.0, 64.0) = 11.0;
uniform float halo_gain : hint_range(0.0, 8.0) = 0.14;   // r14: 0.55 lit a 17 deg white field
uniform float haze_gain : hint_range(0.0, 4.0) = 1.0;   // gold band hugging the skyline
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_storm : hint_range(0.0, 1.0) = 0.0;
uniform float exposure : hint_range(0.1, 8.0) = 0.75;
// r15: how far up the dome the deck reaches. The key art's zenith is clear sky, so the band has to
// come off the top; at 1.0 it ran to 60 deg and buried the blue under cloud.
uniform float deck_top : hint_range(0.05, 1.0) = 0.26;
uniform float deck_span : hint_range(0.05, 1.5) = 0.44;
// r15: the panorama blend (see sky/README.md). `pano_blend` 0 = the hand-built dome alone, 1 = the
// CC0 cloud field alone; TimeOfDay keeps control of the ramp either way because the panorama is
// TINTED by the same zenith/horizon colours and its sun is rotated onto `sun_dir`.
uniform sampler2D pano : source_color, filter_linear, hint_default_black;
uniform float pano_blend : hint_range(0.0, 1.0) = 0.0;
uniform float pano_yaw : hint_range(-180.0, 180.0) = 0.0;   // degrees, puts the pano's sun on sun_dir
uniform float pano_gain : hint_range(0.0, 8.0) = 1.0;
// The panorama's mid-grey. Its luminance is divided by this so only its STRUCTURE is taken and the
// plate's own exposure never fights the dome's.
uniform float pano_ref : hint_range(0.01, 8.0) = 0.6;
// The panorama's own horizon is at its equator; the city's cameras look at 0-30 deg, so the pano is
// sampled with a vertical remap that lifts its interesting band down into the frame.
uniform float pano_pitch : hint_range(-1.5, 1.5) = 0.0;


float hash21(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
			   mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

// Flatten the dome to a plane so the cloud band foreshortens toward the horizon like real cloud. The
// 0.75 scale puts several cloud cells in a 40 deg slice of sky — at 0.22 the whole visible dome fell
// inside one noise cell and the "clouds" were a smooth wash.
vec2 cloud_uv(vec3 dir) {
	float y = max(dir.y, 0.02);
	return dir.xz / y * 0.75;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 sd = normalize(sun_dir);

	// Review r2: golden dusk. The horizon is gold in the sun's half and peach opposite it, so the NW
	// sun side of the skyline glows and the rest of the dome stays a warm neutral.
	vec2 dh = normalize(vec2(dir.x, dir.z) + vec2(1e-5));
	vec2 sh = normalize(vec2(sd.x, sd.z) + vec2(1e-5));
	float toward_sun = clamp(dot(dh, sh) * 0.5 + 0.5, 0.0, 1.0);
	vec3 hz = mix(horizon_away, horizon, pow(toward_sun, 1.6));

	// Vertical ramp. The warm band is wide at street level (that is where the camera is) and the
	// blue-violet zenith starts low enough to be visible in a canyon shot — dusk has a blue top.
	// r15: the transitions were `smoothstep(0.0, 0.16)` and `smoothstep(0.18, 0.72)`, i.e. the zenith
	// was still only 64 % in at 30 deg — and `mid_sky` was a BRIGHT warm grey (linear 0.36 against the
	// zenith's 0.03), so 36 % of it turned the "blue top" into a desaturated warm neutral. The key art
	// runs gold -> violet across the visible frame; the ramp now completes by ~17 deg so it does too.
	// r16b §1: the gold band has to HOLD. Measured on the bare-sky pass at the shipping gain, the old
	// pair put the 2-8 deg band at hue 67 while the authored horizon colour (#ffdc9a) lands at 75 —
	// the ramp was already 11 % mid_sky and 5 % zenith by 5 deg of elevation, and `skylo_hue` (0-9 deg)
	// is the number the whole frame is judged on. The transitions now start at ~2 deg and ~6 deg, so
	// the gold is intact across the band the metric reads and the blue still owns everything above
	// ~23 deg. They are not later than that: holding the FULL horizon colour further up the dome put
	// 2.4 % of the sun-side V7 frame over the clip gate (it was 1.04 % at r15), because the horizon
	// colour is the brightest thing in the dome.
	vec3 col = mix(hz, mid_sky, smoothstep(0.03, 0.37, h));
	col = mix(col, zenith, smoothstep(0.10, 0.40, h));
	col = mix(ground, col, smoothstep(-0.05, 0.015, h));

	// Aerial perspective band: the last few degrees above the skyline go pale gold, so towers that
	// reach into it dissolve instead of ending on a hard edge (the key art's haze layers).
	float band = exp(-max(h, 0.0) * 20.0) * haze_gain;
	col = mix(col, hz * 1.06, clamp(band * 0.40 * (0.45 + 0.55 * toward_sun), 0.0, 0.6));

	// Sun: a small disc with a wide warm halo that bleeds into the haze.
	float d = clamp(dot(dir, sd), -1.0, 1.0);
	float cos_r = cos(radians(sun_size_deg));
	float disc = smoothstep(cos_r - 0.0008, cos_r + 0.0004, d);
	float halo = pow(max(d, 0.0), halo_power);
	col += sun_color * (disc * sun_intensity + halo * halo_gain);

	// Clouds: a band that thickens with cover and is LIT FROM BELOW — the underside catches the low sun
	// and the top stays in shadow, which is what makes a dusk sky read as dusk.
	if (h > -0.02 && cloud_cover > 0.002) {
		vec2 uv = cloud_uv(dir) + vec2(TIME * 0.004, TIME * 0.0016);
		// The high octaves are faded out near the horizon, where the projected UV runs away and they
		// would alias into noise.
		float fine = smoothstep(0.05, 0.28, h);
		float n = vnoise2(uv * 0.62) * 0.42 + vnoise2(uv * 1.7) * 0.32
			+ mix(0.5, vnoise2(uv * 4.3), fine) * 0.18 + mix(0.5, vnoise2(uv * 9.1), fine) * 0.08;
		// Review r3: the band has to start just above the skyline (the key art's banks sit ON the towers).
		// r15: and it has to STOP. `deck_top`/`deck_span` bring the deck off the zenith so the blue
		// above it is sky and not cloud — the key art's zenith is clear, and a deck that reached 60 deg
		// is most of why the dome measured as one hue.
		float cband = smoothstep(0.008, 0.055, h) * (1.0 - smoothstep(deck_top, deck_top + deck_span, h));
		// r15, the round's biggest single fix. `mass` used to be `clamp((n - thresh) * 9.0, 0.0, 1.0)`,
		// which is a HARD threshold with a huge gain: at the cover TimeOfDay pushes (0.58 at the mission
		// start, 0.77 at tod 0.6) `thresh` fell to 0.29 and the term clamped to 1.0 across the whole
		// dome, so every pixel of sky took the cloud colour and the "sky" was one flat warm-brown field.
		// Cover now sets the AREA and the SOFTNESS, never the contrast: the transition is two octaves
		// wide at full cover, so there is always visible cloud edge.
		float thresh = mix(0.60, 0.34, cloud_cover);
		float width = mix(0.055, 0.150, cloud_cover);
		float mass = smoothstep(thresh - width, thresh + width, n) * cband;
		// Storm (r6): the deck has to stay STRUCTURED. Cover was mapped straight onto the threshold, so
		// at cover 0.90 `mass` clamped to 1.0 across the whole dome and the sky became one flat violet
		// wall (captures/r6p1_V1.jpg) with no cloud, no horizon and no silhouette left to read. The
		// storm keeps the noise contrast, darkens the body, and gets large-scale gaps the last light
		// comes through.
		mass *= mix(1.0, smoothstep(0.28, 0.64, vnoise2(uv * 0.24 + 11.0)), cloud_storm * 0.85);
		// r15: body in shadow, edge in the sun. The body is VIOLET-GREY (`cloud_body`) and only warms
		// toward the sun, which is what puts a hue difference between the sky's zenith and its horizon;
		// the old single `cloud_warm * 0.20` body could not, whatever the cover.
		// r15: the warmth has to be an EDGE, not a hemisphere. `pow(d, 2.0)` is 0.75 at 30 deg from the
		// sun and 0.25 at 60, so the sunward half of the whole deck took `cloud_warm` and the upper sky
		// rendered magenta — measured on the sky-only probe (no post stack, so nothing else could be
		// responsible): sRGB (156,106,135), hue 342, at 55-75 deg elevation against a shader zenith of
		// Lab 285. pow 6 confines it to ~25 deg, which is where the key art's warm cloud edges are.
		float sun_amt = pow(max(d, 0.0), 6.0);
		vec3 body = cloud_body * cloud_body_gain;
		body = mix(body, cloud_warm * 0.58, sun_amt * 0.55);
		body += sun_color * pow(max(d, 0.0), 10.0) * 0.55 * (1.0 - cloud_storm * 0.7);
		body = mix(body, cloud_dusk * vec3(0.34, 0.32, 0.46), cloud_storm * 0.85);
		// The sunward edge of each bank: thin, bright and warm. This is the structure the key art sells
		// and it is what `sky_rel` measures.
		float rim = smoothstep(0.58, 0.90, n) * cband * (1.0 - cloud_storm);
		vec3 lit_cloud = mix(body, sun_color * 1.30, rim * 0.62 * pow(max(d, 0.0), 1.2));
		col = mix(col, lit_cloud, mass * (0.72 + 0.28 * cloud_cover));
	}

	// r15 §2: the CC0 panorama (sky/README.md). It supplies the CLOUD FIELD — the thing a value-noise
	// dome cannot make — and the ramp above still supplies the colour, so TimeOfDay keeps control of
	// the time of day, the storm and the sun. The panorama is desaturated to a luminance field and
	// re-tinted by the same zenith/horizon mix the dome uses, so blending it in cannot reintroduce a
	// second, fixed time of day.
	if (pano_blend > 0.001) {
		float yaw = radians(pano_yaw);
		vec3 pd = vec3(dir.x * cos(yaw) - dir.z * sin(yaw), dir.y, dir.x * sin(yaw) + dir.z * cos(yaw));
		vec2 puv = vec2(atan(pd.z, pd.x) / TAU + 0.5, acos(clamp(pd.y, -1.0, 1.0)) / PI);
		puv.y = clamp(puv.y + pano_pitch, 0.002, 0.998);
		vec3 src = texture(pano, puv).rgb * pano_gain;
		float pl = dot(src, vec3(0.2126, 0.7152, 0.0722));
		// Normalised so the panorama's own exposure does not fight the dome's: only its STRUCTURE is
		// taken, at the dome's own value.
		float shape = clamp(pl / max(pano_ref, 0.02), 0.0, 4.0);
		// The SAME two transitions as the dome above (r16b §1), so blending the plate in cannot move
		// the ramp the colour metrics are measured on.
		vec3 tint = mix(mix(hz, mid_sky, smoothstep(0.03, 0.37, h)),
			mix(mid_sky, zenith, smoothstep(0.10, 0.40, h)), 0.65);
		vec3 pcol = tint * shape + sun_color * pow(max(d, 0.0), 6.0) * 0.30 * smoothstep(0.9, 1.6, shape);
		col = mix(col, pcol, pano_blend * smoothstep(-0.02, 0.06, h));
	}

	COLOR = col * exposure;
}

