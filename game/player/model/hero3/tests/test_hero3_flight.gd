extends Node
## hero-v3 r8 gate: the flight pose (lead brief r8 item 3).
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_flight.gd
##
##   1  the pose is off on the ground and blends in on `fly`, and back out again
##   2  the lean tracks the MEASURED speed: ~25 deg at the 50 m/s cruise, more under the 84 m/s boost
##   3  the bank tracks the measured yaw rate and rolls INTO the turn
##   4  the legs trail BACK and TOGETHER in the pose, and the knees stay inside the clamp
##   5  the thruster plumes point along the thrust, i.e. backwards along the velocity
##   6  no bone is left un-posed (no NaN) and the sockets still resolve
##   7  a death in flight cuts the lean and the thrust at once instead of holding them for 0.55 s
##   8  a dead mech powers down: every emissive fades over ~1 s and comes back on the revive

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 120.0
## The cruise and boost speeds `mech_tuning.gd` flies at, and the yaw rate it turns at.
const CRUISE := Hero3Flight.CRUISE
const BOOST := Hero3Flight.BOOST
const TURN := Hero3Flight.TURN_DEG
## The brief's own numbers: "up to about 25 deg at the 50 m/s cruise and more under the 84 m/s boost".
const LEAN_AT_CRUISE := Vector2(20.0, 29.0)
## The legs must end up behind the hips and close together.
const TRAIL_BEHIND_MIN := 2.5
const TRAIL_SPREAD_MAX := 1.6

var failures: Array[String] = []
var _models: Array[Node3D] = []


func _ready() -> void:
	_ground()
	await _cruise()
	await _boost()
	await _bank()
	await _legs()
	await _thrust()
	await _blend_out()
	await _death_in_flight()
	await _power_down()
	for m in _models:
		m.queue_free()
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			print("FAIL ", f)
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


## A model parented to a stand-in body, which is what `Hero3Flight` measures: the HeroModel is a child
## of the body, so its own global transform IS the body's.
func _spawn() -> Node3D:
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	body.add_child(model)
	_models.append(body)
	return model


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


## Fly the stand-in body at `speed` m/s along its own forward for `seconds`, turning at `yaw_deg` a
## second. `Hero3Model._physics_process` is disabled, so the model's own tick is stepped by hand.
func _fly(model: Node3D, speed: float, seconds: float, yaw_deg: float = 0.0) -> void:
	var body := model.get_parent() as Node3D
	var steps := int(seconds / DT)
	for i in steps:
		body.rotate_y(deg_to_rad(yaw_deg) * DT)
		body.global_position += -body.global_transform.basis.z * speed * DT
		model.set_locomotion(Hero3Flight.STATE, speed, Vector2(0.0, 1.0))
		model.flight.sample(model, DT, Hero3Flight.STATE)
		model.gait.set_flight(model.flight.blend, model.flight.lean)
		model.rig.set_thrust_dir(model.flight.thrust)
		model.clips.update(DT)
		model.gait.update(DT)
		model.clips.apply()
		model.rig.update(DT)
		# the lean and the bank are applied to the MODEL NODE, which `_physics_process` does and this
		# stand-in has to do by hand -- without it the body stays upright and the pose is only half on
		model._place_model(Vector3.ZERO)


func _ground() -> void:
	var model := _spawn()
	model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	for i in 60:
		model.flight.sample(model, DT, &"idle")
	_check(model.flight.blend == 0.0, "the flight pose is on while standing (%.2f)"
			% model.flight.blend)
	_check(model.flight.lean == 0.0 and model.flight.bank == 0.0,
			"a standing mech leans or banks")
	_check(model.flight.thrust == Vector3.ZERO, "a standing mech has a thrust direction")


func _cruise() -> void:
	var model := _spawn()
	_fly(model, CRUISE, 2.0)
	var f: Hero3Flight = model.flight
	_check(f.blend > 0.99, "the pose never finished blending in (%.2f)" % f.blend)
	_check(absf(f.speed - CRUISE) < 2.0, "the measured speed is %.1f, not the %.0f m/s cruise"
			% [f.speed, CRUISE])
	var lean := rad_to_deg(f.lean)
	_check(lean >= LEAN_AT_CRUISE.x and lean <= LEAN_AT_CRUISE.y,
			"the cruise lean is %.1f deg, the brief asks for about 25" % lean)
	_check(absf(rad_to_deg(f.bank)) < 1.0, "a straight cruise banks %.1f deg" % rad_to_deg(f.bank))
	print("CRUISE speed %.1f m/s -> lean %.1f deg" % [f.speed, lean])


func _boost() -> void:
	var model := _spawn()
	_fly(model, CRUISE, 1.5)
	var cruise_lean := rad_to_deg(model.flight.lean)
	_fly(model, BOOST, 1.5)
	var f: Hero3Flight = model.flight
	var lean := rad_to_deg(f.lean)
	_check(absf(f.speed - BOOST) < 3.0, "the measured boost speed is %.1f, not %.0f" % [f.speed, BOOST])
	_check(lean > cruise_lean + 3.0, "the boost lean %.1f deg is no more than the cruise %.1f"
			% [lean, cruise_lean])
	_check(lean <= Hero3Flight.MAX_LEAN_DEG + 0.1, "the boost lean %.1f deg is over the ceiling" % lean)
	print("BOOST  speed %.1f m/s -> lean %.1f deg (cruise was %.1f)" % [f.speed, lean, cruise_lean])


func _bank() -> void:
	var model := _spawn()
	_fly(model, CRUISE, 1.5)
	_fly(model, CRUISE, 1.2, TURN)
	var f: Hero3Flight = model.flight
	var rate := rad_to_deg(f.yaw_rate)
	var bank := rad_to_deg(f.bank)
	_check(absf(rate - TURN) < 12.0, "the measured yaw rate is %.0f deg/s, not %.0f" % [rate, TURN])
	_check(absf(bank) > 15.0, "a full-rate turn banks only %.1f deg" % bank)
	_check(absf(bank) <= Hero3Flight.MAX_BANK_DEG + 0.1, "the bank %.1f deg is over the ceiling" % bank)
	# the bank has to roll INTO the turn: a positive yaw rate (turning left) must not roll right
	# `Quaternion(Vector3.BACK, +b)` tips the mech's up axis toward -X, i.e. its top leans LEFT, so a
	# positive yaw rate (a left turn) and a positive bank are the same direction.
	_check(signf(bank) == signf(rate), "the bank rolls the wrong way (rate %.0f, bank %.0f)"
			% [rate, bank])
	print("BANK   yaw %.0f deg/s -> bank %.1f deg" % [rate, bank])


func _legs() -> void:
	var model := _spawn()
	_fly(model, CRUISE, 2.0)
	var skel: Skeleton3D = model.skeleton
	var hip := skel.to_global(skel.get_bone_global_pose(skel.find_bone("R_Thigh")).origin)
	var r := skel.to_global(skel.get_bone_global_pose(skel.find_bone("R_Foot")).origin)
	var l := skel.to_global(skel.get_bone_global_pose(skel.find_bone("L_Foot")).origin)
	var back := model.global_transform.basis.z          # the mech's own backward
	var right := model.global_transform.basis.x
	var lhip := skel.to_global(skel.get_bone_global_pose(skel.find_bone("L_Thigh")).origin)
	var behind := ((r - hip).dot(back) + (l - lhip).dot(back)) * 0.5
	# "together" is measured against each foot's OWN hip: the hips themselves are 2.5 m apart on a 16 m
	# mech, so the raw foot-to-foot distance says nothing about whether the legs are splayed.
	var spread := maxf(absf((r - hip).dot(right)), absf((l - lhip).dot(right)))
	_check(behind > TRAIL_BEHIND_MIN, "the feet are only %.2f m behind the hips, they are not trailing"
			% behind)
	_check(spread < TRAIL_SPREAD_MAX, "a foot sits %.2f m outboard of its own hip, the legs are splayed"
			% spread)
	# knees: the clamp is `Hero3LegIk.KNEE_MAX_BEND_DEG` from straight
	for side in ["R", "L"]:
		var knee := _knee_deg(skel, side)
		_check(knee <= 180.0 - Hero3LegIk.KNEE_MIN_BEND_DEG + 0.5,
				"%s knee is locked straight (%.1f deg)" % [side, knee])
		_check(knee >= 180.0 - Hero3LegIk.KNEE_MAX_BEND_DEG - 0.5,
				"%s knee is folded past the clamp (%.1f deg)" % [side, knee])
	# nothing may be left un-posed
	for i in skel.get_bone_count():
		var o := skel.get_bone_global_pose(i).origin
		_check(o.is_finite(), "bone %s has a non-finite origin" % skel.get_bone_name(i))
	print("LEGS   behind %.2f m, spread %.2f m, knees R %.0f L %.0f deg"
			% [behind, spread, _knee_deg(skel, "R"), _knee_deg(skel, "L")])


func _knee_deg(skel: Skeleton3D, side: String) -> float:
	var thigh := skel.find_bone("%s_Thigh" % side)
	var calf := skel.find_bone("%s_Calf" % side)
	var foot := skel.find_bone("%s_Foot" % side)
	var a := skel.get_bone_global_pose(thigh).origin
	var b := skel.get_bone_global_pose(calf).origin
	var c := skel.get_bone_global_pose(foot).origin
	return rad_to_deg((a - b).angle_to(c - b))


func _thrust() -> void:
	var model := _spawn()
	_fly(model, CRUISE, 2.0)
	var f: Hero3Flight = model.flight
	_check(f.thrust != Vector3.ZERO, "the pose has no thrust direction at the cruise")
	var fwd := -model.global_transform.basis.z
	_check(f.thrust.dot(fwd) < -0.8, "the plumes do not run backwards along the flight path (%.2f)"
			% f.thrust.dot(fwd))
	# and the rig has to have actually aimed them
	var aimed := 0
	for flame: MeshInstance3D in model.rig._backpack.map(func(r: Dictionary) -> MeshInstance3D:
			return r["flame"]):
		var dir := (flame.global_transform.basis.y).normalized()
		if dir.dot(f.thrust) > 0.9:
			aimed += 1
	_check(aimed == 2, "%d of the 2 backpack plumes point along the thrust" % aimed)
	print("THRUST %s (dot forward %.2f), %d plumes aimed"
			% [str(f.thrust), f.thrust.dot(fwd), aimed])


func _blend_out() -> void:
	var model := _spawn()
	_fly(model, CRUISE, 2.0)
	_check(model.flight.blend > 0.99, "the pose was not in before the blend-out test")
	var body := model.get_parent() as Node3D
	var steps := int(Hero3Flight.BLEND_OUT / DT) + 30
	for i in steps:
		model.set_locomotion(&"glide", CRUISE, Vector2(0.0, 1.0))
		model.flight.sample(model, DT, &"glide")
		model.gait.set_flight(model.flight.blend, model.flight.lean)
		model._place_model(Vector3.ZERO)
	_check(model.flight.blend == 0.0, "the pose never blended out (%.2f)" % model.flight.blend)
	_check(model.flight.lean == 0.0, "the lean survives the blend-out")
	_check(is_instance_valid(body), "the stand-in body went away")
	# and the model node must be back exactly where it started
	_check(model.model.position.distance_to(model._model_rest) < 0.001,
			"the model did not come back to its rest offset (%s vs %s)"
			% [str(model.model.position), str(model._model_rest)])
	_check(model.model.transform.basis.is_equal_approx(Basis.IDENTITY),
			"the model kept a lean after the blend-out")


## The lead's dead-lock finding: a death taken in flight kept its lean and its thrust direction alive
## for the full 0.55 s blend-out, so the wreck flew itself for half a second. The cut is `DEAD_BLEND`.
func _death_in_flight() -> void:
	var model := _spawn()
	_fly(model, CRUISE, 2.0)
	_check(model.flight.blend > 0.99, "the pose was not in before the death test")
	_check(model.flight.thrust != Vector3.ZERO, "no thrust direction to cut")
	model.play_action(&"death", 0.06)
	# one tick: the thrust has to be gone the same tick the death takes hold
	model.flight.dead = true
	model.flight.sample(model, DT, Hero3Flight.STATE)
	_check(model.flight.thrust == Vector3.ZERO,
			"the plumes are still aimed on the tick the mech dies (%s)" % str(model.flight.thrust))
	var steps := int(Hero3Flight.DEAD_BLEND / DT) + 2
	for i in steps:
		model.flight.sample(model, DT, Hero3Flight.STATE)
	_check(model.flight.blend == 0.0, "the lean is still on %.2f s after the death (%.2f)"
			% [(steps * DT), model.flight.blend])
	_check(model.flight.lean == 0.0, "the lean survives the death cut")
	# and the gate is that it is FASTER than the ordinary blend-out it used to take
	_check(Hero3Flight.DEAD_BLEND < Hero3Flight.BLEND_OUT * 0.5,
			"the death cut is not meaningfully faster than the ordinary blend-out")
	print("DEATH  thrust cut on tick 1, lean gone by %.2f s (was %.2f s)"
			% [steps * DT, Hero3Flight.BLEND_OUT])


## A dead mech is a wreck: the cyan seams, the amber vents, the gold anchor, the weapon edges and the
## modelled visor and drone tips all fade over `Hero3Shade.POWER_TIME` and come back on the revive.
func _power_down() -> void:
	var model := _spawn()
	var shade: Hero3Shade = model.rig.shade
	_check(shade != null, "the model has no shade to power down")
	if shade == null:
		return
	var glow: Hero3Glow = model.rig.glow
	for i in 30:
		model.rig.update(DT)
	_check(is_equal_approx(shade.power, 1.0), "a live mech is not at full power (%.2f)" % shade.power)
	var lit_line: float = shade.shell.get_shader_parameter(&"line_gain")
	model.play_action(&"death", 0.06)
	model.rig.set_powered(false)
	# half way through the ramp the lights must already be visibly down, and not yet out
	for i in int(Hero3Shade.POWER_TIME * 0.5 / DT):
		model.rig.update(DT)
	var half := shade.power
	_check(half > 0.05 and half < 0.95, "the power ramp is not a ramp (%.2f at half time)" % half)
	var half_line: float = shade.shell.get_shader_parameter(&"line_gain")
	_check(half_line < lit_line * 0.95, "the seam lines did not dim (%.3f -> %.3f)"
			% [lit_line, half_line])
	for i in int(Hero3Shade.POWER_TIME / DT) + 10:
		model.rig.update(DT)
	_check(is_equal_approx(shade.power, 0.0), "the mech never finished powering down (%.2f)"
			% shade.power)
	_check(is_zero_approx(float(shade.shell.get_shader_parameter(&"line_gain"))),
			"the seam lines are still lit on a wreck")
	_check(is_zero_approx(float(shade.shell.get_shader_parameter(&"gold_glow"))),
			"the gold trim is still self-lit on a wreck")
	_check(is_zero_approx(float(shade.shell.get_shader_parameter(&"vent_pulse"))),
			"the vents are still lit on a wreck")
	var panel: ShaderMaterial = glow.vent[0].material_override as ShaderMaterial
	_check(is_zero_approx(float(panel.get_shader_parameter(&"glow_gain"))),
			"the chest grille is still lit on a wreck")
	_check(is_zero_approx(glow.tips[0].material_override.albedo_color.a)
			or glow.tips[0].material_override.albedo_color.get_luminance() < 0.01,
			"a drone tip is still lit on a wreck")
	# the revive: `PlayerMech.heal()` is the one place every revive passes through and it calls
	# `stop_action`, so that is the edge the model powers back up on
	model.stop_action()
	model.rig.set_powered(true)
	for i in int(Hero3Shade.POWER_TIME / DT) + 10:
		model.rig.update(DT)
	_check(is_equal_approx(shade.power, 1.0), "the revive did not bring the lights back (%.2f)"
			% shade.power)
	_check(is_equal_approx(float(shade.shell.get_shader_parameter(&"line_gain")), lit_line),
			"the seam lines came back at the wrong gain")
	print("POWER  %.2f -> %.2f -> %.2f over %.2f s each way"
			% [1.0, half, shade.power, Hero3Shade.POWER_TIME])
