class_name Hero3Clips
extends RefCounted
## The registry of authored action clips (hero-v3, brief step 3 / lead r3 block B).
##
## One file per family, each a plain `Array` of clip dictionaries, so a clip reads as data:
##   {"id": &"melee_l1", "frames": 29.0, "tracks": [{"bone": "R_Upperarm", "keys": [[0, x, y, z], ...]}]}
## Keys are `[frame, euler.x, euler.y, euler.z]` at 60 fps, applied in the bone's rest space exactly
## the way `Hero3Posture.READY_POSE` is, so the two compose without a special case.

const FPS := 60.0


## Every clip, keyed by its SPEC §10 id. Built once per model.
static func build() -> Dictionary:
	var out := {}
	for family: Array in [Hero3ClipsMelee.all(), Hero3ClipsDefense.all(), Hero3ClipsMove.all(),
			Hero3ClipsReact.all(), Hero3ClipsWeapon.all(), Hero3ClipsSkill.all()]:
		for clip: Dictionary in family:
			out[clip["id"]] = _finish(clip)
	return out


## Turn a family's `{tracks: [...]}` into the `{bones: {name: keys}}` the player samples, and derive
## the length in seconds from the frame count.
static func _finish(clip: Dictionary) -> Dictionary:
	var bones := {}
	for track: Dictionary in clip.get("tracks", []):
		bones[String(track["bone"])] = track["keys"]
	var out := clip.duplicate()
	out["bones"] = bones
	out["frames"] = float(clip["frames"])
	out["length"] = float(clip["frames"]) / FPS
	return out


## A track row, so the family files stay one line per bone.
static func track(bone: String, keys: Array) -> Dictionary:
	return {"bone": bone, "keys": keys}


## One key: `[frame, euler.x, euler.y, euler.z]`.
static func key(frame: float, euler: Vector3) -> Array:
	return [frame, euler.x, euler.y, euler.z]


## Degrees to radians, so the family files can be authored in degrees and read by a human.
static func d(x: float, y: float, z: float) -> Vector3:
	return Vector3(deg_to_rad(x), deg_to_rad(y), deg_to_rad(z))
