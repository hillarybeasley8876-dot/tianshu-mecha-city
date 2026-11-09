class_name WeaponTeardownSuite
extends RefCounted
## `WeaponSystem.stop_volley()` — the death gate's hook (mech-move Request 17, reviews/weapons-r7.md).
##
## The gate must stop what is RUNNING and hand nothing back, so every check here is one of two kinds:
##   * stopped — no charge, no spin, no paint, no ADS and no strafe-aim after the call;
##   * carried — the cell, the belt, the heat, the gatling's state, the missile cooldown and the
##               selected weapon are identical across the call, and no `weapon_switched` fires.
##
## Only the component's public surface is read: the whole point of the hook is that the death gate no
## longer has to write `_paint_time` / `_lock_timer` behind the launcher's back. `MechTeardown` is
## another unit's file — `player/mech/tests/test_death.gd` is what proves the gate takes this path.

static func run(h: WeaponTestHarness) -> void:
	var switched: Array[StringName] = []
	var on_switch := func(id: StringName) -> void: switched.append(id)
	Events.weapon_switched.connect(on_switch)
	await _rifle_and_paint(h, switched)
	await _gatling(h, switched)
	Events.weapon_switched.disconnect(on_switch)
	h.release_all()
	h.clear_targets()
	h.system.reset()
	await h.step(0.2)


## The state the gate actually meets in a firefight: the rifle charging a shot while the Hailstorm
## paints locks, with rounds already spent, ADS held and strafe-aim up.
static func _rifle_and_paint(h: WeaponTestHarness, switched: Array[StringName]) -> void:
	var sys := h.system
	sys.reset()                         # factory state, and it announces nothing
	await h.step(0.2)
	h.clear_targets()
	for i in 3:
		h.add_target(Vector3(float(i - 1) * 10.0, 11.5, -60.0), 8.0)
	h.aim_at(Vector3(0.0, 11.5, -60.0))
	await h.step(0.1)
	await h.tap(&"fire", 0.3)           # spend two rounds of the cell
	await h.tap(&"fire", 0.3)
	h.press(&"fire")                    # and hold: the charge runs up
	h.press(&"missiles")                # while the launcher paints
	h.press(&"aim")
	await h.step(0.7)
	var hs := sys.hailstorm
	h.check("teardown.pre_rifle_charging", sys.rifle.is_firing(), "charge %.2f"
			% sys.rifle.charge_ratio())
	h.check("teardown.pre_rifle_spent", sys.rifle.ammo < sys.rifle.tuning.magazine,
			"ammo %d" % sys.rifle.ammo)
	h.check("teardown.pre_painting", hs.painting and hs.locks.size() > 0,
			"painting %s, %d locks" % [hs.painting, hs.locks.size()])
	h.check("teardown.pre_ads_and_strafe", sys.ctx.ads and sys.ctx.strafe_aim
			and h.player.strafe_aim, "ads %s strafe %s" % [sys.ctx.ads, sys.ctx.strafe_aim])

	var before := _snapshot(sys)
	switched.clear()
	sys.stop_volley()
	var after := _snapshot(sys)
	h.release_all()

	var hud := sys.hud_state()
	h.check("teardown.rifle_charge_cancelled", not sys.rifle.is_firing()
			and sys.rifle.charge_ratio() == 0.0, "charge %.2f" % sys.rifle.charge_ratio())
	h.check("teardown.hud_charge_zero", int(hud["charge_stage"]) == 0
			and is_zero_approx(float(hud["charge"])), "stage %s charge %.2f"
			% [hud["charge_stage"], hud["charge"]])
	h.check("teardown.paint_cancelled", not hs.painting and hs.locks.is_empty()
			and not bool(hud["missile_painting"]), "painting %s, %d locks"
			% [hs.painting, hs.locks.size()])
	h.check("teardown.ads_and_strafe_dropped", not sys.ctx.ads and not sys.ctx.strafe_aim
			and not h.player.strafe_aim, "ads %s strafe %s mech %s"
			% [sys.ctx.ads, sys.ctx.strafe_aim, h.player.strafe_aim])
	h.check("teardown.nothing_switched", switched.is_empty(), "%d weapon_switched" % switched.size())
	_carry(h, "rifle", before, after)

	# Nothing may creep back while the corpse lies there: with every button up, a tick of the
	# component must not re-arm the charge, the spin or the paint.
	await h.step(0.3)
	h.check("teardown.stays_quiet", not sys.rifle.is_firing() and sys.gatling.spin() == 0.0
			and not hs.painting and hs.locks.is_empty(), "charge %.2f spin %.2f locks %d"
			% [sys.rifle.charge_ratio(), sys.gatling.spin(), hs.locks.size()])


## The same call with the gatling out: a hot, spinning barrel must stop spinning and stay hot.
static func _gatling(h: WeaponTestHarness, switched: Array[StringName]) -> void:
	var sys := h.system
	sys.gatling.reset_state()
	sys.switch_weapon(1)
	await h.step(0.4)
	h.check("teardown.gatling_selected", sys.current == WeaponSystem.GATLING,
			"current %d" % sys.current)
	await h.hold(&"fire", 0.6)
	h.check("teardown.pre_gatling_spinning", sys.gatling.spin() > 0.0
			and sys.gatling.heat > 0.0, "spin %.2f heat %.1f"
			% [sys.gatling.spin(), sys.gatling.heat])

	var before := _snapshot(sys)
	switched.clear()
	sys.stop_volley()
	var after := _snapshot(sys)
	h.release_all()

	h.check("teardown.gatling_spin_cancelled", sys.gatling.spin() == 0.0
			and not sys.gatling.is_firing(), "spin %.2f" % sys.gatling.spin())
	h.check("teardown.nothing_switched_gatling", switched.is_empty(),
			"%d weapon_switched" % switched.size())
	_carry(h, "gatling", before, after)
	await h.step(0.3)
	h.check("teardown.gatling_stays_quiet", sys.gatling.spin() == 0.0
			and not sys.gatling.is_firing(), "spin %.2f" % sys.gatling.spin())


## Everything the gate must leave alone, read in one place so the carry check is a plain comparison.
static func _snapshot(sys: WeaponSystem) -> Dictionary:
	return {
		"rifle_ammo": sys.rifle.ammo,
		"rifle_reloading": sys.rifle.reloading,
		"gatling_ammo": sys.gatling.ammo,
		"gatling_heat": sys.gatling.heat,
		"gatling_state": int(sys.gatling.state),
		"gatling_superheated": sys.gatling.superheated_left,
		"missile_cd": sys.hailstorm.cooldown,
		"missile_salvos": sys.hailstorm.salvos,
		"current": sys.current,
		"weapon": sys.current_weapon(),
	}


static func _carry(h: WeaponTestHarness, phase: String, before: Dictionary,
		after: Dictionary) -> void:
	# `str()` on two dictionaries built in the same order: a readable diff on failure, and no
	# dependence on how `Dictionary ==` treats nested values.
	h.check("teardown.%s_carry_unchanged" % phase, str(before) == str(after),
			"%s -> %s" % [before, after])
