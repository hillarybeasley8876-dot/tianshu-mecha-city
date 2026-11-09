class_name AudioTableEnemies
extends RefCounted
## Sound rows for the HUSK roster (SPEC §7). Telegraphs carry priority 80 so a busy mix can never
## bury them (dossier §8 risk 10). Table_hero.gd documents the row keys.

const C1 := 1
const C2 := 2
const C3 := 3
const C4 := 4
const C5 := 5
const C7 := 7
const C0 := 0

static func rows() -> Dictionary:
	return {
		&"ripper_chitter_loop": {"bus": &"Enemies", "class": C1, "prio": 20.0, "cap": 6,
			"loop": true},
		&"ripper_step": {"bus": &"Enemies", "class": C1, "prio": 30.0, "cap": 6, "interval_ms": 60,
			"variants": 4, "pitch": [0.9, 1.12]},
		&"ripper_leap_tell": {"bus": &"Enemies", "class": C1, "prio": 80.0, "cap": 3,
			"variants": 2},
		&"ripper_bite": {"bus": &"Enemies", "class": C2, "prio": 60.0, "cap": 4, "variants": 3},
		&"ripper_death": {"bus": &"Enemies", "class": C2, "prio": 55.0, "cap": 4, "variants": 3},
		&"mantis_glint": {"bus": &"Enemies", "class": C2, "prio": 80.0, "cap": 2, "variants": 2},
		&"mantis_swing": {"bus": &"Enemies", "class": C2, "prio": 60.0, "cap": 3, "variants": 3},
		&"mantis_grab_tell": {"bus": &"Enemies", "class": C2, "prio": 80.0, "cap": 2,
			"variants": 2},
		&"mantis_death": {"bus": &"Enemies", "class": C3, "prio": 60.0, "cap": 2, "variants": 2},
		&"spitter_charge": {"bus": &"Enemies", "class": C3, "prio": 80.0, "cap": 3, "variants": 2},
		&"acid_lob": {"bus": &"Enemies", "class": C3, "prio": 60.0, "cap": 3, "variants": 3},
		&"acid_impact_loop": {"bus": &"Enemies", "class": C3, "prio": 25.0, "cap": 3, "loop": true},
		&"spitter_death": {"bus": &"Enemies", "class": C3, "prio": 60.0, "cap": 2, "variants": 2},
		&"harrier_screech": {"bus": &"Enemies", "class": C3, "prio": 80.0, "cap": 2, "variants": 3},
		&"harrier_flyby": {"bus": &"Enemies", "class": C7, "prio": 50.0, "cap": 2, "variants": 3},
		&"harrier_wings": {"bus": &"Enemies", "class": C2, "prio": 25.0, "cap": 3, "loop": true},
		&"harrier_death": {"bus": &"Enemies", "class": C3, "prio": 58.0, "cap": 2, "variants": 2},
		&"jugg_roar": {"bus": &"Enemies", "class": C4, "prio": 82.0, "cap": 1, "variants": 2},
		&"jugg_step": {"bus": &"Enemies", "class": C3, "prio": 50.0, "cap": 2, "variants": 3,
			"far": "kill_large_far", "far_delay": true},
		&"jugg_slam": {"bus": &"Impacts", "class": C4, "prio": 88.0, "cap": 1, "variants": 2,
			"far": "kill_large_far", "far_delay": true},
		&"jugg_plate_break": {"bus": &"Impacts", "class": C3, "prio": 80.0, "cap": 2,
			"variants": 2},
		&"titan_step_far": {"bus": &"Bed", "class": C5, "prio": 45.0, "cap": 2, "variants": 2},
		&"titan_roar": {"bus": &"Enemies", "class": C5, "prio": 90.0, "cap": 1},
		&"boss_roar": {"bus": &"Enemies", "class": C5, "prio": 92.0, "cap": 1},
		&"titan_breath_beam": {"bus": &"Enemies", "class": C4, "prio": 85.0, "cap": 1},
		&"spire_pulse_loop": {"bus": &"Bed", "class": C4, "prio": 25.0, "cap": 3, "loop": true},
		&"spire_destroyed": {"bus": &"Impacts", "class": C4, "prio": 95.0, "cap": 1,
			"far": "kill_large_far", "far_delay": true},
		# The one tell that must never be buried: enemies call it directly (enemy_base.gd) at every
		# unblockable wind-up, so it rides the never-ducked UI bus at near-telegraph priority.
		&"telegraph_unblockable": {"bus": &"UI", "class": C3, "prio": 92.0, "cap": 2,
			"interval_ms": 220, "pitch": [0.97, 1.05]},
	}
