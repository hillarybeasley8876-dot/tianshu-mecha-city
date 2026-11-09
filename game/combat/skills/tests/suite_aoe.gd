class_name SkillAoeSuite
extends RefCounted
## S6 Shockcore Burst and S7 Undertow Well: the radial falloff, the line-of-sight gate, the enemy-shot
## deletion, the field's pull / slow / prime, and the COLLAPSE detonation every other unit reaches
## through the `&"prime_detonators"` group.

static func run(h: SkillTestHarness) -> void:
	await _burst_frames(h)
	await _burst_falloff(h)
	await _burst_deletes_shots(h)
	await _well_field(h)
	await _well_targeting(h)
	await _collapse(h)


# --- S6 Shockcore Burst --------------------------------------------------------------------------

## 18 f of startup with super armour, then the damage lands on the first active frame.
static func _burst_frames(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var t := h.system.tuning
	var foe := h.add_enemy(Vector3(0.0, 0.0, -20.0))
	foe.hp = 1e9
	foe.hp_max = 1e9
	await h.step(0.05)
	h.check("burst.fires", h.system.try_burst(), "begin() refused")
	h.check("burst.super_armour_in_startup", h.system.burst.is_super_armoured(), "no super armour")
	await h.step(t.burst_startup * 0.6)
	h.near("burst.no_damage_yet", foe.damage_taken, 0.0, 0.01)
	h.check("burst.still_arming", h.system.burst.is_super_armoured(), "left the startup early")
	await h.step(t.burst_startup * 0.6)
	h.check("burst.damage_landed", foe.damage_taken > 0.0, "nothing landed after the startup")
	h.check("burst.super_armour_ended", not h.system.burst.is_super_armoured(),
			"still armoured in the active window")
	await h.step(t.burst_active + t.burst_recovery + 0.05)
	h.check("burst.returns_to_idle", not h.system.burst.is_busy(), "never recovered")


## 1,800 inside 12 m falling to 600 at the 32 m rim, and a wall blocks it entirely.
static func _burst_falloff(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var t := h.system.tuning
	var core := h.add_target(Vector3(0.0, 4.0, -6.0))  # inside the 12 m core
	var edge := h.add_target(Vector3(0.0, 0.0, -30.0))  # near the 32 m rim
	var outside := h.add_target(Vector3(0.0, 0.0, -60.0))
	await h.step(0.05)
	h.system.try_burst()
	await h.step(t.burst_startup + 0.05)
	h.near("burst.core_damage", core.damage_taken, t.burst_damage, 1.0)
	h.check("burst.edge_between", edge.damage_taken > t.burst_edge_damage * 0.9 \
			and edge.damage_taken < t.burst_damage,
			"edge took %.0f (core %.0f, rim %.0f)" % [edge.damage_taken, t.burst_damage,
			t.burst_edge_damage])
	h.near("burst.outside_untouched", outside.damage_taken, 0.0, 0.01)
	h.check("burst.victims_counted", h.system.burst.victims() == 2,
			"%d victims" % h.system.burst.victims())
	h.near("burst.core_at_rim", t.falloff(t.burst_radius - 0.01, t.burst_radius, t.burst_core,
			t.burst_damage, t.burst_edge_damage), t.burst_edge_damage, 1.0)
	h.near("burst.zero_past_rim", t.falloff(t.burst_radius + 1.0, t.burst_radius, t.burst_core,
			t.burst_damage, t.burst_edge_damage), 0.0, 0.001)

	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var hidden := h.add_target(Vector3(0.0, 0.0, -20.0))
	h.add_wall(Vector3(0.0, 12.0, -12.0), Vector3(60.0, 40.0, 3.0))
	await h.step(0.05)
	h.system.try_burst()
	await h.step(t.burst_startup + 0.05)
	h.near("burst.wall_blocks", hidden.damage_taken, 0.0, 0.01)


## Enemy shots inside the radius are deleted on the active frame (Assault Armour [AC-AA]).
static func _burst_deletes_shots(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var t := h.system.tuning
	var shooter := h.add_enemy(Vector3(0.0, 0.0, -40.0))
	var attack := EnemyAttack.new()
	attack.id = &"test_bolt"
	attack.damage = 100.0
	attack.projectile_speed = 8.0     # slow, so it is still inside the radius when the burst lands
	attack.blast_radius = 0.0
	var shot := EnemyProjectilePool.spawn(h.root, Vector3(0.0, 8.0, -18.0),
			Vector3(0.0, 8.0, -40.0), attack, shooter)
	h.check("burst.shot_spawned", shot != null and shot.is_active(), "no shot to delete")
	await h.step(0.05)
	h.system.try_burst()
	await h.step(t.burst_startup + 0.05)
	h.check("burst.shot_deleted", shot == null or not shot.is_active(), "the shot survived")
	h.check("burst.deletion_counted", h.system.burst.shots_deleted() >= 1,
			"%d deleted" % h.system.burst.shots_deleted())


# --- S7 Undertow Well ----------------------------------------------------------------------------

## The field primes everything inside it, slows the heavies and pulls the light ones in. Both bodies
## stand clear of the throw corridor (x = 0), so this measures the FIELD and not the new arm-on-body
## rule that `_well_targeting` covers.
static func _well_field(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var t := h.system.tuning
	var light := h.add_target(Vector3(18.0, 0.0, -80.0))
	var heavy := h.add_target(Vector3(-14.0, 0.0, -95.0), true)
	heavy.status.configure({"stability": 2600.0})
	await h.step(0.05)
	h.aim.point = Vector3(0.0, 0.0, -80.0)
	h.check("well.fires", h.system.try_well(), "begin() refused")
	await h.step(t.well_arm_time + 0.3)
	h.check("well.armed", h.system.well.is_active(), "never armed")
	h.near("well.full_duration_on_arming", h.system.well.field_left(),
			t.well_field - 0.4, 0.45)
	h.check("well.light_primed", light.status.is_primed(), "the swarmer was not primed")
	h.check("well.heavy_primed", heavy.status.is_primed(), "the brute was not primed")
	h.near("well.heavy_slowed", heavy.status.slow_factor, t.well_slow_heavy, 0.001)
	# the field centre is on the corridor at x = 0, so a Swarmer at x = 18 is dragged inward
	h.check("well.light_pulled", light.global_position.x < 18.0,
			"the swarmer is still at x %.1f" % light.global_position.x)
	h.check("well.field_running", h.system.well.field_left() > 0.0, "the field already ended")
	await h.step(t.well_field)
	h.check("well.field_ends", not h.system.well.is_active(), "outlived its 3.5 s")


## r4 item 2: the well must land on the LOCKED actor (the reticle ray runs metres off a locked target,
## so aiming by the crosshair put the field 50 m past the body it was meant to prime), and with no lock
## a core that meets a body arms on the deck under it instead of flying through to the street beyond.
static func _well_targeting(h: SkillTestHarness) -> void:
	var t := h.system.tuning
	# (a) hard lock 42 m out, reticle 110 m BEHIND it: the field must still land on the target
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var locked := h.add_target(Vector3(0.0, 0.0, -42.0), true)
	await h.step(0.05)
	h.aim.locked = locked
	h.aim.point = Vector3(0.0, 0.0, -152.0)
	h.check("well.lock_throws", h.system.try_well(), "begin() refused with a lock")
	await h.step(t.well_arm_time + 0.4)
	h.check("well.lock_armed", h.system.well.is_active(), "never armed")
	var d_lock := _flat(h.system.well.centre(), locked.global_position)
	h.check("well.lock_lands_on_target", d_lock <= t.well_radius,
			"armed %.1f m from the locked body, field radius %.0f m" % [d_lock, t.well_radius])
	h.check("well.lock_primes_target", locked.status.is_primed(),
			"the locked body was never primed")

	# (b) no lock, reticle on the body itself
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var aimed := h.add_target(Vector3(0.0, 0.0, -42.0), true)
	await h.step(0.05)
	h.aim.point = Vector3(0.0, 3.0, -42.0)
	h.check("well.reticle_throws", h.system.try_well(), "begin() refused with no lock")
	await h.step(t.well_arm_time + 0.4)
	h.check("well.reticle_armed", h.system.well.is_active(), "never armed")
	var d_aim := _flat(h.system.well.centre(), aimed.global_position)
	h.check("well.reticle_lands_on_body", d_aim <= t.well_radius,
			"armed %.1f m from the body under the reticle" % d_aim)
	h.check("well.reticle_primes_target", aimed.status.is_primed(),
			"the body under the reticle was never primed")
	h.check("well.arms_on_the_deck", absf(h.system.well.centre().y) < 2.0,
			"armed at y %.1f, not on the ground under the body" % h.system.well.centre().y)

	# (c) no lock, reticle on open ground with a body standing in the flight path
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var in_path := h.add_target(Vector3(0.0, 0.0, -60.0), true)
	await h.step(0.05)
	h.aim.point = Vector3(0.0, 0.0, -95.0)
	h.check("well.path_throws", h.system.try_well(), "begin() refused")
	await h.step(t.well_arm_time + 0.4)
	var d_path := _flat(h.system.well.centre(), in_path.global_position)
	h.check("well.body_in_path_arms_on_it", d_path <= t.well_radius,
			"the core flew through the body and armed %.1f m past it" % d_path)
	h.check("well.body_in_path_primed", in_path.status.is_primed(),
			"the body in the flight path was never primed")


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A detonator reaching the `&"prime_detonators"` group resolves every primed enemy in range.
static func _collapse(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var t := h.system.tuning
	var primed := h.add_target(Vector3(0.0, 0.0, -40.0))
	var bystander := h.add_target(Vector3(0.0, 0.0, -50.0))
	var far := h.add_target(Vector3(0.0, 0.0, -300.0))
	await h.step(0.05)
	primed.status.prime(t.well_prime)
	far.status.prime(t.well_prime)
	var od_before := h.player.overdrive
	# r4 item 2: audio listens for `Events.prime_collapsed`, and nothing emitted it. A lambda captures
	# locals BY VALUE in GDScript, so the tally lives in a Dictionary the callback can mutate.
	var seen := {"n": 0, "count": 0, "centre": Vector3.ZERO}
	var on_collapsed := func(centre: Vector3, count: int) -> void:
		seen["n"] = int(seen["n"]) + 1
		seen["count"] = count
		seen["centre"] = centre
	Events.prime_collapsed.connect(on_collapsed)
	# exactly what a COLLAPSE detonator in another unit does (CONTRACTS §4)
	h.player.get_tree().call_group(&"prime_detonators", &"detonate_primes",
			Vector3(0.0, 8.0, -40.0), 60.0, h.player)
	Events.prime_collapsed.disconnect(on_collapsed)
	h.check("collapse.emits_prime_collapsed_once", int(seen["n"]) == 1,
			"%d prime_collapsed events for one detonation" % int(seen["n"]))
	h.check("collapse.prime_collapsed_count", int(seen["count"]) == 1,
			"the event reported %d collapsed" % int(seen["count"]))
	h.near("collapse.prime_collapsed_centre", (seen["centre"] as Vector3).distance_to(
			Vector3(0.0, 8.0, -40.0)), 0.0, 0.01)
	h.check("collapse.group_call_reached", h.system.well.collapsed_count() == 1,
			"the group call resolved %d" % h.system.well.collapsed_count())
	h.near("collapse.primed_damage", primed.damage_taken, t.collapse_damage, 1.0)
	h.check("collapse.prime_spent", not primed.status.is_primed(), "the prime was not consumed")
	h.check("collapse.rupture_hits_neighbour", bystander.damage_taken > 0.0,
			"the 20 m rupture missed the bystander")
	h.near("collapse.out_of_range_untouched", far.damage_taken, 0.0, 0.01)
	h.check("collapse.far_still_primed", far.status.is_primed(),
			"a prime outside the radius was spent")
	h.check("collapse.awards_od", h.player.overdrive > od_before,
			"OD %.1f, was %.1f" % [h.player.overdrive, od_before])
