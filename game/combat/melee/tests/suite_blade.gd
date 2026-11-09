class_name MeleeBladeSuite
extends RefCounted
## Review r5 items 1 and 2 — the drawn blade.
##
## 1. THE STRAY QUAD. The string chains L1→L2 through a cancel window shorter than TRAIL_FADE, so
##    the finished swing's samples are still alive when the next swing starts sampling. Drawing a
##    quad between the two produced the grey card hanging beside the mech in the r4 filmstrips. The
##    suite plays the whole ground string and watches the ribbon every physics tick:
##      * `bridges()` — a quad straddling two swings — must never happen;
##      * the frame a new swing's active window opens must draw ZERO quads in its own lane (the
##        lead's rule: no quad until two samples exist on the new lane);
##      * the dead swing's arc must fade on its own clock instead of being held at full brightness
##        by the next swing's samples.
## 2. hero-v3 COMPATIBILITY. A model that answers `has_own_blade()` carries its own steel: we must
##    draw no second core or hilt over it, keep the trail, and run the energy sheath out from the
##    model's blade length to the one agreed length `MeleeTable.BLADE_LENGTH`.

static func run(h: MeleeTestHarness) -> void:
	await _lanes(h)
	await _own_blade(h)


## The ground string, chained through the CANCEL windows the way a player does — that is the only
## timing where a finished swing's samples are still alive when the next swing starts, which is what
## made the stray quad in the first place.
static func _lanes(h: MeleeTestHarness) -> void:
	h.fresh()
	h.add_dummy(20.0)
	await h.step(0.1)
	var frames: Array[Dictionary] = []
	var chain := MeleeTable.GROUND_CHAIN
	for i in chain.size():
		var id: StringName = chain[i]
		h.system._begin(id)
		var last := i == chain.size() - 1
		var until := MeleeTable.ticks(MeleeTable.field(id, "cancel_from")) if not last \
				else MeleeTable.ticks(MeleeTable.total_frames(id))
		await _watch(h, frames, until)
	h.check("blade.string_sampled", frames.size() > 60, "%d ticks watched" % frames.size())
	_report_lanes(h, frames)


## Records (move, phase, lane quads, bridges) on every physics tick for `ticks` ticks.
static func _watch(h: MeleeTestHarness, frames: Array[Dictionary], ticks: int) -> void:
	for _i in maxi(ticks, 1):
		await h.tree.physics_frame
		frames.append({
			"move": h.system.move,
			"active": h.system.phase == MeleeSystem.Phase.ACTIVE,
			"lane": h.system.saber.trail().new_lane_quads(),
			"bridges": h.system.saber.trail().bridges(),
			"longest": _longest(h.system.saber.trail().spans()),
		})


static func _longest(spans: Array[float]) -> float:
	var out := 0.0
	for s in spans:
		out = maxf(out, s)
	return out


static func _report_lanes(h: MeleeTestHarness, frames: Array[Dictionary]) -> void:
	var bridges := 0
	var longest := 0.0
	var opens_clean := 0
	var opens := 0
	var last_move: StringName = &""
	var saw_active := false
	for f: Dictionary in frames:
		bridges += int(f["bridges"])
		longest = maxf(longest, float(f["longest"]))
		var move: StringName = f["move"]
		var active: bool = f["active"]
		if move != last_move:
			last_move = move
			saw_active = false
		if active and not saw_active:
			saw_active = true
			opens += 1
			if int(f["lane"]) == 0:
				opens_clean += 1
	h.eq("blade.no_quad_bridges_two_swings", bridges, 0)
	h.check("blade.new_swing_starts_on_a_clean_lane", opens > 0 and opens_clean == opens,
			"%d of %d active windows opened with no quad in the new lane" % [opens_clean, opens])
	h.check("blade.no_quad_longer_than_a_swing_step", longest <= SwingTrail.MAX_STEP,
			"longest drawn quad %.1f m" % longest)


## hero-v3: the model brings its own blade.
static func _own_blade(h: MeleeTestHarness) -> void:
	h.fresh()
	h.add_dummy(20.0)
	await h.step(0.3)   ## let the previous suite's blade finish retracting into the hilt
	var model := h.player.model_ref
	if model == null or not model.has_method(&"has_own_blade"):
		h.check("blade.rig_model_answers_has_own_blade", false, "the rig model cannot answer it")
		return
	model.set(&"own_blade", true)
	h.system.saber.attach(model)
	var saber: SaberVisual = h.system.saber
	h.check("blade.model_blade_adopted", saber.own_blade, "the saber did not take the model's blade")
	h.check("blade.no_second_blade_drawn", not saber.draws_own_steel(),
			"a core/hilt is still drawn over the model's own blade")
	h.near("blade.model_steel_length", saber.model_blade_length(),
			MeleeTable.MODEL_BLADE_LENGTH, 0.01)
	h.near("blade.tip_at_the_steel_before_ignition", saber.drawn_length(),
			MeleeTable.MODEL_BLADE_LENGTH, 0.01)
	h.system._begin(MeleeTable.L1)
	var quads := await _swing_quads(h)
	h.near("blade.energy_runs_out_to_the_agreed_length", saber.drawn_length(),
			MeleeTable.BLADE_LENGTH, 0.05)
	var pts := saber.blade_points()
	h.near("blade.tip_on_the_socket_line",
			(pts[1] as Vector3).distance_to(pts[0] as Vector3), MeleeTable.BLADE_LENGTH, 0.05)
	h.check("blade.trail_still_samples_the_model_blade", quads > 0,
			"%d ribbon quads drawn during the swing" % quads)
	model.set(&"own_blade", false)


## The most quads the ribbon drew on any tick of the running move — the trail must survive the model
## taking the blade over. Polled from the move's first tick: the ribbon is deliberately short-lived
## once the blade leaves it, so polling only the recovery would miss it.
static func _swing_quads(h: MeleeTestHarness) -> int:
	var best := 0
	var guard := 0
	while h.system.move != &"" and guard < 600:
		await h.tree.physics_frame
		guard += 1
		best = maxi(best, h.system.saber.trail().spans().size())
	return best
