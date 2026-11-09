class_name AudioTableAliases
extends RefCounted
## Alias table for sound ids that other units call.
##
## The feel unit's FeelEvent resources name one id per *layer* of a row (docs/FEEL.md's sound
## column, e.g. `land_heavy` -> land_thud + land_heavy_body + land_heavy_sub + land_hydraulics),
## following the dossier §1.2 advice to design layers separately. We mix those layers into one file
## per event, so each layer id resolves to that event's mix; the voice pool's per-event cap then keeps
## the row to a single voice instead of four copies of the same hit.

const ALIASES: Dictionary = {
	# --- locomotion ---
	&"footstep_clank": &"footstep_hero", &"footstep_thump": &"footstep_hero",
	&"land_thud": &"land_heavy", &"land_heavy_body": &"land_heavy",
	&"land_heavy_sub": &"land_heavy", &"land_hydraulics": &"hydraulic_release",
	&"jump_thrust": &"jump", &"jump_servo": &"jump",
	&"dash_chuff": &"dash", &"dash_whoosh": &"dash",
	&"boost_ignition": &"boost_start", &"boost_sub_40hz": &"boost_start",
	&"boost_roar_loop": &"boost_slide_loop", &"assault_boost_boom": &"assault_boost",
	&"rift_reverse_whoosh": &"rift_out", &"rift_thump": &"rift_out",
	# --- P1 rifle ---
	&"beam_rifle_fire": &"rifle_fire", &"beam_rifle_mech": &"rifle_fire",
	&"beam_rifle_hit": &"rifle_hit", &"beam_rifle_hit_body": &"rifle_hit",
	&"beam_charge_stage_1": &"rifle_charge_1",
	&"beam_charge_stage_2": &"rifle_charge_2", &"beam_charge_stage_click": &"rifle_charge_2",
	&"beam_stage2_hit": &"rifle_stage2_hit", &"beam_stage2_body": &"rifle_stage2_hit",
	&"beam_stage2_sub": &"rifle_stage2_hit",
	# --- P2 gatling ---
	&"gatling_spin": &"gatling_spin_up", &"gatling_vent_hiss": &"gatling_vent",
	&"ui_vent_chime": &"gatling_vent_perfect",
	# --- S3 missiles ---
	&"missile_hit_body": &"missile_hit", &"missile_hit_sub": &"missile_hit",
	&"missile_hit_transient": &"missile_hit",
	# --- melee ---
	&"melee_light_transient": &"melee_light", &"melee_light_body": &"melee_light",
	&"melee_servo": &"melee_light",
	&"melee_heavy_transient": &"melee_heavy", &"melee_heavy_body": &"melee_heavy",
	&"melee_heavy_sub": &"melee_heavy",
	&"lunge_whoosh": &"lunge_hit", &"lunge_transient": &"lunge_hit", &"lunge_body": &"lunge_hit",
	&"charge_slash_transient": &"charge_slash", &"charge_slash_body": &"charge_slash",
	&"charge_slash_sub": &"charge_slash",
	&"finisher_swell": &"finisher", &"finisher_transient": &"finisher", &"finisher_body": &"finisher",
	# --- defence ---
	&"parry_ting": &"parry_perfect", &"parry_thump": &"parry_perfect",
	&"shield_block_clank": &"block", &"catch_release_whoomp": &"catch_release",
	&"dodge_reverse_whoosh": &"perfect_dodge", &"dodge_heartbeat": &"perfect_dodge",
	# --- skills ---
	&"anchor_twang": &"anchor_fire", &"anchor_clank": &"anchor_latch",
	&"fins_launch_chime": &"fins_launch", &"ward_glass_ring": &"ward_hit",
	&"shockcore_inhale": &"shockcore", &"shockcore_boom": &"shockcore",
	&"collapse_reverse_cymbal": &"collapse", &"collapse_boom": &"collapse",
	&"plunge_whistle": &"plunge_dive", &"plunge_boom": &"plunge_land",
	&"plunge_sub_60hz": &"plunge_land",
	&"overdrive_swell": &"overdrive_ignite", &"overdrive_roar": &"overdrive_ignite",
	&"lance_riser": &"lance_charge", &"lance_roar": &"lance_fire", &"lance_sub": &"lance_fire",
	# --- damage and feedback ---
	&"hurt_light_ping": &"hurt_light", &"hurt_light_body": &"hurt_light",
	&"hurt_heavy_transient": &"hurt_heavy", &"hurt_heavy_body": &"hurt_heavy",
	&"hurt_heavy_sub": &"hurt_heavy", &"near_miss_flyby": &"near_miss",
	&"kill_small_body": &"kill_small", &"kill_small_debris": &"debris_concrete",
	&"kill_large_transient": &"kill_large", &"kill_large_body": &"kill_large",
	&"kill_large_sub": &"kill_large", &"ui_kill_confirm": &"kill_confirm",
	&"ui_jackpot": &"jackpot", &"ui_stagger": &"stagger_enemy",
	&"stagger_groan": &"stagger_enemy", &"boss_groan": &"boss_stagger",
	&"boss_stagger_sub": &"boss_stagger", &"boss_stagger_stinger": &"stinger_stagger",
	# --- ids the enemies unit calls directly (there is no Events signal for either moment) ---
	# enemy_shockwave.gd spawns the ring; juggernaut.gd breaks a plate off. Both are one-shot,
	# positional and have no other voice, so they alias onto the bank rows built for them.
	&"juggernaut_slam": &"jugg_slam", &"juggernaut_plate_break": &"jugg_plate_break",
	# flow/hive_spire.gd bursts an acid pod with this id; it is the same Core Rend crack the hit
	# router already maps the `core_rupture` weapon to (event_router.gd WEAPON_SOUNDS).
	&"core_rupture": &"finisher",
	# Remaining layer ids from the FEEL resources (docs/FEEL.md sound column).
	&"gatling_fire": &"gatling_fire_accent", &"footstep_heavy": &"footstep_hero_heavy",
	&"rift_step": &"rift_out", &"cockpit_alarm": &"alarm_warning",
	&"land_heavy_transient": &"land_heavy", &"land_heavy_debris": &"debris_concrete",
	&"missile_hit_debris": &"debris_metal", &"missile_hit_tail": &"kill_large_far",
	&"kill_large_debris": &"debris_metal", &"kill_large_tail": &"kill_large_far",
	&"charge_slash_tail": &"kill_large_far",
	&"finisher_sub": &"finisher", &"finisher_tail": &"kill_large_far",
}
