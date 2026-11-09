extends Node
## hero-v3 gate for lead r4 item 2: the game's MOVE STATES, driven the way the game drives them.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_states.gd
##
## `probe_states.gd` walked every one of these at the reported speed, which is how a 150 m/s dash ended
## up taking 8 steps a second with the feet 13.75 m from their IK targets. For each state, at the real
## speed, this asserts:
##   * no step at all while the ground speed is above the gait's own step limit (measured, not typed:
##     `Hero3Timing.step_limit()`)
##   * the worst ankle miss -- the IK target against the ankle BONE -- is <= 0.15 m
##   * on the ground, the lowest skinned foot or toe vertex is within 0.15 m of where it sits at rest
##
## Skating feet are allowed to slide. That is what a skate is.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 60.0
const MISS_GATE := 0.15
const SOLE_GATE := 0.15
const VSTRIDE := 4
const SAMPLE_EVERY := 3
## label, state, speed from, speed to, seconds, stick, on the ground?
const RUNS: Array = [
	["walk ref", &"walk", 9.0, 9.0, 1.5, Vector2(0.0, -1.0), true],
	["dash_f", &"dash_f", 150.0, 42.0, 0.25, Vector2(0.0, -1.0), true],
	["dash_b", &"dash_b", 150.0, 42.0, 0.25, Vector2(0.0, 1.0), true],
	["dash_l", &"dash_l", 150.0, 42.0, 0.25, Vector2(-1.0, 0.0), true],
	["coast after dash", &"coast", 42.0, 9.0, 1.2, Vector2(0.0, -1.0), true],
	["slide (ground boost)", &"slide", 42.0, 42.0, 1.5, Vector2(0.0, -1.0), true],
	["lunge", &"lunge", 60.0, 60.0, 0.5, Vector2(0.0, -1.0), true],
	["locked", &"locked", 9.0, 0.0, 0.6, Vector2.ZERO, true],
	["glide (air boost)", &"glide", 42.0, 42.0, 1.5, Vector2(0.0, -1.0), false],
	["assault", &"assault", 84.0, 84.0, 1.5, Vector2(0.0, -1.0), false],
	["fly ref", &"fly", 42.0, 42.0, 1.5, Vector2(0.0, -1.0), false],
	["hover ref", &"hover", 0.0, 0.0, 1.5, Vector2.ZERO, false],
]

var failures: Array[String] = []
var _verts: Array = []
var _rest_sole: float = 0.0


func _ready() -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	var skel: Skeleton3D = model.skeleton
	_collect(model, skel)
	_rest_sole = _sole(skel)
	print("STATES step limit %.1f m/s | rest sole %.3f m above the ground | %d foot/toe verts"
			% [model.gait.timing.step_limit(), _rest_sole, _verts.size()])
	for spec: Array in RUNS:
		await _run(model, spec)
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for line in failures:
			print("FAIL %s" % line)
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


## One state at its real speed, moved across the world exactly as `probe_states.gd` moves it.
func _run(model: Node3D, spec: Array) -> void:
	var gait: Hero3Gait = model.gait
	var clips: Hero3ClipPlayer = model.clips
	var skel: Skeleton3D = model.skeleton
	var feet := [skel.find_bone("R_Foot"), skel.find_bone("L_Foot")]
	var ground := bool(spec[6])
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	gait.reset()
	for i in 30:
		_tick(gait, clips)
	var ticks := int(float(spec[4]) / DT)
	var stick: Vector2 = spec[5]
	var dir := Vector3(stick.x, 0.0, stick.y).normalized()
	var steps_over := 0
	var steps_under := 0
	var miss := 0.0
	var sole := _rest_sole
	var skate_slide := 0.0
	var plant_slide := 0.0
	var first := [Vector3.INF, Vector3.INF]
	var was := [false, false]
	var limit := gait.timing.step_limit()
	var was_over := false
	for t in ticks:
		var u := float(t) / float(maxi(ticks - 1, 1))
		var speed := lerpf(float(spec[2]), float(spec[3]), u)
		model.set_locomotion(spec[1], speed, stick)
		if stick != Vector2.ZERO:
			model.position += dir * speed * DT
		_tick(gait, clips)
		# crossing the step limit hands the feet from the skate to the planner (or back), so the
		# "how far has this foot moved while planted" clock restarts there
		if (speed > limit) != was_over:
			was_over = speed > limit
			for i in 2:
				first[i] = Vector3.INF
		var targets: Array[Vector3] = gait.ankle_targets()
		for i in 2:
			var ankle := skel.global_transform * skel.get_bone_global_pose(feet[i]).origin
			miss = maxf(miss, ankle.distance_to(targets[i]))
			var stepping := not gait.is_planted(i)
			if stepping and not was[i]:
				if speed > limit:
					steps_over += 1
				else:
					steps_under += 1
			# A foot that is not stepping still MOVES: a skate slides it with the body, and the gait's
			# heel-to-toe roll swings the ankle 0.8-1.1 m about the contact pivot. Splitting the two
			# is the only way to tell a skate from a plant, which is why the lead's raw
			# "planted-ankle slide" reads 20 m on a coast that is behaving correctly.
			if not stepping:
				if first[i] == Vector3.INF:
					first[i] = ankle
				var moved := ankle.distance_to(first[i])
				if speed > limit:
					skate_slide = maxf(skate_slide, moved)
				else:
					plant_slide = maxf(plant_slide, moved)
			else:
				first[i] = Vector3.INF
			was[i] = stepping
		if ground and t % SAMPLE_EVERY == 0:
			sole = minf(sole, _sole(skel))
	print("STATES %-20s %5.1f->%5.1f m/s | steps over/under the limit %d/%d | ankle miss %.3f m | sole %.3f m | skate slide %.1f m, plant slide %.2f m | clip '%s'"
			% [spec[0], float(spec[2]), float(spec[3]), steps_over, steps_under, miss, sole,
			skate_slide, plant_slide, String(clips.current())])
	if steps_over > 0:
		_fail("%s took %d steps above the %.1f m/s step limit" % [spec[0], steps_over, limit])
	if miss > MISS_GATE:
		_fail("%s missed its IK target by %.3f m, gate %.2f" % [spec[0], miss, MISS_GATE])
	if ground and absf(sole - _rest_sole) > SOLE_GATE:
		_fail("%s left the lower sole at %.3f m, rest is %.3f m, gate %.2f"
				% [spec[0], sole, _rest_sole, SOLE_GATE])
	await get_tree().process_frame


func _tick(gait: Hero3Gait, clips: Hero3ClipPlayer) -> void:
	gait.update(DT)
	clips.update(DT)
	clips.apply()


## The lowest skinned foot or toe vertex, in metres above the ground plane. Only the Foot and Toe
## pieces are collected: nothing else on this rig can reach the floor.
func _sole(skel: Skeleton3D) -> float:
	var xf := skel.global_transform
	var cache := {}
	var low := INF
	for row in _verts:
		var mi: MeshInstance3D = row[3]
		var binds: PackedInt32Array = row[1]
		var wts: PackedFloat32Array = row[2]
		var p := Vector3.ZERO
		for j in wts.size():
			var key := Vector2i(mi.get_instance_id() % 100000, binds[j * 2 + 1])
			if not cache.has(key):
				cache[key] = skel.get_bone_global_pose(binds[j * 2]) \
						* mi.skin.get_bind_pose(binds[j * 2 + 1])
			p += (cache[key] as Transform3D) * (row[0] as Vector3) * wts[j]
		low = minf(low, (xf * p).y)
	return low - skel.global_position.y


func _collect(model: Node3D, skel: Skeleton3D) -> void:
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		var bind_bone := PackedInt32Array()
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			if bone < 0:
				bone = skel.find_bone(String(mi.skin.get_bind_name(b)))
			bind_bone.append(bone)
		for s in mi.mesh.get_surface_count():
			_collect_surface(mi, s, bind_bone, skel)


func _collect_surface(mi: MeshInstance3D, surface: int, bind_bone: PackedInt32Array,
		skel: Skeleton3D) -> void:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bones == null or verts.is_empty():
		return
	var per := int(bones.size() / verts.size())
	for i in range(0, verts.size(), VSTRIDE):
		var top := -1
		var best := -1.0
		var binds := PackedInt32Array()
		var wts := PackedFloat32Array()
		for j in per:
			var w := weights[i * per + j]
			if w <= 0.0:
				continue
			var b := int(bones[i * per + j])
			binds.append(bind_bone[b])
			binds.append(b)
			wts.append(w)
			if w > best:
				best = w
				top = bind_bone[b]
		if top < 0:
			continue
		var bone_name := skel.get_bone_name(top)
		if bone_name.ends_with("_Foot") or bone_name.ends_with("_Toe"):
			_verts.append([verts[i], binds, wts, mi])


func _fail(line: String) -> void:
	failures.append(line)
