class_name MissileSuite
extends RefCounted
## S3 Hailstorm checks: lock rate and the per-target cap, a full 12-missile salvo landing on painted
## dummies inside 2 s, guided mode after release, spore-chaff absorption, the no-lock half salvo and
## the 14 s cooldown.

static func run(h: WeaponTestHarness) -> void:
	await _locks(h)
	await _salvo(h)
	await _per_target_cap(h)
	await _guided(h)
	await _chaff(h)
	await _free_salvo(h)
	await _cooldown(h)


static func _line(h: WeaponTestHarness, count: int, spacing: float = 10.0) -> Array[DummyTarget]:
	h.clear_targets()
	var out: Array[DummyTarget] = []
	for i in count:
		out.append(h.add_target(Vector3(float(i - count / 2) * spacing, 11.5, -60.0), 8.0))
	h.aim_at(Vector3(0.0, 11.5, -60.0))
	return out


static func _locks(h: WeaponTestHarness) -> void:
	var hs := h.system.hailstorm
	hs.reset_state()
	var announced: Array[int] = []
	Events.missiles_locked.connect(func(n: int) -> void: announced.append(n))
	_line(h, 3)
	var salvos0 := hs.salvos
	h.press(&"missiles")
	await h.step(0.45)
	var held_locks: Array[Targetable] = hs.locks.duplicate()
	h.release(&"missiles")
	await h.step(0.1)
	var locks := held_locks.size()
	h.check("missiles.lock_rate_10_per_s", locks >= 4 and locks <= 5,
			"%d locks in 0.45 s" % locks)
	var spread := 0
	for t in h.targets:
		for l in held_locks:
			if l == t.lock_point:
				spread += 1
				break
	h.check("missiles.locks_spread_over_targets", spread >= 2, "%d targets locked" % spread)
	h.check("missiles.locks_announced", announced.size() >= locks,
			"%d Events.missiles_locked for %d locks" % [announced.size(), locks])
	h.check("missiles.released_fires", hs.salvos == salvos0 + 1, "salvos %d" % hs.salvos)


static func _salvo(h: WeaponTestHarness) -> void:
	var hs := h.system.hailstorm
	var mm := h.system.missiles
	hs.reset_state()
	mm.clear()
	mm.launched = 0
	mm.impacts = 0
	var targets := _line(h, 3)
	for t in targets:
		t.reset()
	h.press(&"missiles")
	await h.step(1.3)
	h.release(&"missiles")
	await h.step(0.7)
	h.check("missiles.max_12_locks_fires", mm.launched == 12, "launched %d" % mm.launched)
	await h.step(2.0)
	h.check("missiles.all_12_impact_within_2s", mm.impacts == 12, "impacts %d" % mm.impacts)
	var total := 0
	for t in targets:
		total += t.hits
	h.check("missiles.land_on_painted_dummies", total >= 11,
			"%d direct hits across 3 dummies" % total)


static func _per_target_cap(h: WeaponTestHarness) -> void:
	var hs := h.system.hailstorm
	hs.reset_state()
	h.clear_targets()
	h.add_target(Vector3(0.0, 11.5, -60.0), 8.0)
	h.aim_at(Vector3(0.0, 11.5, -60.0))
	h.press(&"missiles")
	await h.step(0.95)
	var locks := hs.locks.size()
	h.release(&"missiles")
	h.check("missiles.max_4_locks_per_target", locks == 4, "%d locks on one target" % locks)


## A salvo is guided to the crosshair while `aim` is held after release: paint the dummies, sweep the
## crosshair onto an unpainted target before the launch, and the whole swarm must follow it there.
static func _guided(h: WeaponTestHarness) -> void:
	var hs := h.system.hailstorm
	var mm := h.system.missiles
	hs.reset_state()
	mm.clear()
	mm.launched = 0
	mm.impacts = 0
	var painted := _line(h, 3)
	h.press(&"aim")
	h.press(&"missiles")
	await h.step(1.0)
	var steered := h.add_target(Vector3(120.0, 11.5, -60.0), 14.0)
	h.aim_at(Vector3(120.0, 11.5, -60.0))
	await h.step(1.0)
	h.release(&"missiles")
	await h.step(3.7)
	h.release(&"aim")
	h.check("missiles.guided_follows_crosshair", steered.hits >= 8,
			"%d hits on the unpainted target" % steered.hits)
	var strays := 0
	for t in painted:
		strays += t.hits
	h.check("missiles.guided_leaves_painted_targets", strays <= 4,
			"%d hits still landed on the painted dummies" % strays)


static func _chaff(h: WeaponTestHarness) -> void:
	var hs := h.system.hailstorm
	var mm := h.system.missiles
	hs.reset_state()
	mm.clear()
	mm.launched = 0
	mm.impacts = 0
	mm.absorbed = 0
	_line(h, 3)
	var cloud := ChaffCloud.new()
	cloud.radius = 18.0
	h.root.add_child(cloud)
	cloud.global_position = Vector3(0.0, 14.0, -30.0)
	await h.step(0.6)
	h.press(&"missiles")
	await h.step(1.3)
	h.release(&"missiles")
	await h.step(3.7)
	h.check("missiles.chaff_absorbs_4", mm.absorbed == 4, "absorbed %d" % mm.absorbed)
	h.check("missiles.rest_get_through", mm.impacts == 8, "impacts %d" % mm.impacts)
	cloud.queue_free()


static func _free_salvo(h: WeaponTestHarness) -> void:
	var hs := h.system.hailstorm
	var mm := h.system.missiles
	hs.reset_state()
	mm.clear()
	mm.launched = 0
	mm.impacts = 0
	h.clear_targets()
	h.aim_at(Vector3(0.0, 11.5, -80.0))
	await h.tap(&"missiles", 0.6)
	h.check("missiles.no_locks_fires_6", mm.launched == 6, "launched %d" % mm.launched)


static func _cooldown(h: WeaponTestHarness) -> void:
	var hs := h.system.hailstorm
	hs.reset_state()
	_line(h, 3)
	await h.tap(&"missiles", 0.6)
	h.check("missiles.cooldown_starts", hs.cooldown > 13.0, "cooldown %.1f" % hs.cooldown)
	var locks_before := hs.locks.size()
	h.press(&"missiles")
	await h.step(0.5)
	h.release(&"missiles")
	h.check("missiles.blocked_on_cooldown", hs.locks.size() == locks_before and hs.cooldown > 0.0,
			"locks %d, cooldown %.1f" % [hs.locks.size(), hs.cooldown])
	await h.step(13.8)
	h.check("missiles.ready_after_14s", hs.cooldown <= 0.0, "cooldown %.1f" % hs.cooldown)
