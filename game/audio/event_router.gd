class_name AudioEventRouter
extends Node
## Maps gameplay events onto sound ids (docs/FEEL.md sound column + ref/research/audio-music.md §3).
##
## Split out of audio.gd so the autoload stays a lifecycle + API file. `host` is the Audio autoload;
## every handler is a plain Callable so AudioVoicePool/AudioMusicDirector stay independent of it.

## Gatling state: the dossier's row 22 wants one loop plus a periodic accent and a release tail,
## never a voice per round. The weapons unit only reports `weapon_fired`, so the loop's lifetime is
## inferred from the gap between shots (15 rounds/s -> 200 ms between accents).
##
## The gap is counted on the *weapon's* clock (Feel.player_delta, same as gatling.gd's fire rate), not
## on wall time: a movie capture spends ~70 ms of wall time per frame, so at 15 rps a wall-clock gap
## reads 280 ms and would release and re-spin the loop after every round.
const GATLING_RELEASE_S := 0.25

var host: Node = null

var _gatling_idle_s: float = 0.0
var _gatling_loop_on: bool = false


func setup(audio_host: Node) -> void:
	host = audio_host
	process_mode = Node.PROCESS_MODE_ALWAYS


## Test/diagnostic view of the gatling loop's state (the release runs on the weapon's clock).
func gatling_loop_on() -> bool:
	return _gatling_loop_on


func add_heat(amount: float) -> void:
	if host.has_method("add_combat_heat"):
		host.add_combat_heat(amount)


func play(id: StringName, at: Vector3 = Vector3.INF, volume_db: float = 0.0) -> void:
	host.play(id, at, volume_db)


func play_loop(id: StringName, on: bool, at: Vector3 = Vector3.INF,
		volume_db: float = 0.0) -> void:
	host.play_loop(id, on, at, volume_db)


func voice(id: StringName, priority: float = 50.0, length_s: float = 1.2) -> void:
	host.voice(id, priority, length_s)


func stinger(id: StringName) -> void:
	host.stinger(id)


# --- FEEL ----------------------------------------------------------------------------------------------
func on_feel_event(event_id: StringName, at: Vector3, strength: float) -> void:
	var sound_id := AudioEventMap.sound_for_feel(event_id)
	if not host.events.has(sound_id):
		host.warn_once(sound_id)
		return
	var volume := linear_to_db(clampf(strength, 0.1, 2.0))
	play(sound_id, at, volume)
	for extra in AudioEventMap.extras_for_feel(event_id):
		play_extra(extra, at)
	if event_id in [&"kill_small", &"kill_large", &"boss_kill", &"melee_heavy", &"missile_hit"]:
		add_heat(0.65)
	elif event_id in [&"rifle_fire", &"gatling_fire", &"melee_light"]:
		add_heat(0.5)
	if event_id == &"hurt_heavy":
		host.mixer.hurt_dip()
	# FEEL's sound column for both kill rows ends "; world -6 dB": the kill owns the moment. boss_kill
	# holds the duck for its 1.2 s of 0.2x slow-mo, kill_large for its 0.35 s.
	if event_id == &"boss_kill":
		host.mixer.duck_world(AudioMixer.WORLD_DUCK_DB, 1.2)
	elif event_id == &"kill_large":
		host.mixer.duck_world(AudioMixer.WORLD_DUCK_DB, 0.5)
	if event_id == &"finisher":
		voice(&"ai_execution_ready", 80.0, 1.4)


func play_extra(extra: StringName, at: Vector3) -> void:
	if String(extra).begins_with("ai_"):
		voice(extra, 60.0, 1.3)
	elif String(extra).begins_with("stinger_"):
		stinger(extra)
	else:
		play(extra, at)


# --- combat events ---------------------------------------------------------------------------------------
## Impact sound for one landed hit. The weapon id decides first (it is the precise answer); the hit
## kind is the fallback for anything that did not name a weapon (CONTRACTS §4, HitInfo.weapon/kind).
const WEAPON_SOUNDS: Dictionary = {
	&"beam_rifle": &"rifle_hit", &"rifle_stage1": &"rifle_hit", &"rifle_stage2": &"rifle_stage2_hit",
	&"gatling": &"gatling_hit", &"hailstorm": &"missile_hit", &"zenith_lance": &"lance_fire",
	&"melee_l1": &"melee_light", &"melee_l2": &"melee_light", &"melee_l3": &"melee_heavy",
	&"air_l1": &"melee_light", &"air_l2": &"melee_light", &"ram_kick": &"melee_heavy",
	&"lunge": &"lunge_hit", &"charge_slash": &"charge_slash", &"crescent_wave": &"charge_slash",
	&"return_cut": &"finisher", &"core_rend": &"finisher", &"core_rupture": &"finisher",
	&"mirror_guard": &"block",
	&"mantis_slash": &"mantis_swing", &"juggernaut_slam": &"jugg_slam",
	&"spitter_acid": &"acid_lob", &"ripper_bite": &"ripper_bite",
}

const KIND_SOUNDS: Dictionary = {
	HitInfo.BEAM: &"rifle_hit", HitInfo.BALLISTIC: &"gatling_hit",
	HitInfo.EXPLOSIVE: &"missile_hit", HitInfo.MELEE: &"melee_light",
	HitInfo.EMP: &"fins_hit", HitInfo.CRUSH: &"land_heavy",
}


func on_hit_landed(hit: HitInfo, receiver: Node) -> void:
	var at := node_position(receiver)
	var sound_id := &"rifle_hit"
	if hit != null:
		sound_id = WEAPON_SOUNDS.get(hit.weapon, KIND_SOUNDS.get(hit.kind, &"rifle_hit"))
	play(&"kill_confirm" if hit != null and hit.finisher else &"hitmarker", Vector3.INF)
	play(sound_id, at)
	add_heat(0.55)


func on_player_damaged(hit: HitInfo) -> void:
	play(&"hurt_light" if hit == null or hit.final_amount < 120.0 else &"hurt_heavy")


func on_enemy_staggered(enemy: Node, _hit: HitInfo) -> void:
	var boss := enemy != null and enemy.has_method("get_team") and is_boss(enemy)
	play(&"boss_stagger" if boss else &"stagger_enemy", node_position(enemy))
	stinger(&"stinger_stagger")
	voice(&"ai_target_staggered", 70.0, 1.2)


func on_enemy_killed(enemy: Node, _hit: HitInfo) -> void:
	var at := node_position(enemy)
	play(&"kill_large" if is_boss(enemy) or is_large(enemy) else &"kill_small", at)
	# The archetype's own death cry rides on top of the generic kill impact (dossier §1.4: the
	# recorded creature layer). Without it a HUSK dies with a metal thud and no voice at all.
	var cry := death_sound(enemy_type(enemy))
	if cry != &"":
		play(cry, at)
	play(&"kill_confirm")
	add_heat(0.7)


func on_attack_blocked(_hit: HitInfo) -> void:
	play(&"block")


func on_parry_success(_hit: HitInfo, _attacker: Node) -> void:
	play(&"parry_perfect")


func on_weapon_fired(weapon: StringName, muzzle: Vector3, _direction: Vector3) -> void:
	match weapon:
		&"rifle": play(&"rifle_fire", muzzle)
		&"gatling":
			_gatling_idle_s = 0.0
			if not _gatling_loop_on:
				_gatling_loop_on = true
				play(&"gatling_spin_up")
				play_loop(&"gatling_fire_loop", true)
			play(&"gatling_fire_accent", muzzle)
		&"missiles": play(&"missile_launch", muzzle)
		_: play(&"rifle_fire", muzzle)
	add_heat(0.55)


func on_weapon_switched(_weapon: StringName) -> void:
	play(&"weapon_switch")


func on_melee_swing(_move: StringName, step: int) -> void:
	play(&"saber_swing_3" if step >= 3 else (&"saber_swing_2" if step == 2 else &"saber_swing"))


func on_skill_used(skill: StringName) -> void:
	match skill:
		&"fins": play(&"fins_launch")
		&"ward": play_loop(&"ward_up_loop", true)
		&"anchor": play(&"anchor_fire")
		&"well": play_loop(&"undertow_loop", true)
		&"plunge": play(&"plunge_dive")
		_: play(&"skill_ready")
	add_heat(0.6)


func on_skill_ready(_skill: StringName) -> void:
	play(&"skill_ready")
	voice(&"ai_skill_ready", 40.0, 1.1)


func on_lock_changed(target: Node3D) -> void:
	play(&"lock_on" if target != null else &"lock_off")
	if target != null:
		voice(&"ai_target_locked", 45.0, 1.1)


func on_missiles_locked(count: int) -> void:
	play(&"missile_lock_full" if count >= 12 else &"missile_lock_tick")


func on_overdrive_changed(active: bool) -> void:
	play(&"overdrive_ignite")
	play_loop(&"overdrive_loop", active)
	if active:
		voice(&"ai_overdrive_engaged", 70.0, 1.3)


func on_combo_changed(count: int, rank: StringName) -> void:
	if count > 0 and rank in [&"A", &"S", &"SS", &"SSS"]:
		play(&"combo_rank_up")
		voice(&"ai_combo_rank", 35.0, 1.1)


func on_enemy_telegraph(enemy: Node, attack: StringName, kind: StringName) -> void:
	var at := node_position(enemy)
	var type_id := enemy_type(enemy)
	var tell := telegraph_sound(type_id)
	if tell != &"":
		play(tell, at)
	if kind == &"unblockable":
		play(&"alarm_warning")
		voice(&"ai_incoming_unblockable", 85.0, 1.4)
	add_heat(0.6)


## Release the gatling loop after GATLING_RELEASE_S of silence on the weapon's own clock. Counted in
## _physics_process (the tick the gatling itself fires on) and PROCESS_MODE_ALWAYS, so a pause still
## releases the loop.
func _physics_process(delta: float) -> void:
	if not _gatling_loop_on:
		return
	_gatling_idle_s += Feel.player_delta(delta)
	if _gatling_idle_s < GATLING_RELEASE_S:
		return
	_gatling_loop_on = false
	play_loop(&"gatling_fire_loop", false)
	play(&"gatling_spin_down")
	play(&"gatling_tail")


# --- movement events ------------------------------------------------------------------------------------
func on_boost_started(kind: StringName) -> void:
	match kind:
		&"quick":
			play(&"dash")
			play(&"hydraulic_release")
		&"slide":
			play(&"boost_start")
			play_loop(&"boost_slide_loop", true)
		&"assault":
			play(&"assault_boost")
			play_loop(&"flight_loop", true)
		_:
			play(&"boost_start")


func on_boost_ended(kind: StringName) -> void:
	play(&"boost_end")
	if kind == &"slide":
		play_loop(&"boost_slide_loop", false)
	elif kind == &"assault":
		play_loop(&"flight_loop", false)


func on_landed(impact_speed: float) -> void:
	play(&"land_heavy" if impact_speed > 25.0 else &"land_light")


func on_footstep(_position: Vector3, heavy: bool) -> void:
	play(&"footstep_hero_heavy" if heavy else &"footstep_hero")


func on_flight_changed(flying: bool) -> void:
	play_loop(&"flight_loop", flying)
	play_loop(&"hover_loop", false)


func on_camera_mode_changed(first_person: bool) -> void:
	play(&"camera_toggle")
	host.mixer.set_first_person(first_person)


# --- flow events ----------------------------------------------------------------------------------------
func on_encounter_started(id: StringName) -> void:
	add_heat(0.8)
	play(&"alarm_caution")
	voice(&"ai_enemies_remaining", 50.0, 1.2)


func on_encounter_cleared(_id: StringName) -> void:
	add_heat(0.3)
	voice(&"ai_objective_done", 65.0, 1.4)


## The spire's own stinger; the flow speaks 「蚀巢已摧毁 n/3」 itself, so no voice line here.
func on_spire_destroyed(_spire: Node3D, _destroyed: int, _total: int) -> void:
	add_heat(0.5)
	stinger(&"stinger_spire_cleared")


## Boss title card: the score goes to boss, the alarm cuts through, the cockpit calls the contact.
func on_boss_intro(_title: String, _subtitle: String) -> void:
	stinger(&"stinger_boss_phase")
	play(&"alarm_warning")
	voice(&"ai_titan_approach", 95.0, 1.6)
	host.music_intensity(1.0)
	add_heat(1.0)


func on_boss_phase(phase: int) -> void:
	stinger(&"stinger_boss_phase")
	voice(&"ai_boss_phase_2" if phase == 2 else &"ai_boss_phase_3", 90.0, 1.5)
	host.music_intensity(1.0)


func on_objective_changed(_text: String) -> void:
	play(&"objective_update")
	voice(&"ai_objective_new", 55.0, 1.3)


func on_paused_changed(paused: bool) -> void:
	play(&"ui_pause")
	host.mixer.set_paused(paused)


func on_player_spawned(_player_node: Node3D) -> void:
	voice(&"ai_systems_online", 80.0, 1.6)


## COLLAPSE detonation (CONTRACTS §4): one detonation sound per blast, the count only lifts the mix.
func on_prime_collapsed(center: Vector3, count: int) -> void:
	play(&"collapse", center, 2.0 if count >= 3 else 0.0)
	play(&"debris_metal", center)
	add_heat(0.7)


## A staggered enemy is in Core Rend reach: the payoff prompt.
func on_execution_ready(enemy: Node) -> void:
	play(&"combo_rank_up")
	voice(&"ai_execution_ready", 75.0, 1.4)


func on_world_ready() -> void:
	"""The city exists: bring up the layer beds (SPEC §2 heights)."""
	play_loop(&"amb_tunnel_hum", true, Vector3(0, -30, 0), -10.0)
	play_loop(&"amb_street", true, Vector3.ZERO, -8.0)
	play_loop(&"amb_wind_high", true, Vector3(0, 120, 0), -14.0)
	play_loop(&"distant_battle_bed", true, Vector3(0, 60, -400), -16.0)
	voice(&"ai_systems_online", 70.0, 1.6)


func on_simple(id: StringName) -> void:
	play(id)


# --- helpers ----------------------------------------------------------------------------------------------
func node_position(node: Node) -> Vector3:
	return (node as Node3D).global_position if node is Node3D else host.chest_position()


func enemy_type(enemy: Node) -> StringName:
	if enemy == null:
		return &""
	# `enemy_type` first: that is the property EnemyBase actually declares (enemies/enemy_base.gd).
	# The other three are the names earlier prototypes used, kept so a stand-in still classifies.
	for key in [&"enemy_type", &"type_id", &"archetype", &"type"]:
		if key in enemy:
			return StringName(enemy.get(key))
	return &""


## Enemy telegraph sounds (dossier §1.4): every one is a gameplay-critical cue, priority 80.
func telegraph_sound(type_id: StringName) -> StringName:
	match type_id:
		&"ripper": return &"ripper_leap_tell"
		&"mantis": return &"mantis_glint"
		&"spitter": return &"spitter_charge"
		&"harrier": return &"harrier_screech"
		&"juggernaut": return &"jugg_roar"
		&"titan": return &"titan_roar"
	return &""


## The archetype's death cry. Only the archetypes with a dedicated recorded vocal get one; the rest
## fall back to the generic kill impact plus debris, which is already playing.
func death_sound(type_id: StringName) -> StringName:
	match type_id:
		&"ripper": return &"ripper_death"
		&"mantis": return &"mantis_death"
		&"spitter": return &"spitter_death"
		&"harrier": return &"harrier_death"
		&"juggernaut": return &"jugg_roar"
		&"titan", &"boss", &"brood_titan": return &"boss_roar"
	return &""


func is_boss(enemy: Node) -> bool:
	return enemy_type(enemy) in [&"titan", &"boss", &"brood_titan"]


func is_large(enemy: Node) -> bool:
	return enemy_type(enemy) in [&"juggernaut", &"spitter", &"mantis"]
