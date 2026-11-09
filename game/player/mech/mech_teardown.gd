class_name MechTeardown
extends RefCounted
## What the death gate stops inside each component (mech-move r7b item 2, r9).
##
## `reset()` is each component's "put the mech back to factory fresh" hook, and two of them hand the
## player back what they spent: `WeaponSystem.reset()` reloads the magazine and the belt, zeroes the
## heat and the missile cooldown and selects the rifle WITHOUT announcing it, and
## `SkillSystem.reset()` restores every charge. The lead ruled carry-over in and refilling out, so the
## gate runs neither: it calls each owner's own death hook, which stops only what is RUNNING (rifle
## charge, gatling spin, missile paint, ADS, guard, saber, anchor line, ward, beam, Overdrive window)
## and leaves ammo, heat, cooldowns, charges and the selected weapon exactly as the killing blow
## found them.
##
## The gate writes no private field of its own. skills r5 made `SkillSystem.on_player_died()` close
## the Overdrive window itself (and leave no aftermath on a death) and weapons r7 shipped
## `WeaponSystem.stop_volley()`, so both components are one call each; a component that ships no
## death hook is matched on `reset()` instead.


## One component, dispatched by what it answers to. The aim system matches none of the three and is
## left alone on purpose: a lock-on is carry-over, not something the gate has to tear down.
static func quiet(c: Node) -> void:
	if c.has_method(&"on_player_died"):
		c.call(&"on_player_died")  # skills: anchor line, ward, beam, Overdrive window
	elif c.has_method(&"current_weapon"):
		c.call(&"stop_volley")  # weapons: rifle charge, gatling spin, missile paint, ADS
	elif c.has_method(&"reset"):
		c.call(&"reset")  # melee (blade, lunge, execution) and defense (guard, field, shield)
