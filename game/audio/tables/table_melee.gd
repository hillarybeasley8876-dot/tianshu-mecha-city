class_name AudioTableMelee
extends RefCounted
## Sound rows for the beam saber, defence and movement specials (table_hero.gd documents the keys).

const C0 := 0
const C2 := 2
const C3 := 3
const C7 := 7

static func rows() -> Dictionary:
	return {
		&"saber_ignite": {"bus": &"Player", "class": C0, "prio": 70.0, "cap": 1},
		&"saber_hum_loop": {"bus": &"Player", "class": C0, "prio": 45.0, "cap": 1, "loop": true,
			"socket": &"saber_r"},
		&"saber_sheathe": {"bus": &"Player", "class": C0, "prio": 50.0, "cap": 1},
		&"saber_swing": {"bus": &"Player", "class": C0, "prio": 70.0, "cap": 2, "variants": 3,
			"pitch": [0.97, 1.05]},
		&"saber_swing_2": {"bus": &"Player", "class": C0, "prio": 70.0, "cap": 2, "variants": 2},
		&"saber_swing_3": {"bus": &"Player", "class": C0, "prio": 75.0, "cap": 2, "variants": 2},
		&"melee_light": {"bus": &"Impacts", "class": C2, "prio": 65.0, "cap": 2, "variants": 3},
		&"melee_heavy": {"bus": &"Impacts", "class": C3, "prio": 85.0, "cap": 2, "variants": 2,
			"far": "kill_large_far", "far_delay": true},
		&"lunge_hit": {"bus": &"Impacts", "class": C2, "prio": 70.0, "cap": 1, "variants": 2},
		&"charge_slash": {"bus": &"Impacts", "class": C3, "prio": 88.0, "cap": 1, "variants": 2,
			"far": "kill_large_far", "far_delay": true},
		&"finisher": {"bus": &"Impacts", "class": C3, "prio": 98.0, "cap": 1},
		&"parry_perfect": {"bus": &"UI", "class": C0, "prio": 100.0, "cap": 1, "variants": 2},
		&"block": {"bus": &"Impacts", "class": C0, "prio": 70.0, "cap": 2, "variants": 3,
			"socket": &"shield_l"},
		&"catch_field_loop": {"bus": &"Weapons", "class": C0, "prio": 40.0, "cap": 1, "loop": true,
			"socket": &"shield_l"},
		&"catch_release": {"bus": &"Weapons", "class": C0, "prio": 75.0, "cap": 1},
		&"perfect_dodge": {"bus": &"UI", "class": C0, "prio": 90.0, "cap": 1},
		&"rift_out": {"bus": &"Player", "class": C0, "prio": 70.0, "cap": 1},
		&"rift_in": {"bus": &"Player", "class": C0, "prio": 70.0, "cap": 1},
		&"near_miss": {"bus": &"Enemies", "class": C7, "prio": 55.0, "cap": 2, "variants": 3},
	}
