extends Node
## Fixture (tooling): a suite whose only error is on the allow-list. The host must print
## TEST KNOWN-ERROR and exit 0.   tools/godot.sh test res://tools/tests/fixture_known_error.gd

func _ready() -> void:
	push_error("fixture: an error the allow-list knows about")
	print("FIXTURE known_error 1 checks, 0 failures")
	print("PASS")
	get_tree().quit(0)
