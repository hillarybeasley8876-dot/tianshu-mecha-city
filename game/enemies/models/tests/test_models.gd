extends Node
## monster-assets: every shipped monster model, checked against the brief's "Done when".
##
##   tools/godot.sh test res://enemies/models/tests/test_models.gd
##
## Per type: the size is within 5 % of the brief, every required action plays and returns its real
## length, the sockets exist (mouth/muzzle, claws, core, at least one weak point), the hit-flash
## instance parameter actually changes, and hit_pause freezes playback.

const TYPES: Array[StringName] = [&"ripper", &"mantis", &"spitter", &"harrier", &"juggernaut",
		&"titan", &"titan_skyline"]
## Clips every type must have (briefs/monster-assets.md "Animation"; the titan extras are in TITAN).
const REQUIRED: Dictionary = {
	&"ripper": [&"idle", &"walk", &"run", &"scuttle", &"leap", &"bite", &"hit", &"death"],
	&"mantis": [&"idle", &"walk", &"run", &"slash_1", &"slash_2", &"slash_3", &"grab",
			&"sidestep_l", &"sidestep_r", &"threat", &"hit", &"stagger", &"death"],
	&"spitter": [&"idle", &"walk", &"scuttle", &"fire", &"hit", &"death"],
	&"harrier": [&"fly", &"glide", &"dive", &"strafe", &"hit", &"death"],
	&"juggernaut": [&"idle", &"walk", &"charge_run", &"charge", &"ground_slam", &"swipe",
			&"roar", &"hit", &"stagger", &"death"],
	&"titan": [&"idle", &"walk", &"roar", &"stomp", &"swipe", &"beam_breath", &"summon", &"hit",
			&"stagger", &"death", &"tail_sweep", &"climb_over", &"phase_roar", &"core_break",
			&"death_fall"],
	&"titan_skyline": [&"idle", &"walk", &"roar"],
}
## Every action id `game/enemies/**` can ask a type for (lead r3): the attack tables in
## ripper/mantis/spitter/harrier/juggernaut.gd, the shared `stagger` and `death` in enemy_base.gd,
## and the boss ids in brood_titan.gd / boss_director.gd / skyline_walker.gd. Each must resolve to
## a clip the type really has — an unresolved id plays no animation at all.
const ASKED: Dictionary = {
	&"ripper": [&"attack_1", &"leap", &"stagger", &"death"],
	&"mantis": [&"attack_1", &"attack_2", &"attack_3", &"grab", &"sidestep", &"stagger", &"death"],
	&"spitter": [&"lob", &"chaff", &"stagger", &"death"],
	&"harrier": [&"strafe", &"dive", &"stagger", &"death"],
	&"juggernaut": [&"charge", &"slam", &"attack_1", &"stagger", &"death"],
	&"titan": [&"core_break", &"phase_roar", &"roar", &"death_fall", &"climb_over", &"stagger",
			&"death"],
	&"titan_skyline": [&"roar", &"climb_over"],
}
## The ground speed `game/enemies/types.gd` drives each type at; the model has to carry it.
const GAME_SPEED: Dictionary = {
	&"ripper": 30.0, &"mantis": 24.0, &"spitter": 18.0, &"harrier": 55.0, &"juggernaut": 20.0,
	&"titan": 14.0, &"titan_skyline": 14.0,
}
## Residual foot slide allowed at that speed (lead r3): 15 %, and 25 % for the swarmer.
const SLIDE_TOLERANCE: Dictionary = {&"ripper": 0.25}
const SLIDE_DEFAULT := 0.15
## `brain.gd` patrols at this fraction of the move speed, so a gait has to be clean there too.
const PATROL_FRACTION := 0.35
const SOCKETS: Array[StringName] = [&"mouth", &"muzzle", &"core", &"chest", &"back"]
const SIZE_TOLERANCE := 0.05

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	for type_name in TYPES:
		await _check_type(type_name)
	await _check_hive()
	await _check_swarm_cost()
	print("TEST %d checks, %d failures" % [_checks, _failures])
	if _failures > 0:
		print("FAIL")
		get_tree().quit(1)
	else:
		print("PASS")
		get_tree().quit(0)


func _check(label: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL %s: %s" % [label, detail])


func _load(type_name: StringName) -> MonsterModel:
	var path := "res://enemies/models/%s/%s_model.tscn" % [type_name, type_name]
	var packed := load(path) as PackedScene
	if packed == null:
		_check(String(type_name), false, "cannot load " + path)
		return null
	var model := packed.instantiate() as MonsterModel
	if model == null:
		_check(String(type_name), false, path + " root is not a MonsterModel")
		return null
	add_child(model)
	return model


func _check_type(type_name: StringName) -> void:
	var model := _load(type_name)
	if model == null:
		return
	var label := String(type_name)
	await get_tree().process_frame

	# size within 5 % of the brief
	var target := model.target_size()
	var measured := model.measured_size()
	var axis := String((model.rig.get("size", {}) as Dictionary).get("axis", "height"))
	_check(label, target > 0.0, "no target size in the rig data")
	_check(label, target > 0.0 and absf(measured - target) <= target * SIZE_TOLERANCE,
			"%s %.2f m against a target of %.2f m" % [axis, measured, target])

	# every required action plays and reports its real length
	for action: StringName in REQUIRED[type_name]:
		var length := model.play_action(action)
		# Tripo's ambient idles run ~15 s; the bound only has to catch a zero or a runaway length
		_check(label, length > 0.05 and length < 20.0,
				"action '%s' returned %.2f s" % [action, length])
		_check(label, model.animation != null and model.animation.is_playing(),
				"action '%s' did not start playback" % action)
		var declared := float((model.rig.get("clips", {}) as Dictionary)
				.get(String(action), {}).get("length", -1.0))
		_check(label, declared > 0.0 and absf(length - declared) < 0.02,
				"action '%s' is %.2f s but the rig data says %.2f s" % [action, length, declared])

	# every id the enemies unit can ask for resolves to a clip this type really has (lead r3)
	var actions := model.rig.get("actions", {}) as Dictionary
	var asked_length := 0.0
	for asked: StringName in ASKED[type_name]:
		var clip := String(actions.get(String(asked), ""))
		_check(label, clip != "", "action id '%s' is not in the rig's action table" % asked)
		_check(label, model.rig.get("clips", {}).has(clip),
				"action id '%s' maps to '%s', which is not a clip" % [asked, clip])
		var played := model.play_action(asked)
		_check(label, played > 0.05,
				"action id '%s' played nothing (%.2f s)" % [asked, played])
		asked_length = maxf(asked_length, played)
	# an id nothing maps to must answer with the fallback length, not a script error
	_check(label, is_equal_approx(model.play_action(&"no_such_action"), MonsterModel.MISSING_ACTION),
			"an unknown action did not return MISSING_ACTION")
	# an action owns the player for its length (lead audit 1), so wait the last one out before
	# the locomotion checks below ask for the player back
	await get_tree().create_timer(asked_length + 0.05).timeout

	# locomotion states drive a looping clip
	for state: StringName in [&"idle", &"walk", &"run"]:
		model.set_locomotion(state, 8.0)
		_check(label, model.animation != null and model.animation.is_playing(),
				"set_locomotion(%s) left the model still" % state)

	_check_gait(label, model, type_name)
	_check_stride(label, model)
	await _check_one_shot_hold(label, model)

	# sockets
	for socket_name in SOCKETS:
		var node := model.socket(socket_name)
		_check(label, node != null and node != model.visual,
				"socket '%s' is missing" % socket_name)
	_check(label, not model.weak_points().is_empty(), "no weak_* sockets")
	for claw: StringName in [&"claw_l", &"claw_r"]:
		_check(label, model.socket(claw) != model.visual, "socket '%s' is missing" % claw)

	# hit flash reaches the shader as an instance parameter
	model.set_hit_flash(0.0)
	var before := _flash_of(model)
	model.set_hit_flash(1.0)
	var after := _flash_of(model)
	_check(label, is_equal_approx(before, 0.0) and after > 0.5,
			"hit flash instance parameter went %.2f -> %.2f" % [before, after])

	# hit_pause freezes the model's own animation
	model.set_locomotion(&"walk", 8.0)
	model.hit_pause(0.25)
	_check(label, model.animation != null and is_zero_approx(model.animation.speed_scale),
			"hit_pause did not stop playback")
	await get_tree().create_timer(0.4).timeout
	_check(label, model.animation != null and model.animation.speed_scale > 0.0,
			"playback did not resume after hit_pause")

	# telegraph and stagger go through the same instance parameters
	model.set_telegraph(EnemyAttack.UNBLOCKABLE, 1.0)
	_check(label, _param_of(model, &"tell") > 0.5, "telegraph did not reach the shader")
	model.set_stagger(true)
	_check(label, not is_zero_approx(model.visual.rotation_degrees.z),
			"set_stagger did not change the pose")
	_check_look(label, model)
	model.queue_free()


## The look pass (lead look r1): the rig carries a measured grade and the material really uses it.
## Without this a rebuilt texture silently puts the monsters back to brown mid-tones.
func _check_look(label: String, model: MonsterModel) -> void:
	var look := model.rig.get("look", {}) as Dictionary
	_check(label, not look.is_empty(), "no 'look' block in the rig data")
	if look.is_empty():
		return
	var gain := float(look.get("albedo_gain", 0.0))
	_check(label, gain >= 0.15 and gain <= 0.90,
			"albedo_gain %.3f is outside [0.15, 0.90]" % gain)
	_check(label, float(look.get("metallic_cap", 1.0)) <= 0.2,
			"metallic_cap %.2f — the chitin reflects the dusk sky again" % float(look.get("metallic_cap", 1.0)))
	_check(label, float(look.get("roughness_floor", 0.0)) >= 0.3,
			"roughness_floor %.2f is too glossy" % float(look.get("roughness_floor", 0.0)))
	_check(label, float(look.get("rim_gain", 0.0)) > 0.0, "no rim gain")
	var material := _material_of(model)
	if material == null:
		_check(label, false, "no ShaderMaterial on the model")
		return
	_check(label, is_equal_approx(float(material.get_shader_parameter(&"albedo_gain")), gain),
			"the shader's albedo_gain is %.3f, the rig says %.3f"
			% [float(material.get_shader_parameter(&"albedo_gain")), gain])
	_check(label, is_equal_approx(float(material.get_shader_parameter(&"emission_energy")),
					float(look.get("emission_energy", 0.0))),
			"the shader's emission_energy does not match the rig")


func _material_of(model: MonsterModel) -> ShaderMaterial:
	for mesh in model.meshes:
		if mesh.material_override is ShaderMaterial:
			return mesh.material_override as ShaderMaterial
	return null


func _flash_of(model: MonsterModel) -> float:
	return _param_of(model, &"hit_flash")


## The gait ladder (lead r3): a slow body keeps the Tripo loop, a body at the gameplay speed gets the
## authored fast gait, and neither slides past the bar. The ladder is what makes that work without the
## enemies unit changing state, so the check drives `walk` at both ends of the range.
func _check_gait(label: String, model: MonsterModel, type_name: StringName) -> void:
	var ladder := model.rig.get("gait", {}) as Dictionary
	_check(label, not ladder.is_empty(), "no gait ladder in the rig data")
	var speed := float(GAME_SPEED[type_name])
	var ceiling := float(model.rig.get("speed_scale_max", MonsterModel.MAX_SPEED_SCALE))
	_check(label, ceiling >= MonsterModel.MAX_SPEED_SCALE
					and ceiling <= MonsterModel.MAX_SPEED_SCALE_LIMIT,
			"speed_scale_max %.2f is outside [%.1f, %.1f]"
			% [ceiling, MonsterModel.MAX_SPEED_SCALE, MonsterModel.MAX_SPEED_SCALE_LIMIT])
	for state: String in ladder:
		var rungs := ladder[state] as Array
		_check(label, not rungs.is_empty(), "gait state '%s' has no rungs" % state)
		for rung: Variant in rungs:
			var entry := rung as Dictionary
			var clip := String(entry["clip"])
			_check(label, (model.rig.get("clips", {}) as Dictionary).has(clip),
					"gait state '%s' names clip '%s', which the rig does not have" % [state, clip])
			# the rung's own clean maximum must be what the build says it is
			var stride := float(entry.get("stride", 0.0))
			var want := stride * ceiling / (1.0 - float(SLIDE_TOLERANCE.get(type_name,
					SLIDE_DEFAULT))) if stride > 0.1 else 1.0e9
			_check(label, absf(float(entry["clean_max"]) - want) < 0.05,
					"rung '%s' claims clean up to %.1f m/s, the numbers give %.1f"
					% [clip, float(entry["clean_max"]), want])
		if state != "run":
			continue
		# the top rung is what carries the gameplay speed, and it must stay inside the bar — at the
		# move speed and at the 0.35x patrol speed brain.gd uses for `walk`
		var top := rungs[rungs.size() - 1] as Dictionary
		var top_stride := float(top.get("stride", 0.0))
		if top_stride <= 0.1:
			continue        # nothing is planted: a flyer in the air
		var floor_scale := float(model.rig.get("speed_scale_min", MonsterModel.MIN_SPEED_SCALE))
		_check(label, floor_scale >= MonsterModel.MIN_SPEED_SCALE_LIMIT and floor_scale <= ceiling,
				"speed_scale_min %.2f is outside [%.2f, %.2f]"
				% [floor_scale, MonsterModel.MIN_SPEED_SCALE_LIMIT, ceiling])
		for driven: float in [speed, speed * PATROL_FRACTION]:
			var picked := _rung_for(rungs, driven)
			var stride := float(picked.get("stride", 0.0))
			if stride <= 0.1:
				continue
			var played := stride * clampf(driven / stride, floor_scale, ceiling)
			var slide := absf(driven - played) / driven
			_check(label, slide <= float(SLIDE_TOLERANCE.get(type_name, SLIDE_DEFAULT)),
					"at %.1f m/s the '%s' gait slides %.0f %% (stride %.2f m/s, %.2f-%.2fx)"
					% [driven, String(picked["clip"]), slide * 100.0, stride, floor_scale, ceiling])
		model.set_locomotion(StringName(state), speed)
		_check(label, model.animation.current_animation.contains(String(top["clip"])),
				"at %.0f m/s the model plays '%s', not the fast gait '%s'"
				% [speed, model.animation.current_animation, String(top["clip"])])


## The rung the model picks at `speed`, mirroring MonsterModel: of the rungs that stay clean, the one
## whose authored stride is nearest the speed the body is moving.
func _rung_for(rungs: Array, speed: float) -> Dictionary:
	var best: Dictionary = rungs[rungs.size() - 1]
	var best_score := INF
	for rung: Variant in rungs:
		var entry := rung as Dictionary
		if speed > float(entry.get("clean_max", 0.0)):
			continue
		var stride := float(entry.get("stride", 0.0))
		var score := 0.0 if stride <= 0.1 else (stride if speed <= 0.5
				else absf(log(speed / stride)))
		if score < best_score:
			best_score = score
			best = entry
	return best


## Stride contract (lead r1): every gait clip declares the ground speed its legs were authored for,
## and driving the body at exactly that speed plays that clip at 1x — which is also the ladder's own
## contract, since a rung's stride is by definition the nearest one to itself. The fastest rung of
## each state is then driven far past its stride to prove the ceiling clamps.
func _check_stride(label: String, model: MonsterModel) -> void:
	var strides := model.rig.get("stride_speed", {}) as Dictionary
	var gait := model.rig.get("gait", {}) as Dictionary
	var ceiling := float(model.rig.get("speed_scale_max", MonsterModel.MAX_SPEED_SCALE))
	for state: String in gait:
		var rungs := gait[state] as Array
		for rung: Variant in rungs:
			var clip_id := String((rung as Dictionary)["clip"])
			_check(label, strides.has(clip_id), "gait clip '%s' has no stride_speed" % clip_id)
			if clip_id == "idle":
				continue
			var stride := float(strides.get(clip_id, 0.0))
			if stride <= 0.0:
				# a flight clip: nothing is planted, so it plays at its authored rate
				model.set_locomotion(StringName(state), 12.0)
				_check(label, is_equal_approx(model.animation.speed_scale, 1.0),
						"clip '%s' has no stride but is scaled to %.2f"
						% [clip_id, model.animation.speed_scale])
				continue
			model.set_locomotion(StringName(state), stride)
			_check(label, model.animation.current_animation.contains(clip_id),
					"at %.2f m/s the '%s' ladder plays '%s' instead of '%s'"
					% [stride, state, model.animation.current_animation, clip_id])
			_check(label, absf(model.animation.speed_scale - 1.0) < 0.01,
					"clip '%s' at its own stride %.2f m/s plays at %.2fx"
					% [clip_id, stride, model.animation.speed_scale])
		var top := rungs[rungs.size() - 1] as Dictionary
		var top_stride := float(top.get("stride", 0.0))
		if top_stride <= 0.1:
			continue
		model.set_locomotion(StringName(state), top_stride * 8.0)
		_check(label, is_equal_approx(model.animation.speed_scale, ceiling),
				"state '%s' far above its fastest stride should clamp to %.2fx, got %.2f"
				% [state, ceiling, model.animation.speed_scale])


## Lead audit 1: EnemyBase re-asserts a locomotion state every physics tick, so an attack started by
## play_action was cross-faded back to idle one tick later — monsters wound up and struck in their
## idle loop. The one-shot now owns the player for its own length.
func _check_one_shot_hold(label: String, model: MonsterModel) -> void:
	model.set_locomotion(&"idle", 0.0)
	var attack: StringName = ASKED[model.body_type][0]
	var length := model.play_action(attack)
	var playing := model.animation.current_animation
	for tick in 6:
		model.set_locomotion(&"idle", 0.0)        # what attack_windup does every tick
		await get_tree().physics_frame
	_check(label, model.animation.current_animation == playing,
			"set_locomotion(&\"idle\") stole the '%s' attack after %d ticks (now '%s')"
			% [attack, 6, model.animation.current_animation])
	await get_tree().create_timer(length + 0.1).timeout
	for tick in 2:
		model.set_locomotion(&"walk", 6.0)
		await get_tree().physics_frame
	_check(label, model.animation.current_animation != playing,
			"the '%s' attack never handed the player back to locomotion" % attack)


func _param_of(model: MonsterModel, parameter: StringName) -> float:
	for mesh in model.meshes:
		var value: Variant = mesh.get_instance_shader_parameter(parameter)
		if value != null:
			return float(value)
	return -1.0


func _check_hive() -> void:
	var packed := load("res://enemies/models/hive/hive_model.tscn") as PackedScene
	var hive := packed.instantiate() as HiveModel if packed != null else null
	if hive == null:
		_check("hive", false, "cannot load hive_model.tscn")
		return
	add_child(hive)
	await get_tree().process_frame
	_check("hive", absf(hive.measured_size() - hive.target_size()) <= hive.target_size() * SIZE_TOLERANCE,
			"height %.2f m against a target of %.2f m" % [hive.measured_size(), hive.target_size()])
	_check("hive", hive.collision_mesh() != null, "no convex collision proxy")
	for state: StringName in [&"intact", &"cracked", &"destroyed"]:
		hive.set_state(state)
		await get_tree().process_frame
		_check("hive", hive.state() == state, "set_state(%s) did not take" % state)
		var visible_count := 0
		for key: StringName in hive.meshes:
			if key != &"collision" and (hive.meshes[key] as MeshInstance3D).visible:
				visible_count += 1
		_check("hive", visible_count == 1, "state %s shows %d meshes" % [state, visible_count])
	_check("hive", not hive.weak_points().is_empty(), "no weak_* sockets on the hive")
	_check("hive", hive.socket(&"core") != hive, "no core socket")
	# the four glowing bulbs flow places its pods on (lead r3); `weak_points()` is how flow finds
	# them, so they have to be in that list and not only in the socket table
	var pods: Array[Node3D] = []
	for node in hive.weak_points():
		if String(node.name).begins_with("pod_"):
			pods.append(node)
	_check("hive", pods.size() == 4, "%d pod_* sockets, expected 4" % pods.size())
	for i in 4:
		var socket := hive.socket(StringName("pod_%d" % i))
		_check("hive", socket != hive and String(socket.name) == "pod_%d" % i,
				"socket pod_%d is missing" % i)
		_check("hive", socket.position.y >= hive.target_size() * 0.15,
				"pod_%d sits %.1f m up a %.0f m spire — not a targetable weak point"
				% [i, socket.position.y, hive.target_size()])
	# the pods' own glow (lead look r1): the mask reaches the shader and one bulb can go out
	var hive_material: ShaderMaterial = null
	for key: StringName in hive.meshes:
		if hive.meshes[key].material_override is ShaderMaterial:
			hive_material = hive.meshes[key].material_override as ShaderMaterial
			break
	_check("hive", hive_material != null, "no ShaderMaterial on the hive")
	if hive_material != null:
		_check("hive", hive_material.get_shader_parameter(&"pod_mask_tex") is Texture2D,
				"the hive's pod mask never reached the shader")
		_check("hive", float(hive_material.get_shader_parameter(&"emission_energy")) <= 1.5,
				"emission_energy %.2f — the trunk blooms into a lime blob again"
				% float(hive_material.get_shader_parameter(&"emission_energy")))
	_check("hive", hive.pods_alive() == 4, "a fresh hive starts with %d live pods" % hive.pods_alive())
	hive.set_pod_alive(2, false)
	var alive := _pod_param(hive)
	_check("hive", is_zero_approx(alive.z) and is_equal_approx(alive.x, 1.0),
			"set_pod_alive(2, false) left pod_alive at %s" % alive)
	_check("hive", hive.pods_alive() == 3, "pods_alive() says %d after one burst" % hive.pods_alive())
	hive.set_pod_alive(2, true)
	_check("hive", hive.pods_alive() == 4, "a pod did not come back on")
	hive.queue_free()


## The `pod_alive` instance uniform as the shader sees it, or all-zero if nothing carries it. The
## collision proxy is skipped: `HiveModel._push` never touches it, so it would answer with the
## shader's own default.
func _pod_param(hive: HiveModel) -> Vector4:
	for key: StringName in hive.meshes:
		if key == &"collision":
			continue
		var value: Variant = hive.meshes[key].get_instance_shader_parameter(&"pod_alive")
		if value is Vector4:
			return value as Vector4
	return Vector4.ZERO


## The lead asked for the trash-mob cost: 40 rippers on screen must stay inside the frame budget,
## so the test measures the per-model draw calls and skinned vertex count it would pay.
func _check_swarm_cost() -> void:
	for type_name: StringName in [&"ripper", &"mantis"]:
		var model := _load(type_name)
		if model == null:
			continue
		await get_tree().process_frame
		var verts := 0
		var surfaces := 0
		for mesh in model.meshes:
			if mesh.mesh == null:
				continue
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				if arrays.is_empty():
					continue
				surfaces += 1
				verts += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		print("COST %-12s meshes %d  surfaces %d  skinned verts %d  (x40 = %d)"
				% [type_name, model.meshes.size(), surfaces, verts, verts * 40])
		_check(String(type_name), surfaces <= 4,
				"%d draw calls per copy is too many for a trash mob" % surfaces)
		model.queue_free()


