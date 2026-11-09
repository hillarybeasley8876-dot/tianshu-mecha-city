shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// A hive pod sac (look/flow.md item 1). The old pod was one flat emissive sphere; this is the
// membrane the key art shows — a dark chitin shell with an acid core lit from inside, fresnel on the
// grazing edge so the silhouette stays dark against the dusk. Energy stays at or under 1.5 so the
// bloom does not turn the cluster into the lime blob monster-assets' emission item is fixing.
//
// The breathing is TIME in the shader, not a per-frame material write: three spires × five clusters
// used to re-upload a StandardMaterial3D 12 times a second for a sine wave.

uniform vec3 acid : source_color = vec3(0.62, 0.95, 0.22);
uniform vec3 chitin : source_color = vec3(0.045, 0.062, 0.055);
uniform float core_energy : hint_range(0.0, 3.0) = 1.4;
uniform float phase = 0.0;              // per-cluster, so the pods do not breathe in lockstep
uniform float translucency : hint_range(0.0, 1.0) = 0.55;
// The breathing band. A pod keeps the slow, shallow swell it always had; the hive core asks for
// 0.6 -> 1.4 at 1.2 Hz, which is the heartbeat the fight's last target needs (flow-look-r1 polish 1).
uniform float pulse_lo : hint_range(0.0, 3.0) = 0.56;
uniform float pulse_hi : hint_range(0.0, 3.0) = 1.0;
uniform float pulse_hz : hint_range(0.0, 8.0) = 0.334;
// Veining density. A pod sac is 4 m across and wants big blotches; the core's sacs are the same size
// but are read from 70 m, where six cells across the whole membrane is a flat wash.
uniform float mottle_scale : hint_range(1.0, 40.0) = 6.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float mottle(vec2 uv, float scale) {
	vec2 cell = floor(uv * scale);
	vec2 f = fract(uv * scale);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	vec2 w = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 2.4);
	// The membrane thins towards the middle of the sac, so the core reads through it.
	float flesh = smoothstep(0.02, 0.55, ndv) * (0.55 + 0.45 * mottle(UV, mottle_scale));
	float pulse = mix(pulse_lo, pulse_hi, 0.5 + 0.5 * sin(TIME * 6.2831853 * pulse_hz + phase));

	ALBEDO = mix(chitin, acid * 0.35, flesh);
	EMISSION = acid * core_energy * pulse * flesh * (1.0 - rim * 0.85);
	ALPHA = clamp(0.30 + 0.62 * flesh + 0.25 * rim, 0.0, 1.0) * (0.55 + 0.45 * translucency);
	ROUGHNESS = mix(0.22, 0.82, rim);
	SPECULAR = 0.45;
	METALLIC = 0.0;
}
