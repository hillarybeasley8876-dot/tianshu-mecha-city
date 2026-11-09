class_name EnemyAttack
extends RefCounted
## One enemy attack (enemies-owned): a data row the brain runs as telegraph → active → recover.
## SPEC §7.1 sets the floors: a parryable glint is readable ≥ 400 ms before contact, an unblockable
## gets ≥ 600 ms plus its own sound and shape cue. `make` raises any row that is under them, so an
## archetype table cannot ship an unreadable windup.

const PARRYABLE := &"parryable"
const UNBLOCKABLE := &"unblockable"
const RANGED := &"ranged"        ## a projectile / arc: not parryable, but catchable when reflectable

var id: StringName = &"attack"
var kind: StringName = UNBLOCKABLE
var telegraph: float = 0.45      ## anticipation, ≥ EnemyTypes.min_telegraph(kind)
var active: float = 0.18         ## the damaging window
var recover: float = 0.55        ## window of opportunity
var damage: float = 100.0
var impact: float = 60.0         ## poise damage against the player
var knockback: float = 8.0       ## m/s
var hit_kind: StringName = HitInfo.MELEE
var range_min: float = 0.0       ## metres; the brain only starts the attack inside [min, max]
var range_max: float = 24.0
var arc_deg: float = 120.0       ## frontal arc the active window sweeps
var cooldown: float = 2.0
var weight: float = 1.0          ## random pick weight inside the archetype's table
var lunge_speed: float = 0.0     ## m/s toward the target during the active window (leaps, charges)
var reflectable: bool = false    ## projectiles the catch field can return
var blast_radius: float = 0.0    ## > 0 = area damage on landing
var projectile_speed: float = 0.0  ## > 0 = spawn a pooled enemy projectile instead of a melee sweep
var shockwave_radius: float = 0.0 ## > 0 = expanding ground ring (jump over it)
var anim: StringName = &"attack"


static func make(row: Dictionary) -> EnemyAttack:
	var a := EnemyAttack.new()
	for key: String in row.keys():
		if key in a:
			a.set(key, row[key])
		else:
			push_warning("EnemyAttack: unknown key '%s' in attack '%s'" % [key, a.id])
	a.telegraph = maxf(a.telegraph, EnemyTypes.min_telegraph(a.kind))
	return a


static func make_all(rows: Array) -> Array[EnemyAttack]:
	var out: Array[EnemyAttack] = []
	for r: Dictionary in rows:
		out.append(make(r))
	return out


func total_time() -> float:
	return telegraph + active + recover


## A move that cannot damage the player: the spitter's spore-chaff cloud. It is utility, not an
## attack on the player, so it must NOT take one of the two ranged tokens — a chaff puff that
## occupies a volley slot for 1.3 s and then shuts the whole kind for the 0.8 s re-grant denies a
## real acid arc, and how many puffs land in a 20 s window is pure chance. That chance is what made
## the incoming-damage reading swing 326-434 DPS and the SPEC §7.1 gate fail one run in ten
## (lead r12). The brain runs utility moves for free.
func is_utility() -> bool:
	return damage <= 0.0 and projectile_speed <= 0.0 and blast_radius <= 0.0 \
			and shockwave_radius <= 0.0 and lunge_speed <= 0.0


func build_hit(source: Node) -> HitInfo:
	var h := HitInfo.new()
	h.amount = damage
	h.stagger = impact
	h.kind = hit_kind
	h.source = source
	h.weapon = id
	h.parryable = kind == PARRYABLE
	h.unblockable = kind == UNBLOCKABLE
	return h
