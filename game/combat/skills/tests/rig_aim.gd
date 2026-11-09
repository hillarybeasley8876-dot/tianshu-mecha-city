class_name SkillRigAim
extends Node3D
## AimSystem stand-in (CONTRACTS §5): the crosshair is a settable point and the lock is a settable
## Targetable, so a test can aim and lock without a camera.

var point: Vector3 = Vector3(0.0, 11.5, -200.0)
var locked: Node3D = null
var soft: Node3D = null


func aim_point() -> Vector3:
	return point


func aim_dir_from(from: Vector3) -> Vector3:
	var d := point - from
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD


func hard_target() -> Node3D:
	return locked


func soft_target() -> Node3D:
	return soft if soft != null else locked


func targets_in_view(_max_count: int, _max_range: float) -> Array[Node3D]:
	return [] as Array[Node3D]


func camera() -> Camera3D:
	return null


func is_first_person() -> bool:
	return false


func hud_state() -> Dictionary:
	return {"aim_point": point, "hard_target": locked}
