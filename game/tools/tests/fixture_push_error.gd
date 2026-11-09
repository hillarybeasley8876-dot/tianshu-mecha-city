extends Node
## Fixture (tooling): a suite that logs an engine ERROR (push_error) and still quits 0. The strict
## host must exit 1; the old host exits 0.   tools/godot.sh test res://tools/tests/fixture_push_error.gd

func _ready() -> void:
	push_error("fixture: this push_error is not on the allow-list")
	print("FIXTURE push_error 1 checks, 0 failures")
	print("PASS")
	get_tree().quit(0)
