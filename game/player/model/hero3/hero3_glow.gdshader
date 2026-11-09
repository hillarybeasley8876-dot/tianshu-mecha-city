shader_type spatial;
// NOT `unshaded`: Godot's unshaded path outputs ALBEDO and ignores EMISSION, which is why the first
// version of this shader drew nothing at all. A lit surface with a black albedo emits only EMISSION,
// which is exactly what a glow panel wants.
render_mode cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

// A glow panel on the Tianshu (hero-v3 r7, reworked in r8): the visor slit and the chest portcullis.
//
// r7 drew these ADDITIVELY over the armour, and the lead was right that the inside of the grille read
// as noise. An additive panel does not OCCLUDE: wherever its own emission is low the atlas behind it
// shows straight through, and the sternum plate under the portcullis is bright gold trim, so seven
// dark gaps over it came out as cream blotches with a smeared bright patch in the middle. The
// concept's cavity is DARK with light coming out of it, so this panel now MIXES -- it draws its own
// dark cavity and its own gold bars, and the armour behind it is never seen again.
//
//   * feathered alpha, so there is no hard quad silhouette;
//   * `stripes` vertical lit gaps with `duty` of each period lit, the rest being the bars;
//   * the bars as lit gold METAL, so they take their colour from the environment exactly the way the
//     armour's own trim does (the lead's r7 ruling on GOLD_GLOW: a self-lit trim reads as paint);
//   * a `centre` envelope, because a lit cavity is brightest in the middle;
//   * `core_gain` on a thin band down the middle, which is the visor's hot line.
//
// No `return` anywhere in `fragment()`: Godot rejects it outright and the whole shader then fails to
// compile, which leaves the panel on the engine's fallback material -- measured, that is what made
// the visor read as an unlit navy slab in the first r8 close-up pass.

uniform vec3 glow_color : source_color = vec3(1.0, 0.69, 0.25);
uniform vec3 bar_color : source_color = vec3(1.0, 0.70, 0.28);
// The recess behind the bars. Warm near-black, not blue: it sits inside a gold-trimmed chest.
uniform vec3 cavity_color : source_color = vec3(0.030, 0.022, 0.016);
uniform float glow_gain = 0.32;
uniform float bar_rough = 0.30;
uniform float cavity_rough = 0.85;
// Fraction of each axis spent on the falloff. 0.5 is a soft blob, 0.06 a crisp edge with a
// half-centimetre feather at mech scale.
uniform vec2 feather = vec2(0.06, 0.30);
// Vertical lit gaps across the quad. 0 draws a solid panel, which is what the visor slit is.
uniform float stripes = 0.0;
uniform float duty = 0.45;
// 1 = brightest in the middle, the way a lit cavity looks.
uniform float centre = 1.0;
// The thin hot line down the middle of the opening, and how wide it is as a fraction of the height.
uniform float core_gain = 0.0;
uniform float core_width = 0.14;
// The measurement hook: draws the sheet flat grey with its own alpha UNCHANGED, so a capture is an
// exact screen mask of the part of the panel that is actually visible. Without it the mask is the
// whole quad, including the fully transparent feather, and the gate measures sky through the edge.
uniform int flat_mask = 0;

void fragment() {
	vec2 d = min(UV, vec2(1.0) - UV);
	vec2 f = smoothstep(vec2(0.0), feather, d);
	float edge = f.x * f.y;
	float lit = 1.0;
	if (stripes > 0.5) {
		float s = fract(UV.x * stripes);
		lit = smoothstep(0.0, max(duty * 0.5, 1e-4), min(s, 1.0 - s));
	}
	float env = mix(1.0, (1.0 - abs(UV.x * 2.0 - 1.0)) * (1.0 - abs(UV.y * 2.0 - 1.0) * 0.45),
			clamp(centre, 0.0, 1.0));
	float core = core_gain * exp(-pow((UV.y - 0.5) / max(core_width, 1e-3), 2.0));

	if (flat_mask > 0) {
		ALBEDO = vec3(0.5);
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = vec3(0.0);
	} else {
		// the cavity darkens toward its own edges, so it reads as a recess rather than a flat plate
		ALBEDO = mix(bar_color, cavity_color * mix(0.45, 1.0, env), lit);
		METALLIC = 1.0 - lit;
		ROUGHNESS = mix(bar_rough, cavity_rough, lit);
		EMISSION = glow_color * (glow_gain * lit + core) * env;
	}
	ALPHA = edge;
}
