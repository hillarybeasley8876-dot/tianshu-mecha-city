extends "res://player/mech/tests/mech_test_base.gd"
## mech-move r8 item 2 — monsters are not a moving floor (status/enemies.md Request 19).
##
## `CharacterBody3D.platform_floor_layers` defaults to EVERY layer, so a monster moving under the mech
## read as a kinematic platform: the hero was carried along with it, and `platform_on_leave` handed it
## the monster's velocity on the way off — which is how a spawning or patrolling monster flings the
## mech. `MechBuild.build_body` now pins the mask to `Layers.WORLD | Layers.PROPS`.
##
## The gate: the hero stands on a moving monster's back for 2 s and is neither carried nor flung,
## while a moving WORLD platform (the deck case) still carries it.
##
## Both bodies are `CharacterBody3D` driven by `velocity` + `move_and_slide` (what makes Godot treat
## a body as a moving platform at all) at the same speed in the same direction. The only difference
## is the collision layer, so the suite measures the mask and nothing else.

const MOVER := preload("res://player/mech/tests/platform_mover.gd")
## A 16 m mech needs a big back to stand on, and it must out-run the 2 s slide or the hero walks off
## the front of it and the measurement becomes a fall instead of a carry.
const BACK := Vector3(60.0, 4.0, 60.0)
const SLIDE := 8.0     ## m/s the body slides in +X
const WINDOW := 240    ## 2 s at 120 Hz


func _run() -> void:
	await _setup()

	await _test_monster_does_not_carry()
	await _test_world_platform_still_carries()
	_report("mech-move platforms")


# --- checks --------------------------------------------------------------------------------------

## The headline gate: 2 s standing on a moving monster's back, under 1 m/s of carry, and stepping off
## it must not hand the hero the monster's motion either.
func _test_monster_does_not_carry() -> void:
	var r := await _ride(Layers.ENEMY, Vector3(-120.0, 0.0, 60.0), "monster")
	_ok(r["carried"] < 1.0, "standing on a moving monster for 2 s does not carry the hero",
			"carried=%.2f m/s" % r["carried"])
	_ok(r["fling"] < 1.0, "and stepping off the monster does not fling it",
			"fling=%.2f m/s" % r["fling"])
	_ok(r["on_back"], "the hero really was standing on the monster the whole time",
			"floor=%s" % r["on_back"])


## ... but a moving world platform (the deck / maglev case) still carries the mech, or the fix has
## broken every moving floor in the game.
func _test_world_platform_still_carries() -> void:
	var r := await _ride(Layers.WORLD, Vector3(-40.0, 0.0, 60.0), "world platform")
	_ok(r["carried"] > SLIDE * 0.6, "a moving world platform still carries the hero",
			"carried=%.2f m/s want>%.2f" % [r["carried"], SLIDE * 0.6])
	_ok(r["on_back"], "and the hero stays on it", "floor=%s" % r["on_back"])


# --- the ride ------------------------------------------------------------------------------------

## Put the hero on a slab on `layer`, slide the slab at SLIDE for 2 s, and measure how much of that
## motion the hero picked up. `carried` is how fast the hero actually TRAVELLED (its own velocity
## stays zero while a platform carries it, so drift is the honest number); `fling` is the peak
## horizontal speed in the half second after it jumps off, which is where `platform_on_leave` bites.
func _ride(layer: int, at: Vector3, label: String) -> Dictionary:
	var body := CharacterBody3D.new()
	body.name = "Slab"
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = at + Vector3(0.0, BACK.y * 0.5, 0.0)
	body.set_script(MOVER)
	body.set_meta(&"speed", SLIDE)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BACK
	shape.shape = box
	body.add_child(shape)
	add_child(body)

	# The feet land on the slab's top face, so the body origin is a capsule half above it.
	await _reset(at + Vector3(0.0, BACK.y + GROUND_Y, 0.0))
	if not _p.is_on_floor():
		push_warning("platform test: the hero never landed on the %s" % label)
	var start := _p.global_position
	body.set_meta(&"drive", true)
	for i in WINDOW:
		await get_tree().physics_frame
	var drift := Vector2(_p.global_position.x - start.x, _p.global_position.z - start.z).length()
	var on_back := _p.is_on_floor()

	# Step off it while it is still sliding: a platform the mask excludes must hand over nothing.
	var fling := 0.0
	await _tap(&"jump")
	for i in 60:
		await get_tree().physics_frame
		fling = maxf(fling, _speed())
	body.set_meta(&"drive", false)
	body.queue_free()
	await _step(2)
	print("PLAT %-14s carried=%.2f fling=%.2f floor=%s" % [label, drift / 2.0, fling, on_back])
	return {"carried": drift / (float(WINDOW) / 120.0), "fling": fling, "on_back": on_back}
