extends Node
## hero-v3 r6: the behaviour-identity harness for the `hero3_gait.gd` split.
##   tools/godot.sh test res://player/model/hero3/tests/probe_pose_dump.gd -- --out=<abs path>
##
## Drives the model through a scripted timeline (walk, run, strafe both ways, back-pedal, turn in
## place, accelerate, stop, hop, heavy landing, slide, dash, hover) and writes EVERY bone's global
## pose, every tick, as text. Two runs of this file -- one before a refactor, one after -- are
## compared byte for byte, so "the split changed nothing" is a measurement rather than a claim.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 120.0
## The gate the r6 split has to meet: identical to 1e-5 m and 1e-5 rad.
const GATE_M := 1e-5
const GATE_RAD := 1e-5

var _out: FileAccess
var _model: Node3D
var _skel: Skeleton3D
var _gait: Hero3Gait
var _clips: Hero3ClipPlayer
var _tick: int = 0
var _seg: String = ""


func _ready() -> void:
	# r12 §3 (city-art's `ArtRepo`): derived from the project directory, not a literal home
	# path — the same probe has to run from any checkout.
	var path := ArtRepo.at("tmp/hero-v3/pose.txt")
	var against := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			path = arg.substr(6)
		elif arg.begins_with("--cmp="):
			against = arg.substr(6)
	_out = FileAccess.open(path, FileAccess.WRITE)
	if _out == null:
		print("FAIL cannot write %s" % path)
		get_tree().quit(1)
		return
	_model = (load(SCENE) as PackedScene).instantiate()
	_model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_model)
	_skel = _model.skeleton
	_gait = _model.gait
	_clips = _model.clips
	_out.store_line("bones %d" % _skel.get_bone_count())
	_run()
	_out.close()
	print("POSE wrote %s (%d frames, %d bones)" % [path, _tick, _skel.get_bone_count()])
	if against.is_empty():
		get_tree().quit(0)
		return
	get_tree().quit(0 if _compare(against, path) else 1)


## One segment of the timeline: a state held for `ticks`, with the body moving the way that state
## moves it. `speed` ramps from `speed_from` when that is given (the accelerate case).
func _hold(seg: String, state: StringName, speed: float, input: Vector2, move: Vector3,
		ticks: int, spin: float = 0.0, speed_from: float = -1.0) -> void:
	_seg = seg
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	_gait.reset()
	_clips.stop()
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	for i in 4:
		_step(&"idle", 0.0, Vector2.ZERO, Vector3.ZERO, 0.0)
	for i in ticks:
		var t := float(i) / float(maxi(ticks - 1, 1))
		var spd := lerpf(speed_from, speed, t) if speed_from >= 0.0 else speed
		var step_move := move
		if speed_from >= 0.0:
			step_move = move.normalized() * spd
		_step(state, spd, input, step_move, spin)


func _step(state: StringName, speed: float, input: Vector2, move: Vector3, spin: float) -> void:
	_model.position += move * DT
	if spin != 0.0:
		_model.rotate_y(spin * DT)
	_model.set_locomotion(state, speed, input)
	_clips.update(DT)
	_gait.update(DT)
	_clips.apply()
	_record()


func _record() -> void:
	var xf := _skel.global_transform
	_out.store_line("F %s %d %.9f %.9f %.9f" % [_seg, _tick, _model.position.x, _model.position.y,
			_model.rotation.y])
	for i in _skel.get_bone_count():
		var pose := xf * _skel.get_bone_global_pose(i)
		var q := pose.basis.get_rotation_quaternion()
		_out.store_line("B %d %d %.9f %.9f %.9f %.9f %.9f %.9f %.9f" % [i, _tick, pose.origin.x,
				pose.origin.y, pose.origin.z, q.x, q.y, q.z, q.w])
	_tick += 1


## The timeline. Every gaits' own gate is covered, plus the hand-overs between them: what a refactor
## of the planner, the yaw, the stance or the roll is most likely to break is a TRANSITION, not a
## steady state.
func _run() -> void:
	_hold("walk", &"walk", 9.0, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -9.0), 300)
	_hold("run", &"run", 16.0, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -16.0), 300)
	_hold("strafe_r", &"walk", 9.0, Vector2(1.0, 0.0), Vector3(9.0, 0.0, 0.0), 300)
	_hold("strafe_l", &"walk", 9.0, Vector2(-1.0, 0.0), Vector3(-9.0, 0.0, 0.0), 240)
	_hold("back", &"walk", 6.0, Vector2(0.0, 1.0), Vector3(0.0, 0.0, 6.0), 300)
	_hold("turn", &"walk", 0.0, Vector2.ZERO, Vector3.ZERO, 300, deg_to_rad(55.0))
	_hold("accel", &"run", 16.0, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -16.0), 300, 0.0, 0.0)
	_hold("stop", &"idle", 0.0, Vector2.ZERO, Vector3.ZERO, 120)
	_hold("coast", &"coast", 40.0, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -40.0), 200)
	_hold("slide", &"slide", 30.0, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -30.0), 200)
	_hold("dash", &"dash_f", 60.0, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -60.0), 120)
	_hold("hover", &"hover", 20.0, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -20.0), 120)
	_hold("walk_diag", &"walk", 9.0, Vector2(0.7, -0.7), Vector3(6.3, 0.0, -6.3), 240)
	_jump(14.0, &"land_light", 12.0)
	_jump(40.0, &"land_heavy", 26.0)
	# FULL clips: the ones that key the ROOT and the FEET take the legs away from the planner
	# entirely, which is the hand-over the gait is most likely to get wrong.
	for id: StringName in [&"death", &"hit_knockdown", &"ram_kick", &"execution", &"plunge_land",
			&"melee_l1"]:
		_clip(id)


## One authored clip played alone at idle, exactly as the game plays it.
func _clip(id: StringName) -> void:
	_seg = "clip_%s" % id
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	_gait.reset()
	_clips.stop()
	_model.stop_action()
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	for i in 4:
		_step(&"idle", 0.0, Vector2.ZERO, Vector3.ZERO, 0.0)
	var frames := int(float(_clips.clips[id]["frames"])) + 8
	_model.play_action(id, 0.08)
	for i in frames:
		_step(&"idle", 0.0, Vector2.ZERO, Vector3.ZERO, 0.0)


## A hop and a heavy drop: the state goes up, comes down (with the fall speed the air pose braces
## against), then reports the touchdown before the landing state -- the order the game uses.
func _jump(impact: float, landing: StringName, up_speed: float) -> void:
	_seg = "jump_%s" % landing
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	_gait.reset()
	_clips.stop()
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	for i in 4:
		_step(&"idle", 0.0, Vector2.ZERO, Vector3.ZERO, 0.0)
	var y := 0.0
	var vy := up_speed
	for i in 60:
		vy -= 20.0 * DT
		y = maxf(y + vy * DT, 0.0)
		_model.position.y = y
		_step(&"jump", 8.0, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -8.0), 0.0)
	for i in 60:
		vy -= 20.0 * DT
		y = maxf(y + vy * DT, 0.0)
		_model.position.y = y
		_model.set_fall_speed(maxf(-vy, 0.0))
		_step(&"fall", 8.0, Vector2(0.0, -1.0), Vector3(0.0, 0.0, -8.0), 0.0)
	_model.position.y = 0.0
	_gait.set_impact(impact)
	for i in 120:
		_step(landing, 0.0, Vector2.ZERO, Vector3.ZERO, 0.0)


## Compare a previous dump with this one, line by line, and print the worst difference per segment.
##
## The rotation metric is the CHORD |a - b| on the quaternions, doubled: `2 x acos(dot)` is the
## textbook form but acos loses half its digits approaching 1, so it reports ~1e-3 rad for two
## rotations printed at nine decimals that are in fact identical.
func _compare(before_path: String, after_path: String) -> bool:
	var before := FileAccess.get_file_as_string(before_path).split("\n")
	var after := FileAccess.get_file_as_string(after_path).split("\n")
	if before.size() != after.size():
		print("FAIL %s has %d lines, %s has %d" % [before_path, before.size(), after_path,
				after.size()])
		return false
	var seg := ""
	var seg_pos := 0.0
	var seg_rot := 0.0
	var worst_pos := 0.0
	var worst_rot := 0.0
	for line in before.size():
		var a := before[line].split(" ", false)
		var b := after[line].split(" ", false)
		if a.is_empty() and b.is_empty():
			continue    # the trailing newline both files end with
		if a.size() != b.size() or a[0] != b[0]:
			print("FAIL line %d does not line up:\n  %s\n  %s" % [line, before[line], after[line]])
			return false
		if a[0] == "F" and a[1] != seg:
			_report_seg(seg, seg_pos, seg_rot)
			seg = a[1]
			seg_pos = 0.0
			seg_rot = 0.0
		if a.size() < 6:
			continue
		var pos := 0.0
		for i in range(3, 6):
			pos = maxf(pos, absf(float(a[i]) - float(b[i])))
		var rot := _quat_chord(a, b) if a[0] == "B" else 0.0
		seg_pos = maxf(seg_pos, pos)
		seg_rot = maxf(seg_rot, rot)
		worst_pos = maxf(worst_pos, pos)
		worst_rot = maxf(worst_rot, rot)
	_report_seg(seg, seg_pos, seg_rot)
	print("CMP %d lines, worst %.12f m / %.12f rad" % [before.size(), worst_pos, worst_rot])
	if worst_pos <= GATE_M and worst_rot <= GATE_RAD:
		print("PASS identical within %.6f m / %.6f rad" % [GATE_M, GATE_RAD])
		return true
	print("FAIL exceeds the %.6f m / %.6f rad gate" % [GATE_M, GATE_RAD])
	return false


func _report_seg(seg: String, pos: float, rot: float) -> void:
	if not seg.is_empty():
		print("CMP %-20s max %.12f m  %.12f rad" % [seg, pos, rot])


## The angle between two unit quaternions in radians, from the chord: stable where acos is not. The
## quaternion is the last four columns of a `B` line.
func _quat_chord(a: PackedStringArray, b: PackedStringArray) -> float:
	var dot := 0.0
	for i in 4:
		dot += float(a[a.size() - 4 + i]) * float(b[b.size() - 4 + i])
	var flip := -1.0 if dot < 0.0 else 1.0
	var chord := 0.0
	for i in 4:
		var d := float(a[a.size() - 4 + i]) - flip * float(b[b.size() - 4 + i])
		chord += d * d
	return 2.0 * sqrt(chord)
