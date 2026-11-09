class_name Hurtbox
extends Area3D
## Damage receiver volume (core-owned). Put one or more under an actor; shapes are children.
## Attackers find hurtboxes with ray/shape queries on Layers.*_HURTBOX and call `apply(hit)`, which
## fills the part / weak-point fields, scales the damage and forwards to the actor's take_hit(hit).
## The actor is the nearest ancestor that has `take_hit` (or `actor_path` when set).

@export var part: StringName = &"body"
@export var damage_multiplier: float = 1.0
@export var is_weak_point: bool = false
@export var actor_path: NodePath


func _ready() -> void:
	monitoring = false  # queried, never monitoring: cheap with many enemies
	monitorable = true


func actor() -> Node:
	if not actor_path.is_empty():
		return get_node_or_null(actor_path)
	var n: Node = get_parent()
	while n != null and not n.has_method(&"take_hit"):
		n = n.get_parent()
	return n


## Returns the receiving actor (null if it has none or is already dead).
func apply(hit: HitInfo) -> Node:
	var a := actor()
	if a == null or (a.has_method(&"is_alive") and not bool(a.call(&"is_alive"))):
		return null
	hit.hurtbox_part = part
	hit.weak_point = is_weak_point
	hit.amount *= damage_multiplier
	a.call(&"take_hit", hit)
	return a
