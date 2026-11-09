class_name EnemyDamage
extends RefCounted
## The damage maths of `EnemyBase.take_hit` (enemies-owned), as statics so the monster root stays
## small. Order, from skills-catalog §4.1/§4.6/§4.7 and SPEC §7:
##   1. armour per hurtbox part (`EnemyTypes.ARMOUR`)
##   2. weak point ×2.5
##   3. staggered target ×1.8 (melee / charged / Lance) or ×1.35 (everything else)
##   4. combo scaling, suspended while the target is staggered

const HITSTOP_FRAMES_MIN := 3.0
const HITSTOP_FRAMES_MAX := 12.0
const HITSTOP_DAMAGE_DIVISOR := 150.0
const EXPLOSIVE_HITSTOP := 0.05
const ATTACKER_CREEP := 0.25   ## Sakurai: the attacker keeps creeping during a stop (juice §2.3)


## Damage the receiver actually takes, after armour, weak point, stagger bonus and combo scaling.
static func resolve(host: EnemyBase, hit: HitInfo) -> float:
	var dmg := hit.amount * EnemyTypes.armour_for(host.enemy_type, hit.hurtbox_part)
	if hit.weak_point:
		dmg *= EnemyTypes.WEAK_POINT_MULT
		hit.crit = true
	if host.status.is_staggered():
		dmg *= stagger_multiplier(hit)
	return dmg * host.status.combo_multiplier()


## Poise damage, blunted by the same part armour (shooting a juggernaut's front plate barely moves it).
static func impact(host: EnemyBase, hit: HitInfo) -> float:
	return hit.stagger * EnemyTypes.armour_for(host.enemy_type, hit.hurtbox_part)


## skills-catalog §4.6: melee, charged shots and the Lance take ×1.8 on a staggered target.
static func stagger_multiplier(hit: HitInfo) -> float:
	if hit.kind == HitInfo.MELEE or hit.weapon in EnemyTypes.CHARGED_WEAPONS:
		return EnemyTypes.STAGGER_MULT_MELEE
	return EnemyTypes.STAGGER_MULT_OTHER


## Gunfire never freezes (juice §2.2 / Capcom); melee uses the damage-based frame formula.
static func hitstop_seconds(hit: HitInfo) -> float:
	match hit.kind:
		HitInfo.MELEE:
			var frames := clampf(2.0 + hit.final_amount / HITSTOP_DAMAGE_DIVISOR, HITSTOP_FRAMES_MIN,
					HITSTOP_FRAMES_MAX)
			return frames / 60.0
		HitInfo.EXPLOSIVE:
			return EXPLOSIVE_HITSTOP
		_:
			return 0.0


## Local hit-stop on the victim, plus a quarter of it on the attacker so it visibly creeps on.
static func apply_hitstop(host: EnemyBase, hit: HitInfo) -> void:
	var seconds := hitstop_seconds(hit)
	if seconds <= 0.0:
		return
	host.hit_pause(seconds)
	if hit.source != null and is_instance_valid(hit.source) and hit.source.has_method(&"hit_pause"):
		hit.source.call(&"hit_pause", seconds * ATTACKER_CREEP)
