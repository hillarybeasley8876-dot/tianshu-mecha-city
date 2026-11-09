extends Node
## city-art r15 — the sky panorama contract (`world/art/sky_pano.gd`, `world/art/sky/`).
##
##   tools/godot.sh test res://world/art/tests/test_sky_pano.gd
##
## What is checked, and why each one is a real failure and not a style note:
##  1. the manifest parses and every plate it lists is importable as a Texture2D — a typo in
##     `index.json` otherwise fails silently at runtime, because `SkyPano.apply` degrades to "no
##     panorama" rather than crashing;
##  2. the yaw it computes puts the plate's OWN sun on the world's sun. Get this wrong and the cloud
##     lighting and the key light disagree by a fixed angle in every frame — which looks like an art
##     choice and is not one;
##  3. `apply` on a material with no plate selected forces `pano_blend` to 0, so the shader's
##     `pano_blend > 0.001` branch can never run on a black texture;
##  4. `McMaterials.set_sky_tint` reaches a material that declares `sky_horizon` (the wet-ground
##     analytic reflection) — the same "the push list was empty and nothing errored" failure the haze
##     list had in r3-r5.

var _fails: int = 0


func _ready() -> void:
	_check_manifest()
	_check_yaw()
	_check_no_plate()
	_check_sky_tint()
	print("SKY PANO TEST %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _fail(msg: String) -> void:
	_fails += 1
	push_error("test_sky_pano: " + msg)


func _check_manifest() -> void:
	var man := SkyPano.manifest()
	if man.is_empty():
		_fail("the manifest did not parse — every later check is meaningless")
		return
	var panos: Dictionary = man.get("panos", {})
	if panos.is_empty():
		_fail("the manifest lists no panoramas")
	var dir := String(man.get("dir", ""))
	for id: String in panos:
		var entry: Dictionary = panos[id]
		for key in ["file", "sun_az_deg", "ref", "licence"]:
			if not entry.has(key):
				_fail("pano '%s' has no '%s'" % [id, key])
		if String(entry.get("licence", "")) != "CC0":
			_fail("pano '%s' is not CC0 — this directory is CC0 only" % id)
		var path := dir + String(entry.get("file", ""))
		if not ResourceLoader.exists(path):
			_fail("pano '%s' lists %s, which is not importable" % [id, path])
		elif not (load(path) is Texture2D):
			_fail("pano '%s' did not load as a Texture2D" % id)
	var active := String(man.get("active", ""))
	if not panos.has(active):
		_fail("the manifest's active plate '%s' is not in its own panos table" % active)
	print("SKY PANO manifest ok: %d plates, active=%s" % [panos.size(), active])


func _check_yaw() -> void:
	var sel := SkyPano.selected()
	if sel.is_empty():
		_fail("no plate selected — the yaw check needs one")
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/art/shaders/mc_sky.gdshader") as Shader
	SkyPano.apply(mat, 1.0)
	var blend: float = mat.get_shader_parameter(&"pano_blend")
	var yaw: float = mat.get_shader_parameter(&"pano_yaw")
	if not is_equal_approx(blend, 1.0):
		_fail("apply(mat, 1.0) left pano_blend at %f" % blend)
	# The shader rotates the view direction by `yaw` before the equirect lookup, so the plate's sun
	# (azimuth A) appears in the world at A - yaw. That has to be the world's sun azimuth.
	var lands := wrapf(float(sel["sun_az_deg"]) - yaw, -180.0, 180.0)
	var want := wrapf(SkyPano.WORLD_SUN_AZ_DEG, -180.0, 180.0)
	if absf(lands - want) > 0.01:
		_fail("the plate's sun lands at %.2f deg, not the world's %.2f deg" % [lands, want])
	print("SKY PANO yaw ok: %s sun %.1f -> world %.1f (yaw %.1f)"
		% [sel["id"], float(sel["sun_az_deg"]), lands, yaw])


func _check_no_plate() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/art/shaders/mc_sky.gdshader") as Shader
	mat.set_shader_parameter(&"pano_blend", 0.9)
	SkyPano.apply(mat, 0.0, "none")
	var blend: float = mat.get_shader_parameter(&"pano_blend")
	if not is_equal_approx(blend, 0.0):
		_fail("a forced 0 blend left pano_blend at %f" % blend)
	# A zero blend must not LOAD the plate either: the manifest ships at 0 and the shipped build was
	# paying 44 MB of VRAM for a branch that never ran.
	var fresh := ShaderMaterial.new()
	fresh.shader = load("res://world/art/shaders/mc_sky.gdshader") as Shader
	SkyPano.apply(fresh, 0.0)
	if fresh.get_shader_parameter(&"pano") != null:
		_fail("a zero blend still bound the panorama texture")


func _check_sky_tint() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/art/shaders/mc_surface.gdshader") as Shader
	if mat.shader == null:
		_fail("mc_surface.gdshader did not load")
		return
	McMaterials.register(mat)
	McMaterials.set_sky_tint(Color(0.9, 0.6, 0.3), Color(0.2, 0.3, 0.5))
	var h: Color = mat.get_shader_parameter(&"sky_horizon")
	var z: Color = mat.get_shader_parameter(&"sky_zenith")
	if not h.is_equal_approx(Color(0.9, 0.6, 0.3)):
		_fail("set_sky_tint did not reach mc_surface's sky_horizon (got %s)" % str(h))
	if not z.is_equal_approx(Color(0.2, 0.3, 0.5)):
		_fail("set_sky_tint did not reach mc_surface's sky_zenith (got %s)" % str(z))
	var counts := McMaterials.registered()
	if int(counts.get("skytint", 0)) < 1:
		_fail("no material is on the sky-tint push list: %s" % str(counts))
	print("SKY PANO tint ok: %d materials on the sky-tint list" % int(counts.get("skytint", 0)))
