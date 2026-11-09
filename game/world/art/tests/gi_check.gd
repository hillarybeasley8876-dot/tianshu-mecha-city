extends Node3D
## SDFGI-on-Metal check (city-art, ART.md §3 critic P0 #6). Two boxes and the sun: a saturated
## albedo box sits on the floor and a white box floats above and beside it, so the white box's
## underside can only be lit by bounced light. If SDFGI works on this Apple GPU the underside turns
## red; if it does not, the underside stays sky-lit grey. godot-tech §1.2 lists an open Metal bug
## where SDFGI ignores lights, so the A/B must be run before the GI preset is chosen.
##   tools/godot.sh shot --scene=res://world/art/tests/gi_check.tscn --out=art_gi_nogi --env-only
##   tools/godot.sh shot --scene=res://world/art/tests/gi_check.tscn --out=art_gi_sdfgi --env-only --gi=sdfgi

const ENV_SCENE := preload("res://world/art/environment.tscn")
const KIT := preload("res://world/art/tests/street_kit.gd")

## Camera: looks up at the underside of the white box with the red bouncer filling the lower frame.
const CAM_POS := Vector3(26.0, 15.0, 26.0)
const CAM_LOOK := Vector3(-1.0, 17.0, -1.0)

const BOUNCER := Color("c23a2a")     ## saturated so any bounce is unmistakable
const RECEIVER := Color("e8e8e6")


func _ready() -> void:
	add_child(ENV_SCENE.instantiate())

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = KIT.slab(Vector2(90.0, 90.0))
	floor_mesh.material_override = McMaterials.get_material(&"mc_panel_white")
	add_child(floor_mesh)

	_bouncer(Vector3(0.0, 5.0, 0.0), Vector3(14.0, 10.0, 14.0), BOUNCER)
	# The receiver floats clear of the bouncer so only indirect light reaches its underside.
	_receiver(Vector3(0.0, 21.0, 0.0), Vector3(16.0, 6.0, 16.0))
	_receiver(Vector3(24.0, 8.0, 0.0), Vector3(8.0, 16.0, 8.0), RECEIVER.darkened(0.25))

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 2000.0
	cam.position = CAM_POS
	add_child(cam)
	cam.look_at(CAM_LOOK, Vector3.UP)
	cam.current = true


func _bouncer(centre: Vector3, size: Vector3, colour: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Bouncer"
	mi.mesh = KIT.box(size)
	mi.position = centre
	mi.material_override = _flat(colour)
	add_child(mi)


func _receiver(centre: Vector3, size: Vector3, colour: Color = RECEIVER) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Receiver"
	mi.mesh = KIT.box(size)
	mi.position = centre
	mi.material_override = _flat(colour)
	add_child(mi)


## Fully rough and non-metallic so the result is pure diffuse bounce, with nothing to confuse it.
func _flat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour.srgb_to_linear()
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular = 0.0
	return m
