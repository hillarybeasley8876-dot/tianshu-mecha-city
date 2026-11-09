extends Node
## city-kit — the window-mask texture contract, checked in the engine that actually imports it.
##
##   tools/godot.sh test res://world/kit/tests/test_kit_textures.gd
##
## Three things the Blender pass cannot prove on its own:
##   1. every mask named in kit.json loads as a Texture2D (a bad import would silently drop every lit
##      window in the city, because `McKitSkin` falls back to albedo darkness and a graded Tripo
##      albedo has none);
##   2. the masks import as FORMAT_L8 — an 8-bit grey PNG costs one byte per texel where an RGB one
##      costs three, and the kit's masks are 42 Mpx, so this is 56 MB against 168 MB of VRAM;
##   3. mipmaps are on. Godot imports a 2D PNG with `mipmaps/generate=false`; a 1024 px mask minified
##      onto a 300 px building then aliases and the thin panes flicker in and out as the camera moves.
##      `tools/citykit/win_import.py` rewrites the `.import` params; this is what proves it took.

const KIT_PATH := "res://world/kit/kit.json"


func _ready() -> void:
	var fails := 0
	var text := FileAccess.get_file_as_string(KIT_PATH)
	var kit: Variant = JSON.parse_string(text)
	if typeof(kit) != TYPE_DICTIONARY:
		print("FAIL kit.json is not a JSON object")
		get_tree().quit(1)
		return
	var masks: Array[String] = []
	for m: Dictionary in (kit as Dictionary).get("models", []):
		if m.has("win"):
			masks.append(String(m["win"]))
	if masks.is_empty():
		print("FAIL kit.json names no window mask")
		get_tree().quit(1)
		return
	print("masks in kit.json: %d" % masks.size())
	for rel in masks:
		var path := "res://world/kit/" + rel
		var tex := load(path) as Texture2D
		if tex == null:
			print("FAIL %s does not load as a Texture2D" % path)
			fails += 1
			continue
		var img := tex.get_image()
		if img == null:
			print("FAIL %s has no image data" % path)
			fails += 1
			continue
		if img.get_format() != Image.FORMAT_L8:
			print("FAIL %s imports as %s, not FORMAT_L8 (3x the VRAM)" % [path, img.get_format()])
			fails += 1
		if not img.has_mipmaps():
			print("FAIL %s has no mipmaps — the panes will alias at distance" % path)
			fails += 1
	if fails == 0:
		print("PASS %d window masks: all FORMAT_L8 with mipmaps" % masks.size())
	get_tree().quit(1 if fails > 0 else 0)
