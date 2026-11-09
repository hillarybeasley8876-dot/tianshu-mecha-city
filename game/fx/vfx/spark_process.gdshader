shader_type particles;

// Spark emission (feel unit). Replaces ParticleProcessMaterial for the impact streak kinds so the
// streak LENGTH can be tied to each particle's own speed (CUSTOM.x), which is what makes a spark read
// as a stretched tracer instead of the flat rectangles the r1 review rejected.
// Draw pass: fx/vfx/spark.gdshader.

uniform vec3 emit_direction = vec3(0.0, 0.0, -1.0);
uniform float spread_deg : hint_range(0.0, 180.0) = 55.0;
uniform float speed_min = 18.0;
uniform float speed_max = 40.0;
uniform float gravity = -20.0;
uniform float damping = 4.0;
uniform float width_min = 0.15;
uniform float width_max = 0.30;
// Seconds of travel drawn as streak length; 0.03 s at 30 m/s = a 0.9 m tracer.
uniform float stretch = 0.03;
uniform float size_mul = 1.0;
// Fraction of the life the streak stays white-hot before it cools and fades.
uniform float hold : hint_range(0.0, 0.95) = 0.5;
uniform vec4 color_hot : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform vec4 color_cool : source_color = vec4(1.0, 0.5, 0.12, 1.0);

float rnd(float s) {
	return fract(sin(s * 12.9898) * 43758.5453);
}

void start() {
	// The cone must be built in the emitter's frame: local_coords is false and nothing else applies
	// EMISSION_TRANSFORM here (Godot only does that for ParticleProcessMaterial's generated code),
	// so without this every spark in the game flew toward world -Z whatever the hit normal was.
	vec3 axis = normalize(mat3(EMISSION_TRANSFORM) * emit_direction);
	vec3 ref = abs(axis.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t1 = normalize(cross(ref, axis));
	vec3 t2 = cross(axis, t1);
	// RANDOM_SEED is not unique per particle here, so the randomness is built from INDEX (unique per
	// particle in the emitter) plus a per-burst offset from TIME, otherwise every spark in a burst
	// lands on the same spot and the whole effect reads as one streak.
	float rs = float(INDEX) * 7.13 + fract(TIME * 0.731) * 91.7;
	float r1 = rnd(rs * 1.13 + 3.7);
	float r2 = rnd(rs * 2.71 + 9.1);
	float r3 = rnd(rs * 4.37 + 1.9);
	float a = r1 * TAU;
	// Cosine-space cone sampling, not tan(half_spread): at spread 180 tan() sits on its pole
	// (tan(1.5707964) ~ -2.3e7 in fp32) and threw every wide burst out as a flat disc, or NaN where a
	// fast-math tan returns inf. ct is cos(angle from the axis), so spread 180 is a true hemisphere.
	float sp = mix(speed_min, speed_max, r3);
	float ct = mix(1.0, cos(radians(spread_deg) * 0.5), r2);
	float st = sqrt(max(1.0 - ct * ct, 0.0));
	VELOCITY = (axis * ct + (t1 * cos(a) + t2 * sin(a)) * st) * sp;
	TRANSFORM[0] = vec4(1.0, 0.0, 0.0, 0.0);
	TRANSFORM[1] = vec4(0.0, 1.0, 0.0, 0.0);
	TRANSFORM[2] = vec4(0.0, 0.0, 1.0, 0.0);
	TRANSFORM[3] = vec4(EMISSION_TRANSFORM[3].xyz, 1.0);
	CUSTOM = vec4(sp, 0.0, mix(width_min, width_max, r2), 0.0);
	COLOR = color_hot;
}

void process() {
	float life = max(LIFETIME, 0.001);
	CUSTOM.y += DELTA / life;
	float age = clamp(CUSTOM.y, 0.0, 1.0);
	VELOCITY.y += gravity * DELTA;
	VELOCITY -= VELOCITY * min(damping * DELTA, 0.9);
	// Position is NOT integrated here: the engine already advances the particle by its velocity once
	// per tick, so adding it again doubled every spark's throw.
	CUSTOM.x = length(VELOCITY);

	// White-hot for `hold` of the life, cooling to orange, then out.
	COLOR.rgb = mix(color_hot.rgb, color_cool.rgb, smoothstep(0.0, 1.0, age / max(hold + 0.4, 0.01)));
	COLOR.a = color_hot.a * (1.0 - smoothstep(hold, 1.0, age));

	// Length follows speed; never shorter than a stub, so a dying spark is still a spark. The whole
	// matrix is written, not just the xyz rows: a zero w would collapse the quad to a point.
	float len = max(CUSTOM.x * stretch, CUSTOM.z * 3.0) * size_mul;
	float wid = CUSTOM.z * size_mul;
	// Streaks run along their own velocity. transform_align = Y_TO_VELOCITY is not used: its
	// normalize(cross(v, z)) has no zero guard. Built by hand with an up fallback instead.
	vec3 yd = CUSTOM.x > 1e-4 ? VELOCITY / CUSTOM.x : vec3(0.0, 1.0, 0.0);
	vec3 up = abs(yd.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 xd = normalize(cross(up, yd));
	TRANSFORM[0] = vec4(xd * wid, 0.0);
	TRANSFORM[1] = vec4(yd * len, 0.0);
	TRANSFORM[2] = vec4(cross(xd, yd) * wid, 0.0);
}
