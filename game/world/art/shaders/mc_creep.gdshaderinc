// mc_creep (city-art) — the infection overlay, shared by every surface that can carry it.
//
// The creep is a stain around a hive, not geometry: `mc_hive0..3` are the four nest sites (xyz = world
// position of the base, w = radius) and `mc_hive_levels` their per-site intensity, all pushed by
// InfectionField (CONTRACTS §7). `mc_infection` is the master the flow unit pulls down when the Spire
// dies. Every city surface that includes this gets creep for zero extra draw calls, which is why the
// kit buildings and the procedural roles share one implementation instead of two that drift apart.

global uniform float mc_time;
global uniform vec4 mc_hive0;
global uniform vec4 mc_hive1;
global uniform vec4 mc_hive2;
global uniform vec4 mc_hive3;
global uniform vec4 mc_hive_levels;
global uniform float mc_infection;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float hash21(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1, 0, 0));
	float n010 = hash31(i + vec3(0, 1, 0));
	float n110 = hash31(i + vec3(1, 1, 0));
	float n001 = hash31(i + vec3(0, 0, 1));
	float n101 = hash31(i + vec3(1, 0, 1));
	float n011 = hash31(i + vec3(0, 1, 1));
	float n111 = hash31(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			   mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// Band width in metres is about 2.9 * `w` — that is how the vein width is kept at 0.3-1 m.
float ridge_line(vec3 p, float w) {
	float r = 1.0 - abs(vnoise(p) * 2.0 - 1.0);
	return smoothstep(1.0 - w, 1.0, r);
}

// 1 at the hive, falling off with horizontal distance and climbing height. It stays inside the hive's
// radius (InfectionField clamps that to 120 m) and hugs the lowest 30 m, so creep is a stain around a
// nest and not wallpaper on whole facades.
float hive_field(vec4 site, float level, vec3 p) {
	if (level <= 0.001 || site.w <= 0.0) {
		return 0.0;
	}
	float d = length(p.xz - site.xz);
	float falloff = pow(1.0 - clamp(d / site.w, 0.0, 1.0), 2.2);
	float climb = 1.0 - clamp((p.y - site.y) / 30.0, 0.0, 1.0);
	return clamp(level * falloff * climb * climb, 0.0, 1.0);
}

// How much creep this point carries, from all four sites.
float creep_field(vec3 world, float gain) {
	float f = hive_field(mc_hive0, mc_hive_levels.x, world)
		+ hive_field(mc_hive1, mc_hive_levels.y, world)
		+ hive_field(mc_hive2, mc_hive_levels.z, world)
		+ hive_field(mc_hive3, mc_hive_levels.w, world);
	return clamp(f * mc_infection * gain, 0.0, 1.0);
}

// A darkened chitin stain with a few thin branching acid veins running out of the nest. The stain
// arrives FIRST and darkens the surface, so creep reads as something growing over the wall rather than
// lines drawn on it. Emission stays well under 2 and pulses slowly.
void apply_creep(inout vec3 albedo, inout float rough, inout float metal, inout vec3 emis,
		vec3 world, float gain) {
	float field = creep_field(world, gain);
	if (field <= 0.004) {
		return;
	}
	float blotch = vnoise(world * 0.16) * 0.6 + vnoise(world * 0.55) * 0.4;
	float stain = smoothstep(0.10, 0.55, field * (0.55 + 0.9 * blotch));
	// Veins: two ridged layers, the second offset so branches do not run parallel. Width grows with the
	// field (thick at the source, hair-thin at the edge) and never exceeds ~1 m. Two masks keep it from
	// reading as spaghetti: a patch mask so veins only run in parts of the stain, and a fine break-up so
	// the ridged contours are branches rather than closed loops.
	float w = mix(0.04, 0.15, field);
	float patch = smoothstep(0.42, 0.78, vnoise(world * 0.085));
	float branch = 0.35 + 0.65 * vnoise(world * 1.9);
	float veins = max(ridge_line(world * 0.30, w),
		ridge_line(world * 0.83 + vec3(11.3, 4.7, 2.9), w * 0.5) * 0.65);
	veins *= smoothstep(0.30, 0.70, field) * stain * branch * patch;
	float pulse = 0.72 + 0.28 * sin(mc_time * 0.55 + world.x * 0.03 + world.z * 0.02);
	albedo = mix(albedo, vec3(0.014, 0.019, 0.026), stain);   // chitin #1B2430, darkened
	albedo = mix(albedo, vec3(0.040, 0.062, 0.030), veins * 0.7);
	rough = mix(rough, 0.30, max(stain, veins));               // chitin is wet-glossy
	metal = mix(metal, 0.18, stain);
	emis += vec3(0.608, 1.0, 0.227) * veins * 0.6 * pulse;    // acid #9BFF3A, well under the cap
}
