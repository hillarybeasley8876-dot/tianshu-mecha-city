extends Node
## Fixture (tooling): a suite that raises a real SCRIPT ERROR and still quits 0 — the shape that hid
## melee's Nil pair for four rounds. The strict host must exit 1; the old host exits 0.
##   tools/godot.sh test res://tools/tests/fixture_script_error.gd

func _ready() -> void:
	var freed: Node = Node.new()
	freed.free()
	var typed: Array[Node] = []
	typed.has(freed)                     # invalid (previously freed) instance -> SCRIPT ERROR
	print("FIXTURE script_error 1 checks, 0 failures")
	print("PASS")
	get_tree().quit(0)
