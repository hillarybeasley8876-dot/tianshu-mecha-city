class_name SkillMobilitySuite
extends RefCounted
## S1 Rift Step and S2 Skyhook Anchor: the destination table, the intangible transit, the Ambush
## window, and the grapple's reel ramp / swing threshold / release impulse / light-vs-heavy split.

static func run(h: SkillTestHarness) -> void:
	await _rift_table(h)
	await _rift_transit(h)
	await _rift_ambush(h)
	await _anchor_aims_from_its_socket(h)
	await _anchor_reel(h)
	await _anchor_swing(h)
	await _anchor_release(h)
	await _anchor_enemies(h)


## The cable is FLYN from `hand_l`, so it has to be AIMED from `hand_l` too. Aiming from the chest
## pivot — 4 m lower — makes the flown line overshoot every low anchor by (hand_y - chest_y)/sin(pitch),
## about 25 m on a deck anchor 95 m out: the hook sails over the surface and the line runs out at
## 120 m having touched nothing (r4, found by the SKACC `anchor` beat).
static func _anchor_aims_from_its_socket(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.player.global_basis = Basis.IDENTITY
	h.aim.point = Vector3(0.0, 0.0, -95.0)
	await h.step(0.05)
	h.check("anchor.fires_for_the_aim_check", h.system.try_anchor(), "begin() refused")
	var from := h.system.ctx.socket(SkyhookAnchor.CABLE_SOCKET)
	var dir: Vector3 = h.system.anchor.get(&"_dir")
	var reach := from + dir * from.distance_to(h.aim.point)
	h.check("anchor.aimed_from_the_cable_socket", reach.distance_to(h.aim.point) < 2.0,
			"the flown line passes %.1f m from the aim point (hand_l %s, chest %s)"
			% [reach.distance_to(h.aim.point), from, h.system.ctx.chest()])
	h.system.anchor.detach_silently()
	h.system.reset()


# --- S1 Rift Step --------------------------------------------------------------------------------

## A destination must leave the mech's capsule centre at least half a capsule above the target's feet,
## which is where the floor is: the un-lifted table put it exactly on the floor (audit #1).
static func _clears_floor(h: SkillTestHarness, at: Vector3) -> bool:
	var half: float = h.system.ctx.half_height()
	return at.y >= half - 0.01 and at.y <= h.player.global_position.y + 0.5


## Ground-plane distance: the destination table is a horizontal table, and the enemy origin is its
## feet while the mech's is its capsule centre, so the vertical offset is not part of the reach.
static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _rift_table(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var t := h.system.tuning
	var rift := h.system.rift
	var foe := h.add_enemy(Vector3(0.0, 0.0, -40.0))
	await h.step(0.05)
	# the dummy faces -Z like every actor in the project (CONTRACTS §2)
	foe.global_basis = Basis.IDENTITY
	var behind := rift.destination(Vector2.ZERO, foe)
	h.near("rift.neutral_behind_dist", _flat_dist(behind, foe.global_position), t.rift_behind, 0.01)
	h.check("rift.neutral_behind_side", behind.z > foe.global_position.z,
			"behind = %.1f, target z = %.1f" % [behind.z, foe.global_position.z])
	# the destination is a place for the mech's CAPSULE CENTRE, so it has to sit at the mech's own
	# origin height — built from the target's feet it dropped the mech 7.5 m into the floor (audit #1)
	h.check("rift.behind_height", _clears_floor(h, behind),
			"behind.y = %.2f, would sink the capsule centre" % behind.y)
	var forward := rift.destination(Vector2(0.0, 1.0), foe)
	h.check("rift.forward_is_behind", forward.distance_to(behind) < 0.01,
			"forward gave %.1f, neutral gave %.1f" % [forward.z, behind.z])
	var right := rift.destination(Vector2(1.0, 0.0), foe)
	h.near("rift.right_flank_dist", _flat_dist(right, foe.global_position), t.rift_flank, 0.01)
	h.check("rift.right_flank_side", right.x > foe.global_position.x, "right flank x = %.1f" % right.x)
	var left := rift.destination(Vector2(-1.0, 0.0), foe)
	h.check("rift.left_is_mirrored", left.x < foe.global_position.x, "left flank x = %.1f" % left.x)
	var back := rift.destination(Vector2(0.0, -1.0), foe)
	h.near("rift.backoff_dist", _flat_dist(back, foe.global_position), t.rift_backoff, 0.01)
	h.check("rift.backoff_opens_range", back.z > foe.global_position.z, "back-off z = %.1f" % back.z)
	h.check("rift.backoff_height", _clears_floor(h, back),
			"back-off y = %.2f, would sink the capsule centre" % back.y)
	# arrival facing must be level: a pitched basis written into the CharacterBody3D tilts the capsule
	# and every ctx.facing() consumer, and nothing in locomotion re-levels it (audit #2)
	h.near("rift.facing_level_behind", rift.arrival_facing(Vector2.ZERO, foe).y, 0.0, 0.001)
	h.near("rift.facing_level_backoff", rift.arrival_facing(Vector2(0.0, -1.0), foe).y, 0.0, 0.001)
	var free := rift.destination(Vector2(0.0, 1.0), null)
	h.near("rift.no_lock_distance", free.distance_to(h.player.global_position), t.rift_free, 0.01)
	h.check("rift.no_lock_forward", free.z < h.player.global_position.z, "free blink z = %.1f" % free.z)


## 9 f of transit with collision off and i-frames on; the mech is standing at the destination with
## its collision restored once the blink lands.
static func _rift_transit(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.aim.locked = null
	h.check("rift.fires", h.system.try_rift_step(), "begin() refused")
	var mask_during := (h.player as CollisionObject3D).collision_mask
	h.check("rift.collision_off_in_transit", mask_during == 0, "mask %d" % mask_during)
	h.check("rift.invulnerable_in_transit", h.player.is_invulnerable(), "no i-frames in transit")
	var want := h.system.rift.destination(Vector2(0.0, 1.0), null)
	await h.step(h.system.tuning.rift_transit * 1.2)
	h.check("rift.arrived", h.player.global_position.distance_to(want) < 1.0,
			"at %.1f, wanted %.1f" % [h.player.global_position.z, want.z])
	h.check("rift.collision_restored",
			(h.player as CollisionObject3D).collision_mask == Layers.MASK_CHARACTER,
			"mask %d" % (h.player as CollisionObject3D).collision_mask)
	h.check("rift.decoy_left_behind", h.system.rift.has_decoy(), "no decoy shell at the origin")
	await h.step(h.system.tuning.rift_decoy + 0.1)
	h.check("rift.decoy_expires", not h.system.rift.has_decoy(), "decoy outlived its 0.6 s")


## The 0.45 s Ambush window opens after the 6 f recovery and multiplies the next hit.
static func _rift_ambush(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.system.try_rift_step()
	await h.step(h.system.tuning.rift_transit + h.system.tuning.rift_recovery * 0.5)
	h.check("ambush.closed_during_recovery", not h.system.is_ambushing(), "opened too early")
	await h.step(h.system.tuning.rift_recovery)
	h.check("ambush.open_after_recovery", h.system.is_ambushing(), "never opened")
	var t := h.system.tuning
	await h.step(0.02)  # the system refreshes the multipliers at the end of every physics tick
	h.near("ambush.damage_multiplier", h.system.ctx.damage_mult, t.rift_ambush_damage, 0.001)
	h.near("ambush.impact_multiplier", h.system.ctx.impact_mult, t.rift_ambush_impact, 0.001)
	await h.step(t.rift_ambush + 0.1)
	h.check("ambush.expires", not h.system.is_ambushing(), "outlived its 0.45 s")
	h.near("ambush.cleared_multiplier", h.system.ctx.damage_mult, 1.0, 0.001)


# --- S2 Skyhook Anchor ---------------------------------------------------------------------------

## The reel ramps 60 -> 92 m/s over 0.6 s and the mech's velocity points at the anchor.
static func _anchor_reel(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.player.velocity = Vector3.ZERO
	h.add_wall(Vector3(0.0, 20.0, -115.0), Vector3(80.0, 80.0, 4.0))
	h.aim.point = Vector3(0.0, 19.5, -115.0)
	h.aim.locked = null
	await h.step(0.05)
	h.check("anchor.fires", h.system.try_anchor(), "begin() refused")
	var flight := 115.0 / h.system.tuning.anchor_speed
	await h.step(flight * 1.4)
	h.check("anchor.latched_surface", h.system.anchor.is_attached(),
			"state %d after %.2f s of flight" % [h.system.anchor.state(), flight])
	var t := h.system.tuning
	# the flight wait overshoots the latch by a few frames, so the start of the ramp is asserted as a
	# band rather than a point: still on the ramp, still well short of the top speed
	var start_speed := h.system.anchor.reel_speed()
	h.check("anchor.reel_ramps_from_start",
			start_speed >= t.reel_start and start_speed < t.reel_top * 0.85,
			"reel started at %.1f m/s (ramp is %.0f -> %.0f)" % [start_speed, t.reel_start,
			t.reel_top])
	await h.step(t.reel_ramp)
	h.near("anchor.reel_top", h.system.anchor.reel_speed(), t.reel_top, 6.0)
	h.check("anchor.pulls_toward_hook", h.player.velocity.z < -10.0,
			"velocity %.1f, %.1f, %.1f" % [h.player.velocity.x, h.player.velocity.y,
			h.player.velocity.z])
	h.system.anchor.reset()


## Aiming more than 25 deg off the cable turns the reel into a swing.
static func _anchor_swing(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.add_wall(Vector3(0.0, 20.0, -115.0), Vector3(80.0, 80.0, 4.0))
	h.aim.point = Vector3(0.0, 19.5, -115.0)
	await h.step(0.05)
	h.system.try_anchor()
	await h.step(115.0 / h.system.tuning.anchor_speed * 1.4)
	h.check("anchor.attached_before_swing", h.system.anchor.is_attached(), "never latched")
	h.aim.point = h.player.global_position + Vector3(60.0, 0.0, -40.0)
	await h.step(0.05)
	h.check("anchor.swing_angle_over_threshold",
			h.system.anchor.off_cable_angle() > h.system.tuning.swing_angle_deg,
			"off-cable angle %.1f deg" % h.system.anchor.off_cable_angle())
	await h.step(0.05)
	h.check("anchor.swinging", h.system.anchor.is_swinging(), "the aim never switched it to a swing")
	h.system.anchor.reset()


## Jump releases the line and adds +12 m/s up.
static func _anchor_release(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.player.velocity = Vector3.ZERO
	h.add_wall(Vector3(0.0, 20.0, -115.0), Vector3(80.0, 80.0, 4.0))
	h.aim.point = Vector3(0.0, 19.5, -115.0)
	await h.step(0.05)
	h.system.try_anchor()
	await h.step(115.0 / h.system.tuning.anchor_speed * 1.4)
	h.system.anchor.release_jump()
	h.check("anchor.jump_release_up",
			h.player.velocity.y >= h.system.tuning.release_up - 0.01,
			"vy %.2f, wanted >= %.2f" % [h.player.velocity.y, h.system.tuning.release_up])
	await h.step(0.05)
	h.check("anchor.detached_after_release", not h.system.anchor.is_attached(), "still attached")


## Light enemies are yanked to 18 m in front; heavies pull the mech in instead.
static func _anchor_enemies(h: SkillTestHarness) -> void:
	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	h.player.global_basis = Basis.IDENTITY
	var t := h.system.tuning
	var light := h.add_enemy(Vector3(0.0, 0.0, -50.0))
	h.aim.locked = light
	h.aim.point = light.global_position + Vector3.UP * 3.0
	await h.step(0.05)
	h.system.try_anchor()
	await h.step(t.anchor_range / t.anchor_speed * 0.5)
	h.check("anchor.snapped_to_light", h.system.anchor.attached_enemy() == light,
			"no enemy latched")
	await h.step(t.yank_time * 1.3)
	h.near("anchor.yank_distance", light.global_position.distance_to(h.player.global_position),
			t.yank_distance, 3.0)
	h.check("anchor.yank_in_front", light.global_position.z < h.player.global_position.z,
			"yanked to z %.1f, player at %.1f" % [light.global_position.z,
			h.player.global_position.z])
	h.system.anchor.reset()

	h.reset()
	h.clear_enemies()
	h.player.global_position = Vector3(0.0, 8.0, 0.0)
	var heavy := h.add_enemy(Vector3(0.0, 0.0, -90.0), true)
	h.aim.locked = heavy
	h.aim.point = heavy.global_position + Vector3.UP * 11.0
	await h.step(0.05)
	h.system.try_anchor()
	await h.step(90.0 / t.anchor_speed * 1.2)
	h.check("anchor.heavy_latched", h.system.anchor.attached_enemy() == heavy, "no enemy latched")
	var before := h.player.global_position.z
	var hp_before := heavy.hp
	await h.step(0.25)
	h.check("anchor.heavy_pulls_player_in", h.player.velocity.z < -10.0,
			"player velocity z %.1f" % h.player.velocity.z)
	h.check("anchor.heavy_did_not_move", absf(heavy.global_position.z + 90.0) < 2.0,
			"heavy moved to z %.1f" % heavy.global_position.z)
	h.system.anchor.hook_kick()
	h.near("anchor.hook_kick_damage", hp_before - heavy.hp, t.hook_kick_damage, 1.0)
	h.check("anchor.player_moved", h.player.global_position.z < before,
			"player still at z %.1f" % h.player.global_position.z)
	h.system.anchor.reset()
	h.aim.locked = null
