class_name DefenseVisualSuite
extends RefCounted
## r7 — the Mirror Guard has to read as an ENERGY SHIELD, not the flat mint-green tile the showcase
## reel showed. The pixels can only be confirmed in a capture (the lead runs those), so everything
## that decides them is pinned here instead:
##
##   * the materials build, and every uniform the profile writes really exists on the shader;
##   * the interior alpha is under the lead's 0.25 ceiling and the rim over the 0.8 floor — measured
##     from the MATERIAL's own uniform values, not from the constants, so a shader edit that stops
##     taking the profile's numbers fails;
##   * the panel is chest-sized and CURVED (a flat plane would measure ~0 of bulge);
##   * the fade is 0.08 s in / 0.15 s out, the ripple starts at the hit point and is gone inside
##     0.5 s, and the parry burst spawns its shards and frees them inside 1 s;
##   * the catch dome is a distinct, thinner, turning surface that only shows while the field is open.
##
## The alpha maths is mirrored from `mirror_shield.gdshader` in `MirrorShieldProfile`; the mirror and
## the shader take the same numbers from the same place, and `mat.params_match_the_profile` is what
## keeps them from drifting apart.

const ErrorCounter := preload("res://tools/error_counter.gd")
const HERO_SHADE := "res://player/model/hero3/hero3_shade.gd"

## The lead's numbers, restated here so the test fails if either side moves.
const CENTER_ALPHA_MAX := 0.25
const RIM_ALPHA_MIN := 0.8
const PANEL_SPAN_MAX := 10.0     ## metres across; the old plate was 13
const SHARD_FREE_SECONDS := 1.0
const RIPPLE_DECAY_SECONDS := 0.5


static func run(h: DefenseTestHarness) -> void:
	_materials(h)
	_form(h)
	await _fade(h)
	await _ripple(h)
	await _parry_burst(h)
	await _dome(h)

## --- materials ---------------------------------------------------------------------------------

## The GLSL is COMPILED here, not just loaded: the dummy renderer's material storage parses a
## shader's code on `Shader.code = …` and logs `SHADER ERROR` / `Shader compilation failed` when it
## does not parse. `tools/godot.sh check` does NOT catch that — measured, a deliberate syntax error
## in this file still reports `CHECK 0 failed` — so this is the only headless gate on the shader.
static func _materials(h: DefenseTestHarness) -> void:
	var source := FileAccess.get_file_as_string(MirrorShieldProfile.SHADER)
	h.check("mat.shader_source_reads", not source.is_empty(),
			"cannot read " + MirrorShieldProfile.SHADER)
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var probe := Shader.new()
	probe.code = source
	## `get_shader_uniform_list()` is what makes the dummy material storage actually PARSE the code
	## (it answers an empty list headless either way, but it runs the compiler). Without it a broken
	## shader is silent here and only shows up as the host's `TEST ERRORS`.
	probe.get_shader_uniform_list()
	var shield_mat := MirrorShieldProfile.material()
	var dome_mat := MirrorShieldProfile.dome_material()
	OS.remove_logger(counter)
	h.check("mat.shader_compiles", counter.errors == 0,
			"%d error(s): %s" % [counter.errors,
			counter.first_errors[0] if counter.first_errors.size() > 0 else ""])
	h.check("mat.shield_material_builds", shield_mat != null and shield_mat.shader != null
			and not shield_mat.shader.code.is_empty())
	h.check("mat.dome_material_builds", dome_mat != null and dome_mat.shader != null
			and not dome_mat.shader.code.is_empty())
	if shield_mat == null or dome_mat == null:
		return
	_uniforms(h, "mat.shield", shield_mat)
	_uniforms(h, "mat.dome", dome_mat)
	h.check("mat.shader_declares_every_uniform",
			_declared(shield_mat.shader.code, MirrorShieldProfile.UNIFORMS),
			"a uniform the profile writes is missing from mirror_shield.gdshader")
	h.check("mat.params_match_the_profile",
			is_equal_approx(float(shield_mat.get_shader_parameter(&"core_alpha")),
					MirrorShieldProfile.CORE_ALPHA)
			and is_equal_approx(float(shield_mat.get_shader_parameter(&"rim_alpha")),
					MirrorShieldProfile.RIM_ALPHA)
			and is_equal_approx(float(shield_mat.get_shader_parameter(&"hex_gain")),
					MirrorShieldProfile.HEX_GAIN),
			"the material and MirrorShieldProfile disagree — one of them was edited alone")
	_alpha(h, "alpha.shield", float(shield_mat.get_shader_parameter(&"core_alpha")),
			float(shield_mat.get_shader_parameter(&"hex_gain")),
			float(shield_mat.get_shader_parameter(&"rim_alpha")))
	_alpha(h, "alpha.dome", float(dome_mat.get_shader_parameter(&"core_alpha")),
			float(dome_mat.get_shader_parameter(&"hex_gain")),
			float(dome_mat.get_shader_parameter(&"rim_alpha")))
	h.check("alpha.profile_mirror_agrees",
			is_equal_approx(MirrorShieldProfile.center_alpha(),
					MirrorShieldProfile.CORE_ALPHA * (1.0 + MirrorShieldProfile.HEX_GAIN))
			and is_equal_approx(MirrorShieldProfile.dome_center_alpha(),
					MirrorShieldProfile.DOME_CORE_ALPHA * (1.0 + MirrorShieldProfile.DOME_HEX_GAIN)))
	_hero_accent(h, shield_mat)


## Every uniform the profile writes must come back off the material: `set_shader_parameter` on a name
## the shader does not declare is silently dropped, and that is exactly how a "fix" would go missing.
static func _uniforms(h: DefenseTestHarness, tag: String, mat: ShaderMaterial) -> void:
	var missing: PackedStringArray = PackedStringArray()
	for name in MirrorShieldProfile.UNIFORMS:
		if mat.get_shader_parameter(name) == null:
			missing.append(String(name))
	h.check("%s.every_uniform_took" % tag, missing.is_empty(),
			"dropped: %s" % ", ".join(missing))


static func _declared(code: String, names: Array[StringName]) -> bool:
	for name in names:
		if not code.contains("uniform ") or code.find(String(name)) < 0:
			return false
	return true


## The interior ceiling is core * (1 + hex gain) — the brightest pixel the middle of the surface can
## produce — and the rim is the rim alpha. Both measured off the material.
static func _alpha(h: DefenseTestHarness, tag: String, core: float, hex: float, rim: float) -> void:
	var centre := core * (1.0 + hex)
	h.check("%s.center_alpha_at_most_%.2f" % [tag, CENTER_ALPHA_MAX], centre <= CENTER_ALPHA_MAX,
			"worst interior pixel %.3f — the hero has to stay visible through it" % centre)
	h.check("%s.rim_alpha_at_least_%.2f" % [tag, RIM_ALPHA_MIN], rim >= RIM_ALPHA_MIN,
			"rim %.3f — the edge is the whole read now" % rim)


## The colour is the hero's own accent, so the guard belongs to the mech instead of being a decal.
static func _hero_accent(h: DefenseTestHarness, mat: ShaderMaterial) -> void:
	var core: Color = mat.get_shader_parameter(&"core_color")
	var script := load(HERO_SHADE) as GDScript
	h.check("mat.hero_shade_script_loads", script != null, "cannot load " + HERO_SHADE)
	if script == null:
		return
	var constants := script.get_script_constant_map()
	h.check("mat.hero_accent_constant_exists", constants.has(&"ACCENT"))
	if not constants.has(&"ACCENT"):
		return
	var accent: Color = constants[&"ACCENT"]
	var d := absf(core.r - accent.r) + absf(core.g - accent.g) + absf(core.b - accent.b)
	h.check("mat.core_color_is_the_hero_accent", d <= 0.02,
			"shield %s vs hero3_shade ACCENT %s" % [str(core), str(accent)])


## --- size and shape ----------------------------------------------------------------------------

static func _form(h: DefenseTestHarness) -> void:
	var shield := h.system.shield
	h.check("form.shield_exists", shield != null)
	if shield == null:
		return
	var span := shield.panel_span()
	h.check("form.panel_is_chest_sized", span <= PANEL_SPAN_MAX and span >= 8.0,
			"%.1f m across — it has to cover the mech's front, not the screen" % span)
	h.check("form.panel_is_curved", shield.panel_bulge() >= 0.9,
			"bulge %.2f m — a flat plane is what the lead rejected" % shield.panel_bulge())
	h.check("form.panel_is_smaller_than_the_old_plate", span < 13.0,
			"the r6 plate was 13.0 m across")


## --- coming and going --------------------------------------------------------------------------

static func _fade(h: DefenseTestHarness) -> void:
	h.near("fade.in_is_0_08_s", MirrorShieldProfile.FADE_IN, 0.08, 0.001)
	h.near("fade.out_is_0_15_s", MirrorShieldProfile.FADE_OUT, 0.15, 0.001)
	var up := 0.0
	for _i in ceili(MirrorShieldProfile.FADE_IN * 120.0):
		up = MirrorShieldProfile.fade_step(up, true, 1.0 / 120.0)
	h.near("fade.step_reaches_1_in_fade_in", up, 1.0, 0.001)
	var down := 1.0
	for _i in ceili(MirrorShieldProfile.FADE_OUT * 120.0):
		down = MirrorShieldProfile.fade_step(down, false, 1.0 / 120.0)
	h.near("fade.step_reaches_0_in_fade_out", down, 0.0, 0.001)
	h.fresh()
	await h.step(0.05)
	h.check("fade.panel_starts_hidden", not h.system.shield.panel_visible())
	h.press(&"guard")
	await h.step(MirrorShieldProfile.FADE_IN + 0.04)
	h.near("fade.live_panel_fades_in", h.system.shield.fade(), 1.0, 0.02)
	h.check("fade.live_panel_is_visible", h.system.shield.panel_visible())
	h.release(&"guard")
	await h.step(DefenseTable.seconds(DefenseTable.MIN_GUARD_FRAMES)
			+ MirrorShieldProfile.FADE_OUT + 0.1)
	h.near("fade.live_panel_fades_out", h.system.shield.fade(), 0.0, 0.001)
	h.check("fade.live_panel_hides_after_the_fade", not h.system.shield.panel_visible(),
			"a panel that pops off mid-fade is the tile again")


## --- the block ripple --------------------------------------------------------------------------

static func _ripple(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.05)
	h.press(&"guard")
	await h.step(0.3)
	h.eq("ripple.state_is_blocking", h.system.hud_state()["state"], "BLOCKING")
	var shield := h.system.shield
	var hit := h.make_hit(6.0, 500.0)
	hit.position = shield.panel_origin() + Vector3(2.0, 0.0, 0.0)
	_fire(h, hit)
	h.check("ripple.hit_was_blocked", h.system.blocked_damage > 0.0,
			"blocked %.1f — the ripple test needs a real block" % h.system.blocked_damage)
	h.check("ripple.starts_at_the_hit_point", shield.ripple_uv().x > 0.3,
			"uv %s — the hit was 2 m to the panel's right" % str(shield.ripple_uv()))
	h.check("ripple.is_strong_at_impact", shield.ripple_strength() > 0.8,
			"strength %.2f" % shield.ripple_strength())
	## The uniform is written on the next tick, and its z is the ring's progress: > 0 means the
	## shader's ripple term is live, and x is where it started.
	await h.ticks(2)
	var u: Vector3 = shield.panel_material().get_shader_parameter(&"ripple")
	h.check("ripple.uniform_carries_the_origin", u.x > 0.3 and u.z > 0.0,
			"uniform %s" % str(u))
	## The lead's ceiling is 0.5 s of wall clock, so the wait is the LEAD's number and not the
	## profile's — a longer RIPPLE_TIME has to fail here rather than move the goalpost.
	await h.step(RIPPLE_DECAY_SECONDS)
	h.check("ripple.decays_to_zero_within_0_5_s", shield.ripple_strength() == 0.0,
			"strength %.3f after %.2f s (RIPPLE_TIME is %.2f)"
			% [shield.ripple_strength(), RIPPLE_DECAY_SECONDS, MirrorShieldProfile.RIPPLE_TIME])
	h.check("ripple.uniform_is_off_after",
			(shield.panel_material().get_shader_parameter(&"ripple") as Vector3) == Vector3.ZERO)
	h.release(&"guard")
	await h.step(0.4)


## --- the perfect-parry burst -------------------------------------------------------------------

static func _parry_burst(h: DefenseTestHarness) -> void:
	h.fresh()
	var attacker := h.add_attacker()
	await h.step(0.1)
	h.press(&"guard")
	await h.ticks(2)
	var shield := h.system.shield
	var consumed := _fire(h, h.make_hit(6.0, 900.0, attacker))
	h.check("parry.hit_was_parried", consumed)
	h.check("parry.panel_flashes", shield.flash() > 0.5, "flash %.2f" % shield.flash())
	## The ring must stay over the glow threshold (ART.md's HDR bloom) without every channel clipping
	## to white — the r6 capture shows what 2.2 did: a white donut with no gold left in it.
	var peak := maxf(DefenseTable.PERFECT_COLOR.r,
			maxf(DefenseTable.PERFECT_COLOR.g, DefenseTable.PERFECT_COLOR.b)) \
			* ShieldVisual.RING_ENERGY
	h.check("parry.ring_blooms_without_clipping", peak > 1.0 and peak < 1.6,
			"peak channel %.2f — over 1.0 blooms, over ~1.6 the gold is gone" % peak)
	h.eq("parry.shards_all_spawn", shield.shards_active(), MirrorShieldProfile.SHARD_COUNT)
	h.eq("parry.pool_is_preinstanced", shield.shard_pool(), MirrorShieldProfile.SHARD_COUNT)
	await h.step(SHARD_FREE_SECONDS)
	h.eq("parry.shards_freed_within_1_s", shield.shards_active(), 0)
	h.eq("parry.pool_did_not_grow", shield.shard_pool(), MirrorShieldProfile.SHARD_COUNT)
	h.release(&"guard")
	await h.step(0.4)


## --- the catch dome ----------------------------------------------------------------------------

static func _dome(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.05)
	var dome := h.system.dome
	h.check("dome.exists", dome != null)
	if dome == null:
		return
	h.check("dome.hidden_before_the_field_opens", not dome.is_showing())
	h.check("dome.radius_is_the_field_radius",
			absf(dome.radius() - DefenseTable.CATCH_RADIUS) < 0.2,
			"%.1f m vs CATCH_RADIUS %.1f" % [dome.radius(), DefenseTable.CATCH_RADIUS])
	h.check("dome.covers_the_orbit", dome.radius() > DefenseTable.CATCH_ORBIT_RADIUS + 1.0,
			"the rounds orbit at %.1f m" % DefenseTable.CATCH_ORBIT_RADIUS)
	h.press(&"guard")
	await h.step(DefenseTable.CATCH_HOLD + MirrorShieldProfile.FADE_IN + 0.05)
	h.check("dome.shows_while_catching", dome.is_showing())
	h.near("dome.fades_in", dome.fade(), 1.0, 0.02)
	var spin0 := dome.spin()
	await h.step(0.2)
	h.check("dome.hex_pattern_turns", absf(dome.spin() - spin0) > 0.05,
			"spin %.3f -> %.3f" % [spin0, dome.spin()])
	var panel_spin: float = h.system.shield.panel_material().get_shader_parameter(&"hex_spin")
	h.check("dome.is_distinct_from_the_panel", is_zero_approx(panel_spin)
			and not is_zero_approx(dome.spin()),
			"panel spin %.3f, dome spin %.3f" % [panel_spin, dome.spin()])
	h.check("dome.is_thinner_than_the_panel",
			float(dome.material().get_shader_parameter(&"core_alpha"))
					< MirrorShieldProfile.CORE_ALPHA,
			"dome core %.3f vs panel %.3f"
			% [float(dome.material().get_shader_parameter(&"core_alpha")),
			MirrorShieldProfile.CORE_ALPHA])
	for _i in 4:
		h.add_shot(9.0, 200.0)
	await h.step(0.3)
	var centre := h.player.global_position + Vector3.UP * DefenseTable.CATCH_ORBIT_HEIGHT
	var inside := 0
	for s in h.shots:
		if is_instance_valid(s) and (s.global_position - centre).length() <= dome.radius():
			inside += 1
	h.check("dome.caught_rounds_orbit_inside_it", inside >= 3,
			"%d of %d rounds inside the dome" % [inside, h.shots.size()])
	h.release(&"guard")
	await h.step(DefenseTable.seconds(DefenseTable.MIN_GUARD_FRAMES)
			+ MirrorShieldProfile.FADE_OUT + 0.1)
	h.check("dome.closes_when_the_guard_drops", not dome.is_showing() and dome.fade() == 0.0,
			"fade %.3f" % dome.fade())


## Runs a hit through every filter the rig player carries (CONTRACTS §5), the way the player's own
## damage pipeline does. True = something consumed it.
static func _fire(h: DefenseTestHarness, hit: HitInfo) -> bool:
	var consumed := false
	for f: Callable in h.player.filters:
		if f.is_valid():
			consumed = bool(f.call(hit)) or consumed
	return consumed
