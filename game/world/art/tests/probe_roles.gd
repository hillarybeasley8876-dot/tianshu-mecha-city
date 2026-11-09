extends Node
## Diagnostic: which flat colour does `--art-debug=roles` give each mc_* role? (city-art)
##   tools/godot.sh test res://world/art/tests/probe_roles.gd


func _ready() -> void:
	for role in McMaterials.ROLE_NAMES:
		var h := int(String(role).hash())
		var c := Color(float(h % 1000) / 1000.0, float(h / 1000 % 1000) / 1000.0,
			float(h / 1000000 % 1000) / 1000.0)
		print("ROLE %-16s linear=(%.3f,%.3f,%.3f) srgb8=(%d,%d,%d)"
			% [role, c.r, c.g, c.b, int(c.srgb_to_linear().r * 255.0),
			   int(c.srgb_to_linear().g * 255.0), int(c.srgb_to_linear().b * 255.0)])
	get_tree().quit(0)
