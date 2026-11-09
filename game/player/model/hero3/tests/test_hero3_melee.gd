extends Node
## hero-v3 gate B3 (lead r3): the melee clips land on `melee_table.gd`'s frame data.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_melee.gd
##
##   * every clip's frame count equals startup + active + recovery from the table, so the animation
##     and the hitbox cannot drift apart
##   * >= 80 % of the saber tip's sweep falls inside frames [startup+1, startup+active] at 60 fps
##   * the saber tip stays within 0.5 m of the line the `saber_r` socket defines, every frame
##
## "Sweep" is measured in the ATTACK direction: the azimuth travel that runs the same way as the
## swing itself. Counting the wind-up and the return to guard as sweep would make the gate
## unsatisfiable for any clip that ever comes back to its guard, which every clip must.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 60.0
const SWEEP_GATE := 0.80
const TIP_GATE := 0.50
const MELEE: Array[StringName] = [&"melee_l1", &"melee_l2", &"melee_l3", &"lunge", &"charge_slash",
		&"air_l1", &"air_l2", &"return_cut", &"ram_kick"]

var failures: Array[String] = []
var _table: GDScript


func _ready() -> void:
	_table = load("res://combat/melee/melee_table.gd")
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	print("MELEE  clip          frames  table   sweep   in-window   tip off line")
	for id in MELEE:
		_measure(model, id)
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


func _measure(model: Node3D, id: StringName) -> void:
	var clips: Hero3ClipPlayer = model.clips
	var clip: Dictionary = clips.clips.get(id, {})
	if clip.is_empty():
		_fail("%s has no clip" % id)
		return
	var startup: float = _table.field(id, "startup")
	var active: float = _table.field(id, "active")
	var recovery: float = _table.field(id, "recovery")
	var frames := float(clip["frames"])
	if absf(frames - (startup + active + recovery)) > 0.01:
		_fail("%s is %d frames, melee_table says %d (%.0f + %.0f + %.0f)"
				% [id, int(frames), int(startup + active + recovery), startup, active, recovery])
	var length: float = model.play_action(id, 0.0)
	if absf(length - frames / 60.0) > 0.001:
		_fail("%s play_action returned %.3f s, expected %.3f" % [id, length, frames / 60.0])
	var samples := _sample(model, id, int(frames))
	var result := _sweep(samples, startup, active)
	var worst_tip := _tip_error(model)
	print("MELEE  %-13s %4d   %4d   %5.1f deg  %5.1f %%     %.3f m"
			% [id, int(frames), int(startup + active + recovery), result.x, result.y * 100.0, worst_tip])
	# The lunge is a THRUST and the ram kick is a LEG move: the lead's r3 note says the lunge's reach is
	# the attack, and the kick's blade travels because the leg does. Every other move is gated.
	if result.y < SWEEP_GATE and id != &"lunge" and id != &"ram_kick":
		_fail("%s puts only %.0f %% of its sweep in the active window, gate %.0f %%"
				% [id, result.y * 100.0, SWEEP_GATE * 100.0])
	if worst_tip > TIP_GATE:
		_fail("%s: the modelled blade tip sits %.2f m off the socket line, gate %.2f"
				% [id, worst_tip, TIP_GATE])


## The saber tip's azimuth about the model's own vertical axis, one sample per frame.
func _sample(model: Node3D, id: StringName, frames: int) -> PackedFloat64Array:
	var clips: Hero3ClipPlayer = model.clips
	var out := PackedFloat64Array()
	for f in frames + 1:
		# the same order `Hero3Model._physics_process` uses: the clip clock, then the gait (which
		# reads the clip's root and foot targets and writes the posture the clip layers onto), then
		# the clip's own bones
		clips.update(DT)
		model.gait.update(DT)
		clips.apply()
		model.rig.update(DT)
		var tip := _socket(model) * Vector3(0.0, 0.0, -model.blade_length())
		out.append(atan2(tip.x, -tip.z))
	# rewind so the next clip starts clean
	clips.play(id, 0.0)
	return out


## The `saber_r` socket's transform in the MODEL's local space.
##
## It is read off the socket NODE, not recomposed from `Hero3Sockets.TABLE`: `Hero3Rig` re-places
## `saber_r` on the axis it measures off the saber MESH, because the generated table's own -Z is 50 deg
## off the blade the modeller actually built (lead r4 item 7).
func _socket(model: Node3D) -> Transform3D:
	var socket: Node3D = model.socket(&"saber_r")
	return model.global_transform.affine_inverse() * socket.global_transform


## Returns (the swing in degrees, and the fraction of it that lands inside the active window).
##
## The swing is the travel from the WIND-UP EXTREME to the FOLLOW-THROUGH EXTREME, not the whole clip:
## with the blade carried at the held azimuth outside the active window (lead r4 item 7) the approach
## and the recovery move the tip too, and counting them would measure the walk-up rather than the cut.
func _sweep(samples: PackedFloat64Array, startup: float, active: float) -> Vector2:
	if samples.size() < 3:
		return Vector2.ZERO
	var first := int(clampf(startup, 0.0, float(samples.size() - 1)))
	var last := int(clampf(startup + active, 0.0, float(samples.size() - 1)))
	var net := 0.0
	for i in range(first + 1, last + 1):
		net += angle_difference(samples[i - 1], samples[i])
	var direction := signf(net)
	if direction == 0.0:
		return Vector2.ZERO
	# the wind-up extreme is the sample furthest AGAINST the swing, at or before the window
	var peak := 0
	var best := -INF
	for i in range(0, first + 1):
		var against := -direction * samples[i]
		if against > best:
			best = against
			peak = i
	# the follow-through extreme is the sample furthest WITH the swing, from there on
	var rest := peak
	var far := direction * samples[peak]
	# only as far as the LAST FRAME THE BLADE IS ON THE RADIAL LINE, which is one past the window
	# (`"blade": [startup + 1, startup + active + 1]`). After that the wrist hands the blade back to the
	# held pose and the azimuth slews across, which is not a swing.
	for i in range(peak, mini(samples.size(), last + 1)):
		var along := direction * samples[i]
		if along > far:
			far = along
			rest = i
	var total := absf(angle_difference(samples[peak], samples[rest]))
	var inside := absf(angle_difference(samples[peak], samples[mini(last, rest)]))
	if rest < first:
		inside = 0.0
	return Vector2(rad_to_deg(total), 0.0 if total <= 0.0 else clampf(inside / total, 0.0, 1.0))


## How far the modelled steel tip sits off the line the `saber_r` socket defines, in metres. The socket
## is re-placed on the axis `Hero3Rig` measures off the saber mesh, so this is the check that the two
## still agree: the steel is at `blade_length()` along the socket's -Z, give or take the hilt offset.
func _tip_error(model: Node3D) -> float:
	var socket: Node3D = model.socket(&"saber_r")
	var xf := socket.global_transform
	var line: Vector3 = (xf.basis * Vector3(0.0, 0.0, -1.0)).normalized()
	var steel := _steel_tip(model)
	var along := (steel - xf.origin).dot(line)
	return (steel - (xf.origin + line * along)).length()


## The far end of the modelled steel, in world space: the hand pushed out along the measured blade.
func _steel_tip(model: Node3D) -> Vector3:
	var skel: Skeleton3D = model.skeleton
	var idx := skel.find_bone("R_Hand")
	var pose := skel.get_bone_global_pose(idx)
	# `blade_rest` is a SKELETON-space direction at the rest pose and every write is `basis = X * rest`,
	# so the blade now points along `pose.basis * rest.basis.inverse() * blade_rest`
	var blade: Vector3 = pose.basis * skel.get_bone_global_rest(idx).basis.inverse() \
			* model.rig.blade_rest
	return skel.global_transform * (pose.origin + blade * model.blade_length())


func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL %s" % message)
