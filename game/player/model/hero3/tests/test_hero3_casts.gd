extends Node
## hero-v3 gate for lead r4 item 8: every skill cast has ONE CLEAR KEY POSE, and it is HELD.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_casts.gd
##
##   * there is a run of at least `HOLD` consecutive frames over which no tracked bone moves more than
##     `HOLD_EPS` -- the pose is HELD, not swept through
##   * that held pose is at least `AMPLITUDE` away from the clip's NEUTRAL pose, so it reads as a
##     pose and not a twitch
##
## Both halves are needed, and each alone gives a false PASS. Asking only for a steady run passes
## every cast on its own tail: burst held 8 frames at 36 of 38, overdrive_ignite 7 frames at 65 of 66,
## which is the clip settling back to neutral. Asking instead for the single most EXTREME frame to be
## steady fails all five, because the most extreme frame of a shoulder launch is the three-frame
## recoil at `fire + 3` -- an accent that is supposed to snap, and the readable key pose is the open
## pod rack it snaps out of, which IS held.
##
## So the test finds the longest steady run and then asks how far that run sits from neutral.
## The five casts the review named. `well_throw` is the odd one out -- it is a two-handed throw and
## the only weapon clip that is not an offset on the aim.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 60.0
## A 16 m mech: 1 m of hand travel is about 6% of its height, which is the least that reads as a pose.
const AMPLITUDE := 1.0
const HOLD := 6
## Over a held pose no tracked bone may move more than this in total across the whole run.
const HOLD_EPS := 0.15
const CASTS: Array[StringName] = [&"burst", &"lance_fire", &"overdrive_ignite", &"well_throw",
		&"fins_send"]
## The bones a cast is read from: the two hands, the head and the chest. A cast that moved nothing but
## a finger would not be a cast.
const TRACKED: Array[String] = ["R_Hand", "L_Hand", "Head", "Spine02"]

var failures: Array[String] = []


func _ready() -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	print("CASTS  clip                frames  amplitude  longest hold  held pose at")
	for id in CASTS:
		_cast(model, id)
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for line in failures:
			print("FAIL %s" % line)
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


## One cast: play it, record where the tracked bones are every frame, then measure the key pose.
func _cast(model: Node3D, id: StringName) -> void:
	if not model.clips.has(id):
		_fail("%s: no such clip" % id)
		return
	model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	model.gait.reset()
	model.stop_action()
	model.set_aim(Vector3.ZERO, 0.0)
	for i in 60:
		_tick(model)
	var frames := int(float(model.clips.clips[id]["frames"]))
	var track: Array = []
	model.play_action(id, 0.06)
	for f in frames + 6:
		_tick(model)
		track.append(_pose(model))
	var hold := _longest_hold(track)
	var distinct := _from_neutral(track, int(hold[1]), int(hold[2]))
	print("CASTS  %-18s %5d  %8.2f m  %8d f     held f%d..f%d"
			% [id, frames, distinct, int(hold[0]), int(hold[1]), int(hold[2])])
	if int(hold[0]) < HOLD:
		_fail("%s: its steadiest run is only %d frames, gate %d -- the key pose is swept through, not held"
				% [id, int(hold[0]), HOLD])
	if distinct < AMPLITUDE:
		_fail("%s: its held pose is only %.2f m from neutral, gate %.2f m -- that is a twitch, not a key "
				% [id, distinct, AMPLITUDE] + "pose")


## The longest run of frames over which no tracked bone moves more than `HOLD_EPS`, as
## `[length, first, last]`. Ties go to the run that sits FURTHEST from neutral, so a clip that is
## steady both at its key pose and at its tail is judged on the key pose.
func _longest_hold(track: Array) -> Array:
	var best := 0
	var best_at := 0
	var best_end := 0
	var best_dist := -1.0
	for start in track.size():
		var end := start
		while end + 1 < track.size() and _spread(track, start, end + 1) <= HOLD_EPS:
			end += 1
		var length := end - start + 1
		var dist := _from_neutral(track, start, end)
		if length > best or (length == best and dist > best_dist):
			best = length
			best_at = start
			best_end = end
			best_dist = dist
	return [best, best_at, best_end]


## How far the pose held over `track[start..end]` sits from the clip's NEUTRAL pose. Neutral is the
## mean of the first and last frames: every one of these clips starts and ends where it began, so that
## is the pose the key pose has to be distinguishable FROM.
func _from_neutral(track: Array, start: int, end: int) -> float:
	var worst := 0.0
	for b in TRACKED.size():
		var neutral := ((track[0][b] as Vector3) + (track[track.size() - 1][b] as Vector3)) * 0.5
		var held := Vector3.ZERO
		for f in range(start, end + 1):
			held += track[f][b] as Vector3
		worst = maxf(worst, (held / float(end - start + 1)).distance_to(neutral))
	return worst


## How far any tracked bone travels anywhere in `track[start..end]`.
func _spread(track: Array, start: int, end: int) -> float:
	var worst := 0.0
	for b in TRACKED.size():
		var lo := track[start][b] as Vector3
		var hi := lo
		for f in range(start + 1, end + 1):
			var p := track[f][b] as Vector3
			lo = lo.min(p)
			hi = hi.max(p)
		worst = maxf(worst, (hi - lo).length())
	return worst


## Where the tracked bones are, in the model's own space.
func _pose(model: Node3D) -> Array:
	var skel: Skeleton3D = model.skeleton
	var out: Array = []
	for name in TRACKED:
		var bone := skel.find_bone(name)
		out.append(model.to_local(skel.global_transform * skel.get_bone_global_pose(bone).origin))
	return out


func _tick(model: Node3D) -> void:
	model.clips.update(DT)
	model.gait.update(DT)
	model.clips.apply()
	model.rig.update(DT)


func _fail(line: String) -> void:
	failures.append(line)
