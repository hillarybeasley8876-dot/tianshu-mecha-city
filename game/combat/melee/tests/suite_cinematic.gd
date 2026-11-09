class_name MeleeCinematicSuite
extends RefCounted
## Core Rend framing (review r1 MUST-FIX 1): for EVERY shot of EVERY class, both fighters must be
## inside the frustum with at least 8 % of margin, and the camera must stand clear of the world and
## of both bodies. The r1 captures were black because the shots were authored in a frame the rig no
## longer uses; this suite is what stops that coming back.

## A representative victim per class: [half-width, height, half-depth] in metres.
const VICTIMS: Dictionary = {
	&"light": Vector3(4.0, 10.0, 4.0),
	&"brute": Vector3(8.0, 22.0, 8.0),
	&"colossus": Vector3(13.0, 40.0, 13.0),
}
const HERO := Vector3(7.0, 16.0, 5.0)     ## a 16 m mech, half-extents
const GAP := 12.0                          ## metres between the two, inside the 14 m execution gate
const MARGIN := 0.08                       ## fraction of the viewport kept clear on every side
const CLEARANCE := 1.0                     ## metres the camera keeps off every AABB
const VIEW := Vector2i(1600, 900)          ## the aspect every capture and the game run at


static func run(h: MeleeTestHarness) -> void:
	## Framing is aspect-dependent, so pin the viewport to the shipping 16:9 before measuring.
	h.tree.root.size = VIEW
	var cam := Camera3D.new()
	cam.name = "FramingCam"
	cam.near = 0.3
	cam.far = 4000.0
	h.root.add_child(cam)
	await h.ticks(1)
	for cls: StringName in ExecutionDirector.SHOTS.keys():
		await _class(h, cam, cls)
	cam.queue_free()
	_shapes(h)
	await _targetable(h)


## The real `AimSystem.hard_target()` hands out a `Targetable` marker, not the enemy (CONTRACTS §4).
## The rig aim returns the enemy directly, which hid a Core Rend that could never fire in the game;
## this drives the executor through a genuine Targetable so that cannot come back.
static func _targetable(h: MeleeTestHarness) -> void:
	h.fresh()
	var enemy := h.add_dummy(10.0)
	enemy.stagger()
	await h.ticks(2)
	var marker := Targetable.new()
	marker.name = "LockPoint"
	enemy.add_child(marker)
	marker.global_position = enemy.global_position
	await h.ticks(1)
	var executor := h.system.executor
	h.check("lock.marker_resolves_to_the_enemy",
			ExecutionDirector.actor_of(marker) == enemy)
	h.check("lock.marker_is_a_valid_target", marker.is_valid_target())
	h.check("lock.available_through_marker", executor.available(marker),
			"the Core Rend gate must accept a Targetable")
	h.check("lock.class_of_marker", ExecutionDirector.class_of(marker) == &"light")
	var started := executor.start(marker)
	h.check("lock.start_through_marker", started)
	executor.cancel()
	h.fresh()
	await h.step(0.1)


## The built meshes have to be the size the tables say: an over-scaled crescent fills the frame and
## reads as a white slab, which is exactly how the r1/r2 captures went wrong.
static func _shapes(h: MeleeTestHarness) -> void:
	var wave := CrescentMesh.build(MeleeTable.WAVE_WIDTH, MeleeTable.WAVE_THICKNESS,
			MeleeTable.WAVE_HEIGHT).get_aabb()
	h.near("mesh.crescent_chord", wave.size.x, MeleeTable.WAVE_WIDTH, 1.0)
	h.near("mesh.crescent_height", wave.size.y, MeleeTable.WAVE_HEIGHT, 1.5)
	h.check("mesh.crescent_is_a_sheet", wave.size.z < MeleeTable.WAVE_THICKNESS * 3.0,
			"depth %.1f m — a crescent, not a slab" % wave.size.z)
	var blade := CombatMesh.blade(MeleeTable.BLADE_LENGTH, MeleeTable.BLADE_HALF).get_aabb()
	h.near("mesh.blade_length", blade.size.z, MeleeTable.BLADE_LENGTH, 0.5)
	h.check("mesh.blade_tapers", blade.size.x < 2.0,
			"hilt %.2f m across — the blade must stay a blade" % blade.size.x)


static func _class(h: MeleeTestHarness, cam: Camera3D, cls: StringName) -> void:
	var size: Vector3 = VICTIMS[cls]
	var hero_at := Vector3(0.0, HERO.y * 0.5, 0.0)
	var victim_at := Vector3(0.0, size.y * 0.5, -GAP)
	var hero := AABB(hero_at - HERO * 0.5, HERO)
	var victim := AABB(victim_at - size * 0.5, size)
	var frame := ExecutionDirector.duel_frame(hero_at, victim_at)
	var duration := float(ExecutionDirector.CLASSES[cls]["duration"])
	var core := Vector3(victim.get_center().x, victim.position.y + victim.size.y
			* ExecutionDirector.CORE_FRACTION, victim.get_center().z)
	var shots := ExecutionDirector.shots_for(cls, duration, frame, core,
			hero_at + Vector3.UP * 2.0)
	h.eq("cine.%s.shot_count" % cls, shots.size(),
			(ExecutionDirector.SHOTS[cls] as Array).size())
	for i in shots.size():
		var shot: Dictionary = shots[i]
		_aim(cam, frame, shot)
		_frame_check(h, "%s.s%d" % [cls, i], cam, frame, shot, hero, victim)


## Places the camera exactly the way `camera_cinematic._apply` does, before its collision resolve.
static func _aim(cam: Camera3D, frame: Transform3D, shot: Dictionary) -> void:
	var eye: Vector3 = frame * (shot["offset"] as Vector3)
	var aim: Vector3 = frame * (shot["look"] as Vector3)
	var dir := aim - eye
	cam.global_transform = Transform3D(
			frame.basis if dir.length_squared() < 0.01
					else Basis.looking_at(dir.normalized(), Vector3.UP), eye)
	cam.fov = float(shot.get("fov", 50.0))


static func _frame_check(h: MeleeTestHarness, tag: String, cam: Camera3D, frame: Transform3D,
		shot: Dictionary, hero: AABB, victim: AABB) -> void:
	var eye: Vector3 = frame * (shot["offset"] as Vector3)
	var view := cam.get_viewport().get_visible_rect().size
	for pair: Array in [["hero", hero], ["victim", victim]]:
		var name := String(pair[0])
		var box: AABB = pair[1]
		var centre: Vector3 = box.get_center()
		h.check("cine.%s.%s_in_frustum" % [tag, name], cam.is_position_in_frustum(centre),
				"centre %v outside the frustum" % centre)
		var px := cam.unproject_position(centre)
		h.check("cine.%s.%s_margin" % [tag, name], _inside(px, view),
				"centre at %v of %v (margin %.0f %%)" % [px, view, MARGIN * 100.0])
	h.check("cine.%s.clear_of_hero" % tag, not hero.grow(CLEARANCE).has_point(eye),
			"camera %v inside the hero" % eye)
	h.check("cine.%s.clear_of_victim" % tag, not victim.grow(CLEARANCE).has_point(eye),
			"camera %v inside the victim" % eye)
	h.check("cine.%s.clear_of_world" % tag, not _in_world(cam, eye),
			"camera %v inside world geometry" % eye)


## True when `px` sits at least MARGIN inside the viewport on every side.
static func _inside(px: Vector2, view: Vector2) -> bool:
	var mx := view.x * MARGIN
	var my := view.y * MARGIN
	return px.x >= mx and px.x <= view.x - mx and px.y >= my and px.y <= view.y - my


## A sphere query at the camera on the world layer: the shot must not start inside the scenery.
static func _in_world(cam: Camera3D, eye: Vector3) -> bool:
	var space := cam.get_world_3d().direct_space_state
	if space == null:
		return false
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, eye)
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return not space.intersect_shape(params, 1).is_empty()
