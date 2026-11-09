extends Node3D
## city-kit — the kit on its own, for verifying the placer before city-build's skin mode is in the
## build (`--kit-only` in my own scene, brief step 7). It is NOT a look-dev scene: the lighting is a
## stand-in for ART.md §3 so geometry, scale and the window layer can be judged, and the real judgement
## happens in the city.
##
##   tools/godot.sh shot --scene=res://world/kit/tests/kit_scene.tscn --out=kit_city \
##       --cams=A3:0,40,60:0,120,-260:60

const PLACER := preload("res://world/kit/kit_placer.tscn")
const SUN_ELEVATION := 18.0
const SUN_AZIMUTH := 315.0


func _ready() -> void:
	_add_light()
	_add_environment()
	var placer := PLACER.instantiate()
	add_child(placer)
	if placer.has_method("setup"):
		placer.call("setup", null, {})
	print("KitScene: %d MultiMeshInstance3D batches under %s" % [_batches(placer), placer.name])


func _batches(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		n += 1 if child is MultiMeshInstance3D else 0
		n += _batches(child)
	return n


func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.827, 0.627)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 500.0
	sun.rotation_degrees = Vector3(-SUN_ELEVATION, 180.0 - SUN_AZIMUTH, 0.0)
	add_child(sun)


func _add_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.169, 0.298, 0.494)
	sky_mat.sky_horizon_color = Color(0.949, 0.722, 0.502)
	sky_mat.ground_horizon_color = Color(0.784, 0.639, 0.478)
	sky_mat.ground_bottom_color = Color(0.227, 0.204, 0.251)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.910, 0.725, 0.541)
	env.fog_density = 0.0016
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)
