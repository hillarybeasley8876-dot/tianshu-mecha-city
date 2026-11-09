class_name FpVfxSuite
extends RefCounted
## First-person VFX size checks (lead r5 item 1). The cockpit lens sits ~6 m from `muzzle_r`, where a
## muzzle visual sized for the 42 m third-person arm covers a third of the frame. The rule is one
## camera-mode path in WeaponContext, so these drive the real WeaponSystem with input actions and
## measure what the pools actually drew — the muzzle flash apart from the impact sparks the same
## pool draws at the target.

const FP_FLASH := 2.2 * WeaponContext.FP_SCALE   ## 0.594 m: the lead's "<= 0.6 m in first person"

static func run(h: WeaponTestHarness) -> void:
	h.check("fp.gatling_is_selected", h.system.current_weapon() == &"gatling",
			"weapon %s" % h.system.current_weapon())
	await _flash(h)
	await _rifle(h)
	await _salvo(h)
	_hint(h)


## One second of gatling fire in each camera mode; the flash peak must follow the mode, the impact
## sparks at the target must not.
static func _flash(h: WeaponTestHarness) -> void:
	var g := h.system.gatling
	var sparks := h.system.sparks
	h.clear_targets()
	h.add_target(Vector3(0.0, 11.5, -100.0), 24.0)
	h.aim_at(Vector3(0.0, 11.5, -100.0))
	h.aim.first_person = false
	g.reset_state()
	sparks.reset_peaks()
	var third := await _burst(h, 1.0)
	h.check("fp.flash_fired_in_third_person", third >= 9,
			"%d rounds in 1 s (0.3 s spin-up then 15/s)" % third)
	h.near("fp.flash_third_person_2_2m", sparks.flash_peak_m(), 2.2, 0.001)
	h.near("fp.impacts_draw_in_third_person", sparks.spark_peak_m(), 1.2, 0.001)
	h.aim.first_person = true
	sparks.reset_peaks()
	await _burst(h, 1.0)
	h.near("fp.flash_first_person_0_6m", sparks.flash_peak_m(), FP_FLASH, 0.001)
	h.check("fp.flash_first_person_under_0_6m", sparks.flash_peak_m() <= 0.6,
			"%.3f m" % sparks.flash_peak_m())
	h.check("fp.impacts_stay_full_size_in_first_person", sparks.spark_peak_m() >= 1.0,
			"impact sparks shrank to %.3f m" % sparks.spark_peak_m())
	h.aim.first_person = false
	sparks.reset_peaks()
	await _burst(h, 1.0)
	h.near("fp.flash_back_to_third_person_2_2m", sparks.flash_peak_m(), 2.2, 0.001)


static func _burst(h: WeaponTestHarness, seconds: float) -> int:
	var g := h.system.gatling
	var n0 := g.rounds_fired
	await h.hold(&"fire", seconds)
	return g.rounds_fired - n0


## The rifle's muzzle ring, shock ring and beam glow all sit at the same muzzle: a plain tap and a
## stage-2 release must shrink with the camera mode too.
static func _rifle(h: WeaponTestHarness) -> void:
	var beams := h.system.beams
	var t := h.system.rifle.tuning
	h.system.switch_weapon(-1)
	await h.step(0.5)
	h.check("fp.rifle_is_selected", h.system.current_weapon() == &"beam_rifle",
			"weapon %s" % h.system.current_weapon())
	h.clear_targets()
	h.add_target(Vector3(0.0, 11.5, -300.0), 24.0)
	h.aim_at(Vector3(0.0, 11.5, -300.0))
	h.aim.first_person = false
	h.system.rifle.reset_state()
	beams.reset_peaks()
	await h.tap(&"fire", 0.4)
	h.near("fp.rifle_ring_third_person", beams.ring_peak_m(), t.muzzle_ring_radius, 0.001)
	h.near("fp.rifle_glow_third_person", beams.glow_peak_m(), t.beam_glow_radius, 0.001)
	var muzzle := h.system.ctx.socket(&"muzzle_r")
	h.check("fp.rifle_beam_starts_at_the_muzzle_in_third_person",
			beams.last_beam_from().distance_to(muzzle) < 0.01,
			"%.2f m from the muzzle" % beams.last_beam_from().distance_to(muzzle))
	h.aim.first_person = true
	h.system.rifle.reset_state()
	beams.reset_peaks()
	await h.tap(&"fire", 0.4)
	h.near("fp.rifle_ring_first_person", beams.ring_peak_m(), t.muzzle_ring_radius * WeaponContext.FP_SCALE,
			0.001)
	h.near("fp.rifle_glow_first_person", beams.glow_peak_m(), t.beam_glow_radius * WeaponContext.FP_SCALE,
			0.001)
	h.check("fp.rifle_beam_starts_down_range_in_first_person",
			beams.last_beam_from().distance_to(muzzle) >= WeaponContext.FP_BEAM_START - 0.01,
			"%.2f m from the muzzle" % beams.last_beam_from().distance_to(muzzle))
	# stage 2: the 9.6 m ring and the 7 m glow are what whited the cockpit out
	h.system.rifle.reset_state()
	beams.reset_peaks()
	h.press(&"fire")
	await h.step(1.3)
	h.release(&"fire")
	await h.step(0.1)
	h.near("fp.rifle_stage2_ring_first_person", beams.ring_peak_m(),
			t.shock_ring_radius * WeaponContext.FP_SCALE, 0.001)
	h.near("fp.rifle_stage2_glow_first_person", beams.glow_peak_m(),
			t.stage2_glow_radius * WeaponContext.FP_SCALE, 0.001)
	h.aim.first_person = false
	h.system.rifle.reset_state()
	h.system.switch_weapon(1)
	await h.step(0.5)


## The Hailstorm rails are ~4 m from the cockpit lens: the launch dust puff and the flash light that
## go with them are what flooded the canopy (the movie caught it; the stills did not).
static func _salvo(h: WeaponTestHarness) -> void:
	var hs := h.system.hailstorm
	h.clear_targets()
	h.add_target(Vector3(0.0, 11.5, -120.0), 12.0)
	h.aim_at(Vector3(0.0, 11.5, -120.0))
	for fp: bool in [false, true]:
		h.aim.first_person = fp
		hs.reset_state()
		h.system.sparks.reset_peaks()
		h.system.beams.reset_peaks()
		h.press(&"missiles")
		await h.step(0.3)
		h.release(&"missiles")
		await h.step(0.2)
		var tag := "first_person" if fp else "third_person"
		var want := HailstormLauncher.PUFF_SIZE * (WeaponContext.FP_SCALE if fp else 1.0) * 2.0
		h.near("fp.launch_puff_%s" % tag, h.system.sparks.puff_peak_m(), want, 0.001)
		var light := 2.6 * (WeaponContext.FP_OPACITY if fp else 1.0)
		h.near("fp.launch_light_%s" % tag, h.system.beams.flash_peak_energy(), light, 0.001)
		await h.step(0.6)
	h.aim.first_person = false


## With no AimSystem the mode comes from camera-aim's signal instead (a component running without
## one: the range scene, the headless rig).
static func _hint(h: WeaponTestHarness) -> void:
	var ctx := h.system.ctx
	var aim := ctx.aim
	ctx.aim = null
	Events.camera_mode_changed.emit(true)
	h.check("fp.hint_takes_the_signal", ctx.fp_hint, "fp_hint stayed false")
	h.near("fp.hint_drives_the_size", ctx.fp_size(2.2), FP_FLASH, 0.001)
	h.near("fp.hint_drives_the_opacity", ctx.fp_alpha(), WeaponContext.FP_OPACITY, 0.001)
	Events.camera_mode_changed.emit(false)
	h.near("fp.hint_clears_on_toggle_back", ctx.fp_size(2.2), 2.2, 0.001)
	ctx.aim = aim
	h.check("fp.aim_wins_over_the_hint", not ctx.is_first_person(), "aim read disagrees")
	h.aim.first_person = true
	h.check("fp.aim_read_is_live", ctx.is_first_person(), "aim read disagrees")
	h.aim.first_person = false
