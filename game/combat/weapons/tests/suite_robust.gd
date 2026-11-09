class_name WeaponRobustSuite
extends RefCounted
## Regression checks for the numeric-robustness audit (reviews/weapons-audit.md, 2026-11-02):
##
##   1. the pooled visuals are world-space even though they hang under a moving mech
##   2. painting the Hailstorm at nothing banks no lock debt
##   3. the gatling's heat / jam / Superheated clocks run while it is holstered
##   4. a ring with a zero lifetime is refused, and an afterglow outlives its beam
##   5. a fresh missile trail draws no smoke for samples it never wrote
##
## The rig is left where the other suites expect it (origin, rifle, everything reset).

static func run(h: WeaponTestHarness) -> void:
	await _world_space_pools(h)
	await _holstered_gatling(h)
	await _lock_debt(h)
	await _beam_edges(h)
	await _trail_edges(h)
	h.player.debug_teleport([0.0, 0.0, 0.0], 0.0)
	h.release_all()
	h.system.reset()
	await h.step(0.2)


## Audit #1: with the mech away from the origin every tracer, casing, beam and trail used to be
## drawn at `player_xf * world_pos`.
static func _world_space_pools(h: WeaponTestHarness) -> void:
	var base := Vector3(140.0, 0.0, -60.0)
	h.player.debug_teleport([base.x, base.y, base.z], 25.0)
	await h.step(0.1)
	var names: Array[String] = ["Beams", "Sparks", "Casings", "Bullets", "Missiles"]
	var all_top := true
	for nm in names:
		var n := h.system.get_node_or_null(NodePath(nm)) as Node3D
		var ok := n != null and n.top_level and n.global_transform.is_equal_approx(
				Transform3D.IDENTITY)
		all_top = all_top and ok
		h.check("robust.%s_is_world_space" % nm.to_lower(), ok,
				"top_level %s, xf %s" % [n.top_level if n != null else "?", n.global_transform
				if n != null else Transform3D.IDENTITY])
	h.check("robust.all_pools_world_space", all_top, "the mech sits at %s" % base)
	var forward := -h.player.global_transform.basis.z
	var aim_point := base + Vector3(0.0, 11.5, 0.0) + forward * 260.0
	h.clear_targets()
	h.aim_at(aim_point)
	await h.step(0.1)
	var muzzle: Vector3 = h.system.ctx.socket(&"muzzle_r")
	var dir: Vector3 = h.system.ctx.aim_dir_from(muzzle)
	await h.tap(&"fire", 0.02)
	var beam := _live_beam(h.system.beams)
	h.check("robust.beam_drawn_in_world_space", beam != null and _off_line(beam.global_position,
			muzzle, dir) < 3.0, "beam at %s, muzzle %s" % [beam.global_position if beam != null
			else Vector3.ZERO, muzzle])
	await _tracer_check(h)


## One gatling tracer MultiMesh must draw in world space while the mech is displaced. The instance
## transforms themselves are unreadable headless (MultiMesh reads back through the rendering server),
## so the invariant checked is the one that makes them world positions: an identity node transform.
static func _tracer_check(h: WeaponTestHarness) -> void:
	h.system.switch_weapon(1)
	await h.step(0.4)
	h.system.gatling.reset_state()
	await h.hold(&"fire", 0.5)
	var mmi := _multimesh(h.system.bullets)
	var xf := mmi.global_transform if mmi != null else Transform3D()
	h.check("robust.tracer_multimesh_is_world_space", mmi != null
			and xf.is_equal_approx(Transform3D.IDENTITY),
			"%d live rounds, tracer node at %s (mech at %s)" % [h.system.bullets.active_count(),
			xf.origin, h.player.global_position])
	h.check("robust.rounds_left_the_displaced_mech", h.system.bullets.active_count() > 0
			and h.player.global_position.length() > 100.0,
			"%d rounds in flight from a mech at %s" % [h.system.bullets.active_count(),
			h.player.global_position])
	h.system.switch_weapon(-1)
	await h.step(0.4)


## Distance from `p` to the ray `origin + dir * t` (dir is unit length).
static func _off_line(p: Vector3, origin: Vector3, dir: Vector3) -> float:
	var v := p - origin
	return (v - dir * v.dot(dir)).length()


static func _live_beam(pool: BeamPool) -> MeshInstance3D:
	for i in BeamPool.CAPACITY:
		var n := pool.get_node_or_null(NodePath("Beam%d" % i)) as MeshInstance3D
		if n != null and n.visible:
			return n
	return null


static func _multimesh(from: Node) -> MultiMeshInstance3D:
	for c in from.get_children():
		if c is MultiMeshInstance3D:
			return c as MultiMeshInstance3D
	return null


## Audit #3: the gauge belongs to the mech, not to the trigger. Before the fix the heat arc, the
## jam clock and Superheated all froze for as long as the rifle was out.
static func _holstered_gatling(h: WeaponTestHarness) -> void:
	var g := h.system.gatling
	h.system.switch_weapon(1)
	await h.step(0.4)
	g.reset_state()
	h.clear_targets()
	h.aim_at(Vector3(0.0, 11.5, -120.0))
	await h.hold(&"fire", 2.5)
	var hot := g.heat
	h.check("robust.gatling_heated_before_swap", hot > 20.0, "heat %.1f" % hot)
	g.superheated_left = g.tuning.superheated_time
	h.system.switch_weapon(-1)
	await h.step(0.45)
	h.check("robust.rifle_out", h.system.current_weapon() == PierceLightRifle.ID, "weapon %s"
			% h.system.current_weapon())
	var heat0 := g.heat
	await h.step(1.2)
	h.check("robust.heat_cools_while_holstered", g.heat <= heat0 - 15.0,
			"heat %.1f -> %.1f over 1.2 s holstered" % [heat0, g.heat])
	h.check("robust.superheated_expires_while_holstered", g.superheated_left < 3.0,
			"superheated_left %.2f" % g.superheated_left)
	# A VENT sweep nobody can answer while holstered must still resolve (silently) into a jam.
	g.reset_state()
	g.heat = 100.0
	g.state = ThunderSpindleGatling.State.VENT
	await h.step(g.tuning.vent_sweep + 0.1)
	h.check("robust.holstered_vent_resolves", g.state != ThunderSpindleGatling.State.VENT,
			"state %d after a %.1f s sweep" % [g.state, g.tuning.vent_sweep])
	h.check("robust.holstered_vent_jams", g.state == ThunderSpindleGatling.State.JAM,
			"state %d" % g.state)
	var jam0 := g.state
	await h.step(g.tuning.jam_time + 0.1)
	h.check("robust.holstered_jam_clears", jam0 == ThunderSpindleGatling.State.JAM
			and g.state == ThunderSpindleGatling.State.READY, "state %d" % g.state)
	g.reset_state()


## Audit #2: 1.2 s of painting at nothing used to bank 1.2 s of lock debt and pay it out as a burst
## the moment a target entered the box.
static func _lock_debt(h: WeaponTestHarness) -> void:
	var hs := h.system.hailstorm
	hs.reset_state()
	h.system.missiles.clear()
	h.clear_targets()
	h.aim_at(Vector3(0.0, 11.5, -60.0))
	var salvos0 := hs.salvos
	h.press(&"missiles")
	await h.step(1.2)
	h.check("robust.empty_paint_banks_nothing", hs.locks.is_empty() and hs.salvos == salvos0,
			"%d locks, %d salvos with nothing in the box" % [hs.locks.size(), hs.salvos])
	for i in 3:
		h.add_target(Vector3(float(i - 1) * 12.0, 11.5, -60.0), 8.0)
	await h.step(2.0 * WeaponTestHarness.STEP)
	var first := hs.locks.size()
	h.check("robust.locks_do_not_burst", first <= 1 and hs.salvos == salvos0,
			"%d locks and %d salvos in the first 2 ticks after the sweep" % [first,
			hs.salvos - salvos0])
	await h.step(0.45)
	h.check("robust.locks_stay_paced", hs.locks.size() <= 6 and hs.locks.size() >= 3,
			"%d locks 0.45 s later (10/s)" % hs.locks.size())
	h.release(&"missiles")
	await h.step(0.1)


## Audit #4/#5: a zero-lifetime ring used to be made visible and then never hidden, because the fade
## returns early on a countdown that starts at zero. Audit #6: the After layer is a child of the core,
## so hiding the core at 0.14 s also killed the 0.4 s afterglow.
static func _beam_edges(h: WeaponTestHarness) -> void:
	var pool := h.system.beams
	var refused := pool.ring(Vector3(0.0, 11.5, -20.0), Vector3.UP, Color.WHITE, 6.0, 0.0)
	h.check("robust.zero_life_ring_refused", refused == -1, "slot %d" % refused)
	var stuck := 0
	for i in BeamPool.CAPACITY:
		var r := pool.get_node_or_null(NodePath("Ring%d" % i)) as MeshInstance3D
		if r != null and r.visible:
			stuck += 1
	h.check("robust.no_ring_left_visible", stuck == 0, "%d rings visible" % stuck)
	var slot := pool.beam(Vector3(0.0, 11.5, 0.0), Vector3(0.0, 11.5, -120.0), 1.0, 3.0,
			Color.WHITE, Color(0.2, 0.9, 1.0), 0.14, 0.4)
	h.check("robust.charged_beam_takes_a_slot", slot >= 0, "slot %d" % slot)
	if slot < 0:
		return
	var node := pool.get_node_or_null(NodePath("Beam%d" % slot)) as MeshInstance3D
	await h.step(0.22)
	h.check("robust.afterglow_outlives_the_beam", node != null and node.visible,
			"beam visible %s at 0.22 s (life 0.14 s, afterglow 0.4 s)" % (node.visible
			if node != null else false))
	var reused := pool.beam(Vector3(0.0, 11.5, 0.0), Vector3(0.0, 11.5, -60.0), 1.0, 3.0,
			Color.WHITE, Color(0.2, 0.9, 1.0), 0.14, 0.0)
	h.check("robust.afterglow_slot_not_reused", reused != slot,
			"slot %d handed out again while its afterglow was fading" % reused)
	await h.step(0.45)
	h.check("robust.afterglow_hides_when_done", node != null and not node.visible,
			"beam still visible after the afterglow aged out")


## Audit #7: the 19 history slots a fresh missile never wrote used to render as smoke at the pool
## origin for the first SMOKE_LIFE seconds of world time.
static func _trail_edges(h: WeaponTestHarness) -> void:
	var vis := h.system.missiles.visuals
	vis.clear()
	vis.begin(0.05)   # world clock barely started: _now < SMOKE_LIFE
	vis.launch(0, Vector3(0.0, 30.0, -40.0))
	vis.body(0, Vector3(0.0, 30.0, -40.0), Vector3.FORWARD)
	h.check("robust.fresh_trail_draws_one_smoke_puff", vis.live_samples(0) == 1,
			"%d of %d history slots still young enough to draw (want 1)"
			% [vis.live_samples(0), MissileVisuals.SAMPLES])
	vis.begin(MissileVisuals.SAMPLE_DT * 2.0)
	vis.sample(0, Vector3(0.0, 30.0, -45.0))
	h.check("robust.written_samples_age_in", vis.live_samples(0) == 2,
			"%d young slots after a second sample" % vis.live_samples(0))
	vis.clear()
	h.check("robust.clear_ages_every_sample_out", vis.live_samples(0) == 0,
			"%d young slots after clear()" % vis.live_samples(0))
