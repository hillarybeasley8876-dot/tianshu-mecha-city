shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The HUSK body shader (monster-assets). One ShaderMaterial per monster TYPE is shared by every
// instance; everything that varies per monster is an instance uniform, so 40 rippers on screen cost
// one material (brief: "per-instance tints via set_instance_shader_parameter").
//
// Textures come straight from the Tripo PBR set baked into <type>.glb:
//   albedo   — base colour
//   orm      — occlusion (R), roughness (G), metallic (B), packed by Tripo
//   normal   — tangent-space normal, OpenGL convention
//   emission — the acid-green / violet mask derived from the albedo in mon_emit.py
// Emission and hit flash are added, never multiplied into ALBEDO: a hit has to read as light, and
// lighting the albedo flattens the silhouette (ART.md §1, juice §12 readability).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float emission_energy : hint_range(0.0, 12.0) = 3.0;
uniform float normal_depth : hint_range(0.0, 2.0) = 1.0;
// Hit flash (lead r5 item 2). It used to add `hit_flash * 4.0` of pure white to every texel, which is
// 2.4 against the monster's own emission of 2.0: one missile impact turned a mantis into a flat
// beige cut-out with no form, and a salvo kept it there. It is now weighted toward the rim and the
// veins, so an impact reads as the creature's edges and glow flaring while the carapace keeps its
// shading, and it is tinted so the flare belongs to the HUSK palette instead of erasing it.
// Rapid re-hits RE-ARM the flash (set_hit_flash clamps to 1) rather than adding to it, so a salvo
// cannot stack its way to white.
uniform float flash_energy : hint_range(0.0, 4.0) = 1.0;
uniform vec3 flash_color : source_color = vec3(0.86, 1.0, 0.78);
uniform float flash_body : hint_range(0.0, 1.0) = 0.0;
uniform float flash_veins : hint_range(0.0, 6.0) = 3.4;
uniform float flash_rim_power : hint_range(0.5, 8.0) = 4.5;

// --- look pass (lead look r1) ---------------------------------------------------------------------
// ART.md §1 wants charcoal chitin with thin acid veins that pop against warm mid-tones at every
// distance. The Tripo albedos are 2-4.6x brighter than #1B2430 and half-metallic, so under the dusk
// sky the monsters reflected the warm haze and read as brown smudges. Every number below comes from
// `<type>_rig.json`'s "look" block, so it is per type and measured at build time, not guessed here.
uniform float albedo_gain : hint_range(0.0, 2.0) = 1.0;
uniform float metallic_cap : hint_range(0.0, 1.0) = 1.0;
uniform float roughness_floor : hint_range(0.0, 1.0) = 0.0;
uniform float rim_gain : hint_range(0.0, 4.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(0.608, 1.0, 0.227);

// The hive's four pod bulbs (mon_hive writes `<hive>_pods.png`, one channel per pod). Coverage > 0
// means "this texel belongs to a bulb": its veins burn `pod_boost` times hotter, and flow switching
// `pod_alive[i]` off when the pod bursts takes that bulb's light with it.
uniform sampler2D pod_mask_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float pod_boost : hint_range(1.0, 6.0) = 1.0;
instance uniform vec4 pod_alive = vec4(1.0);

// 0..1 white additive hit flash (CONTRACTS §6 set_hit_flash).
instance uniform float hit_flash = 0.0;
// Scales the whole glow: the hive's cracked state dims it, overdrive-style states raise it.
instance uniform float emission_scale = 1.0;
// Attack tell: white glint = parryable, red = unblockable (SPEC §7 counters).
instance uniform float tell = 0.0;
instance uniform vec3 tell_color = vec3(1.0);
// How hard the tell drives the veins, and how thin its rim is (lead r5 item 2). The tell used to be
// `mix(glow, tell_color * (0.8 + 2.4 * length(glow)), tell)`, and that constant 0.8 landed on every
// texel — at tell = 1 the whole carapace emitted and the median luma went 0.04-0.26 -> 0.82-0.85
// with 84-98 % of the monster's pixels above 0.5. The tell now only reaches texels the emission
// mask actually covers, plus a thin rim, which is what the comment always claimed.
uniform float tell_energy : hint_range(0.0, 8.0) = 2.6;
uniform float tell_rim_gain : hint_range(0.0, 4.0) = 1.0;
// Juggernaut armour plates breaking off, 0..1 (SPEC §7).
instance uniform float armor_damage = 0.0;

void fragment() {
	vec4 alb = texture(albedo_tex, UV);
	ALBEDO = alb.rgb * albedo_gain * mix(1.0, 0.5, armor_damage);
	vec3 orm = texture(orm_tex, UV).rgb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.6;
	// Wet chitin: never a mirror, never a mirror-smooth highlight.
	ROUGHNESS = max(mix(orm.g, 0.95, armor_damage * 0.5), roughness_floor);
	METALLIC = min(orm.b * (1.0 - armor_damage * 0.6), metallic_cap);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;

	vec3 glow = texture(emission_tex, UV).rgb * emission_energy * emission_scale;
	// The emission mask on its own, 0..1: "is this texel a vein or a core". The tell and the flash
	// both gate on it so neither can wash the carapace.
	float glow_mask = clamp(length(texture(emission_tex, UV).rgb) * 2.0, 0.0, 1.0);
	vec4 pods = texture(pod_mask_tex, UV);
	float pod_cover = dot(pods, vec4(1.0));
	glow *= mix(1.0, pod_boost, pod_cover) * (1.0 - dot(pods, vec4(1.0) - pod_alive));

	// Rim: the acid (or, on the harrier, cool sky-tinted) outline that keeps a 100 m silhouette
	// readable against both the dusk sky and a warm deck. It doubles past 40 m, where the veins
	// themselves are down to a few pixels.
	float dist = length(VERTEX);
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.0);
	rim *= mix(1.0, 2.0, smoothstep(40.0, 160.0, dist));

	// The tell lights the veins and cores, not the carapace: keep the dark silhouette readable.
	float tell_rim = pow(1.0 - facing, 4.0);
	vec3 tell_add = tell_color * tell * (tell_energy * glow_mask + tell_rim_gain * tell_rim);

	// The flash flares the edges and the veins and leaves the flat carapace alone. `flash_body` is 0
	// by design: any constant term lands on every texel, which is exactly what turned a mantis into
	// a beige cut-out. Measured with `probe_flash`: a 0.10 body term still took the median luma 3.1x.
	float flash_mask = mix(flash_body, 1.0, pow(1.0 - facing, flash_rim_power))
			+ flash_veins * glow_mask;
	EMISSION = glow + rim * rim_color * rim_gain + tell_add
			+ flash_color * (hit_flash * flash_energy * flash_mask);
}
