shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// hero-v3 r10: the backpack thruster flame. A cone mesh with an animated additive shader, NOT the
// white box quads TAA smeared into mosaic ghosts on the old hero (brief root cause #4).
//
// r9's version was `ALBEDO = tint * (0.35 + 2.4 * core) * throttle * flicker` with no radial term at
// all: every fragment of the cone came out the same near-white at the same alpha with a hard
// elliptical silhouette, which is the flat white slab the lead saw. This one has a hot core that
// falls off to the hero's accent, a soft radial falloff, shock-diamond banding and a flicker.
//
// EVERY number below is a uniform written by `Hero3Plume` — that file is the only place the look is
// tuned, and `tests/hero3_plume_check.gd` measures it headless through `Hero3Plume.shade()`, a
// line-for-line mirror of `fragment()` below. Edit the two together or not at all.
//
// The flame's LENGTH and WIDTH are not here: `Hero3Rig` scales the node by `Hero3Plume.reach(level)`
// along its axis and `Hero3Plume.width(level)` across it, so `along` always runs 0 at the nozzle to
// 1 at the real tip and the gate can measure the plume's world length off the node.

uniform float level : hint_range(0.0, 1.0) = 0.0;
// The cone's own height in metres at scale 1, so `along` is the fraction along the plume.
uniform float height = 3.4;
// The cone's own radii at the mouth and the tip, so `rim` is the fraction across the disc. The rig
// writes these from the MEASURED nozzle (`Hero3Nozzle`); they are geometry, not look.
uniform float radius_base = 0.7;
uniform float radius_tip = 0.04;
uniform float time_s = 0.0;
uniform vec3 core_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 accent_color : source_color = vec3(0.30, 0.90, 1.00);
uniform float gate_span = 0.05;
uniform float body_head = 0.35;
uniform float core_pow = 2.0;
uniform float core_span = 0.18;
// The axial INTENSITY falloff. Without it the accent cyan is multiplied by the full gain for the
// whole first third of the plume and clips to white on screen -- measured on an offline render of
// this exact maths (`tmp/hero-v3/plume_preview.py`): the "hot core" was the top 25 % of the flame.
uniform float glow_span = 0.40;
uniform float glow_floor = 0.18;
uniform float radial_pow = 1.5;
uniform float edge_kill = 0.18;
// Where the bottom cap's own disc starts to fade, as a fraction of its radius.
uniform float rim_start = 0.30;
uniform float diamond_n = 4.0;
uniform float diamond_depth = 0.34;
uniform float diamond_hz = 5.0;
uniform float diamond_ramp = 0.10;
uniform float diamond_fade = 0.55;
uniform float flicker_hz = 22.0;
uniform float flicker_depth = 0.13;
uniform float flicker_wave = 9.0;
uniform float gain_min = 0.90;
uniform float gain_max = 2.60;
uniform float idle_glow = 0.30;
uniform float idle_span = 0.045;

varying float along;
// 1 on the cone's flat caps (whose normal runs along the axis), 0 on the wall.
varying float cap;
// The vertex's own distance from the axis, as a fraction of the cone's radius at that height: 0..1
// across a cap, and exactly 1 everywhere on the wall.
varying float rim;

void vertex() {
	// CylinderMesh runs along local Y from -height/2 (the wide base, ON the measured mouth) to
	// +height/2 (the tip). The r8 line divided by the node's Y scale instead of the cone's height,
	// which put `along` outside [0, 1] and drew the bright root at the FAR end of the plume -- the
	// detached flame the lead saw floating behind the mech's shoulders. The node's scale is the
	// flame's length now, so the vertex is the right thing to divide.
	along = clamp(VERTEX.y / max(height, 0.001) + 0.5, 0.0, 1.0);
	cap = smoothstep(0.7, 0.95, abs(NORMAL.y));
	rim = clamp(length(VERTEX.xz) / max(mix(radius_base, radius_tip, along), 0.001), 0.0, 1.0);
}

void fragment() {
	float lv = clamp(level, 0.0, 1.0);
	// no flame at all below the gate: `MechContact.thruster_level` is exactly 0.0 on the ground, so a
	// walking mech has a nozzle ember and nothing else (lead r9's gate, kept).
	float gate = smoothstep(0.0, gate_span, lv);
	float body = 1.0 - smoothstep(body_head, 1.0, along);
	// the hot near-white head: full at the mouth, gone by ~3 * core_span up the plume
	float core = pow(body, core_pow) * exp(-along / max(core_span, 0.001)) * gate;
	// The radial falloff, from whichever surface this fragment is on. On the WALL it is the shell's
	// chord through the volume -- 1 where the view ray runs along the surface (the middle of the
	// projected plume) and exactly 0 at the silhouette, so there is no hard edge for TAA to smear.
	// On the CAP it is the disc's own radius, because a cap's normal points straight down the axis
	// and `dot(NORMAL, VIEW)` is 1 right out to its edge -- which drew the rear view as a hard-edged
	// uniform white disc until this term existed (measured on the offline render).
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float disc = 1.0 - smoothstep(rim_start, 1.0, rim);
	float soft = mix(facing, disc, cap);
	float radial = pow(soft, radial_pow) * smoothstep(0.0, edge_kill, soft);
	// shock diamonds, held off the nozzle so the core stays clean and faded out before the tip
	float band = 0.5 + 0.5 * sin(along * diamond_n * TAU - time_s * diamond_hz * TAU);
	float env = smoothstep(0.0, diamond_ramp, along)
			* (1.0 - smoothstep(diamond_fade, 1.0, along));
	float diamonds = 1.0 + diamond_depth * (band * 2.0 - 1.0) * env * lv;
	float flick = 1.0 - flicker_depth
			* (0.5 + 0.5 * sin(time_s * flicker_hz * TAU + along * flicker_wave));
	// the always-on nozzle ember, so a grounded mech still has a live mouth
	float ember = idle_glow * (1.0 - smoothstep(0.0, idle_span, along));
	vec3 tint = mix(accent_color, core_color, core);
	// ALPHA is COVERAGE -- how much gas is along the view ray -- and INTENSITY is ALBEDO. Keeping the
	// banding out of ALPHA is not a detail: `body * diamonds * flick` peaks at 1.34, so with the
	// diamonds in ALPHA the whole crest clipped flat at 1.0 and the shock diamonds vanished from the
	// brightest third of the plume, which is the one place they read. Measured: the gate's own peak
	// finder saw 2 peaks 0.008 apart (one crest, double-counted) and none at all before along 0.54.
	ALBEDO = tint * mix(gain_min, gain_max, lv)
			* (glow_floor + (1.0 - glow_floor) * exp(-along / max(glow_span, 0.001)))
			* diamonds * flick;
	// additive and depth_draw_never: the plume adds light and never writes depth, so it can never
	// hide the hero behind it
	ALPHA = clamp(radial * max(body * gate, ember), 0.0, 1.0);
}
