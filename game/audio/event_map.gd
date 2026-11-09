class_name AudioEventMap
extends RefCounted
## Which sound every FEEL row and every gameplay moment plays.
##
## FEEL ids (docs/FEEL.md) normally equal their sound id; OVERRIDES lists the ones that do not.
## The FEEL list is spelled out rather than inferred so the test can prove full coverage.

const FEEL_IDS: Array[StringName] = [
	&"rifle_fire", &"rifle_hit", &"rifle_charge_1", &"rifle_charge_2", &"rifle_stage2_hit",
	&"gatling_fire", &"gatling_hit", &"gatling_vent_perfect", &"gatling_vent_good",
	&"gatling_overheat", &"gatling_jam", &"missile_launch", &"missile_hit",
	&"melee_light", &"melee_heavy", &"lunge_hit", &"charge_slash", &"finisher", &"parry_perfect",
	&"block", &"catch_release", &"perfect_dodge", &"dash", &"boost_start", &"assault_boost",
	&"jump", &"land_light", &"land_heavy", &"footstep_heavy", &"hurt_light", &"hurt_heavy",
	&"last_stand", &"near_miss", &"kill_small", &"kill_large", &"boss_kill", &"jackpot",
	&"stagger_enemy", &"boss_stagger",
	&"shockcore", &"collapse", &"plunge_land", &"rift_step", &"anchor_latch", &"fins_launch",
	&"ward_hit", &"overdrive_ignite", &"lance_fire", &"boss_roar",
]

const OVERRIDES: Dictionary = {
	&"footstep_heavy": &"footstep_hero_heavy",
	&"rift_step": &"rift_out",
	&"gatling_fire": &"gatling_fire_accent",
	# weapons r5 split the vent into perfect / good / jam. The good vent is the same steam release
	# without the ring, so it reuses the plain hiss (r16-lead-decisions: gatling_vent_good ->
	# gatling_vent); the miss and the overheat have their own rows.
	&"gatling_vent_good": &"gatling_vent",
}

## Extra sounds a FEEL row layers on top of its own id (payoffs get more than one layer).
const FEEL_EXTRAS: Dictionary = {
	&"kill_small": [&"kill_confirm"],
	&"kill_large": [&"kill_confirm", &"stinger_kill_large"],
	&"boss_kill": [&"kill_confirm", &"stinger_kill_large", &"ai_kill_confirm"],
	&"finisher": [&"kill_confirm"],
	&"boss_stagger": [&"stinger_stagger"],
	&"parry_perfect": [&"ai_parry_perfect"],
	&"overdrive_ignite": [&"ai_overdrive_engaged"],
	&"lance_fire": [&"ai_lance_fired"],
	&"boss_roar": [&"titan_roar"],
	&"hurt_heavy": [&"alarm_warning"],
	&"last_stand": [&"ai_armor_critical"],
	&"missile_hit": [&"debris_concrete"],
}


static func sound_for_feel(feel_id: StringName) -> StringName:
	return OVERRIDES.get(feel_id, feel_id)


static func extras_for_feel(feel_id: StringName) -> Array:
	return FEEL_EXTRAS.get(feel_id, [])


## Movement/combat Events signals mapped to their sound id. Signals with conditional logic (hits,
## kills, damage, lock-on) are handled by dedicated methods in audio.gd instead.
const SIMPLE_SIGNALS: Dictionary = {
	&"jumped": &"jump",
	&"energy_depleted": &"energy_outage",
	&"perfect_dodge": &"perfect_dodge",
	&"ultimate_fired": &"lance_fire",
	&"player_died": &"stinger_defeat",
	&"game_won": &"stinger_victory",
}
