class_name AudioTableWorld
extends RefCounted
## Ambience beds, emitters, destruction, music stingers and the cockpit AI voice lines.
## Table_hero.gd documents the row keys; `dir` selects the folder under res://audio/ (default sfx).

const C0 := 0
const C1 := 1
const C2 := 2
const C3 := 3
const C4 := 4
const C6 := 6

static func rows() -> Dictionary:
	var rows: Dictionary = {
		&"amb_tunnel_hum": {"bus": &"Bed", "class": C0, "prio": 20.0, "cap": 1, "loop": true,
			"ext": "ogg"},
		&"amb_street": {"bus": &"Bed", "class": C0, "prio": 20.0, "cap": 1, "loop": true,
			"ext": "ogg"},
		&"amb_wind_high": {"bus": &"Bed", "class": C0, "prio": 20.0, "cap": 1, "loop": true,
			"ext": "ogg"},
		&"amb_storm_crown": {"bus": &"Bed", "class": C0, "prio": 20.0, "cap": 1, "loop": true,
			"ext": "ogg"},
		&"distant_battle_bed": {"bus": &"Bed", "class": C0, "prio": 15.0, "cap": 1, "loop": true,
			"ext": "ogg"},
		&"siren_emitter": {"bus": &"Bed", "class": C4, "prio": 15.0, "cap": 4, "variants": 2},
		&"maglev_pass": {"bus": &"Bed", "class": C3, "prio": 18.0, "cap": 2},
		&"neon_buzz": {"bus": &"Bed", "class": C6, "prio": 10.0, "cap": 8, "loop": true},
		&"glass_shatter": {"bus": &"Impacts", "class": C2, "prio": 30.0, "cap": 4, "variants": 3},
		&"debris_concrete": {"bus": &"Impacts", "class": C2, "prio": 20.0, "cap": 6, "variants": 3},
		&"debris_metal": {"bus": &"Impacts", "class": C2, "prio": 20.0, "cap": 6, "variants": 3},
	}
	rows.merge(_stingers())
	rows.merge(_voice_lines())
	return rows


static func _stingers() -> Dictionary:
	var out: Dictionary = {}
	for id in [&"stinger_stagger", &"stinger_kill_large", &"stinger_boss_phase",
			&"stinger_spire_cleared", &"stinger_victory", &"stinger_defeat"]:
		out[id] = {"bus": &"Stinger", "class": C0, "prio": 90.0, "cap": 1, "interval_ms": 2000,
			"ext": "ogg", "dir": "music/stingers"}
	return out


## 46 cockpit AI lines (Chinese with English tags), minimax speech-2.8-hd, labelled AI-generated.
static func _voice_lines() -> Dictionary:
	var out: Dictionary = {}
	for id in [
		&"ai_boot", &"ai_systems_online", &"ai_target_locked", &"ai_target_lost",
		&"ai_energy_low", &"ai_energy_restored", &"ai_armor_75", &"ai_armor_50",
		&"ai_armor_25", &"ai_armor_critical", &"ai_missile_alert", &"ai_incoming_unblockable",
		&"ai_overdrive_ready", &"ai_overdrive_engaged", &"ai_skill_ready", &"ai_parry_perfect",
		&"ai_combo_rank", &"ai_target_staggered", &"ai_execution_ready", &"ai_kill_confirm",
		&"ai_multi_kill", &"ai_gatling_heat", &"ai_vent_now", &"ai_reload", &"ai_ammo_low",
		&"ai_spire_down_1", &"ai_spire_down_2", &"ai_spire_down_3", &"ai_district_clear",
		&"ai_titan_approach", &"ai_titan_roar", &"ai_boss_phase_2", &"ai_boss_phase_3",
		&"ai_boss_staggered", &"ai_boss_core_exposed", &"ai_ultimate_ready", &"ai_lance_fired",
		&"ai_objective_new", &"ai_objective_done", &"ai_enemies_remaining", &"ai_rift_unstable",
		&"ai_barrier_down", &"ai_drone_link", &"ai_anchor_locked", &"ai_well_charged",
		&"ai_victory", &"ai_failure",
	]:
		out[id] = {"bus": &"Voice", "class": C0, "prio": 95.0, "cap": 1, "interval_ms": 8000,
			"ext": "ogg", "dir": "voice"}
	return out
