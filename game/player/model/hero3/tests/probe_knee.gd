extends Node
## What the knee is actually doing in the poses the interpenetration gate fails. Prints the bend angle
## of both knees every few frames, so the clamp can be set from a measurement.
##   tools/godot.sh test res://player/model/hero3/tests/probe_knee.gd

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 60.0

var _model: Node3D


func _ready() -> void:
	_model = (load(SCENE) as PackedScene).instantiate()
	_model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_model)
	_run(&"hit_knockdown", 40, 0.0, &"idle")
	_run(&"death", 100, 0.0, &"idle")
	_run(&"guard_up", 44, 0.0, &"idle")
	_run(&"", 40, 42.0, &"slide")
	_idle_drift()
	_clip_moves_legs()
	_walk_then_idle()
	get_tree().quit(0)


## The pieces gate measures `guard_up` straight after a 4 s walk, and reads the right knee 1.5 m
## forward of where it is at rest. guard_up has no leg keys. Does the WALK leave the stance behind?
func _walk_then_idle() -> void:
	var skel: Skeleton3D = _model.skeleton
	_model.position = Vector3.ZERO
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	_model.gait.reset()
	_model.stop_action()
	for i in 30:
		_tick()
	print("WALK  rest           R knee %s" % _at(skel, "R_Calf"))
	_model.set_locomotion(&"walk", 9.0, Vector2(0.0, -1.0))
	_model.gait.reset()
	for i in 240:
		_model.position += Vector3(0.0, 0.0, -9.0) * DT
		_tick()
	print("WALK  after walk     R knee %s" % _at(skel, "R_Calf"))
	_model.position = Vector3.ZERO
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	_model.gait.reset()
	_model.stop_action()
	for f in 90:
		_tick()
		if f % 15 == 0:
			print("WALK  idle f%-3d      R knee %s  skate %.3f  stance_t %.3f"
					% [f, _at(skel, "R_Calf"), _model.gait.skate.blend, _model.gait.debug_stance_t()])


## Does playing an UPPER-BODY clip move the legs? guard_up keys the spine, clavicles and arms only.
func _clip_moves_legs() -> void:
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	_model.gait.reset()
	_model.stop_action()
	_model.set_aim(Vector3.ZERO, 0.0)
	for i in 30:
		_tick()
	var skel: Skeleton3D = _model.skeleton
	var before := _at(skel, "R_Calf")
	print("CLIP before        R knee %s" % before)
	_model.play_action(&"guard_up", 0.06)
	for f in 40:
		_tick()
		if f % 8 == 0:
			print("CLIP guard_up f%-3d R knee %s  moved %.3f m  stance_w %.3f  root_w %.3f"
					% [f, _at(skel, "R_Calf"), _at(skel, "R_Calf").distance_to(before),
					_model.clips.stance_weight(), _model.clips.root_weight()])


## Does anything move at idle between tick 30 (where the pieces gate takes its rest baseline) and
## tick 70 (where it measures guard_up)? guard_up is upper-body only, so its legs must be identical.
func _idle_drift() -> void:
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	_model.gait.reset()
	_model.stop_action()
	_model.set_aim(Vector3.ZERO, 0.0)
	var skel: Skeleton3D = _model.skeleton
	for f in 121:
		_tick()
		if f % 10 == 0:
			print("IDLE f%-4d pelvis y %7.4f  R knee %6.2f deg  R knee at %s"
					% [f, _at(skel, "Pelvis").y, _bend("R"), _at(skel, "R_Calf")])


func _run(clip: StringName, frames: int, speed: float, state: StringName) -> void:
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	_model.gait.reset()
	_model.stop_action()
	_model.set_aim(Vector3.ZERO, 0.0)
	for i in 30:
		_tick()
	if state != &"idle":
		_model.set_locomotion(state, speed, Vector2(0.0, -1.0))
	elif clip != &"":
		_model.play_action(clip, 0.06)
	var label := String(clip) if clip != &"" else String(state)
	var worst_r := 0.0
	var worst_l := 0.0
	for f in frames:
		_tick()
		worst_r = maxf(worst_r, _bend("R"))
		worst_l = maxf(worst_l, _bend("L"))
		if f % 8 == 0:
			print("KNEE %-16s f%-3d  R %6.1f deg   L %6.1f deg" % [label, f, _bend("R"), _bend("L")])
	print("KNEE %-16s WORST  R %6.1f deg   L %6.1f deg" % [label, worst_r, worst_l])


## The knee's bend from straight, in degrees: 0 is a locked knee, 180 is fully folded. It is the angle
## between the hip->knee and knee->ankle directions, which is 0 when the leg is straight.
func _bend(side: String) -> float:
	var skel: Skeleton3D = _model.skeleton
	var hip := _at(skel, side + "_Thigh")
	var knee := _at(skel, side + "_Calf")
	var ankle := _at(skel, side + "_Foot")
	return rad_to_deg((knee - hip).normalized().angle_to((ankle - knee).normalized()))


func _at(skel: Skeleton3D, bone_name: String) -> Vector3:
	return skel.get_bone_global_pose(skel.find_bone(bone_name)).origin


func _tick() -> void:
	_model.clips.update(DT)
	_model.gait.update(DT)
	_model.clips.apply()
	_model.rig.update(DT)
