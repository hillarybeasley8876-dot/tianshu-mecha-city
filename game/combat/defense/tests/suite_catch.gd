class_name DefenseCatchSuite
extends RefCounted
## Mirror Guard's projectile half (skills-catalog §4.4 S5, [TF-VS]): a shot that flies into the
## perfect window is turned back at 135 %, and holding past 0.3 s opens the catch field that freezes
## up to 24 rounds for 3 s and throws them back in a 20° cone at 135 %.


static func run(h: DefenseTestHarness) -> void:
	await _reflect(h)
	await _catch(h)
	await _catch_cap(h)
	await _release_cone(h)
	await _catch_timeout(h)
	await _non_reflectable(h)


## Perfect vs a projectile: the shot is turned back at its shooter with 135 % damage.
static func _reflect(h: DefenseTestHarness) -> void:
	h.fresh()
	var shooter := h.add_attacker(30.0)
	var shot := h.add_shot(9.0, 200.0)
	shot.set_meta(&"owner", shooter)
	await h.step(0.05)
	h.press(&"guard")
	await h.ticks(4)
	h.check("reflect.shot_is_reflected", shot.is_reflected(), "perfect window open")
	var hit: HitInfo = shot.get_meta(&"hit", null)
	h.near("reflect.damage_is_135_percent", hit.amount if hit != null else 0.0,
			200.0 * DefenseTable.REFLECT_MULT, 0.01)
	h.eq("reflect.counted_as_parry", h.system.parries, 1)
	var vel: Vector3 = shot.get(&"velocity")
	var to_shooter := (shooter.global_position - shot.global_position).normalized()
	h.check("reflect.aimed_at_the_shooter", vel.normalized().dot(to_shooter) > 0.9,
			"dir %s vs %s" % [str(vel.normalized()), str(to_shooter)])
	h.near("reflect.speed", vel.length(), DefenseTable.REFLECT_SPEED, 0.01)
	h.release(&"guard")
	await h.step(0.4)


## Hold ≥0.3 s and the shots in the 12 m frontal hemisphere freeze and orbit the mech. The rounds are
## fired after the perfect window has closed — one that arrives inside it is reflected instead.
static func _catch(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.05)
	h.press(&"guard")
	await h.open_catch_field()
	var a := h.add_shot(10.0)
	var b := h.add_shot(11.0)
	await h.ticks(8)
	h.check("catch.field_opens_after_0_3s", h.system.catch_count() >= 1,
			"caught %d" % h.system.catch_count())
	h.check("catch.shot_is_frozen", not a.is_physics_processing() and not b.is_physics_processing(),
			"frozen rounds stop moving")
	var pos_a := a.global_position
	await h.step(0.1)
	h.check("catch.frozen_shot_does_not_fly_on",
			a.global_position.distance_to(pos_a) < DefenseTable.REFLECT_SPEED * 0.1,
			"moved %.1f m" % a.global_position.distance_to(pos_a))
	h.check("catch.stays_inside_the_field",
			a.global_position.distance_to(h.player.global_position) \
					< DefenseTable.CATCH_RADIUS + DefenseTable.CATCH_ORBIT_RADIUS + 4.0,
			"distance %.1f" % a.global_position.distance_to(h.player.global_position))
	h.release(&"guard")
	await h.step(0.3)


## skills-catalog §4.4: the field holds at most 24 rounds, however many are fired.
static func _catch_cap(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.05)
	h.press(&"guard")
	await h.open_catch_field()
	for i in 30:
		var shot := h.add_shot(6.0 + float(i % 5) * 0.8)
		shot.global_position += Vector3(float(i % 6) - 2.5, float(i % 3), 0.0) * 0.6
	await h.step(0.5)
	h.eq("cap.never_over_24", h.system.catch_count(), DefenseTable.CATCH_MAX)
	h.check("cap.at_least_one_caught", h.system.catch_count() > 0)
	h.release(&"guard")
	await h.step(0.4)


## Release throws the caught rounds back in a 20° cone at 135 %.
static func _release_cone(h: DefenseTestHarness) -> void:
	h.fresh()
	h.aim.look_at_point(Vector3(0.0, 8.0, -200.0))
	await h.step(0.05)
	h.press(&"guard")
	await h.open_catch_field()
	var shots: Array[EnemyProjectile] = []
	for i in 6:
		shots.append(h.add_shot(9.0, 100.0))
	await h.step(0.2)
	var caught := h.system.catch_count()
	h.check("cone.rounds_are_caught", caught >= 3, "caught %d" % caught)
	h.release(&"guard")
	await h.ticks(2)
	h.eq("cone.field_is_empty", h.system.catch_count(), 0)
	var forward := Vector3(0.0, 0.0, -1.0)
	var half_cone := deg_to_rad(DefenseTable.RELEASE_CONE_DEG) * 0.5
	var worst := 0.0
	var reflected := 0
	for s in shots:
		if not is_instance_valid(s) or not s.is_reflected():
			continue
		reflected += 1
		var dir: Vector3 = (s.get(&"velocity") as Vector3).normalized()
		worst = maxf(worst, forward.angle_to(dir))
		var hit: HitInfo = s.get_meta(&"hit", null)
		h.near("cone.damage_135_percent_%d" % reflected, hit.amount if hit != null else 0.0,
				100.0 * DefenseTable.REFLECT_MULT, 0.01)
	h.check("cone.all_caught_rounds_returned", reflected == caught,
			"%d of %d" % [reflected, caught])
	h.check("cone.within_20_degrees", worst <= half_cone + 0.02,
			"widest %.1f°, cone %.1f°" % [rad_to_deg(worst), DefenseTable.RELEASE_CONE_DEG])
	await h.step(0.3)


## The field can only hold for 3 s, then it lets go by itself (skills-catalog §4.4).
static func _catch_timeout(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.05)
	h.press(&"guard")
	await h.open_catch_field()
	h.add_shot(9.0)
	await h.step(0.2)
	h.check("timeout.caught_before_the_cap", h.system.catch_count() >= 1)
	await h.step(DefenseTable.CATCH_MAX_TIME + 0.3)
	h.eq("timeout.auto_released_at_3s", h.system.catch_count(), 0)
	h.release(&"guard")
	await h.step(0.3)


## Only `reflectable` shots can be caught or parried — beams and plain slugs are not (the enemies
## unit sets the metadata honestly, CONTRACTS §6).
static func _non_reflectable(h: DefenseTestHarness) -> void:
	h.fresh()
	await h.step(0.05)
	h.press(&"guard")
	await h.open_catch_field()
	var shot := h.add_shot(9.0, 200.0, false)
	await h.step(0.3)
	h.eq("plain.non_reflectable_is_ignored", h.system.catch_count(), 0)
	h.check("plain.not_reflected", not shot.is_reflected())
	h.release(&"guard")
	await h.step(0.3)
