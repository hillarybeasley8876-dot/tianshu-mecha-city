extends CharacterBody3D
## The driver for `test_platform.gd`'s two moving bodies: a monster's back and a world platform.
##
## Both are `CharacterBody3D` moved by `velocity` + `move_and_slide`, which is what makes Godot treat
## a body as a moving platform for a rider, and both slide at the same speed in the same direction.
## The ONLY difference between them is the collision layer, so the suite measures exactly what
## `platform_floor_layers` changed and nothing else.
##
## `drive` is set by the test for the 2 s window it measures; outside it the body holds still so the
## hero can settle on its back.

func _physics_process(_delta: float) -> void:
	if not bool(get_meta(&"drive", false)):
		return
	velocity.x = float(get_meta(&"speed", 8.0))
	move_and_slide()
