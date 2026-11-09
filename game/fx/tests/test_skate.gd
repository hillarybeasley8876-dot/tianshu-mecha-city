extends Node
## feel r5b item 4 - feet-contact sparks and dust under the boost skate and the ground slide.
##     tools/godot.sh test res://fx/tests/test_skate.gd
##
## The hero unit owns the lean and the backpack plumes; this is the ground half of hero-v3 r9 item 3
## ("the run-to-skate change sold with lean, sparks and dust"). The gate: the emitters fire while the
## mech skates ON THE GROUND, stop the instant it leaves the floor, park on the real foot bones, and
## never grow past their four emitters / 128 particles - a 42 m/s skate must not steal a kill's
## blast out of the shared pools.

const SKATE_SPEED := 42.0
const TOL := 0.05

var _fails: int = 0
var _lib: VfxLibrary
var _mech: FakeMech
var _rig: FakeRig


## A stand-in for PlayerMech: the trail only asks for move_state(), is_grounded(), model() and
## velocity, so a fake lets the test move the feet without a 16 m skinned mech.
class FakeMech:
	extends CharacterBody3D

	var state: StringName = &"slide"
	var grounded: bool = true
	var rig: Node3D = null

	func move_state() -> StringName:
		return state

	func is_grounded() -> bool:
		return grounded

	func model() -> Node3D:
		return rig


## The trail reads the feet off `model().skeleton`, so the stand-in rig carries a real Skeleton3D
## with the hero's own bone names.
class FakeRig:
	extends Node3D

	var skeleton: Skeleton3D = null


func _ready() -> void:
	await get_tree().process_frame
	_floor()
	_lib = VfxLibrary.new()
	_lib.name = "Vfx"
	add_child(_lib)
	_mech = _build_mech()
	add_child(_mech)
	_lib.skate.set_player(_mech)
	await get_tree().physics_frame
	_wants()
	await _skating()
	await _follows_the_feet()
	await _airborne()
	await _budget()
	print("TEST feel skate: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		_fails += 1


func _floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 2.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	add_child(body)


func _build_mech() -> FakeMech:
	_rig = FakeRig.new()
	_rig.name = "Rig"
	_rig.skeleton = Skeleton3D.new()
	_rig.skeleton.name = "Skeleton3D"
	_rig.skeleton.add_bone(&"Root")
	for i in FxSkateTrail.FEET.size():
		var bone := _rig.skeleton.add_bone(FxSkateTrail.FEET[i])
		_rig.skeleton.set_bone_parent(bone, 0)
		var side := 1.0 if i == 0 else -1.0
		_rig.skeleton.set_bone_rest(bone,
				Transform3D(Basis.IDENTITY, Vector3(side * 1.6, 0.25, 0.0)))
		_rig.skeleton.set_bone_pose_position(bone, Vector3(side * 1.6, 0.25, 0.0))
	_rig.add_child(_rig.skeleton)
	var mech := FakeMech.new()
	mech.name = "FakeMech"
	mech.rig = _rig
	mech.velocity = Vector3(0.0, 0.0, -SKATE_SPEED)
	mech.add_child(_rig)
	return mech


## Pure predicate: which states scrape, and only on the ground.
func _wants() -> void:
	_check(FxSkateTrail.wants(&"slide", true, SKATE_SPEED), "the 42 m/s boost skate scrapes")
	_check(FxSkateTrail.wants(&"assault", true, 60.0), "the assault boost scrapes")
	_check(FxSkateTrail.wants(&"dash_f", true, 30.0), "a ground dash slide scrapes")
	_check(not FxSkateTrail.wants(&"slide", false, SKATE_SPEED), "the same skate in the air does not")
	_check(not FxSkateTrail.wants(&"run", true, 16.0), "a 16 m/s run does not")
	_check(not FxSkateTrail.wants(&"idle", true, 0.0), "standing still does not")
	_check(not FxSkateTrail.wants(&"slide", true, 9.0), "a 9 m/s walk does not")


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## On the ground at 42 m/s: every emitter runs and both feet are parked on the floor.
func _skating() -> void:
	_mech.grounded = true
	_mech.state = &"slide"
	_mech.velocity = Vector3(0.0, 0.0, -SKATE_SPEED)
	await _ticks(4)
	var trail := _lib.skate
	_check(trail.active(), "the trail is running while the mech skates on the ground")
	_check(_emitting() == 4, "all four emitters are emitting (%d)" % _emitting())
	var feet := trail.contacts()
	_check(feet.size() == 2, "two foot contacts (%d)" % feet.size())
	var on_floor := true
	for at in feet:
		on_floor = on_floor and absf(at.y) <= TOL
	_check(on_floor, "both contacts sit on the floor (%.3f, %.3f)" % [feet[0].y, feet[1].y])
	_check(absf(feet[0].x - feet[1].x) > 1.0,
			"the two contacts are the two feet, not one point (%.2f apart)" % absf(feet[0].x - feet[1].x))


## The emitters follow the foot bones: move the mech 12 m and both contacts move with it.
func _follows_the_feet() -> void:
	_mech.global_position = Vector3(12.0, 0.0, 7.0)
	await _ticks(4)
	var feet := _lib.skate.contacts()
	_check(absf(feet[0].x - 13.6) <= TOL and absf(feet[1].x - 10.4) <= TOL,
			"the contacts track the R/L foot bones (%.2f, %.2f)" % [feet[0].x, feet[1].x])
	_check(absf(feet[0].z - 7.0) <= TOL, "and the mech's z (%.2f)" % feet[0].z)
	# A placeholder model has no skeleton: the two emitters fall back to one stance width either
	# side of it rather than stacking into a single plume.
	_mech.rig = Node3D.new()
	_mech.add_child(_mech.rig)
	_mech.rig.global_position = Vector3(0.0, 0.0, 0.0)
	await _ticks(4)
	var flat := _lib.skate.contacts()
	_check(absf(flat[0].x - 1.6) <= TOL and absf(flat[1].x + 1.6) <= TOL,
			"a model with no skeleton still gets two feet (%.2f, %.2f)" % [flat[0].x, flat[1].x])
	_mech.rig = _rig
	await _ticks(2)


## Off the floor: everything stops, even though the state is still the skate and the speed is 42.
func _airborne() -> void:
	_mech.grounded = false
	await _ticks(4)
	_check(not _lib.skate.active(), "the trail stops the moment the mech leaves the floor")
	_check(_emitting() == 0, "no emitter is left running in the air (%d)" % _emitting())
	_mech.grounded = true
	_mech.state = &"run"
	_mech.velocity = Vector3(0.0, 0.0, -16.0)
	await _ticks(4)
	_check(not _lib.skate.active(), "a 16 m/s run on the ground does not start it again")
	_mech.state = &"dash_f"
	_mech.velocity = Vector3(0.0, 0.0, -30.0)
	await _ticks(4)
	_check(_lib.skate.active() and _emitting() == 4, "a ground dash slide starts it again")


## The budget: four emitters and 128 particles, fixed, whatever the mech does - and not one pooled
## VFX slot, so a skate can never starve a kill of its blast.
func _budget() -> void:
	var trail := _lib.skate
	var children := trail.get_child_count()
	var pool := _lib.active_count()
	var nodes := _lib.get_child_count()
	await _ticks(240)
	_check(trail.emitter_count() == 4, "four emitters, built once (%d)" % trail.emitter_count())
	_check(trail.particle_budget() == 128,
			"128 particles is the whole budget (%d)" % trail.particle_budget())
	_check(trail.get_child_count() == children,
			"a 2 s skate instantiated nothing (%d children)" % trail.get_child_count())
	_check(_lib.get_child_count() == nodes,
			"and the library grew no nodes either (%d)" % _lib.get_child_count())
	_check(_lib.active_count() == pool,
			"the skate used no pooled VFX slot (%d live)" % _lib.active_count())
	await _real_model()


## The real rig: the hero model's own skeleton must answer `R_Foot` / `L_Foot`, or the whole trail
## silently falls back to a stance-width guess.
func _real_model() -> void:
	var packed := load("res://player/model/hero3/hero3_model.tscn") as PackedScene
	if packed == null:
		_check(false, "res://player/model/hero3/hero3_model.tscn loads")
		return
	var hero := packed.instantiate() as Node3D
	_mech.rig = hero
	_mech.add_child(hero)
	await _ticks(8)
	var skel: Variant = hero.get(&"skeleton")
	_check(skel is Skeleton3D, "the hero model exposes its Skeleton3D")
	if skel is Skeleton3D:
		var bones := PackedStringArray()
		for name in FxSkateTrail.FEET:
			bones.append("%s=%d" % [name, (skel as Skeleton3D).find_bone(name)])
		_check(not "=-1" in " ".join(bones), "both foot bones exist (%s)" % " ".join(bones))
	var feet := _lib.skate.contacts()
	_check(_lib.skate.active() and absf(feet[0].x - feet[1].x) > 1.0,
			"the trail parks on the real mech's two feet (%.2f apart)" % absf(feet[0].x - feet[1].x))


func _emitting() -> int:
	var n := 0
	for child in _lib.skate.get_children():
		if child is GPUParticles3D and (child as GPUParticles3D).emitting:
			n += 1
	return n
