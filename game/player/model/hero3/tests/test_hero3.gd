extends Node
## hero-v3 gate: the HeroModel API answers on the real exported mech, the sockets exist, and the
## procedural gait keeps its feet. Run with
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3.gd
##
## What it measures, against the brief's "Done when":
##   * every CONTRACTS §5 socket resolves to a Node3D
##   * planted-foot slide <= 3 % of the stride at 9 and 16 m/s
##   * no foot ever goes below the ground
##   * the knee never bends past 170 deg
##   * every SPEC §10 action id answers play_action. The list is the brief's 45 plus `gatling_spin`,
##     which `combat/weapons/gatling.gd` calls and the brief did not name (lead r3 item B1).

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const SOCKETS: Array[StringName] = [&"muzzle_r", &"hand_r", &"hand_l", &"shield_l", &"saber_r",
		&"back", &"wing_l", &"wing_r", &"missile_l", &"missile_r", &"cockpit", &"chest"]
const ACTIONS: Array[StringName] = [&"melee_l1", &"melee_l2", &"melee_l3", &"lunge",
		&"charge_slash", &"air_l1", &"air_l2", &"return_cut", &"ram_kick", &"execution",
		&"guard_up", &"parry", &"catch_hold", &"catch_release", &"fire_r", &"charge_r",
		&"reload", &"missile_launch", &"anchor_fire", &"fins_send", &"burst", &"well_throw",
		&"plunge_dive", &"plunge_land", &"overdrive_ignite", &"lance_fire", &"rift_out",
		&"rift_in", &"ward", &"dash_f", &"dash_b", &"dash_l", &"dash_r", &"slide", &"hover",
		&"fly", &"jump", &"fall", &"land_light", &"land_heavy", &"hit_light", &"hit_heavy",
		&"hit_knockdown", &"stagger", &"death", &"gatling_spin"]
const SLIDE_GATE := 0.03      ## fraction of the travel a planted foot may drift
const GROUND_GATE := -0.02    ## metres below y = 0 a foot may reach
const KNEE_GATE_DEG := 150.0  ## the knee never folds past this (bend from straight)
## Lead r2 item 4: these four are what the filmstrip has to show, so they are gates, not prints.
const CADENCE_GATE := Vector2(0.9, 1.6)   ## steps/s at walk: a 16 m machine, not a terrier
const STRIDE_GATE := 5.0                  ## metres per step at walk
const DOUBLE_SUPPORT_GATE := 0.10         ## fraction of the cycle with both feet down at walk
const MID_STANCE_KNEE_GATE := Vector2(25.0, 60.0)   ## degrees of bend when the foot is under the hip
const REACH_GATE := 0.15    ## metres the solved ankle may miss its target before the leg is over-extended

var failures: Array[String] = []
var model: Node3D
var skeleton: Skeleton3D


func _ready() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_fail("hero3_model.tscn did not load")
		_finish()
		return
	model = packed.instantiate()
	add_child(model)
	skeleton = model.get_node_or_null(^"Model/Hero3Rig/Skeleton3D") as Skeleton3D
	if skeleton == null:
		_fail("hero3_model.tscn has no Model/Hero3Rig/Skeleton3D")
		_finish()
		return
	_check_sockets()
	_check_origin()
	_check_gait(9.0)
	_check_gait(16.0)
	_check_gait(0.0, true)
	_check_blade()
	_check_actions()
	_finish()


func _check_sockets() -> void:
	for socket_name in SOCKETS:
		var node: Node3D = model.socket(socket_name)
		if node == null:
			_fail("socket %s is missing" % socket_name)
	print("SOCKETS %d checked" % SOCKETS.size())


## The model must stand on y = 0 between the feet and face -Z (CONTRACTS §5).
func _check_origin() -> void:
	var lowest := INF
	var highest := -INF
	for i in skeleton.get_bone_count():
		var p := skeleton.get_bone_global_rest(i).origin
		lowest = minf(lowest, p.y)
		highest = maxf(highest, p.y)
	print("ORIGIN bones y %.2f .. %.2f" % [lowest, highest])
	var head := skeleton.find_bone("Head")
	if head < 0:
		_fail("no Head bone")
	elif skeleton.get_bone_global_rest(head).origin.y < 12.0:
		_fail("Head bone is at %.2f m, expected ~13.9" % skeleton.get_bone_global_rest(head).origin.y)


## Drive the gait at a fixed ground speed and measure what the feet actually do.
##
## The model node MOVES, because that is what PlayerMech does and it is the only way a planted foot
## can be measured for slide: the gait holds each plant at a fixed WORLD point, so a foot that rides
## along with the body shows up here immediately.
##
## Everything the lead asked to see on a filmstrip is measured here instead of eyeballed: stride,
## cadence, double support, pelvis height and the knee angle at mid-stance.
func _check_gait(speed: float, turning: bool = false) -> void:
	var gait: Hero3Gait = model.gait
	if gait == null:
		_fail("no Hero3Gait on the model")
		return
	var walking := speed <= Hero3Gait.WALK_SPEED
	var label := "TURN" if turning else "GAIT %.0f m/s" % speed
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	model.set_locomotion(&"run" if speed > 12.0 else &"walk", speed,
			Vector2.ZERO if turning else Vector2(0.0, -1.0))
	gait.reset()
	var dt := 1.0 / 120.0
	var ticks := 720
	var planted_last := gait.planted_feet()
	var was_planted: Array[bool] = [true, true]
	var slide := 0.0
	var lowest := 0.0
	var worst_knee := 0.0
	var steps := 0
	var support := PackedInt32Array([0, 0, 0])
	var mid_knee := PackedFloat64Array()
	var pelvis_lo := INF
	var pelvis_hi := -INF
	var reach_err := 0.0
	for tick in ticks:
		if turning:
			model.rotate_y(deg_to_rad(55.0) * dt)
		else:
			model.position += Vector3(0.0, 0.0, -speed * dt)
		gait.update(dt)
		var ground := skeleton.global_position.y
		support[gait.support_count()] += 1
		pelvis_lo = minf(pelvis_lo, gait.pelvis_height())
		pelvis_hi = maxf(pelvis_hi, gait.pelvis_height())
		var targets := gait.foot_targets()
		var ankles := gait.ankle_targets()
		for i in targets.size():
			# the sole target carries the measured mesh trim under it (hero-v3 r9 item 1); the gate is
			# about where the PLANNER aims the foot, which is the target minus that trim
			lowest = minf(lowest, targets[i].y - ground - gait.sole_trim(i))
			var spec: Dictionary = Hero3Gait.LEGS[i]
			var foot := skeleton.find_bone(String(spec["foot"]))
			reach_err = maxf(reach_err, skeleton.to_global(
					skeleton.get_bone_global_pose(foot).origin).distance_to(ankles[i]))
			if gait.is_planted(i) and gait.stance_offset(i) < 0.6:
				mid_knee.append(_knee_angle_deg(i))
			worst_knee = maxf(worst_knee, _knee_angle_deg(i))
		var now := gait.planted_feet()
		for i in now.size():
			var planted := gait.is_planted(i)
			# slide is only the drift of a foot that was ALREADY planted: the frame a step lands is a
			# step, not a slide, and counting it would charge the whole stride to the gate
			if planted and was_planted[i]:
				slide += now[i].distance_to(planted_last[i])
			if planted_last[i].distance_to(now[i]) > 0.01:
				steps += 1
			was_planted[i] = planted
		planted_last = now
	var travelled := speed * float(ticks) * dt
	var slide_frac := slide / maxf(travelled, 0.001)
	var rep := gait.report()
	var stride := float(rep["stride"])
	var cadence := float(rep["cadence"])
	var double_support := float(support[2]) / float(ticks)
	var flight := float(support[0]) / float(ticks)
	var mid := _median(mid_knee)
	print(("%s  stride %.2f m  cadence %.2f steps/s  steps %d  slide %.3f m (%.2f%%)  "
			+ "lowest foot %.3f m  knee mid-stance %.1f deg (worst %.1f)  double support %.0f%%  "
			+ "flight %.0f%%  pelvis %.2f..%.2f m  ankle miss %.3f m") % [label, stride, cadence, steps, slide,
			slide_frac * 100.0, lowest, mid, worst_knee, double_support * 100.0, flight * 100.0,
			pelvis_lo, pelvis_hi, reach_err])
	if slide_frac > SLIDE_GATE:
		_fail("planted-foot slide %.2f%% at %.0f m/s, gate %.0f%%"
				% [slide_frac * 100.0, speed, SLIDE_GATE * 100.0])
	if lowest < GROUND_GATE:
		_fail("a foot reached %.3f m at %.0f m/s" % [lowest, speed])
	if reach_err > REACH_GATE:
		_fail("the solved ankle missed its target by %.3f m at %.0f m/s, gate %.2f -- the leg is "
				% [reach_err, speed, REACH_GATE] + "over-extended and the foot is skating")
	if worst_knee > KNEE_GATE_DEG:
		_fail("knee folded to %.1f deg at %.0f m/s, gate %.0f" % [worst_knee, speed, KNEE_GATE_DEG])
	if steps < 4:
		_fail("only %d steps in %.0f s at %.0f m/s -- the planner is not advancing the feet"
				% [steps, float(ticks) * dt, speed])
	if turning:
		if steps < 4:
			_fail("turning in place took %d steps: the feet are sliding round with the hips" % steps)
		return
	if walking:
		if cadence < CADENCE_GATE.x or cadence > CADENCE_GATE.y:
			_fail("walk cadence %.2f steps/s, gate %.1f-%.1f" % [cadence, CADENCE_GATE.x,
					CADENCE_GATE.y])
		if stride < STRIDE_GATE:
			_fail("walk stride %.2f m, gate %.1f m" % [stride, STRIDE_GATE])
		if double_support < DOUBLE_SUPPORT_GATE:
			_fail("walk double support %.0f%%, gate %.0f%% -- the walk has a flight phase"
					% [double_support * 100.0, DOUBLE_SUPPORT_GATE * 100.0])
		if mid < MID_STANCE_KNEE_GATE.x or mid > MID_STANCE_KNEE_GATE.y:
			_fail("knee at mid-stance %.1f deg, gate %.0f-%.0f -- the leg is not crouched"
					% [mid, MID_STANCE_KNEE_GATE.x, MID_STANCE_KNEE_GATE.y])
	elif flight < 0.05:
		_fail("run flight %.0f%%: the run is not bounding" % [flight * 100.0])
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO


## The bend of the knee from straight: 0 is a locked leg. (The old gate compared this against 170
## deg, which is the EXTENSION angle, so it could never fire.)
func _knee_angle_deg(leg: int) -> float:
	var spec: Dictionary = Hero3Gait.LEGS[leg]
	var thigh := skeleton.find_bone(String(spec["thigh"]))
	var calf := skeleton.find_bone(String(spec["calf"]))
	var a := skeleton.get_bone_global_pose(thigh).basis.y.normalized()
	var b := skeleton.get_bone_global_pose(calf).basis.y.normalized()
	return rad_to_deg(a.angle_to(b))


func _median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return -1.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _check_actions() -> void:
	var missing: Array[String] = []
	for id in ACTIONS:
		if model.play_action(id) <= 0.0:
			missing.append(String(id))
	if missing.is_empty():
		print("ACTIONS %d all answered" % ACTIONS.size())
	else:
		print("ACTIONS %d of %d missing (clips not authored yet): %s"
				% [missing.size(), ACTIONS.size(), ", ".join(missing)])
		_fail("%d SPEC §10 action ids have no clip" % missing.size())


## The blade-ownership handshake with melee-defense (review r5 item 2): the model answers
## `has_own_blade`, so `SaberVisual` draws no second blade and starts its energy sheath exactly
## `blade_length()` metres out along the `saber_r` socket. If that number and the modelled steel ever
## disagree, the sheath starts in mid-air.
func _check_blade() -> void:
	if not model.has_own_blade():
		_fail("has_own_blade() must be true -- the model carries its own steel")
	var length := float(model.blade_length())
	var table := load("res://combat/melee/melee_table.gd")
	var agreed := float(table.get_script_constant_map()["MODEL_BLADE_LENGTH"])
	print("BLADE steel %.1f m, MeleeTable.MODEL_BLADE_LENGTH %.1f m, reach %.1f m"
			% [length, agreed, float(table.get_script_constant_map()["BLADE_LENGTH"])])
	if absf(length - agreed) > 0.01:
		_fail("blade_length() %.2f m disagrees with MeleeTable.MODEL_BLADE_LENGTH %.2f m"
				% [length, agreed])
	var socket: Node3D = model.socket(&"saber_r")
	if socket == null:
		_fail("saber_r socket is missing, so the sheath has nothing to hang on")
		return
	var tip := socket.to_global(Vector3(0.0, 0.0, -length))
	var steel := _farthest_weapon_point(socket.global_position, 16.0)
	print("BLADE socket %s, tip along -Z at %.2f m from the origin" % [socket.global_position,
			tip.distance_to(socket.global_position)])
	if steel < length * 0.8:
		_fail("the modelled steel reaches only %.1f m from the socket, blade_length() says %.1f"
				% [steel, length])


## How far the saber mesh actually reaches from the socket, in metres.
func _farthest_weapon_point(from: Vector3, limit: float) -> float:
	var saber := model.rig.weapon(&"Hero3Saber") as MeshInstance3D
	if saber == null or saber.mesh == null:
		return 0.0
	var best := 0.0
	var stack: Array[Node] = [saber]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh != null:
				for i in mesh_node.mesh.get_surface_count():
					var arrays := mesh_node.mesh.surface_get_arrays(i)
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					for v in verts:
						best = maxf(best, from.distance_to(mesh_node.to_global(v)))
		stack.append_array(node.get_children())
		if best > limit:
			break
	return best


func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)
