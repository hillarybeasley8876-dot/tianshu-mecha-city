extends Node
## hero-v3 r9 item 3 (b): what the gait actually DOES, measured on the real model, headless.
##   tools/godot.sh test res://player/model/hero3/tests/probe_gait.gd
##
##   slip      metres a PLANTED foot travels in world space, per step (gate 0.05 m)
##   cadence   steps per second, and stride in metres, against the ground speed
##   pelvis    vertical travel per step, in metres -- the weight the lead asks for
##   arm       peak-to-peak upperarm swing fore/aft, in degrees
##   torso     peak-to-peak chest yaw against the pelvis, in degrees
##   lean      the chest's pitch off vertical, in degrees -- a 16 m machine at 16 m/s that stands
##             bolt upright is the first thing the eye reads as "wrong"
##
## The model node MOVES, because that is what `PlayerMech` does and it is the only way a planted foot
## can be measured for slide at all: the gait holds each plant at a fixed WORLD point, so any movement
## of the sole is slide by definition.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 120.0
const SLIP_GATE := 0.05
const TICKS := 600
const WARM := 180
## label, state, speed, stick, turn rate (deg/s, 0 = travel straight).
const CASES: Array = [
	["walk 9 m/s", &"walk", 9.0, Vector2(0.0, -1.0), 0.0],
	["run 16 m/s", &"run", 16.0, Vector2(0.0, -1.0), 0.0],
	["skate 42 m/s", &"slide", 42.0, Vector2(0.0, -1.0), 0.0],
	["strafe 9 m/s", &"walk", 9.0, Vector2(-1.0, 0.0), 0.0],
	["back 9 m/s", &"walk", 9.0, Vector2(0.0, 1.0), 0.0],
	["turn in place", &"walk", 0.0, Vector2.ZERO, 55.0],
]

var model: Node3D
var skeleton: Skeleton3D
var gait: Hero3Gait
## Footstep count. A GDScript lambda captures by value, so the counter cannot be a local.
var _steps: int = 0
var _debug: bool = false


func _ready() -> void:
	model = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	skeleton = model.skeleton
	gait = model.gait
	print("GAIT %-13s | %-24s | %-22s | %-19s | %s"
			% ["case", "slip per step (m)", "cadence / stride", "pelvis per step (m)",
			"arm swing / torso yaw / lean (deg)"])
	_debug = not _arg("--debug=", "").is_empty()
	for row: Array in CASES:
		if _debug and String(row[0]) != _arg("--case=", ""):
			continue
		_run(row)
	print("PASS")
	get_tree().quit(0)


## One case: drive the model by hand for TICKS and measure everything the lead asked for.
func _run(row: Array) -> void:
	var label := String(row[0])
	var speed := float(row[2])
	var stick: Vector2 = row[3]
	var turn := float(row[4])
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	model.set_locomotion(row[1], speed, stick)
	gait.reset()
	var dir := Vector3(stick.x, 0.0, stick.y).normalized() if stick.length() > 0.01 else Vector3.ZERO
	var m := _blank()
	_steps = 0
	var last_plant: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var was_planted: Array[bool] = [false, false]
	for c in gait.footstep.get_connections():
		gait.footstep.disconnect(c["callable"])
	gait.footstep.connect(func(_s: String, _p: Vector3, _v: float) -> void: _steps += 1)
	for tick in TICKS:
		if turn != 0.0:
			model.rotate_y(deg_to_rad(turn) * DT)
		elif dir != Vector3.ZERO:
			model.position += dir * speed * DT
		gait.update(DT)
		if tick < WARM and not _debug:
			_sample(m, last_plant, was_planted, false)
			if tick == WARM - 1:
				_steps = 0        ## the warm-up's own footsteps are not the cadence
			continue
		_sample(m, last_plant, was_planted, true)
		if _debug:
			_flat_debug()
	_finish(label, m, _steps, speed)


## What the reach floor is actually seeing: the horizontal hip-to-ankle distance per leg, and the
## depth it demands. This is where a duck-walk comes from.
func _flat_debug() -> void:
	var parts: Array[String] = []
	for i in 2:
		var leg: Dictionary = gait.step.legs[i]
		var hip := gait.frame.hip_ground(leg)
		var ankle := gait.ankle_targets()[i]
		var flat := Vector2(ankle.x - hip.x, ankle.z - hip.z).length()
		parts.append("%s flat %.2f u %.2f used %d step %d t %.2f" % [leg["spec"]["side"], flat,
				Hero3Timing.leg_phase(gait.step.phase, i), int(leg["used"]),
				int(leg["stepping"]), float(leg["t"])])
	print("FLAT phase %.3f yaw %.0f drop %.2f | %s" % [gait.step.phase,
			rad_to_deg(gait.body_yaw()), float(gait.report()["drop"]), " | ".join(parts)])


func _blank() -> Dictionary:
	return {"slip": 0.0, "slip_steps": 0, "worst_step": 0.0, "step_slip": 0.0,
			"pelvis_lo": INF, "pelvis_hi": -INF, "arm_lo": INF, "arm_hi": -INF,
			"yaw_lo": INF, "yaw_hi": -INF, "lean_lo": INF, "lean_hi": -INF,
			"drop_lo": INF, "drop_hi": -INF,
			"stride_lo": INF, "stride_hi": -INF, "last_plant": [Vector3.ZERO, Vector3.ZERO],
			"cadence": 0.0}


## One tick of measurement. `count` is false during the warm-up, when the values are tracked but not
## folded into the totals (a gait reset is a hard cut, not a step).
func _sample(m: Dictionary, last_plant: Array[Vector3], was_planted: Array[bool],
		count: bool) -> void:
	var xf := skeleton.global_transform
	var pelvis := skeleton.find_bone("Pelvis")
	var chest := skeleton.find_bone("Spine02")
	var hip_y := (xf * skeleton.get_bone_global_pose(pelvis).origin).y
	m["pelvis_lo"] = minf(float(m["pelvis_lo"]), hip_y)
	m["pelvis_hi"] = maxf(float(m["pelvis_hi"]), hip_y)
	var arm := _arm_angle()
	m["arm_lo"] = minf(float(m["arm_lo"]), arm)
	m["arm_hi"] = maxf(float(m["arm_hi"]), arm)
	var yaw := rad_to_deg(_chest_yaw(pelvis, chest))
	m["yaw_lo"] = minf(float(m["yaw_lo"]), yaw)
	m["yaw_hi"] = maxf(float(m["yaw_hi"]), yaw)
	var drop := float(gait.report()["drop"])
	m["drop_lo"] = minf(float(m["drop_lo"]), drop)
	m["drop_hi"] = maxf(float(m["drop_hi"]), drop)
	var lean := rad_to_deg(_chest_lean(chest))
	m["lean_lo"] = minf(float(m["lean_lo"]), lean)
	m["lean_hi"] = maxf(float(m["lean_hi"]), lean)
	for i in 2:
		var planted := gait.is_planted(i)
		var at := _sole_world(i)
		if count and planted and was_planted[i]:
			# HORIZONTAL only: a planted foot rolls heel to toe, which moves the contact REFERENCE up
			# and down by a few centimetres without the boot going anywhere. Slip is travel ALONG the
			# ground.
			var d := at - last_plant[i]
			m["step_slip"] = float(m["step_slip"]) + Vector2(d.x, d.z).length()
		if was_planted[i] and not planted:
			# the foot has just left the ground: close the step and bank its slip
			if count:
				m["slip"] = float(m["slip"]) + float(m["step_slip"])
				m["slip_steps"] = int(m["slip_steps"]) + 1
				m["worst_step"] = maxf(float(m["worst_step"]), float(m["step_slip"]))
			m["step_slip"] = 0.0
		elif planted and not was_planted[i]:
			var last: Array = m["last_plant"]
			if count and last[i] != Vector3.ZERO:
				var stride := (at - (last[i] as Vector3)).length()
				m["stride_lo"] = minf(float(m["stride_lo"]), stride)
				m["stride_hi"] = maxf(float(m["stride_hi"]), stride)
			last[i] = at
		last_plant[i] = at
		was_planted[i] = planted


## Where this foot is TOUCHING the ground, in world space: the ankle bone posed, with the contact
## pivot the foot is rolling about put back in the foot's own frame.
##
## NOT the ankle itself. The ankle travels 0.8-1.1 m through a stance because the foot rolls heel to
## toe about a contact point that does not move -- measuring the ankle charges that roll to the slide
## gate and reported 1.7 m of "slip" on a foot that never moved.
func _sole_world(i: int) -> Vector3:
	var leg: Dictionary = gait.step.legs[i]
	var ankle := skeleton.global_transform * skeleton.get_bone_global_pose(int(leg["foot"])).origin
	var roll := gait.foot_rolls()[i]
	var back := gait.frame.foot_back(gait.body_yaw())
	# `Hero3Sole.ankle` is `contact + up * ankle_h + ankle_offset`, so this inverts it exactly
	return ankle - Vector3.UP * float(leg["ankle_h"]) - Hero3Foot.ankle_offset(leg, roll, back)


## How far the right HAND has swung fore and aft of its own shoulder, in metres. Measuring the hand
## and not the upperarm's euler is deliberate: the shoulder's rest basis is not axis-aligned, so an
## euler reads a swing the eye never sees.
func _arm_angle() -> float:
	var hand := skeleton.find_bone("R_Hand")
	var shoulder := skeleton.find_bone("R_Upperarm")
	if hand < 0 or shoulder < 0:
		return 0.0
	var xf := skeleton.global_transform
	var fwd := -xf.basis.z
	return ((xf * skeleton.get_bone_global_pose(hand).origin)
			- (xf * skeleton.get_bone_global_pose(shoulder).origin)).dot(fwd)


## The chest's yaw against the pelvis, in radians: the counter-rotation the lead asks for.
func _chest_yaw(pelvis: int, chest: int) -> float:
	var p := skeleton.get_bone_global_pose(pelvis).basis
	var c := skeleton.get_bone_global_pose(chest).basis
	var rel := p.inverse() * c
	return atan2(rel.x.z, rel.x.x)


## The chest's pitch off vertical, in radians: positive is leaning forward.
func _chest_lean(chest: int) -> float:
	var up := (skeleton.global_transform.basis * skeleton.get_bone_global_pose(chest).basis \
			* Vector3.UP).normalized()
	var fwd := -skeleton.global_transform.basis.z
	return atan2(up.dot(fwd), up.y)


func _finish(label: String, m: Dictionary, steps: int, _speed: float) -> void:
	var n := maxi(int(m["slip_steps"]), 1)
	var secs := float(TICKS - WARM) * DT
	var rep := gait.report()
	print("GAIT %-13s | mean %.3f worst %.3f (%d steps) | %.2f steps/s  step %.2f m  same-foot %.2f-%.2f m | pelvis %.2f m | arm %.2f m  torso %.1f  lean %.1f..%.1f  drop %.2f..%.2f"
			% [label, float(m["slip"]) / float(n), float(m["worst_step"]), int(m["slip_steps"]),
			float(rep["cadence"]), float(rep["stride"]), float(m["stride_lo"]), float(m["stride_hi"]),
			float(m["pelvis_hi"]) - float(m["pelvis_lo"]),
			float(m["arm_hi"]) - float(m["arm_lo"]),
			float(m["yaw_hi"]) - float(m["yaw_lo"]),
			float(m["lean_lo"]), float(m["lean_hi"]),
			float(m["drop_lo"]), float(m["drop_hi"])])
	if float(m["worst_step"]) > SLIP_GATE:
		print("GAIT FAIL %s: a planted foot slid %.3f m in one step, gate %.2f"
				% [label, float(m["worst_step"]), SLIP_GATE])


func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return fallback
