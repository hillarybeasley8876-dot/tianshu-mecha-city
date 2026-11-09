class_name HitInfo
extends RefCounted
## One hit (core-owned). Built by the attacker, passed to `receiver.take_hit(hit)`, then broadcast
## via Events.hit_landed. Kinds drive armour, VFX and sound choices downstream.

const BEAM := &"beam"
const BALLISTIC := &"ballistic"
const EXPLOSIVE := &"explosive"
const MELEE := &"melee"
const EMP := &"emp"
const CRUSH := &"crush"

var amount: float = 0.0            ## damage before the receiver's armour / weak-point multiplier
var kind: StringName = BALLISTIC
var stagger: float = 0.0           ## poise damage (enemies stagger when poise reaches 0)
var knockback: Vector3 = Vector3.ZERO  ## world-space impulse in m/s applied to the receiver
var position: Vector3 = Vector3.ZERO   ## world-space impact point
var normal: Vector3 = Vector3.UP       ## surface normal at the impact point
var source: Node = null            ## attacking actor (player or enemy root)
var weapon: StringName = &""       ## weapon / skill / attack id (e.g. &"beam_rifle", &"ripper_bite")
var hurtbox_part: StringName = &"" ## filled by Hurtbox.apply(): which part was hit
var weak_point: bool = false       ## filled by Hurtbox.apply()
var crit: bool = false
var parryable: bool = false        ## enemy melee that a perfect parry can deflect
var unblockable: bool = false      ## must be dodged (red telegraph)
var finisher: bool = false         ## execution on a staggered enemy
var final_amount: float = 0.0      ## damage actually applied (receiver writes it)


static func make(amount_: float, kind_: StringName, source_: Node, weapon_: StringName) -> HitInfo:
	var h := HitInfo.new()
	h.amount = amount_
	h.kind = kind_
	h.source = source_
	h.weapon = weapon_
	return h


func duplicate_hit() -> HitInfo:
	var h := HitInfo.new()
	for p in ["amount", "kind", "stagger", "knockback", "position", "normal", "source", "weapon",
			"hurtbox_part", "weak_point", "crit", "parryable", "unblockable", "finisher", "final_amount"]:
		h.set(p, get(p))
	return h
