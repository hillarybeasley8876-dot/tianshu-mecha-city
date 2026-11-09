class_name BossTuning
extends RefCounted
## Every Brood Titan number (boss unit). Sources: SPEC §7/§7.1, skills-catalog §4.6 (Colossus row),
## juice-impact §11.1 (boss windups), MAP §2/§4 (the Crown). Nothing else in `enemies/boss/**`
## invents a number: it all comes from here so a balance pass edits one file.
##
## Scale note: the titan is 60 m against a 16 m hero. Ranges below are absolute metres, already at
## that scale (the dossier's ×2 rule applies to the 8 m-hero numbers, not to these).

const TYPE := &"titan"
const DISPLAY_NAME := "巢母 BROOD TITAN"

# --- pools -------------------------------------------------------------------------------------
const HP_MAX := 150000.0
const STABILITY := 9000.0
const STABILITY_DECAY := 0.08      ## fraction of max per second
const DECAY_DELAY := 2.0
const STAGGER_TIME := 3.4
const STAGGER_IMMUNITY := 6.0

const CORE_HP := 8000.0
## SPEC §7.1: a hit on a core counts ×1.0 against the main pool and ×2.5 against the core pool.
const CORE_MAIN_MULT := 1.0
const CORE_POOL_MULT := 2.5
## skills-catalog §4.6: Core Rend on a Colossus is 12 % of max HP and is NOT lethal.
const EXECUTE_FRACTION := 0.12

const HEIGHT := 60.0
const RADIUS := 18.0
const MASS := 400.0
const TURN_RATE := 55.0            ## deg/s — slow on purpose: flanking is the whole fight
const MOVE_SPEED := 16.0
const SIGHT := 1200.0
const ENGAGE := 90.0

# --- per-part armour (EnemyTypes.ARMOUR has no titan row and is enemies-owned, so it lives here) --
const ARMOUR: Dictionary = {
	&"body": 1.0, &"head": 0.6, &"legs": 0.5,
	&"core_l": 1.0, &"core_r": 1.0, &"core_chest": 1.0,
}

## The three weak cores: id, hurtbox part, local position on the 60 m body, the attack its break
## removes, and the display name the HUD plate shows.
const CORES: Array[Dictionary] = [
	{"id": &"l_shoulder", "part": &"core_l", "pos": Vector3(-15.5, 44.0, -4.0),
		"removes": &"titan_swipe", "label": "L 肩"},
	{"id": &"r_shoulder", "part": &"core_r", "pos": Vector3(15.5, 44.0, -4.0),
		"removes": &"titan_summon", "label": "R 肩"},
	{"id": &"chest", "part": &"core_chest", "pos": Vector3(0.0, 37.0, -8.5),
		"removes": &"titan_beam", "label": "胸"},
]
const CORE_RADIUS := 4.6

# --- phases ------------------------------------------------------------------------------------
## SPEC §7.1 uptime targets: P1 90 s, P2 120 s, P3 90 s. The thresholds cut the 150k pool into
## 52.5k / 52.5k / 45k, which at ~50 % uptime of the 1,000 DPS player is 105 / 105 / 90 s.
const PHASE_THRESHOLDS: Array[float] = [0.65, 0.30]
const PHASE_COUNT := 3
## The 2–3 s roar the player watches between phases (brief §4).
const PHASE_CINEMATIC := 2.6
const INTRO_CINEMATIC := 7.0
const DEATH_CINEMATIC := 4.0       ## Events.game_won fires this long after the killing blow
## The title card at the intro roar (CONTRACTS §6 `Events.boss_intro`): the HUD draws it, audio plays
## a stinger. Subtitle = where the player is standing when they read it.
const INTRO_SUBTITLE := "CROWN DECK +224 — SPIRE OF THE HIVE"
## CONTRACTS §5 "Large-target framing": a hard-locked target this tall makes the rig lengthen its arm
## and raise its pitch, so the hero and the titan's head share the frame.
const FRAMING_HEIGHT := HEIGHT

# --- the death beat (brief §5) -------------------------------------------------------------------
## The chain of `kill_large` blasts climbs the body over this long, while it is still standing and
## the camera can see it; the topple and the slide over the rim run over COLLAPSE_TIME after that.
const COLLAPSE_BLAST_TIME := 1.5
const COLLAPSE_BLASTS := 6
## `kill_large` is a 28 m fireball (VfxPresets.RADIUS): six of them at scale 1.4 whited out the whole
## 60 m body and the capture showed a white silhouette instead of a toppling titan. Small enough that
## each blast reads as a bloom ON the body, big enough to still be a blast.
const COLLAPSE_BLAST_SCALE := 0.8
const COLLAPSE_TIME := 3.0
const COLLAPSE_FALL_DEG := 88.0
## Tuned from the capture: at 26 m/s and 70 m the body cleared the rim in under 2 s and the camera was
## looking at an empty deck before the victory beat had started.
const COLLAPSE_SLIDE := 17.0        ## m/s the body slides outward as it goes over the rim
const COLLAPSE_DROP := 34.0         ## m it has fallen below the deck by the end of the topple
## Dust and smoke bloom out of the rim where the body crossed it, and keep burning through the
## victory beat.
const COLLAPSE_DUST_SCALE := 3.0
const COLLAPSE_SMOKE_TIME := 14.0

## Which attacks each phase may pick, before cores remove any.
const PHASE_ATTACKS: Array[Array] = [
	[&"titan_stomp", &"titan_swipe", &"titan_summon", &"titan_tail"],
	[&"titan_stomp", &"titan_swipe", &"titan_summon", &"titan_tail", &"titan_beam"],
	[&"titan_stomp", &"titan_swipe", &"titan_summon", &"titan_tail", &"titan_beam",
		&"titan_lightning"],
]
## P2: "faster swipes". P3: everything comes out 25 % quicker again.
const PHASE_SPEED: Array[float] = [1.0, 0.88, 0.75]
## SPEC §7.1 "unblockables ≥ 600 ms (boss ≥ 800 ms)" and a parryable glint ≥ 400 ms. Phase speed
## scaling may never push a windup under these, so the fight gets faster without getting unfair.
const BOSS_MIN_UNBLOCKABLE := 0.85
const BOSS_MIN_PARRYABLE := 0.50
## P3 "enraged combos": this many attacks are chained before the titan rests.
const PHASE_CHAIN: Array[int] = [1, 1, 2]
const PHASE_REST: Array[float] = [1.6, 1.3, 0.7]

# --- attacks -----------------------------------------------------------------------------------
## juice §11.1: a boss heavy wants a 700–1,200 ms windup, a boss perilous 900–1,400 ms. Every
## unblockable below is ≥ 0.8 s (SPEC §7.1 "boss ≥ 800 ms") and every parryable ≥ 0.4 s of glint.
## Knockback is deliberately modest: the arena is a 300 m disc with a 224 m drop, and a shove
## that reads as "hit hard" at 60 m scale would otherwise throw the player off the crown every hit.
const STOMP := {
	"id": &"titan_stomp", "kind": EnemyAttack.UNBLOCKABLE, "telegraph": 0.9, "active": 0.35,
	"recover": 1.5, "damage": 2200.0, "impact": 900.0, "knockback": 20.0, "range_min": 0.0,
	"range_max": 110.0, "arc_deg": 360.0, "cooldown": 6.0, "weight": 1.3,
	"shockwave_radius": 80.0, "hit_kind": HitInfo.CRUSH, "anim": &"stomp",
}
const SWIPE := {
	"id": &"titan_swipe", "kind": EnemyAttack.PARRYABLE, "telegraph": 1.1, "active": 0.28,
	"recover": 1.2, "damage": 1800.0, "impact": 700.0, "knockback": 22.0, "range_min": 0.0,
	"range_max": 85.0, "arc_deg": 120.0, "cooldown": 3.2, "weight": 1.6, "anim": &"swipe",
}
const BEAM := {
	"id": &"titan_beam", "kind": EnemyAttack.UNBLOCKABLE, "telegraph": 1.4, "active": 4.0,
	"recover": 2.0, "damage": 900.0, "impact": 0.0, "knockback": 10.0, "range_min": 60.0,
	"range_max": 460.0, "arc_deg": 360.0, "cooldown": 16.0, "weight": 1.1, "anim": &"beam_breath",
}
const SUMMON := {
	"id": &"titan_summon", "kind": EnemyAttack.RANGED, "telegraph": 1.2, "active": 0.4,
	"recover": 1.6, "damage": 0.0, "impact": 0.0, "knockback": 0.0, "range_min": 0.0,
	"range_max": 420.0, "arc_deg": 360.0, "cooldown": 25.0, "weight": 0.7, "anim": &"summon",
}
## Rear only: the arc is measured from the tail, not the face (see BroodTitan.rear_arc_hit).
const TAIL := {
	"id": &"titan_tail", "kind": EnemyAttack.UNBLOCKABLE, "telegraph": 1.0, "active": 0.35,
	"recover": 1.4, "damage": 2000.0, "impact": 800.0, "knockback": 26.0, "range_min": 0.0,
	"range_max": 75.0, "arc_deg": 200.0, "cooldown": 7.0, "weight": 1.0, "anim": &"tail_sweep",
}
const LIGHTNING := {
	"id": &"titan_lightning", "kind": EnemyAttack.UNBLOCKABLE, "telegraph": 1.0, "active": 0.4,
	"recover": 0.9, "damage": 1600.0, "impact": 600.0, "knockback": 16.0, "range_min": 0.0,
	"range_max": 420.0, "arc_deg": 360.0, "cooldown": 4.5, "weight": 1.4, "anim": &"roar",
}

const ATTACK_ROWS: Dictionary = {
	&"titan_stomp": STOMP, &"titan_swipe": SWIPE, &"titan_beam": BEAM,
	&"titan_summon": SUMMON, &"titan_tail": TAIL, &"titan_lightning": LIGHTNING,
}

# --- adds --------------------------------------------------------------------------------------
const SUMMON_RIPPERS := 6
const SUMMON_HARRIERS := 2
const SUMMON_CAP := 10            ## live adds; a summon over the cap is skipped, not queued
const SUMMON_RADIUS := 130.0      ## m from the titan, on the deck edge

# --- beam breath -------------------------------------------------------------------------------
const BEAM_LENGTH := 420.0
const BEAM_WIDTH := 14.0
const BEAM_SWEEP_DEG := 150.0     ## total sweep across the deck over the active window
const BEAM_TICK := 0.25           ## s between damage ticks
const BEAM_ORIGIN_HEIGHT := 48.0  ## the mouth, above the player's flight ceiling on the deck
## Behind the central core the beam cannot reach — the cover the arena's Ø80 core is there for.
const BEAM_BLIND_HEIGHT := 26.0

# --- phase-3 storm -----------------------------------------------------------------------------
const STORM_AMOUNT := 1.0
const STORM_SECONDS := 6.0
const LIGHTNING_CIRCLES := 3
const LIGHTNING_RADIUS := 16.0
const LIGHTNING_SPREAD := 90.0

# --- arena (MAP §2/§4, layout `B1_crown`) -------------------------------------------------------
## The Crown is a stepped ziggurat: three concentric rings RISING toward the centre (layout
## `B1_crown.rim_steps` r150/r126/r104, 8 m apart), a Ø80 core on the top ring that the titan circles
## and the player hides behind, and four 24 m fins at 45°. The outer ring is cut into RIM_SEGMENTS
## wedges, which are the only floor out there — so a wedge that breaks is a hole.
const DECK_Y := 224.0
## Centre of the Crown in Godot space. It is NOT the map origin: `data/map/city_layout.json` puts
## `B1_crown` and the `spire` landmark at Blender (0, 120), which is Godot (0, 224, -120).
const CROWN_CENTRE := Vector3(0.0, DECK_Y, -120.0)
## Below this the player is somewhere in the city and the director does not even look for the deck:
## the Crown is at +224 and the S4 ring the catapult catches is at +160.
const CROWN_SEARCH_Y := 150.0
const DECK_RADIUS := 150.0        ## Ø300
const RIM_STEPS: Array[Dictionary] = [
	{"radius": 150.0, "rise": 0.0}, {"radius": 126.0, "rise": 8.0}, {"radius": 104.0, "rise": 16.0},
]
const CORE_COVER_RADIUS := 40.0   ## Ø80 the titan circles and the player hides behind
const CORE_COVER_HEIGHT := 32.0
const FIN_COUNT := 4
const FIN_HEIGHT := 24.0
const FIN_WIDTH := 16.0
const FIN_ANGLE_DEG := 45.0
const RIM_SEGMENTS := 12
const RIM_SEGMENTS_BROKEN := 4    ## P2: this many rim segments fall away
## Falling off the crown puts the player on the S4 ring; the catapult throws them back inside this.
const CATAPULT_DELAY := 3.0
const CATAPULT_TIMEOUT := 12.0
const CATAPULT_SPEED := 90.0

# --- skyline walker ----------------------------------------------------------------------------
const WALKER_RADIUS := 820.0      ## outside the ±700 playable square, inside the ±900 skyline
const WALKER_SPEED := 14.0
const WALKER_HEIGHT := 90.0       ## the titan_skyline model at ×1.5
const WALKER_Y := 60.0
const WALKER_ROAR_STOP := 6.0     ## seconds it stands and roars when a spire falls
const WALKER_TURN := 22.0         ## deg/s


## Phase index (1-based) for a main-pool ratio.
static func phase_for(ratio: float) -> int:
	if ratio > PHASE_THRESHOLDS[0]:
		return 1
	if ratio > PHASE_THRESHOLDS[1]:
		return 2
	return 3


## The HP the pool is restored to when the player respawns at the start of `phase` (SPEC §7.1
## checkpoints: "boss restored to the phase threshold").
static func phase_start_hp(phase: int) -> float:
	return HP_MAX * phase_fraction(phase)


## The pool FRACTION a phase starts at, so a scaled pool (a scripted `--boss-hp-scale` run, or a
## checkpoint restore that keeps the scale) can be placed at a phase threshold without knowing the
## tuning constant.
static func phase_fraction(phase: int) -> float:
	if phase <= 1:
		return 1.0
	return PHASE_THRESHOLDS[0] if phase == 2 else PHASE_THRESHOLDS[1]


static func armour_for(part: StringName) -> float:
	return float(ARMOUR.get(part, 1.0))


static func core_row(part: StringName) -> Dictionary:
	for row: Dictionary in CORES:
		if row["part"] == part:
			return row
	return {}


static func attack_ids(phase: int) -> Array:
	var index: int = clampi(phase - 1, 0, PHASE_ATTACKS.size() - 1)
	return PHASE_ATTACKS[index]


## Height of the Crown's floor at `radius` metres from the arena centre: the ziggurat's top step
## inside `RIM_STEPS[2]`, one step down inside `RIM_STEPS[1]`, the outer ring beyond that.
static func deck_height_at(radius: float) -> float:
	for i in range(RIM_STEPS.size() - 1, -1, -1):
		var step: Dictionary = RIM_STEPS[i]
		if radius <= float(step["radius"]):
			return float(step["rise"])
	return 0.0


## An attack row scaled for `phase`. The active window, recovery and cooldown all shrink with the
## phase speed; the telegraph shrinks too but never under the boss floors above, so P3 is faster
## without becoming unreadable.
static func scaled_row(id: StringName, phase: int) -> Dictionary:
	var row: Dictionary = (ATTACK_ROWS.get(id, {}) as Dictionary).duplicate(true)
	if row.is_empty():
		push_error("BossTuning: no attack row '%s'" % id)
		return {}
	var k: float = PHASE_SPEED[clampi(phase - 1, 0, PHASE_SPEED.size() - 1)]
	row["active"] = float(row.get("active", 0.2)) * k
	row["recover"] = float(row.get("recover", 1.0)) * k
	row["cooldown"] = float(row.get("cooldown", 4.0)) * k
	var floor_t := BOSS_MIN_UNBLOCKABLE if row.get("kind") == EnemyAttack.UNBLOCKABLE \
			else BOSS_MIN_PARRYABLE
	row["telegraph"] = maxf(float(row.get("telegraph", 1.0)) * k, floor_t)
	return row
