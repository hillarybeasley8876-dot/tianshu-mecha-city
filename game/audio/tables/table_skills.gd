class_name AudioTableSkills
extends RefCounted
## Sound rows for skills S4-S8, overdrive/lance and the feedback layer (table_hero.gd has the keys).

const C0 := 0
const C2 := 2
const C3 := 3
const C4 := 4

static func rows() -> Dictionary:
	return {
		&"anchor_fire": {"bus": &"Player", "class": C0, "prio": 65.0, "cap": 1, "variants": 2},
		&"anchor_latch": {"bus": &"Player", "class": C2, "prio": 75.0, "cap": 1, "variants": 2},
		&"anchor_reel_loop": {"bus": &"Player", "class": C0, "prio": 40.0, "cap": 1, "loop": true},
		&"fins_launch": {"bus": &"Weapons", "class": C0, "prio": 80.0, "cap": 1, "variants": 2,
			"socket": &"wing_r"},
		&"fins_hit": {"bus": &"Impacts", "class": C2, "prio": 55.0, "cap": 6, "variants": 3},
		&"ward_up_loop": {"bus": &"Player", "class": C0, "prio": 40.0, "cap": 1, "loop": true},
		&"ward_hit": {"bus": &"Impacts", "class": C0, "prio": 60.0, "cap": 3, "variants": 3},
		&"ward_break": {"bus": &"Impacts", "class": C2, "prio": 85.0, "cap": 1},
		&"shockcore": {"bus": &"Impacts", "class": C3, "prio": 88.0, "cap": 1,
			"far": "kill_large_far", "far_delay": true},
		&"undertow_loop": {"bus": &"Weapons", "class": C3, "prio": 45.0, "cap": 1, "loop": true},
		&"collapse": {"bus": &"Impacts", "class": C3, "prio": 90.0, "cap": 1,
			"far": "kill_large_far", "far_delay": true},
		&"plunge_dive": {"bus": &"Player", "class": C0, "prio": 70.0, "cap": 1},
		&"plunge_land": {"bus": &"Impacts", "class": C4, "prio": 90.0, "cap": 1, "variants": 2,
			"far": "kill_large_far", "far_delay": true},
		&"overdrive_ignite": {"bus": &"Player", "class": C0, "prio": 95.0, "cap": 1},
		&"overdrive_loop": {"bus": &"Player", "class": C0, "prio": 35.0, "cap": 1, "loop": true},
		&"lance_charge": {"bus": &"Weapons", "class": C0, "prio": 90.0, "cap": 1},
		&"lance_fire": {"bus": &"Weapons", "class": C4, "prio": 98.0, "cap": 1,
			"far": "kill_large_far", "far_delay": true},
		&"skill_ready": {"bus": &"UI", "class": C0, "prio": 75.0, "cap": 1, "interval_ms": 500,
			"variants": 3},
		&"hitmarker": {"bus": &"UI", "class": C0, "prio": 100.0, "cap": 1, "interval_ms": 30},
		&"hitmarker_weak": {"bus": &"UI", "class": C0, "prio": 95.0, "cap": 1, "interval_ms": 30},
		&"kill_confirm": {"bus": &"UI", "class": C0, "prio": 100.0, "cap": 3, "interval_ms": 80},
		&"kill_small": {"bus": &"Impacts", "class": C2, "prio": 70.0, "cap": 3, "interval_ms": 80,
			"variants": 3, "far": "kill_large_far", "far_delay": true},
		# kill_large / stagger_enemy carry a short interval because one moment reaches the router
		# twice: EnemyBase emits Events.enemy_killed / enemy_staggered *and* calls
		# Feel.play(kill_large / stagger_enemy) for the hit-stop and VFX. Without the interval the
		# same impact stacked two copies of itself in the same frame.
		&"kill_large": {"bus": &"Impacts", "class": C4, "prio": 90.0, "cap": 2, "interval_ms": 60,
			"variants": 2, "far": "kill_large_far", "far_delay": true},
		# The brood titan's death. It LAYERS with kill_large rather than replacing it: the row's own
		# `fx/events/boss_kill.tres` audio column, brood_titan.gd's direct call and the router's
		# on_enemy_killed all land on kill_large (cap 2 + 60 ms interval, so it is one impact), and
		# this row is the climax on top - the titan's death cry, the sub drop and the long collapse,
		# deliberately without another explosion crack.
		&"boss_kill": {"bus": &"Impacts", "class": C4, "prio": 99.0, "cap": 1,
			"interval_ms": 3000, "far": "kill_large_far", "far_delay": true},
		&"kill_large_far": {"bus": &"Bed", "class": C4, "prio": 40.0, "cap": 3, "variants": 2},
		&"jackpot": {"bus": &"UI", "class": C0, "prio": 100.0, "cap": 1, "interval_ms": 1000},
		&"stagger_enemy": {"bus": &"Impacts", "class": C3, "prio": 82.0, "cap": 2, "interval_ms": 60,
			"variants": 2},
		&"boss_stagger": {"bus": &"Impacts", "class": C4, "prio": 92.0, "cap": 1},
		&"combo_rank_up": {"bus": &"UI", "class": C0, "prio": 85.0, "cap": 1, "interval_ms": 400,
			"variants": 2},
		&"ui_move": {"bus": &"UI", "class": C0, "prio": 100.0, "cap": 1, "interval_ms": 40},
		&"ui_confirm": {"bus": &"UI", "class": C0, "prio": 100.0, "cap": 1},
		&"ui_back": {"bus": &"UI", "class": C0, "prio": 100.0, "cap": 1},
		&"ui_pause": {"bus": &"UI", "class": C0, "prio": 100.0, "cap": 1},
		&"objective_update": {"bus": &"UI", "class": C0, "prio": 95.0, "cap": 1},
	}
