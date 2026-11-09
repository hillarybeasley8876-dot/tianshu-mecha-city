class_name MechBuild
extends RefCounted
## Builds the PlayerMech body, its model and its components (CONTRACTS §1: the loader is the mech's).
## Split out of `player_mech.gd` so that file stays the physics frame and the public API.
##
## Every function here is called once, from `PlayerMech._ready` or its first physics frame.

const HERO_MODEL := "res://player/model/hero3/hero3_model.tscn"
const PLACEHOLDER_MODEL := "res://player/model/placeholder/placeholder_model.tscn"
const TUNING_PATH := "res://player/mech/mech_tuning.tres"
const DEBUG_CAMERA := preload("res://player/mech/debug_camera.gd")


static func load_tuning() -> MechTuning:
	var t := load(TUNING_PATH) as MechTuning
	if t == null:
		push_warning("PlayerMech: %s missing, using script defaults" % TUNING_PATH)
		return MechTuning.new()
	return t


static func build_body(p: PlayerMech, t: MechTuning) -> void:
	p.collision_layer = Layers.PLAYER
	p.collision_mask = Layers.MASK_CHARACTER
	p.floor_max_angle = deg_to_rad(t.floor_max_angle_deg)
	p.floor_snap_length = t.floor_snap
	p.floor_stop_on_slope = true
	p.safe_margin = 0.01
	# lead r8 item 2 (status/enemies.md Request 19): the engine default for `platform_floor_layers` is
	# EVERY layer, so a monster walking under the mech was a kinematic platform — `get_platform_velocity`
	# handed the hero the monster's own motion and a spawning one flung it. Only world and static
	# scenery carries the mech now. Enemies stay solid (MASK_CHARACTER still collides with them), they
	# just never carry, and a deck or a moving world platform is untouched.
	p.platform_floor_layers = Layers.WORLD | Layers.PROPS
	var shape := CollisionShape3D.new()
	shape.name = "Body"
	var capsule := CapsuleShape3D.new()
	capsule.radius = t.capsule_radius
	capsule.height = maxf(t.capsule_height, t.capsule_radius * 2.0)
	shape.shape = capsule
	p.add_child(shape)


## The world's `PlayerSpawn` marker (CONTRACTS §7) lifted by half the capsule, else above the origin.
static func spawn_fallback(world: Node, t: MechTuning) -> Transform3D:
	var half := t.capsule_height * 0.5
	var xf := Transform3D(Basis.IDENTITY, Vector3(0.0, half, 0.0))
	if world != null:
		var m := world.find_child("PlayerSpawn", true, false) as Node3D
		if m != null:
			xf = m.global_transform
			xf.origin.y += half
	return xf


static func instance_model(p: PlayerMech) -> Node3D:
	var path := HERO_MODEL if ResourceLoader.exists(HERO_MODEL) else PLACEHOLDER_MODEL
	if not ResourceLoader.exists(path):
		push_error("PlayerMech: no model scene at %s" % path)
		return null
	var packed := load(path) as PackedScene
	var node := packed.instantiate() as Node3D
	if node == null:
		push_error("PlayerMech: %s is not a Node3D scene" % path)
		return null
	node.name = "Model"
	# CONTRACTS §5: the model origin is BETWEEN THE FEET at y = 0, and the body origin is the capsule
	# CENTRE, so the model hangs half a capsule below it. This line was missing, and the hero stood
	# 7.5 m above every floor in the game -- measured by `probe_float.gd` at 7.36-7.48 m of gap on the
	# sandbox flat, on a ramp and on a kerb, against both the collision floor and the rendered one.
	node.position.y = -p.tuning.capsule_height * 0.5
	p.add_child(node)
	return node


static func build_hurtboxes(p: PlayerMech, t: MechTuning) -> void:
	var half := t.capsule_height * 0.5
	_hurtbox(p, "Torso", &"torso", Vector3(0.0, half * 0.5, 0.0), half, t.capsule_radius * 0.92)
	_hurtbox(p, "Legs", &"legs", Vector3(0.0, -half * 0.5, 0.0), half, t.capsule_radius * 0.85)


static func _hurtbox(p: PlayerMech, node_name: String, part: StringName, at: Vector3, height: float,
		radius: float) -> void:
	var box := Hurtbox.new()
	box.name = node_name
	box.part = part
	box.collision_layer = Layers.PLAYER_HURTBOX
	box.collision_mask = 0
	box.position = at
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	shape.shape = capsule
	box.add_child(shape)
	p.add_child(box)


## Instances every component scene in CONTRACTS §5 order (missing ones are skipped) and records the
## two the mech itself reads. `MechDeath` walks `PlayerMech.components()` to stop them all.
static func load_components(p: PlayerMech, paths: PackedStringArray) -> void:
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var node := (load(path) as PackedScene).instantiate()
		if node == null:
			push_error("PlayerMech: cannot instance component " + path)
			continue
		p.add_child(node)
		p._components.append(node)
		if path.ends_with("aim_system.tscn"):
			p._aim = node
		elif path.ends_with("weapon_system.tscn"):
			p._weapons = node


## main.gd spawns the player before the camera rig, so `Game.camera_rig` is still null in `_ready` even
## when the rig is coming. The stand-in camera is therefore decided on the first physics frame.
static func ensure_debug_camera(p: PlayerMech) -> void:
	if Game.camera_rig != null:
		return
	var cam := Camera3D.new()
	cam.name = "DebugCamera"
	cam.set_script(DEBUG_CAMERA)
	cam.top_level = true
	p.add_child(cam)
	p.locomotion().debug_camera = cam
