class_name HudFakeRig
extends Node3D
## Minimal CameraRig stand-in for the HUD test: the HUD only ever asks the rig for its camera and its
## `hud_state()`, so the test does not need the real rig (or a player) to exercise world-anchored
## widgets like damage numbers and lock markers.

var cam: Camera3D = null
var first_person: bool = false


func camera() -> Camera3D:
	return cam


func hud_state() -> Dictionary:
	return {"first_person": first_person, "ads": false, "fov": 55.0, "arm_length": 28.0,
			"cinematic": false}


func is_first_person() -> bool:
	return first_person


func look_dir() -> Vector3:
	return -global_basis.z if cam == null else -cam.global_basis.z
