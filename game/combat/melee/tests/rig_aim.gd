class_name MeleeRigAim
extends Node3D
## Test stand-in for the AimSystem (camera-aim contract, CONTRACTS §5). The suites point the
## crosshair and pick the hard-lock target directly, so the melee gate logic (24–80 m lunge band,
## execution target) is exercised without depending on the camera unit.

var point: Vector3 = Vector3(0.0, 11.5, -100.0)
var hard: Node3D = null
var soft: Node3D = null


func aim_point() -> Vector3:
	return point


func aim_dir_from(from: Vector3) -> Vector3:
	var d := point - from
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD


func hard_target() -> Node3D:
	return hard if is_instance_valid(hard) else null


func soft_target() -> Node3D:
	return soft if is_instance_valid(soft) else null


func targets_in_view(_max_count: int, _max_range: float) -> Array[Node3D]:
	return []


func camera() -> Camera3D:
	return null


func is_first_person() -> bool:
	return false


func look_at_point(p: Vector3) -> void:
	point = p


func lock(t: Node3D) -> void:
	hard = t
	soft = t
	if t != null:
		point = t.global_position
