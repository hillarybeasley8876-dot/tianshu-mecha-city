class_name FpNearSuite
extends RefCounted
## Lead r6 item 1 — the orange slabs in the first-person view, identified and gated headless.
##
## The r5 fix scaled the visuals anchored at the muzzle, but everything that keeps flying after the
## shot has left the barrel was still drawn at third-person size a few metres from the cockpit lens:
## a spent casing is a 1.25 m orange box and the ejection port is ~6 m from the eye. This suite drives
## a real first-person gatling burst and, every few ticks, lists every DRAWN primitive within 15 m of
## the lens (`FpNearScan`) — owner, shape, distance, size, how much of the frame it covers, colour.
## The gate is a filter over that list, so it cannot be satisfied by hiding the symptom.
##
## Third person is the control: the same burst must still draw 1.25 m casings and a 2.2 m flash.

const RADIUS := 15.0        ## the lead's "list everything within 15 m of the lens"
const GATE_RADIUS := 8.0    ## the lead's gate radius
const SLAB_MAX := 0.5       ## m: the lead's "no orange quad larger than 0.5 m"
const HARD_MAX := 0.6       ## m: the r5 muzzle flash the lead already accepted, as a general ceiling
const COVER_MAX := 16.0     ## deg across the 62 deg frame: nothing orange may own a quarter of it
const SCAN_EVERY := 1       ## the gate is "on any tick", so every physics tick is scanned
const BURST := 1.2          ## s of gatling fire per pass (0.3 s spin-up, then 15 rounds/s)
const SALVO_WATCH := 1.6    ## s of missile circus watched after the launch


static func run(h: WeaponTestHarness) -> void:
	_rig(h)
	await _gatling(h)
	await _salvo(h)


## The gate is only worth anything if the rig's lens really is ~6 m from the ejection port, and the
## two pools restate WeaponContext.FP_SCALE rather than importing it across a cyclic class reference.
static func _rig(h: WeaponTestHarness) -> void:
	var ctx := h.system.ctx
	var lens := ctx.lens()
	var muzzle := ctx.socket(&"muzzle_r")
	h.near("fp_near.lens_is_about_6m_from_the_muzzle", lens.distance_to(muzzle), 6.0, 1.0)
	h.check("fp_near.lens_follows_the_aim_camera",
			h.aim.camera() != null and lens.distance_to(h.aim.camera().global_position) < 0.01,
			"lens %.1f m from the rig camera" % lens.distance_to(
					h.aim.camera().global_position if h.aim.camera() != null else Vector3.ZERO))
	h.near("fp_near.fp_scale_agrees_with_the_context", CasingPool.FP_SCALE,
			WeaponContext.FP_SCALE, 0.0001)
	h.near("fp_near.missile_fp_scale_agrees_with_the_context", MissileVisuals.FP_SCALE,
			WeaponContext.FP_SCALE, 0.0001)
	h.check("fp_near.casing_box_is_1_25m_in_third_person",
			absf(CasingPool.SIZE.z - 1.25) < 0.001, "box is %.2f m long" % CasingPool.SIZE.z)


## A first-person gatling burst: the identification scan and the gate.
static func _gatling(h: WeaponTestHarness) -> void:
	h.clear_targets()
	h.add_target(Vector3(0.0, 11.5, -100.0), 24.0)
	h.aim_at(Vector3(0.0, 11.5, -100.0))
	if h.system.current_weapon() != &"gatling":
		h.system.switch_weapon(1)
		await h.step(0.5)
	h.aim.first_person = true
	h.system.gatling.reset_state()
	h.system.missiles.clear()
	await h.step(0.1)
	var acc := _blank()
	h.press(&"fire")
	await _watch(h, acc, BURST)
	h.release(&"fire")
	h.check("fp_near.scan_saw_geometry", int(acc["hits"]) > 0,
			"the scan found nothing within %.0f m — it is vacuous" % RADIUS)
	h.check("fp_near.burst_really_fired", h.system.gatling.rounds_fired > 0,
			"no rounds left the barrel")
	_gate(h, acc, "gatling")
	h.near("fp_near.casings_are_cockpit_sized", h.system.casings.drawn_length(),
			CasingPool.SIZE.z * WeaponContext.FP_SCALE, 0.001)
	h.check("fp_near.casings_never_need_the_near_hide", int(acc["hidden"]) == 0,
			"%d casings fell inside %.1f m of the lens — the throw is not clearing the canopy"
			% [int(acc["hidden"]), CasingPool.FP_HIDE])
	h.aim.first_person = false


## The same gate over the missile circus: the shoulder rails are closer to the lens than the muzzle
## is, and an engine flare is a 3.6 m orange billboard.
static func _salvo(h: WeaponTestHarness) -> void:
	h.clear_targets()
	h.add_target(Vector3(0.0, 11.5, -140.0), 16.0)
	h.aim_at(Vector3(0.0, 11.5, -140.0))
	h.aim.first_person = true
	h.system.hailstorm.reset_state()
	h.system.missiles.clear()
	h.system.missiles.visuals.reset_peaks()
	await h.step(0.1)
	var acc := _blank()
	h.press(&"missiles")
	await h.step(0.35)
	h.release(&"missiles")
	await _watch(h, acc, SALVO_WATCH)
	h.check("fp_near.salvo_really_launched", h.system.missiles.active_count() > 0
			or h.system.hailstorm.salvos > 0, "no missiles left the rails")
	_gate(h, acc, "salvo")
	h.aim.first_person = false


## The two gates, plus the identification table: the worst frame each pool ever put inside 15 m of
## the lens, over the whole pass.
static func _gate(h: WeaponTestHarness, acc: Dictionary, tag: String) -> void:
	var slab: Dictionary = acc["slab"]
	var hard: Dictionary = acc["hard"]
	var cover: Dictionary = acc["cover"]
	h.check("fp_near.%s_no_orange_slab_within_8m" % tag, slab.is_empty(),
			"" if slab.is_empty() else FpNearScan.row(slab))
	h.check("fp_near.%s_no_hard_orange_primitive_over_0_6m" % tag, hard.is_empty(),
			"" if hard.is_empty() else FpNearScan.row(hard))
	h.check("fp_near.%s_no_orange_primitive_over_16deg_wide" % tag, cover.is_empty(),
			"" if cover.is_empty() else FpNearScan.row(cover))
	var seen: Dictionary = acc["seen"]
	var rows: Array[Dictionary] = []
	for key: String in seen:
		rows.append(seen[key])
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["dist"]) < float(b["dist"]))
	print("NEARSCAN %s ticks=%d hits=%d, worst frame each pool drew inside %.0f m:\n%s"
			% [tag, int(acc["ticks"]), int(acc["hits"]), RADIUS, FpNearScan.table(rows)])


static func _blank() -> Dictionary:
	return {"ticks": 0, "hits": 0, "slab": {}, "hard": {}, "cover": {}, "seen": {}, "hidden": 0}


## Advance `seconds` of physics, scanning the near-lens geometry every SCAN_EVERY ticks. Keeps the
## worst slab and the worst oversized orange primitive for the gates, and the worst frame every pool
## drew for the identification table.
static func _watch(h: WeaponTestHarness, acc: Dictionary, seconds: float) -> void:
	var ctx := h.system.ctx
	# The MultiMesh pools cannot be read back headless, so they record what they write while we watch.
	var pools: Array[Node] = [h.system.casings, h.system.bullets, h.system.missiles.visuals]
	for p in pools:
		p.set(&"recording", true)
	var frames := maxi(int(round(seconds / WeaponTestHarness.STEP)), 1)
	var seen: Dictionary = acc["seen"]
	for i in frames:
		for p in pools:
			p.call(&"begin_record")
		await h.tree.physics_frame
		if i % SCAN_EVERY != 0:
			continue
		acc["ticks"] = int(acc["ticks"]) + 1
		acc["hidden"] = int(acc["hidden"]) + h.system.casings.hidden_near
		var hits := FpNearScan.scan(h.root, ctx.lens(), RADIUS, ctx.model)
		acc["hits"] = int(acc["hits"]) + hits.size()
		for hit in hits:
			var key := String(hit["group"])
			seen[key] = _worst_looking(hit, seen.get(key, {}) as Dictionary)
		var slabs := FpNearScan.slabs(hits, GATE_RADIUS, SLAB_MAX)
		if not slabs.is_empty():
			acc["slab"] = _biggest(slabs, acc["slab"] as Dictionary)
		var hard := FpNearScan.hard_over(hits, GATE_RADIUS, HARD_MAX)
		if not hard.is_empty():
			acc["hard"] = _biggest(hard, acc["hard"] as Dictionary)
		var cover := FpNearScan.thick_over(hits, GATE_RADIUS, COVER_MAX)
		if not cover.is_empty():
			acc["cover"] = _biggest(cover, acc["cover"] as Dictionary)
	for p in pools:
		p.set(&"recording", false)


## The largest primitive of a set, kept across ticks — the gate accumulators are already filtered to
## the gate radius, so raw size is the right comparison there.
static func _biggest(hits: Array[Dictionary], best: Dictionary) -> Dictionary:
	var out := best
	for hit in hits:
		if out.is_empty() or float(hit["long_m"]) > float(out["long_m"]):
			out = hit
	return out


## The frame in which a pool looked BIGGEST from the lens: apparent size, not raw metres, so the
## identification table names the casing that was 6 m away rather than the one that had tumbled
## widest by the time it was 10 m out.
static func _worst_looking(hit: Dictionary, best: Dictionary) -> Dictionary:
	if best.is_empty():
		return hit
	var a := float(hit["long_m"]) / maxf(float(hit["dist"]), 0.01)
	var b := float(best["long_m"]) / maxf(float(best["dist"]), 0.01)
	return hit if a > b else best


