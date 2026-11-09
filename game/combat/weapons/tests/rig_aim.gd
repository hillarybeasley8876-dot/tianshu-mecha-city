class_name RigAim
extends Node3D
## Test stand-in for the AimSystem (camera-aim contract, CONTRACTS §5). The tests drive the
## crosshair by setting `point`; `targets_in_view` hands back every valid Targetable in range and
## lets the launcher apply its own paint box, so the real filtering path is exercised.

var point: Vector3 = Vector3(0.0, 11.5, -100.0)
var scan_range: float = 1000.0
## Camera mode (camera-aim contract): the real AimSystem answers `is_first_person()` from the rig,
## so the stand-in takes it as state the tests set — the same live read the weapons do.
var first_person: bool = false
## The cockpit lens (camera-aim contract, `AimSystem.camera()`). A real Camera3D, parked at the eye
## point `RigPlayer.lens()` returns, so `WeaponContext.lens()` and the near-lens scan measure the
## same thing in the rig as they do in the game.
var cam: Camera3D = null


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "RigCamera"
	cam.fov = 62.0          ## the game's first-person FOV (camera-aim), for the coverage numbers
	cam.current = false     ## never takes the viewport: this rig renders nothing
	add_child(cam)


func _physics_process(_delta: float) -> void:
	var p := get_parent() as RigPlayer
	if cam != null and p != null:
		cam.global_position = p.lens()


func aim_point() -> Vector3:
	return point


func aim_dir_from(from: Vector3) -> Vector3:
	var d := point - from
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD


func hard_target() -> Targetable:
	return null


func soft_target() -> Targetable:
	return null


func targets_in_view(max_count: int, max_range: float) -> Array[Targetable]:
	var out: Array[Targetable] = []
	var tree := get_tree()
	if tree == null:
		return out
	for n in tree.get_nodes_in_group(&"targetable"):
		var t := n as Targetable
		if t != null and t.is_valid_target() and global_position.distance_to(t.global_position) \
				<= minf(max_range, scan_range):
			out.append(t)
			if out.size() >= max_count:
				break
	return out


func camera() -> Camera3D:
	return cam


func is_first_person() -> bool:
	return first_person
