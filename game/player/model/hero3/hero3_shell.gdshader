shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The Tianshu body shell (hero-v3 r7). Replaces the Tripo StandardMaterial3D on `Hero3Body`'s
// armour surface so the concept's reads survive a dark city:
//
//   * the cyan seam lines EMIT instead of being albedo pixels that vanish on the shaded side;
//   * the black armour keeps a small linear floor (Tripo baked it at 0.009, which is a hole rather
//     than a colour) and a dielectric sheen, so the plates stay near-black with a highlight on them
//     instead of turning into lifted grey-blue diffuse;
//   * the gold trim is a real metal AND its albedo is pushed to a gold hue, because a metal's colour
//     is its albedo times the environment and the environment at dusk is not gold;
//   * a view-dependent rim and a hemisphere fill lift the silhouette off a dark background.
//
// `emis_tex` is `blender/hero3/hero3_emissive.py`'s output: R = steady accent lines, G = vents
// (pulsed from the rig), B = gold trim.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D emis_tex : source_color, filter_linear_mipmap, repeat_disable;

// Linear floor under the dark armour, and the luma band it fades out over. Neutral on purpose: a blue
// floor plus a blue sky fill is what turned the plates blue-grey on city-art r15's light.
uniform vec3 lift_color : source_color = vec3(0.020, 0.020, 0.021);
uniform vec2 lift_band = vec2(0.008, 0.130);
// The gold trim: metallic 1, a tight roughness, and an albedo forced to a gold hue. The Tripo bake
// left the trim at metallic 0.51 with a tan albedo, which reads as dirty brass, not gold.
uniform float gold_metallic = 1.0;
uniform vec2 gold_roughness = vec2(0.26, 0.40);
uniform vec3 gold_albedo : source_color = vec3(0.56, 0.52, 0.13);
uniform float gold_tint = 0.8;
// A metal's colour is its albedo times the environment, and the environment at --tod 0.6 is a warm
// orange wall, which dragged the trim's measured hue from 47 deg down to 26. A small gold-tinted
// emission anchors it: measured on the 4-angle sheet, the trim now sits in the gold band at every
// time of day instead of going orange whenever the sun does.
uniform float gold_glow = 0.13;
// The black armour is a DIELECTRIC, not a metal: a metal's specular is tinted by its albedo, so
// metallic black armour reflects nothing and reads as a hole. Lacquered plate wants a low metallic,
// a mid roughness and a raised F0, which is what puts the city's own light on the plates.
uniform float armour_metallic = 0.12;
uniform float armour_roughness = 0.28;
uniform float armour_specular = 0.85;

uniform vec3 accent_color : source_color = vec3(0.30, 0.90, 1.0);
uniform float line_gain = 0.9;
uniform vec3 vent_color : source_color = vec3(1.00, 0.62, 0.16);
uniform float vent_gain = 3.5;
// 0 = idle, 1 = the hero is boosting / in overdrive / charging. Driven by `Hero3Shade`.
uniform float vent_pulse = 0.35;

// Silhouette rim. `rim_gain` is 0 in first person: the cockpit view must not glow.
uniform vec3 rim_color : source_color = vec3(0.55, 0.66, 0.82);
uniform float rim_gain = 0.0;
uniform float rim_power = 3.2;

// A character fill. At --tod 0.6 the sun is behind the mech and the only light on the camera side is
// the ambient, so a black dielectric has no form at all -- measured, 52 % of the hero's pixels sat
// under 0.03 display luma at the trailer's own cold-open camera. This is a HEMISPHERE, so the plates
// still separate from each other instead of flattening into one grey mass. It rides the same
// `fill_gain` switch as the rim and is off in first person.
uniform vec3 fill_sky : source_color = vec3(0.055, 0.058, 0.065);
uniform vec3 fill_ground : source_color = vec3(0.070, 0.052, 0.036);
uniform float fill_gain = 0.0;

// The measurement hook the palette gate uses: 1 writes the gold mask, 2 the plate mask, straight to
// emission on a black surface, so `tmp/hero-v3/palette.py` can measure the trim's hue and the
// plates' luma on a real frame instead of guessing which pixels are which.
uniform int debug_mask = 0;

void fragment() {
	vec3 mask = texture(emis_tex, UV).rgb;
	float line = mask.r;
	float vent = mask.g;
	float gold = mask.b;

	vec3 albedo = texture(albedo_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;

	float luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	float dark = 1.0 - smoothstep(lift_band.x, lift_band.y, luma);
	albedo += lift_color * dark * (1.0 - line) * (1.0 - gold);
	albedo = mix(albedo, gold_albedo, gold * gold_tint);

	float armour = 1.0 - gold;
	float metallic = mix(mix(orm.b, armour_metallic, armour), gold_metallic, gold);
	float roughness = mix(mix(orm.g, armour_roughness, armour),
			clamp(orm.g, gold_roughness.x, gold_roughness.y), gold);

	ALBEDO = albedo;
	METALLIC = metallic;
	SPECULAR = mix(armour_specular, 0.5, gold);
	ROUGHNESS = clamp(roughness, 0.04, 1.0);
	AO = orm.r;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.0;

	if (debug_mask > 0) {
		float plate = step(0.5, 1.0 - gold) * (1.0 - step(0.35, line + vent));
		float m = debug_mask == 1 ? gold : (debug_mask == 2 ? plate : 1.0);
		ALBEDO = vec3(0.0);
		METALLIC = 0.0;
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = vec3(m);
	} else {
		vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(normalize(NORMAL), 0.0)).xyz);
		// The vents use `vent_color`, NOT `accent_color`. r7 declared the amber and then emitted the
		// cyan through it, so every vent on the mech threw a 1.19-gain CYAN -- and a cyan that far over
		// white, added to a warm gold sternum and run through the tonemapper, is exactly the cream
		// blotch the lead found inside the chest grille (lead r8 item 1). Measured on the r8 close-up
		// sheet: the share of grille pixels at saturation < 0.25 and value > 0.8 falls 1.42 % -> 0.21 %
		// when the vents are muted, and the brightest pixel goes from (245,222,173) s=0.29 to
		// (243,155,55) s=0.77 once they emit amber instead.
		vec3 emit = accent_color * (line * line_gain)
				+ vent_color * (vent * vent_gain * vent_pulse);
		emit += gold_albedo * (gold * gold_glow);
		emit += albedo * mix(fill_ground, fill_sky, world_n.y * 0.5 + 0.5) * fill_gain;
		float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		emit += rim_color * (pow(1.0 - facing, rim_power) * rim_gain);
		EMISSION = emit;
	}
}
