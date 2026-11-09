class_name AudioTableHero
extends RefCounted
## Sound rows for the hero mech: locomotion, mechanisms, cockpit and damage.
## Keys: bus, class (C0..C7 index), prio, cap, interval_ms, variants, pitch [min,max], socket,
## loop, ext, far (stem of the far variant), far_delay, volume_db. See audio/sound_bank.gd.

const C0 := 0
const C2 := 2
const C3 := 3

static func rows() -> Dictionary:
	return {
		&"footstep_hero": {"bus": &"Player", "class": C0, "prio": 40.0, "cap": 2, "interval_ms": 90,
			"variants": 4, "pitch": [0.96, 1.04]},
		&"footstep_hero_heavy": {"bus": &"Player", "class": C0, "prio": 45.0, "cap": 2,
			"interval_ms": 120, "variants": 3, "pitch": [0.95, 1.03]},
		&"servo_move_s": {"bus": &"Player", "class": C0, "prio": 25.0, "cap": 2, "interval_ms": 120,
			"variants": 3, "pitch": [0.9, 1.1]},
		&"servo_move_m": {"bus": &"Player", "class": C0, "prio": 25.0, "cap": 2, "interval_ms": 120,
			"variants": 3, "pitch": [0.9, 1.1]},
		&"servo_move_l": {"bus": &"Player", "class": C0, "prio": 28.0, "cap": 2, "interval_ms": 150,
			"variants": 2, "pitch": [0.92, 1.06]},
		&"hydraulic_release": {"bus": &"Player", "class": C0, "prio": 30.0, "cap": 1,
			"interval_ms": 200, "variants": 2},
		&"jump": {"bus": &"Player", "class": C0, "prio": 55.0, "cap": 1, "interval_ms": 120,
			"variants": 2, "pitch": [0.96, 1.05]},
		&"land_light": {"bus": &"Player", "class": C0, "prio": 55.0, "cap": 1, "variants": 3,
			"pitch": [0.94, 1.06]},
		&"land_heavy": {"bus": &"Impacts", "class": C3, "prio": 80.0, "cap": 1, "variants": 3,
			"far": "kill_large_far", "far_delay": true},
		&"hover_loop": {"bus": &"Player", "class": C0, "prio": 35.0, "cap": 1, "loop": true},
		&"flight_loop": {"bus": &"Player", "class": C0, "prio": 40.0, "cap": 1, "loop": true},
		&"boost_start": {"bus": &"Player", "class": C0, "prio": 70.0, "cap": 1, "interval_ms": 150},
		&"boost_slide_loop": {"bus": &"Player", "class": C0, "prio": 35.0, "cap": 1, "loop": true},
		&"dash": {"bus": &"Player", "class": C0, "prio": 60.0, "cap": 3, "interval_ms": 80,
			"variants": 3, "pitch": [0.95, 1.08]},
		&"assault_boost": {"bus": &"Player", "class": C0, "prio": 85.0, "cap": 1},
		&"boost_end": {"bus": &"Player", "class": C0, "prio": 40.0, "cap": 1, "variants": 2},
		&"energy_outage": {"bus": &"Cockpit", "class": C0, "prio": 85.0, "cap": 1,
			"interval_ms": 1500},
		&"camera_toggle": {"bus": &"UI", "class": C0, "prio": 60.0, "cap": 1, "variants": 2},
		&"hurt_light": {"bus": &"Player", "class": C0, "prio": 65.0, "cap": 2, "interval_ms": 90,
			"variants": 3},
		&"hurt_heavy": {"bus": &"Player", "class": C0, "prio": 88.0, "cap": 1, "interval_ms": 150,
			"variants": 2},
		# FEEL `last_stand`: the hit that takes the mech below 15 % and leaves it alive. The row's own
		# 60 s cooldown is the real limiter; the 5 s interval only stops a second pipeline (the
		# fx/tests re-fire) from doubling the moment.
		&"last_stand": {"bus": &"Player", "class": C0, "prio": 96.0, "cap": 1,
			"interval_ms": 5000},
		&"alarm_warning": {"bus": &"Cockpit", "class": C0, "prio": 92.0, "cap": 1,
			"interval_ms": 2500},
		&"alarm_caution": {"bus": &"Cockpit", "class": C0, "prio": 70.0, "cap": 1,
			"interval_ms": 1000},
		&"heartbeat_loop": {"bus": &"Cockpit", "class": C0, "prio": 30.0, "cap": 1, "loop": true},
	}
