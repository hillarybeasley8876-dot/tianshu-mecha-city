class_name Targetable
extends Marker3D
## Lock-on point (core-owned). Enemies add one at their centre of mass and optional extra ones on weak
## points. The aim/lock system scans the &"targetable" group; HUD draws markers from it.

@export var priority: float = 1.0          ## higher wins ties (elites, boss weak points)
@export var radius: float = 3.0            ## rough world-space size, for screen-space lock tests
@export var is_weak_point: bool = false
@export var actor_path: NodePath


func _enter_tree() -> void:
	add_to_group(&"targetable")


func actor() -> Node:
	if not actor_path.is_empty():
		return get_node_or_null(actor_path)
	var n: Node = get_parent()
	while n != null and not n.has_method(&"take_hit"):
		n = n.get_parent()
	return n


func is_valid_target() -> bool:
	var a := actor()
	return is_inside_tree() and is_visible_in_tree() and a != null \
			and (not a.has_method(&"is_alive") or bool(a.call(&"is_alive")))
