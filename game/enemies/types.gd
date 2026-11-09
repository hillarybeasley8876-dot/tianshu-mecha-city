class_name EnemyTypes
extends RefCounted
## Per-archetype tuning (enemies-owned). Numbers from SPEC §7 and skills-catalog §4.1/§4.6;
## where the docs are silent the value is marked [tuning] and also listed in status/enemies.md.
## Distances and speeds are already at the 16 m hero scale (SPEC scale rule S = 2).

const RIPPER := &"ripper"
const MANTIS := &"mantis"
const SPITTER := &"spitter"
const HARRIER := &"harrier"
const JUGGERNAUT := &"juggernaut"

const ALL: Array[StringName] = [RIPPER, MANTIS, SPITTER, HARRIER, JUGGERNAUT]

## Attack phases (seconds), SPEC §7.1 balance model. A parryable glint must be readable 400 ms
## before contact (273 ms reaction + input/display + buffer); an unblockable needs 600 ms plus its
## own sound and shape cue, because colour alone is not an accessible tell.
const PHASE_MIN_TELEGRAPH := 0.40
const PHASE_MIN_UNBLOCKABLE := 0.60
## SPEC §7.1: the player's sustained single-target damage. Time-to-kill targets are quoted against
## it, so every archetype's HP below is that TTK band times this number.
const PLAYER_DPS := 1000.0
## TTK bands in seconds (SPEC §7.1). `balance_report()` prints the measured figure for each.
const TTK_BAND: Dictionary = {
	RIPPER: Vector2(0.0, 0.5),
	HARRIER: Vector2(2.0, 4.0),
	SPITTER: Vector2(4.0, 6.0),
	MANTIS: Vector2(6.0, 10.0),
	JUGGERNAUT: Vector2(20.0, 30.0),
}
## The hurtbox part a competent player is meant to shoot. The juggernaut's sustained case is its
## armoured body (×0.35) — that is what the 20–30 s band refers to. Flanking to the ×2.5 back point
## is the reward for the whole fight, and the ×0.15 front plate is what stops you cheesing it.
const TTK_PART: Dictionary = {
	RIPPER: &"body", HARRIER: &"body", SPITTER: &"body", MANTIS: &"body", JUGGERNAUT: &"body",
}

## Per type: hp, stability, stability decay (fraction of max per second), decay delay, stagger time,
## immunity after stagger, body height (m), mass, move speed (m/s), turn rate (deg/s),
## sight range (m), sight half angle (deg), preferred combat distance (m), nav class.
const STATS: Dictionary = {
	RIPPER: {
		"hp": 400.0, "stability": 150.0, "decay": 0.30, "decay_delay": 0.8, "stagger": 0.8,
		"immunity": 0.0, "height": 6.0, "mass": 1.0, "speed": 30.0, "turn": 540.0,
		"sight": 320.0, "fov": 80.0, "engage": 18.0, "nav": &"small", "radius": 2.4,
	},
	MANTIS: {
		"hp": 8000.0, "stability": 700.0, "decay": 0.15, "decay_delay": 1.2, "stagger": 1.4,
		"immunity": 1.5, "height": 14.0, "mass": 3.0, "speed": 24.0, "turn": 360.0,
		"sight": 380.0, "fov": 70.0, "engage": 30.0, "nav": &"medium", "radius": 4.5,
	},
	SPITTER: {
		"hp": 5000.0, "stability": 900.0, "decay": 0.14, "decay_delay": 1.3, "stagger": 1.8,
		"immunity": 2.0, "height": 12.0, "mass": 3.5, "speed": 18.0, "turn": 240.0,
		"sight": 450.0, "fov": 75.0, "engage": 220.0, "nav": &"medium", "radius": 5.0,
	},
	HARRIER: {
		"hp": 3000.0, "stability": 300.0, "decay": 0.25, "decay_delay": 1.0, "stagger": 1.2,
		"immunity": 1.0, "height": 16.0, "mass": 1.6, "speed": 55.0, "turn": 200.0,
		"sight": 420.0, "fov": 90.0, "engage": 90.0, "nav": &"small", "radius": 5.0,
	},
	JUGGERNAUT: {
		"hp": 9000.0, "stability": 2600.0, "decay": 0.12, "decay_delay": 1.5, "stagger": 2.6,
		"immunity": 3.0, "height": 22.0, "mass": 9.0, "speed": 20.0, "turn": 150.0,
		"sight": 400.0, "fov": 70.0, "engage": 40.0, "nav": &"large", "radius": 8.0,
	},
}

## Damage multipliers per hurtbox part (armour). Weak points are marked on the Hurtbox itself and
## additionally use WEAK_POINT_MULT.
const ARMOUR: Dictionary = {
	RIPPER: {&"body": 1.0, &"head": 1.15, &"weak": 1.0},
	MANTIS: {&"body": 1.0, &"head": 1.2, &"weak": 1.0},
	SPITTER: {&"body": 1.0, &"head": 1.1, &"weak": 1.0},
	HARRIER: {&"body": 1.0, &"head": 1.3, &"weak": 1.0},
	JUGGERNAUT: {&"body": 0.35, &"plate": 0.15, &"head": 0.5, &"weak": 1.0},
}

## SPEC §7: the juggernaut's glowing back point and the spitter's sac take ×2.5.
const WEAK_POINT_MULT := 2.5
## skills-catalog §4.6: damage vs a staggered target.
const STAGGER_MULT_MELEE := 1.8
const STAGGER_MULT_OTHER := 1.35
## Weapon ids that count as "charged" for the ×1.8 bonus (weapons unit sets HitInfo.weapon).
## Melee is already covered by `hit.kind == MELEE`; this list is the charged *ranged* ids.
const CHARGED_WEAPONS: Array[StringName] = [
	&"rifle_stage1", &"rifle_stage2", &"charge_slash", &"zenith_lance",
]


## Display names (HUD plates), SPEC §7.
const DISPLAY_NAMES: Dictionary = {
	RIPPER: "裂爪 Ripper", MANTIS: "镰影 Mantis", SPITTER: "酸巢 Spitter",
	HARRIER: "鸣翼 Harrier", JUGGERNAUT: "裂山 Juggernaut",
}


static func get_stat(type: StringName, key: String, fallback: float = 0.0) -> float:
	var t: Dictionary = STATS.get(type, {})
	return float(t.get(key, fallback))


static func display_name(type: StringName) -> String:
	return String(DISPLAY_NAMES.get(type, String(type)))


static func is_type(type: StringName) -> bool:
	return STATS.has(type)


## SPEC §7.1: the shortest windup this kind of attack may ship with.
static func min_telegraph(kind: StringName) -> float:
	return PHASE_MIN_UNBLOCKABLE if kind == EnemyAttack.UNBLOCKABLE else PHASE_MIN_TELEGRAPH


static func armour_for(type: StringName, part: StringName) -> float:
	var table: Dictionary = ARMOUR.get(type, {})
	return float(table.get(part, 1.0))


## Seconds to kill `type` at `dps` (SPEC §7.1 uses PLAYER_DPS), shooting the part the design
## intends — the armour of that part is the only multiplier, so a weak point makes it faster and
## the juggernaut's front plate makes it far slower.
static func time_to_kill(type: StringName, dps: float = PLAYER_DPS) -> float:
	var armour := armour_for(type, TTK_PART.get(type, &"body"))
	var applied := maxf(dps * armour, 1.0)
	return get_stat(type, "hp", 1.0) / applied


## True when the archetype's TTK sits inside its SPEC §7.1 band.
static func ttk_in_band(type: StringName, dps: float = PLAYER_DPS) -> bool:
	var band: Vector2 = TTK_BAND.get(type, Vector2.ZERO)
	return time_to_kill(type, dps) >= band.x - 0.001 and time_to_kill(type, dps) <= band.y + 0.001


## One line per archetype: HP, the part, the resulting TTK and the band it has to sit in.
static func balance_report(dps: float = PLAYER_DPS) -> Array[String]:
	var out: Array[String] = []
	for type: StringName in ALL:
		var band: Vector2 = TTK_BAND.get(type, Vector2.ZERO)
		out.append("%-11s hp %7.0f  %-5s x%.2f -> TTK %6.2f s (band %.1f-%.1f s) %s"
				% [type, get_stat(type, "hp", 0.0), TTK_PART.get(type, &"body"),
				armour_for(type, TTK_PART.get(type, &"body")), time_to_kill(type, dps),
				band.x, band.y, "ok" if ttk_in_band(type, dps) else "OUT OF BAND"])
	return out


## CONTRACTS §7 agent class for this archetype: `small` (r 1.5 m), `medium` (r 4 m), `large` (r 9 m).
## Flyers carry a class too (their spawn ring uses that map) but never walk one — EnemyLocomotion
## only builds a NavigationAgent3D for ground types.
static func nav_class(type: StringName) -> StringName:
	return StringName((STATS.get(type, {}) as Dictionary).get("nav", &""))


## The navigation map this archetype should walk on: the world's class map when the world provides
## one (CONTRACTS §7 `world.nav_map(class)`), otherwise the default world map. Returns an invalid
## RID when there is nothing to walk on yet — callers must check `map_ready` before querying.
static func nav_map_for(node: Node3D, type: StringName) -> RID:
	var world := Game.world
	var cls := nav_class(type)
	if cls != &"" and world != null and is_instance_valid(world) and world.has_method(&"nav_map"):
		var rid: RID = world.call(&"nav_map", cls)
		if rid.is_valid():
			return rid
	return node.get_world_3d().navigation_map


## Queries before the first map synchronisation are engine errors, so callers check this first.
static func map_ready(map: RID) -> bool:
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0


## True when this archetype's map may be queried at all. A world that bakes its own class maps
## answers for itself (CONTRACTS §7 `world.nav_ready(class)`) because the iteration id goes
## non-zero a frame before the polygons are queryable; everything else falls back to the map's own
## iteration check. Callers must steer directly instead of querying while this is false
## (lead note 02:40).
static func nav_query_ready(node: Node3D, type: StringName) -> bool:
	var world := Game.world
	var cls := nav_class(type)
	if cls != &"" and world != null and is_instance_valid(world) and world.has_method(&"nav_ready"):
		return bool(world.call(&"nav_ready", cls))
	return map_ready(nav_map_for(node, type))
