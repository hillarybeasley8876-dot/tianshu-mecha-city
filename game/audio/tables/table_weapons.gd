class_name AudioTableWeapons
extends RefCounted
## Sound rows for P1 rifle, P2 gatling and S3 Hailstorm (see audio/tables/table_hero.gd for keys).

const C0 := 0
const C2 := 2
const C3 := 3
const C7 := 7

static func rows() -> Dictionary:
	return {
		&"rifle_fire": {"bus": &"Weapons", "class": C0, "prio": 90.0, "cap": 3, "variants": 3,
			"socket": &"muzzle_r", "pitch": [0.97, 1.03]},
		&"rifle_charge_1": {"bus": &"Weapons", "class": C0, "prio": 75.0, "cap": 1},
		&"rifle_charge_2": {"bus": &"Weapons", "class": C0, "prio": 80.0, "cap": 1},
		&"rifle_stage2_release": {"bus": &"Weapons", "class": C0, "prio": 92.0, "cap": 1},
		&"rifle_hit": {"bus": &"Impacts", "class": C2, "prio": 60.0, "cap": 3, "interval_ms": 40,
			"variants": 3},
		&"rifle_stage2_hit": {"bus": &"Impacts", "class": C3, "prio": 85.0, "cap": 2,
			"variants": 2, "far": "kill_large_far", "far_delay": true},
		&"gatling_spin_up": {"bus": &"Weapons", "class": C0, "prio": 70.0, "cap": 1},
		&"gatling_spin_down": {"bus": &"Weapons", "class": C0, "prio": 55.0, "cap": 1},
		&"gatling_fire_loop": {"bus": &"Weapons", "class": C0, "prio": 88.0, "cap": 1, "loop": true},
		# Every third round at 15 rps = one accent per 200 ms (dossier row 22).
		&"gatling_fire_accent": {"bus": &"Weapons", "class": C0, "prio": 75.0, "cap": 2,
			"interval_ms": 200},
		&"gatling_tail": {"bus": &"Weapons", "class": C2, "prio": 60.0, "cap": 1},
		&"gatling_hit": {"bus": &"Impacts", "class": C2, "prio": 55.0, "cap": 4, "interval_ms": 35,
			"variants": 4},
		&"gatling_vent": {"bus": &"Weapons", "class": C0, "prio": 70.0, "cap": 1},
		&"gatling_vent_perfect": {"bus": &"Weapons", "class": C0, "prio": 85.0, "cap": 1},
		&"gatling_jam": {"bus": &"Weapons", "class": C0, "prio": 88.0, "cap": 1},
		&"gatling_overheat": {"bus": &"Weapons", "class": C0, "prio": 85.0, "cap": 1,
			"interval_ms": 1000},
		&"weapon_switch": {"bus": &"Weapons", "class": C0, "prio": 65.0, "cap": 1, "variants": 2},
		&"reload": {"bus": &"Weapons", "class": C0, "prio": 65.0, "cap": 1},
		&"missile_lock_tick": {"bus": &"UI", "class": C0, "prio": 80.0, "cap": 1, "interval_ms": 55},
		&"missile_lock_full": {"bus": &"UI", "class": C0, "prio": 90.0, "cap": 1},
		&"missile_launch": {"bus": &"Weapons", "class": C0, "prio": 85.0, "cap": 6,
			"interval_ms": 35, "variants": 3, "socket": &"missile_r"},
		&"missile_flight": {"bus": &"Weapons", "class": C7, "prio": 40.0, "cap": 6, "loop": true},
		&"missile_hit": {"bus": &"Impacts", "class": C3, "prio": 85.0, "cap": 4, "variants": 3,
			"far": "kill_large_far", "far_delay": true},
		&"lock_on": {"bus": &"UI", "class": C0, "prio": 85.0, "cap": 1, "interval_ms": 200},
		&"lock_off": {"bus": &"UI", "class": C0, "prio": 70.0, "cap": 1, "interval_ms": 200},
	}
