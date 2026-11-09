class_name Hero3Drones
extends RefCounted
## The seven blade drones on the Tianshu's back frame (hero-v3, lead r8 item 4).
##
## They are BONES inside the one rigid-skinned body mesh, not separate `MeshInstance3D`s, so the two
## things that act on them have to go through the skeleton: the fan (`set_open`) rotates their bones,
## and the per-drone hide API collapses a bone's basis so its blade shrinks into the frame it is
## mounted on. A zero-scaled basis would be a singular matrix, so a hidden blade is scaled to
## `HIDDEN_SCALE` -- 2 mm of a 2 m blade, which is under one pixel at every camera in the game.
##
## The modelled cyan tip on each blade (`Hero3Glow`) is a separate little mesh and is hidden with it.

## Bit `i` of a mask means "drone `i` (0-based) is DEPLOYED -- its blade on the back must not be
## drawn". `Drone_1..4` ride `wing_l` and `Drone_5..7` ride `wing_r`; `fins_max` is 6, so the lead's
## mapping is 3 fins a side and `Drone_1` (bit 0) always stays docked (r16 decisions, skills r4).
const ALL := 0x7F
const HIDDEN_SCALE := 0.001
## How fast the fan opens. The hide is instant: a fin leaves its blade on the launch frame, and a
## half-faded 2 m blade on the back for 0.2 s reads as a bug rather than as a transition.
const FAN_LERP := 7.0
## The fan: each drone swings out of the folded rest pose by this much at `set_open(1)`. Index 0 is
## Drone_1 (the far blade), and the sweep is staggered so the fan opens from the spine outwards.
const FAN_DEG: Array[float] = [26.0, 20.0, 14.0, 8.0, -10.0, -16.0, -22.0]

var skeleton: Skeleton3D
var glow: Hero3Glow = null
## `Hero3Rig.DRONE_BONES`, index-aligned with every mask this class takes.
var bones: Array[String] = []

var _fan: float = 0.0
var _fan_target: float = 0.0
var _docked: int = 0


func setup(skeleton_: Skeleton3D, bones_: Array[String], glow_: Hero3Glow) -> void:
	skeleton = skeleton_
	bones = bones_
	glow = glow_


## 0 folds the blades along the frame, 1 fans them out the way the concept sheet draws them.
func set_open(open: float) -> void:
	_fan_target = clampf(open, 0.0, 1.0)


## Hide or show individual blades (skills r4, the Corona Fins). A SET bit is a drone that is OUT as
## a fin, so its copy on the back must not be drawn; a clear bit is a docked blade, drawn as usual.
## The mask is absolute, not additive: passing 0 shows all seven.
func set_docked(mask: int) -> void:
	_docked = mask & ALL
	_apply_visibility()


## The mask `set_docked` was last given, so a caller can read back what it asked for.
func docked() -> int:
	return _docked


## One drone at a time, 0-based. `deployed` true hides the blade, exactly as a set bit does.
func set_deployed(index: int, deployed: bool) -> void:
	if index < 0 or index >= bones.size():
		push_warning("Hero3Drones: no drone at index %d" % index)
		return
	set_docked((_docked | (1 << index)) if deployed else (_docked & ~(1 << index)))


func is_deployed(index: int) -> bool:
	return index >= 0 and index < bones.size() and (_docked & (1 << index)) != 0


## Where drone `index`'s mount sits in WORLD space, so a fin can leave its own blade rather than a
## station marker. `Hero3Rig.drone_tip` is the same number; this is the one on the model API.
func tip(index: int) -> Vector3:
	if skeleton == null or index < 0 or index >= bones.size():
		return Vector3.ZERO
	var idx := skeleton.find_bone(bones[index])
	if idx < 0:
		push_warning("Hero3Drones: missing bone %s" % bones[index])
		return Vector3.ZERO
	return skeleton.to_global(skeleton.get_bone_global_pose(idx).origin)


func update(delta: float) -> void:
	_fan = lerpf(_fan, _fan_target, clampf(delta * FAN_LERP, 0.0, 1.0))
	_apply_fan()


func fan() -> float:
	return _fan


func _apply_visibility() -> void:
	if glow == null:
		return
	for i in bones.size():
		glow.set_tip_hidden(i, (_docked & (1 << i)) != 0)


## The fan, written as an ABSOLUTE skeleton-space basis (every write in this unit is one, see
## `Hero3LegIk.set_pose`), with the hidden blades' basis scaled away on top.
func _apply_fan() -> void:
	for i in bones.size():
		var idx := skeleton.find_bone(bones[i])
		if idx < 0:
			continue
		var rest := skeleton.get_bone_global_rest(idx)
		var swing := Quaternion(Vector3.UP, deg_to_rad(FAN_DEG[i] * _fan))
		var basis := Basis(rest.basis.get_rotation_quaternion() * swing)
		if (_docked & (1 << i)) != 0:
			basis = basis.scaled(Vector3.ONE * HIDDEN_SCALE)
		# the FK origin, not the rest origin: see Hero3LegIk.set_pose for why
		skeleton.set_bone_global_pose(idx, Transform3D(basis,
				skeleton.get_bone_global_pose(idx).origin))


func report() -> Dictionary:
	return {"fan": snappedf(_fan, 0.01), "docked": _docked,
			"hidden": "%d/7" % _count_bits(_docked)}


static func _count_bits(mask: int) -> int:
	var n := 0
	for i in 7:
		if (mask & (1 << i)) != 0:
			n += 1
	return n
