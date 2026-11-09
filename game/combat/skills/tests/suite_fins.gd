class_name SkillFinSuite
extends RefCounted
## S4 Corona Fins and the Corona Ward: the fin count derived from Marks, the beam volley, the return
## leg, the docked-blade hide/show round trip, and the 3,000 point absorption cap with its
## passes-through rules.

static func run(h: SkillTestHarness) -> void:
	await _count_from_marks(h)
	await _beams(h)
	await _return_and_dock(h)
	await _drone_hide(h)
	await _hero3_drone_api(h)
	await _ward(h)
	await _ward_timeout(h)
	await _pool_never_steals_an_open_piece(h)
	await _beam_axis_follows_the_line(h)


## Six fins in flight drop ~30 ribbons a second. Those ribbons have their own pool, and anything the
## shared pools still have to recycle goes to the piece with the least life left — so a piece an owner
## is HOLDING OPEN (the Skyhook cable, the three Lance layers, opened with a 3,600 s life) is never
## hijacked out from under it (audit #6).
## r4 item 3: the beam mesh is a cylinder whose local +Y is its axis. `line()` used to hang it under a
## quarter-turned pivot whose `global_transform` it then overwrote every frame, which wiped the quarter
## turn and laid the tube ACROSS the beam: from the gameplay camera the lance was a flat translucent
## pink wedge with hard straight edges instead of a round beam of light.
static func _beam_axis_follows_the_line(h: SkillTestHarness) -> void:
	var vfx := h.system.ctx.vfx
	h.check("fins.beam_pool_exists", vfx != null, "no SkillVfx on the context")
	if vfx == null:
		return
	var beam := vfx.beam()
	beam.open(Color.WHITE, 0.5, 2.0)
	var from := Vector3(10.0, 40.0, -30.0)
	var to := Vector3(-160.0, 95.0, 420.0)
	beam.line(from, to, 16.0)
	var mesh := beam.find_child("Beam", true, false) as MeshInstance3D
	h.check("fins.beam_mesh_found", mesh != null, "no MeshInstance3D named Beam inside SkillFxBeam")
	if mesh == null:
		beam.stop()
		return
	var dir := (to - from).normalized()
	var axis := mesh.global_basis.y.normalized()
	h.check("fins.beam_tube_lies_along_the_beam", absf(axis.dot(dir)) > 0.999,
			"the tube's axis is %.1f deg off the beam" % rad_to_deg(axis.angle_to(dir)))
	# the width must be lateral, not along the beam: the old slab was `length` deep and `width` tall
	var lateral := mesh.global_basis.x.length() + mesh.global_basis.z.length()
	var along := mesh.global_basis.y.length()
	h.near("fins.beam_width_is_lateral", lateral / maxf(along, 0.001),
			2.0 * 16.0 / (to - from).length(), 0.001)
	beam.stop()


static func _pool_never_steals_an_open_piece(h: SkillTestHarness) -> void:
	var vfx := h.system.ctx.vfx
	h.check("fins.vfx_pool_exists", vfx != null, "no SkillVfx on the context")
	if vfx == null:
		return
	var held := vfx.beam()
	held.open(Color.WHITE, 0.3, 2.0)   # an OPEN_LIFE holder, exactly like the cable core
	var held_left := held.life_left()
	for i in 60:
		vfx.beam().flash(Vector3.ZERO, Vector3.FORWARD * 10.0, 1.0, Color.CYAN, 0.2, 2.0, 0.5)
	h.check("fins.open_piece_not_stolen", held.life_left() >= held_left - 0.5,
			"the held piece lost %.1f s of its life to recycling" % (held_left - held.life_left()))
	held.stop()


## 2 + 2 x Marks -> 2 / 4 / 6 fins (skills-catalog §4.7 "Rifle -> Fins").
static func _count_from_marks(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var t := h.system.tuning
	var foe := h.add_target(Vector3(0.0, 0.0, -80.0))
	h.aim.locked = foe
	await h.step(0.05)
	h.near("fins.count_no_marks", float(h.system.fins.fin_count_for(foe)), 2.0, 0.001)
	foe.status.add_marks(1)
	h.near("fins.count_one_mark", float(h.system.fins.fin_count_for(foe)), 4.0, 0.001)
	foe.status.add_marks(1)
	h.near("fins.count_two_marks", float(h.system.fins.fin_count_for(foe)), 6.0, 0.001)
	h.near("fins.max_is_six", float(t.fins_max), 6.0, 0.001)
	# the marks are read, not consumed: the rifle keeps its own bookkeeping
	h.check("fins.marks_survive_send", foe.status.marks == 2,
			"marks %d before the send" % foe.status.marks)
	h.check("fins.send_ok", h.system.try_fins(), "send refused")
	h.check("fins.six_launched", h.system.fins.fins_out() == 6,
			"%d fins out" % h.system.fins.fins_out())
	# SPEC §6 S4: the fins ARE the hero's blades, so a 6-fin send takes six blades off the back and
	# leaves `Drone_1` — the one blade no fin ever maps to — docked.
	h.check("fins.six_blades_hidden", h.player.rig_model.drones_hidden() == 6,
			"%d of 7 blades hidden" % h.player.rig_model.drones_hidden())
	h.check("fins.drone_1_stays_docked", not h.player.rig_model.drone_deployed(0),
			"Drone_1 was deployed, but no fin maps to it")


## Each fin fires 4 beams 0.22 s apart for 110 damage; 6 fins is 24 beams over 0.88 s.
static func _beams(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var t := h.system.tuning
	var foe := h.add_target(Vector3(0.0, 0.0, -80.0))
	h.aim.locked = foe
	foe.status.add_marks(1)
	foe.status.add_marks(1)
	await h.step(0.05)
	h.system.try_fins()
	# the fins launch from the wing sockets and cross ~80 m at 150 m/s before they start firing
	var flight := h.player.global_position.distance_to(foe.global_position) / t.fin_speed
	await h.step(flight + t.fin_beam_gap * float(t.fin_beams) + 0.2)
	var want := t.fin_damage * float(t.fin_beams * 6)
	h.near("fins.total_beam_damage", foe.damage_taken, want, want * 0.12)
	h.check("fins.one_hit_per_beam", foe.hit_count() == t.fin_beams * 6,
			"%d hits, wanted %d" % [foe.hit_count(), t.fin_beams * 6])
	var last := foe.last_hit()
	h.check("fins.beam_weapon_id", last != null and last.weapon == &"corona_fin",
			"weapon %s" % (String(last.weapon) if last != null else "<none>"))


## After 2.4 s the fins fly home and the docked blades come back.
static func _return_and_dock(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var foe := h.add_target(Vector3(0.0, 0.0, -80.0))
	h.aim.locked = foe
	await h.step(0.05)
	h.system.try_fins()
	await h.step(h.system.tuning.fin_return + 1.2)
	h.check("fins.all_home", h.system.fins.fins_out() == 0,
			"%d still out" % h.system.fins.fins_out())
	h.check("fins.blades_restored", h.player.rig_model.wings_docked_visible(),
			"the docked blades never came back")
	h.check("fins.drone_mask_cleared", h.player.rig_model.drones_docked() == 0,
			"mask %d after every fin docked" % h.player.rig_model.drones_docked())
	h.check("fins.available_again", h.system.fins.available_fins() == h.system.tuning.fins_max,
			"%d available" % h.system.fins.available_fins())


## The Ward absorbs 3,000 points of projectile damage over 6 s, does not stop melee or shots fired
## from inside, and drops when the budget is gone.
static func _ward(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var t := h.system.tuning
	var hp_before := h.player.hp
	h.check("ward.raises", h.system.try_ward(), "raise_ward refused")
	h.check("ward.active", h.system.fins.ward.is_active(), "not active")
	h.near("ward.absorb_budget", h.system.fins.ward.absorb_left(), t.ward_absorb, 0.01)
	var shot := HitInfo.make(500.0, HitInfo.BALLISTIC, h.add_enemy(Vector3(0.0, 0.0, -60.0)), &"test")
	shot.position = h.player.global_position + Vector3(0.0, 11.5, -30.0)
	h.player.take_hit(shot)
	h.near("ward.absorbs_projectile", shot.final_amount, 0.0, 0.01)
	h.near("ward.player_untouched", h.player.hp, hp_before, 0.01)
	h.near("ward.budget_spent", h.system.fins.ward.absorb_left(), t.ward_absorb - 500.0, 0.01)

	var melee := HitInfo.make(400.0, HitInfo.MELEE, h.add_enemy(Vector3(0.0, 0.0, -60.0)), &"test")
	melee.position = h.player.global_position + Vector3(0.0, 11.5, -8.0)
	h.player.take_hit(melee)
	h.near("ward.melee_passes_through", melee.final_amount, 400.0, 0.01)

	var inside_source := h.add_enemy(Vector3(0.0, 0.0, -4.0))
	var inside := HitInfo.make(300.0, HitInfo.BALLISTIC, inside_source, &"test")
	inside.position = h.player.global_position + Vector3.UP * 11.5
	h.player.take_hit(inside)
	h.near("ward.inside_shot_passes", inside.final_amount, 300.0, 0.01)

	var big := HitInfo.make(t.ward_absorb, HitInfo.EXPLOSIVE,
			h.add_enemy(Vector3(0.0, 0.0, -60.0)), &"test")
	big.position = h.player.global_position + Vector3(0.0, 11.5, -30.0)
	h.player.take_hit(big)
	h.check("ward.drops_at_zero", not h.system.fins.ward.is_active(),
			"still up with %.0f left" % h.system.fins.ward.absorb_left())
	var after := HitInfo.make(200.0, HitInfo.BALLISTIC,
			h.add_enemy(Vector3(0.0, 0.0, -60.0)), &"test")
	after.position = h.player.global_position + Vector3(0.0, 11.5, -30.0)
	h.player.take_hit(after)
	h.near("ward.gone_takes_damage", after.final_amount, 200.0, 0.01)


## The Ward's 6 s timer drops it on its own.
static func _ward_timeout(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.system.try_ward()
	h.near("ward.time_left", h.system.fins.ward.time_left(), h.system.tuning.ward_time, 0.05)
	await h.step(h.system.tuning.ward_time + 0.2)
	h.check("ward.expires_on_timer", not h.system.fins.ward.is_active(), "outlived its 6 s")


## r4 item 4: the fin↔drone mapping. A fin's blade leaves the back when the fin launches and comes back
## only when that fin docks — flying, returning, holding the Ward and respawning all count as "out".
## `fins_max` is 6 with 3 fins a side, so the left wing spends `Drone_2..4` and the right `Drone_5..7`;
## `Drone_1` is never thrown.
static func _drone_hide(h: SkillTestHarness) -> void:
	var model := h.player.rig_model
	h.check("fins.drone_map_is_the_leads", CoronaFins.drone_for_fin(0) == 1
			and CoronaFins.drone_for_fin(1) == 4 and CoronaFins.drone_for_fin(2) == 2
			and CoronaFins.drone_for_fin(3) == 5 and CoronaFins.drone_for_fin(4) == 3
			and CoronaFins.drone_for_fin(5) == 6,
			"fin -> drone map is %s" % str([0, 1, 2, 3, 4, 5].map(
					func(i: int) -> int: return CoronaFins.drone_for_fin(i))))
	h.check("fins.drone_map_skips_drone_1", not [0, 1, 2, 3, 4, 5].any(
			func(i: int) -> bool: return CoronaFins.drone_for_fin(i) == 0),
			"a fin maps to Drone_1, which must always stay docked")

	# a 2-fin send hides exactly the two mapped blades
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var foe := h.add_target(Vector3(0.0, 0.0, -80.0))
	h.aim.locked = foe
	await h.step(0.05)
	h.system.try_fins()
	h.check("fins.two_blades_hidden", model.drones_hidden() == 2,
			"%d blades hidden after a 2-fin send" % model.drones_hidden())
	h.check("fins.two_blades_are_the_mapped_ones",
			model.drone_deployed(CoronaFins.drone_for_fin(0))
			and model.drone_deployed(CoronaFins.drone_for_fin(1))
			and not model.drone_deployed(CoronaFins.drone_for_fin(2)),
			"mask %d after a 2-fin send" % model.drones_docked())

	# a fin shot down stays hidden until it respawns
	h.system.fins.damage_fin(0, 1e6)
	h.check("fins.shot_down_fin_stays_hidden",
			model.drone_deployed(CoronaFins.drone_for_fin(0)),
			"a downed fin re-showed its blade while it was still respawning")
	h.system.fins.reset()
	h.check("fins.reset_shows_every_blade", model.drones_hidden() == 0,
			"%d blades still hidden after reset()" % model.drones_hidden())

	# the Ward hides what it borrows (four for the tetrahedron plus the escort pair)
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.system.try_ward()
	var borrowed := h.system.tuning.ward_fins + h.system.tuning.ward_escort_fins
	h.check("fins.ward_hides_what_it_borrows", model.drones_hidden() == borrowed,
			"%d blades hidden for a %d-fin ward" % [model.drones_hidden(), borrowed])
	h.system.fins.ward.drop()
	h.check("fins.ward_drop_shows_them_again", model.drones_hidden() == 0,
			"%d blades still hidden after the ward dropped" % model.drones_hidden())


## The same contract on the SHIPPED hero: `HeroModel.set_drones_docked` landed in hero-v3 r8 (742876f),
## so this asserts the real model, not a stand-in. It reads PENDING (never a silent pass) if the model
## ever stops offering the method.
const HERO3 := "res://player/model/hero3/hero3_model.tscn"

static func _hero3_drone_api(h: SkillTestHarness) -> void:
	var packed := load(HERO3) as PackedScene
	if packed == null:
		h.check("fins.hero3_drone_api", false, "PENDING: cannot load " + HERO3)
		return
	var hero := packed.instantiate() as Node3D
	h.root.add_child(hero)
	if not hero.has_method(&"set_drones_docked") or not hero.has_method(&"drones_docked"):
		h.check("fins.hero3_drone_api", false,
				"PENDING: Hero3 has no set_drones_docked(mask) / drones_docked() read-back")
		hero.queue_free()
		return
	if hero.get(&"rig") == null:
		# hero-v3 owns this tree and edits it live: while its files are mid-refactor the scene
		# instantiates without a rig, and every read-back is 0 for reasons that are not ours. Report
		# it as PENDING with the cause rather than a silent pass or a red that belongs to nobody.
		h.check("fins.hero3_drone_api", false,
				"PENDING: Hero3 instantiated with no rig (its own tree does not compile right now)")
		hero.queue_free()
		return
	# Point the skill context at the SHIPPED hero for the length of one volley, so the check proves
	# CoronaFins drives the real model — not merely that the model offers the method.
	var was := h.system.ctx.model
	h.system.ctx.model = hero
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var foe := h.add_target(Vector3(0.0, 0.0, -80.0))
	h.aim.locked = foe
	await h.step(0.05)
	h.system.try_fins()
	var two := (1 << CoronaFins.drone_for_fin(0)) | (1 << CoronaFins.drone_for_fin(1))
	h.check("fins.hero3_two_fin_send_hides_its_blades",
			int(hero.call(&"drones_docked")) == two,
			"Hero3 read back mask %d, the 2-fin send asked for %d"
			% [int(hero.call(&"drones_docked")), two])
	h.check("fins.hero3_drone_api", int(hero.call(&"drones_docked")) != 0,
			"a 2-fin send left every Hero3 blade on the back")
	h.system.fins.reset()
	h.check("fins.hero3_reset_shows_every_blade", int(hero.call(&"drones_docked")) == 0,
			"mask %d after reset()" % int(hero.call(&"drones_docked")))
	h.system.ctx.model = was
	h.clear_enemies()
	hero.queue_free()
