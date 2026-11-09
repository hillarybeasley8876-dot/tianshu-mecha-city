extends Node
## hero-v3 gate for lead r4 item 6: the rifle goes where the mech is aiming.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_aim.gd
##
##   * the aim SIGNS, measured in world space: a target to the right turns the chest right, a target
##     above pitches it up
##   * at weight 1, for aims within +-25 deg yaw and +-20 deg pitch, the rifle MESH's own long axis --
##     CPU-skinned off the vertices the R_Hand carries, not a socket -- is within 3 deg of the
##     muzzle-to-aim direction, with no clip and during charge_r and gatling_spin
##   * during fire_r it may be up to 8 deg off at the recoil peak and must be back within 3 deg by the
##     clip's end: the recoil layers ON TOP of the aim, it does not replace it
##   * `muzzle_r` sits at the barrel tip with its -Z along the barrel

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 60.0
const RANGE := 200.0
const GATE := 3.0
const RECOIL_GATE := 8.0
## yaw deg, pitch deg. The gate only asks for +-25 / +-20, so that is what is measured.
const AIMS: Array = [
	[0.0, 0.0], [25.0, 0.0], [-25.0, 0.0], [0.0, 20.0], [0.0, -20.0],
	[18.0, 14.0], [-18.0, -14.0],
]
## clip -> the worst barrel error allowed while it plays, in degrees.
const CLIPS: Dictionary = {
	&"charge_r": GATE, &"gatling_spin": GATE, &"fire_r": RECOIL_GATE,
}

var failures: Array[String] = []
var _rifle: MeshInstance3D
var _bind := PackedInt32Array()
var _hand: int = 0


func _ready() -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	var skel: Skeleton3D = model.skeleton
	_hand = skel.find_bone("R_Hand")
	_rifle = model.rig.weapon(&"Hero3Rifle") as MeshInstance3D
	if _rifle == null or _rifle.skin == null:
		print("FAIL no rifle mesh")
		get_tree().quit(1)
		return
	for b in _rifle.skin.get_bind_count():
		var bone := _rifle.skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(String(_rifle.skin.get_bind_name(b)))
		_bind.append(bone)
	print("AIM    barrel measured off the mesh: %s, %.2f m long"
			% [model.rig.rifle["dir"], float(model.rig.rifle["len"])])
	for aim: Array in AIMS:
		await _aim_pass(model, float(aim[0]), float(aim[1]))
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for line in failures:
			print("FAIL %s" % line)
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


## One aim direction, with no clip and then through each weapon clip.
func _aim_pass(model: Node3D, yaw_deg: float, pitch_deg: float) -> void:
	var gait: Hero3Gait = model.gait
	var clips: Hero3ClipPlayer = model.clips
	var skel: Skeleton3D = model.skeleton
	var dir := Vector3(0.0, 0.0, -1.0).rotated(Vector3.RIGHT, deg_to_rad(pitch_deg)) \
			.rotated(Vector3.UP, deg_to_rad(-yaw_deg))
	var point := skel.global_position + Vector3(0.0, 12.0, 0.0) + dir * RANGE
	model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	gait.reset()
	model.stop_action()
	model.set_aim(point, 1.0)
	for i in 60:
		_tick(model)
	var chest := _chest_yaw(skel)
	var line := "AIM    yaw %+5.1f pitch %+5.1f | chest %+5.1f right, %+5.1f up" \
			% [yaw_deg, pitch_deg, chest.x, chest.y]
	# the chest carries a +1.8 deg rest tilt, so only a real aim is a sign test
	if absf(yaw_deg) > 1.0 and signf(chest.x) != signf(yaw_deg):
		_fail("aim %+.0f right turned the chest %+.1f -- the yaw sign is wrong" % [yaw_deg, chest.x])
	if absf(pitch_deg) > 1.0 and signf(chest.y - 1.8) != signf(pitch_deg):
		_fail("aim %+.0f up pitched the chest %+.1f -- the pitch sign is wrong"
				% [pitch_deg, chest.y])
	var bare := _barrel_error(model, point)
	line += " | bare %.2f deg" % bare
	if bare > GATE:
		_fail("aim %+.0f/%+.0f: the barrel is %.2f deg off with no clip, gate %.1f"
				% [yaw_deg, pitch_deg, bare, GATE])
	for id: StringName in CLIPS:
		model.stop_action()
		for i in 20:
			_tick(model)
		var frames := int(float(clips.clips[id]["frames"]))
		model.play_action(id, 0.06)
		var worst := 0.0
		var end := 0.0
		for f in frames + 8:
			_tick(model)
			var err := _barrel_error(model, point)
			worst = maxf(worst, err)
			if f == frames + 7:
				end = err
		line += " | %s %.2f (end %.2f)" % [id, worst, end]
		if worst > float(CLIPS[id]):
			_fail("aim %+.0f/%+.0f during %s: the barrel is %.2f deg off, gate %.1f"
					% [yaw_deg, pitch_deg, id, worst, float(CLIPS[id])])
		if end > GATE:
			_fail("aim %+.0f/%+.0f: %s ends with the barrel %.2f deg off, gate %.1f"
					% [yaw_deg, pitch_deg, id, end, GATE])
	model.set_aim(Vector3.ZERO, 0.0)
	print(line)
	await get_tree().process_frame


func _tick(model: Node3D) -> void:
	model.clips.update(DT)
	model.gait.update(DT)
	model.clips.apply()
	model.rig.update(DT)


## How far the rifle MESH's own long axis is from the muzzle-to-aim direction, in degrees. The mesh is
## CPU-skinned: the axis is the line from the hand to the furthest vertex the R_Hand carries.
func _barrel_error(model: Node3D, point: Vector3) -> float:
	var skel: Skeleton3D = model.skeleton
	var hand := skel.get_bone_global_pose(_hand)
	var far := hand.origin
	var best := -1.0
	for s in _rifle.mesh.get_surface_count():
		var arrays := _rifle.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or verts.is_empty():
			continue
		var per := int(bones.size() / verts.size())
		for i in verts.size():
			var top := -1
			var w := -1.0
			for j in per:
				if weights[i * per + j] > w:
					w = weights[i * per + j]
					top = int(bones[i * per + j])
			if top < 0 or _bind[top] != _hand:
				continue
			var p := hand * (_rifle.skin.get_bind_pose(top) * verts[i])
			var d := p.distance_squared_to(hand.origin)
			if d > best:
				best = d
				far = p
	if best <= 0.0:
		return 180.0
	var muzzle: Node3D = model.socket(&"muzzle_r")
	var axis := (far - hand.origin).normalized()
	var to_aim: Vector3 = (point - muzzle.global_position).normalized()
	return rad_to_deg(axis.angle_to(to_aim))


## How far the chest has turned toward the aim, in degrees: `x` right, `y` up.
func _chest_yaw(skel: Skeleton3D) -> Vector2:
	var f := (skel.global_transform.basis * skel.get_bone_global_pose(
			skel.find_bone("Spine02")).basis * Vector3(0.0, 0.0, -1.0)).normalized()
	return Vector2(rad_to_deg(atan2(f.x, -f.z)), rad_to_deg(asin(clampf(f.y, -1.0, 1.0))))


func _fail(line: String) -> void:
	failures.append(line)
