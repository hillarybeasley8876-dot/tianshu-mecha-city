extends Node
## hero-v3 gate for lead r4 item 7: the visible blade has to COVER the hitbox, and the sweep direction
## has to be measured rather than typed.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_reach.gd
##
##   * the visible 14 m tip (12 m of steel plus `MeleeTable`'s 2 m energy extension) reaches at least
##     0.8 x `reach` from the mech's vertical axis at mid-active, and at least 0.6 x `reach` across
##     the WHOLE active window
##   * no saber vertex goes below the floor in any clip
##   * it PRINTS the measured sweep direction per clip, so the per-move direction the lead adds to
##     `melee_table.gd` is generated from this and not typed by hand
##
## The blade points radially outward for the active window (`Hero3ClipPlayer._aim_blade`). Before that
## the wrist was authored and the blade swept TANGENTIALLY: the steel tip sat 7.0-9.4 m from the axis
## while the hitbox reaches 16-22 m, so everything from 11 to 20 m out was cut by thin air.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 60.0
const MID_GATE := 0.80
const WINDOW_GATE := 0.60
## The visible tip: `MeleeTable.BLADE_LENGTH`, which is the modelled steel plus the energy extension.
const VISIBLE := 14.0
const FLOOR_GATE := 0.05

var failures: Array[String] = []
var _table: GDScript
var _saber: MeshInstance3D
var _bind := PackedInt32Array()
var _worst_at := Vector3.ZERO
var _worst_bone := ""
var _sweep: Dictionary = {}


func _ready() -> void:
	_table = load("res://combat/melee/melee_table.gd")
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	var skel: Skeleton3D = model.skeleton
	_saber = model.rig.weapon(&"Hero3Saber") as MeshInstance3D
	if _saber == null or _saber.skin == null:
		print("FAIL no saber mesh")
		get_tree().quit(1)
		return
	for b in _saber.skin.get_bind_count():
		var bone := _saber.skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(String(_saber.skin.get_bind_name(b)))
		_bind.append(bone)
	print("REACH  clip            reach  mid-active   window min   sweep          buried")
	for id: StringName in _table.DATA:
		if not model.clips.has(id):
			continue
		var row: Dictionary = _table.DATA[id]
		await _clip(model, id, float(row["startup"]), float(row["active"]), float(row["reach"]))
	_print_sweep_table()
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for line in failures:
			print("FAIL %s" % line)
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


## lead r5 item 6: `MeleeTable.SWEEP` is GENERATED from this, never typed. +1 = the animated blade
## ends on the mech's right (a left-to-right cut), -1 = it ends on its left. Paste the block below
## straight into `combat/melee/melee_table.gd`.
func _print_sweep_table() -> void:
	var keys: Array = _sweep.keys()
	keys.sort()
	var rows: Array[String] = []
	for id: String in keys:
		rows.append("\t&\"%s\": %s," % [id, "1.0" if float(_sweep[id]) > 0.0 else "-1.0"])
	print("SWEEP  const SWEEP: Dictionary = {\n%s\n}" % "\n".join(rows))


## One melee clip: the tip's radius over the active window, the sweep direction, and the deepest
## saber vertex.
func _clip(model: Node3D, id: StringName, startup: float, active: float, reach: float) -> void:
	var gait: Hero3Gait = model.gait
	var clips: Hero3ClipPlayer = model.clips
	model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	gait.reset()
	model.stop_action()
	for i in 60:
		_tick(model)
	var frames := int(float(clips.clips[id]["frames"]))
	model.play_action(id, 0.06)
	var worst := INF
	var mid := 0.0
	var first_az := 0.0
	var last_az := 0.0
	var buried := 0.0
	var buried_at := Vector3.ZERO
	var buried_bone := ""
	var seen := 0
	for f in frames + 8:
		_tick(model)
		var tip := _tip(model)
		var radius := Vector2(tip.x, tip.z).length()
		var az := atan2(tip.x, -tip.z)
		if f >= int(startup) and f < int(startup + active):
			worst = minf(worst, radius)
			if seen == 0:
				first_az = az
			last_az = az
			seen += 1
			if f == int(startup + active * 0.5):
				mid = radius
		var low := _lowest(model)
		if low < buried:
			buried = low
			buried_at = _worst_at
			buried_bone = _worst_bone
	var sweep := rad_to_deg(angle_difference(first_az, last_az))
	var way := "right -> left" if sweep < 0.0 else "left -> right"
	_sweep[String(id)] = 1.0 if sweep > 0.0 else -1.0
	print("REACH  %-14s %5.1f  %6.2f m     %6.2f m     %+6.1f deg %-14s %.3f m"
			% [id, reach, mid, worst, sweep, way, buried])
	if mid < reach * MID_GATE:
		_fail("%s: the visible tip only reaches %.2f m at mid-active, gate %.2f (0.8 x %.1f)"
				% [id, mid, reach * MID_GATE, reach])
	if worst < reach * WINDOW_GATE:
		_fail("%s: the visible tip drops to %.2f m inside the active window, gate %.2f"
				% [id, worst, reach * WINDOW_GATE])
	if buried < -FLOOR_GATE:
		_fail("%s: a saber vertex sits %.3f m below the floor at %s on %s"
				% [id, -buried, buried_at, buried_bone])
	await get_tree().process_frame


func _tick(model: Node3D) -> void:
	model.clips.update(DT)
	model.gait.update(DT)
	model.clips.apply()
	model.rig.update(DT)


## The visible tip: the `saber_r` socket pushed out to `VISIBLE`, in the model's own space.
func _tip(model: Node3D) -> Vector3:
	var socket: Node3D = model.socket(&"saber_r")
	var xf := socket.global_transform
	var local := xf * Vector3(0.0, 0.0, -12.0)
	return model.to_local(xf.origin + (local - xf.origin).normalized() * VISIBLE)


## The lowest skinned saber vertex, in metres above the ground plane.
func _lowest(model: Node3D) -> float:
	var skel: Skeleton3D = model.skeleton
	var poses := {}
	var low := INF
	for s in _saber.mesh.get_surface_count():
		var arrays := _saber.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or verts.is_empty():
			continue
		var per := int(bones.size() / verts.size())
		for i in range(0, verts.size(), 3):
			var top := -1
			var w := -1.0
			for j in per:
				if weights[i * per + j] > w:
					w = weights[i * per + j]
					top = int(bones[i * per + j])
			if top < 0:
				continue
			if not poses.has(top):
				poses[top] = skel.get_bone_global_pose(_bind[top]) \
						* _saber.skin.get_bind_pose(top)
			var world: Vector3 = skel.global_transform * ((poses[top] as Transform3D) * verts[i])
			if world.y < low:
				low = world.y
				_worst_at = world
				_worst_bone = skel.get_bone_name(_bind[top])
	return low - model.global_position.y


func _fail(line: String) -> void:
	failures.append(line)
