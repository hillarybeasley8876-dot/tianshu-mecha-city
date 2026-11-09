extends Node
## Fixture (tooling): a clean suite — no checks failed, no errors. The host must exit 0.
##   tools/godot.sh test res://tools/tests/fixture_clean.gd

func _ready() -> void:
	print("FIXTURE clean 1 checks, 0 failures")
	print("PASS")
	get_tree().quit(0)
