class_name Hero3ClipPlayer
extends RefCounted
## Plays the Tianshu mech's authored action clips (hero-v3, brief step 3 / lead r3 block B).
##
## The clips are DATA, not AnimationPlayer tracks: `blender/hero3/anims/` would mean re-exporting a
## 26 MB GLB for every timing change, and this rig already writes every bone procedurally through
## `Hero3LegIk`. So a clip is a list of `{bone, keys}` rows, each key `[frame, euler.x, euler.y,
## euler.z]`, authored in FRAMES at 60 fps so a melee clip lines up with `melee_table.gd` by reading.
##
## Two layers, and the difference is only which bones a clip names:
##   * `UPPER` clips (fire, guard, melee, the skill casts) drive the arms and the chest; the gait
##     keeps the legs and `Hero3Posture` keeps everything the clip does not name.
##   * `FULL` clips (dash, jump, land, hits, death) also name the legs and the root.
## Either way the player writes LAST, so a clip simply overrides the bones it owns.
##
## Three rules the lead's r4 review pinned down, all of them about LETTING GO:
##   1. Past the last frame the weight ONLY FALLS. The first version added `delta / _blend` and then
##      subtracted the same amount, so it parked at `1 - delta/_blend` (0.72 at a 0.06 s blend)
##      forever: after one melee the legs were frozen and the spine kept writing its last key over
##      the aim chain for the rest of the session (r4 item 1, `probe_release.gd`).
##   2. `stop()` starts the fade NOW, so a looping clip the game turns off does not play on to its
##      last frame first.
##   3. `hold` sits on the last frame at full weight until `stop_action` -- that is what a death is.

const FPS := 60.0
## The euler a bone returns to when a clip is not driving it: the held combat-ready pose for the arm
## chain, the exported rest for everything else.
const BLEND_DEFAULT := 0.08
## A blend of zero still needs a finite window, or the fade-out divides by zero.
const MIN_BLEND := 0.01
## How far the blade tip is kept above the floor, and the span used to work out the flattest downward
## angle that still clears it. 12.5 m covers the 12 m of modelled steel with a little to spare.
const BLADE_CLEARANCE := 0.40
const BLADE_SPAN := 12.5
## How many frames the blade takes to swing its azimuth from the held pose onto the radial line.
const BLADE_RAMP := 2.0

var skeleton: Skeleton3D
var ik: Hero3LegIk
## The posture, so `apply()` can put the held arm pose back on the bones this clip does not own.
var posture: Hero3Posture = null
## Where the saber points with `R_Hand` at euler zero, in skeleton space (`Hero3Rig.blade_rest`).
var blade_rest: Vector3 = Vector3(0.0, -1.0, 0.0)
var clips: Dictionary = {}

var _id: StringName = &""
var _clip: Dictionary = {}
var _frame: float = 0.0
var _weight: float = 0.0
var _blend: float = BLEND_DEFAULT
## `loop` wraps the frame counter forever (hover, fly, gatling_spin); `hold` stops on the last frame
## and stays there (death). Neither one ends on its own -- only `stop()` ends them.
var _loop: bool = false
var _hold: bool = false
var _releasing: bool = false
## A loop clip's cycle starts here, not at frame 0: frames [0, loop_from) are the ENTRY, authored to
## start from the pose the mech is actually in. Without it a loop clip can only reach its pose through
## the blend window, so guard_up -> catch_hold threw the hand 0.67 m in a single frame -- faster than
## either guard's own motion (lead r4 item 4).
var _loop_from: float = 0.0
## Frames of ENTRY ramp: over these the clip eases from the snapshot to its own pose at frame
## `entry`, whatever the mech happened to be doing. An authored frame-0 key cannot do this -- it only
## knows one starting pose, so cutting guard_up four frames into its own raise threw the hand at the
## finished guard (lead r4 item 4).
var _entry: float = 0.0
## The pose each owned bone was in when this clip started, so a chained swing blends out of WHERE THE
## ARM IS rather than out of the ready pose (lead r4 item 4). Without it, melee_l1 -> l2 at its cancel
## frame threw the hand 7.55 m in one frame -- faster than either swing.
var _snapshot: Dictionary = {}
## The bones the OUTGOING clip owned and this one does not. They are not the new clip's business, but
## they cannot be dropped on the floor either: the posture would take them back on the very next
## tick, which is a one-frame snap (guard_up names Spine02 and L_Clavicle, catch_hold does not).
## They fade to the posture over the same window the new clip fades in over.
var _handover: Dictionary = {}
## bone -> the offset this player applied to it last frame, for the LAYERED bones. Two offset clips cut
## into each other (charge_r -> fire_r) have to cross-fade their offsets, not snap from one to the
## other: an offset of zero means "the posture's pose", which is not where the arm was.
var _applied: Dictionary = {}
## Where the blade pointed when this clip started, so it eases in rather than snapping.
var _blade_from: Vector3 = Vector3(0.0, 0.0, -1.0)
var _outgoing: Dictionary = {}


func setup(skeleton_: Skeleton3D, ik_: Hero3LegIk) -> void:
	skeleton = skeleton_
	ik = ik_


## Remember where the blade points right now, so a clip that takes the wrist over eases out of it.
func _capture_blade() -> void:
	if skeleton == null:
		return
	var idx := skeleton.find_bone("R_Hand")
	if idx < 0:
		return
	_blade_from = (skeleton.get_bone_global_pose(idx).basis * blade_rest).normalized()


func has(id: StringName) -> bool:
	return clips.has(id)


func length_of(id: StringName) -> float:
	return float(clips.get(id, {}).get("length", 0.0))


func playing() -> bool:
	return not _clip.is_empty()


func current() -> StringName:
	return _id


func weight() -> float:
	return _weight


## Start a clip and return its length in seconds, or 0.0 when the id is unknown. The caller
## (`Hero3Model.play_action`) reports the gap rather than pretending, which is what the switch gate
## measures.
func play(id: StringName, blend: float = BLEND_DEFAULT) -> float:
	if not clips.has(id):
		return 0.0
	var outgoing: Array[String] = []
	for bone_name: String in _clip.get("bones", {}):
		outgoing.append(bone_name)
	_snapshot_pose(clips[id], outgoing)
	_outgoing = _applied.duplicate()
	_capture_blade()
	_clip = clips[id]
	_id = id
	_frame = 0.0
	_blend = maxf(blend, MIN_BLEND)
	_loop = bool(_clip.get("loop", false))
	_loop_from = clampf(float(_clip.get("loop_from", 0.0)), 0.0, maxf(float(_clip["frames"]) - 1.0, 0.0))
	_entry = clampf(float(_clip.get("entry", 0.0)), 0.0, maxf(float(_clip["frames"]) - 1.0, 0.0))
	_hold = bool(_clip.get("hold", false))
	_releasing = false
	_weight = 0.0
	return float(_clip["length"])


## Fade out at once. The game calls this when a guard ends and when the gatling spins down (the lead
## wires those at the switch), and it is the only way a `loop` or a `hold` clip ever ends.
func stop() -> void:
	_loop = false
	_hold = false
	if _clip.is_empty():
		return
	_releasing = true


## Advance the clip clock and the blend weight.
##
## The weight has exactly two directions and never both in one tick: it rises while the clip is
## running and it falls once the clip is over or has been stopped. Adding and subtracting in the same
## tick is what parked it just under 1 forever (lead r4 item 1).
func update(delta: float) -> void:
	if _clip.is_empty():
		return
	if _releasing:
		_weight = maxf(_weight - delta / _blend, 0.0)
		if _weight <= 0.0:
			_release()
		return
	var frames := float(_clip["frames"])
	if _loop:
		_frame += delta * FPS
		if _frame >= frames:
			_frame = _loop_from + (_frame - frames)
		_weight = minf(_weight + delta / _blend, 1.0)
		return
	if _hold:
		# a held clip sits on its last frame at full weight: death has to stay dead
		_frame = minf(_frame + delta * FPS, frames)
		_weight = minf(_weight + delta / _blend, 1.0)
		return
	_frame += delta * FPS
	if _frame < frames:
		_weight = minf(_weight + delta / _blend, 1.0)
		return
	_frame = frames
	_releasing = true
	_weight = maxf(_weight - delta / _blend, 0.0)
	if _weight <= 0.0:
		_release()


## Let go of every bone: from here the gait and the posture own the whole rig again.
func _release() -> void:
	_clip = {}
	_id = &""
	_weight = 0.0
	_releasing = false
	_snapshot.clear()
	_handover.clear()
	_applied.clear()
	_outgoing.clear()


## True while this bone belongs to the clip rather than to the posture or the gait.
func owns(bone_name: String) -> bool:
	return _weight > 0.0 and _clip.has("bones") and _clip["bones"].has(bone_name)


# --- the root and the feet (lead r4 item 3) ------------------------------------------------------
#
# A FULL clip drives the ROOT and the FEET, never the leg bones. FK keys on the thighs and calves with
# the pelvis at standing height folded the legs up and lifted both feet off the floor: death hung in
# the air with its lower ankle at 5.6 m, hit_knockdown at 4.2 m. `Hero3Gait` reads these targets and
# solves the legs through `Hero3LegIk`, so the soles are on the floor BY CONSTRUCTION.

## 0 unless a clip that owns the feet is playing, and then its blend weight.
func stance_weight() -> float:
	if _clip.is_empty() or not _clip.has("feet"):
		return 0.0
	return _blend_weight()


## 0 unless a clip that owns the root is playing.
func root_weight() -> float:
	if _clip.is_empty() or not _clip.has("root"):
		return 0.0
	return _blend_weight()


## What the clip asks of the root, RAW: `[Vector3 offset, pelvis pitch, pelvis roll]`. The offset is
## in metres added to the root's rest origin, so a negative y is a crouch. Empty when the clip has no
## root track.
func root_pose() -> Array:
	var keys: Array = _clip.get("root", [])
	if keys.is_empty():
		return []
	var key := _sample_key(keys, _entry_frame())
	if key.size() < 6:
		return []
	return [Vector3(float(key[1]), float(key[2]), float(key[3])),
			float(key[4]), float(key[5])]


## Where this side's SOLE belongs, in MODEL space relative to the model origin (which sits between
## the feet at y = 0), or `Vector3.INF` when the clip does not name that side. Model space, not world:
## the targets travel with the mech, exactly as the skate's do.
func foot_target(side: String) -> Vector3:
	var feet: Dictionary = _clip.get("feet", {})
	var keys: Array = feet.get(side, [])
	if keys.is_empty():
		return Vector3.INF
	var key := _sample_key(keys, _entry_frame())
	if key.size() < 4:
		return Vector3.INF
	return Vector3(float(key[1]), float(key[2]), float(key[3]))


## Write every bone the playing clip owns. Called LAST, after the gait and the posture, so a clip
## overrides rather than fights.
func apply() -> void:
	if _clip.is_empty() or _weight <= 0.0:
		return
	var bones: Dictionary = _clip["bones"]
	var writes := {}
	_applied.clear()
	for bone_name: String in bones:
		writes[bone_name] = _basis_for(bone_name, _sample(bones[bone_name], _entry_frame()))
	for bone_name: String in _handover:
		if not bones.has(bone_name):
			writes[bone_name] = Basis.from_euler(
					(_handover[bone_name] as Vector3).lerp(_base(bone_name), 1.0 - _weight))
	for bone_name in _under_owned(bones):
		# the posture's OWN basis, verbatim: this bone is not the clip's business, it just has to be
		# rewritten because the clip moved its parents
		writes[bone_name] = posture.written.get(bone_name,
				Basis.from_euler(posture.ready_euler(bone_name)))
	# Parent bones first, in ONE pass. `set_bone_global_pose` resolves against the parent AT THE MOMENT
	# OF THE CALL, so a bone written before its parent lands a frame stale -- and a second pass over
	# the held arm pose would move the clip's own bones instead.
	var order: Array = writes.keys()
	order.sort_custom(func(a: String, b: String) -> bool:
			return skeleton.find_bone(a) < skeleton.find_bone(b))
	for bone_name: String in order:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			push_warning("Hero3ClipPlayer: clip %s wants missing bone %s" % [_id, bone_name])
			continue
		ik.set_basis(idx, writes[bone_name] * ik.rest_of(bone_name).basis)
		skeleton.force_update_all_bone_transforms()
	_aim_blade()


## A melee clip carries `"elev"`: the blade's ELEVATION above horizontal, in degrees, keyed per
## frame. Its azimuth is not authored at all -- it always points radially outward from the mech's
## vertical axis through the hand -- and inside the `"blade": [from, to]` window the elevation is
## forced to zero and the whole direction is laid into the swing plane `tilt` degrees leans.
##
## This is what makes the visible blade cover the hitbox (lead r4 item 7). An authored wrist angle
## sweeps the blade TANGENTIALLY: the steel tip sat 7.0-9.4 m from the axis while `melee_table.gd`'s
## reach is 16-22 m, so everything from 11 to 20 m out was cut by thin air. It also keeps the tip's
## azimuth stable -- a blade raised straight up in the wind-up has almost no horizontal radius, and
## its azimuth spins through 300 deg of nonsense while the arm is still winding up.
func _aim_blade() -> void:
	if not _clip.has("elev"):
		return
	var idx := skeleton.find_bone("R_Hand")
	if idx < 0:
		return
	var hand := skeleton.get_bone_global_pose(idx).origin
	var radial := Vector3(hand.x, 0.0, hand.z)
	if radial.length() < 0.5:
		return
	radial = radial.normalized()
	var held := _ready_blade()
	var held_az := Vector3(held.x, 0.0, held.z)
	held_az = held_az.normalized() if held_az.length() > 1e-4 else Vector3.FORWARD
	# The azimuth only becomes RADIAL inside the active window. Everywhere else the blade keeps the
	# held pose's azimuth and the `"elev"` track raises and lowers it, which is what a wind-up looks
	# like -- and it keeps the swing inside the window instead of smearing the tip's azimuth across
	# the approach and the recovery.
	var w := _blade_window()
	var az := held_az.slerp(radial, w).normalized()
	var tangent := Vector3.UP.cross(az).normalized()
	var elev := lerpf(_sample_scalar(_clip["elev"], _frame), 0.0, w)
	var dir := az.rotated(tangent, deg_to_rad(elev)) \
			.rotated(tangent, deg_to_rad(float(_clip.get("tilt", 0.0)) * w))
	# never into the floor: a 12 m blade swung from a hand at 8 m has only so much downward angle
	# before the steel goes through the ground, and the gate says no saber vertex may be below it
	var floor_y := (BLADE_CLEARANCE - hand.y) / BLADE_SPAN
	if dir.y < floor_y:
		dir.y = floor_y
		dir = dir.normalized()
	var rest := ik.rest_of("R_Hand").basis
	ik.set_basis(idx, Basis(Quaternion(blade_rest, dir.normalized())) * rest)
	skeleton.force_update_all_bone_transforms()


## Where the held pose points the blade, so a clip can carry it and hand it back.
func _ready_blade() -> Vector3:
	for row: Dictionary in Hero3Posture.READY_POSE:
		if String(row["bone"]) == "R_Hand":
			return (Basis.from_euler(row["euler"]) * blade_rest).normalized()
	return Vector3(0.0, 0.0, -1.0)


## 1 inside the active window, ramping over one frame at each edge, so the blade eases into and out of
## the swing plane instead of snapping to it.
func _blade_window() -> float:
	if not _clip.has("blade"):
		return 0.0
	var window: Array = _clip["blade"]
	# The ramp happens BEFORE `from` and AFTER `to`, so the blade is fully on the radial line for every
	# frame of the active window itself -- ramping inside it would pull the tip back toward the mech
	# on the frames the hitbox is live.
	return minf(clampf((_frame - float(window[0]) + BLADE_RAMP) / BLADE_RAMP, 0.0, 1.0),
			clampf((float(window[1]) + BLADE_RAMP - _frame) / BLADE_RAMP, 0.0, 1.0))


## A `[frame, value]` track: the blade's elevation, and anything else that is one number per frame.
func _sample_scalar(keys: Array, frame: float) -> float:
	if keys.is_empty():
		return 0.0
	var first: Array = keys[0]
	if frame <= float(first[0]):
		return float(first[1])
	var last: Array = keys[keys.size() - 1]
	if frame >= float(last[0]):
		return float(last[1])
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if frame <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			var k := 0.0 if span <= 0.0 else (frame - float(a[0])) / span
			return lerpf(float(a[1]), float(b[1]), k)
	return float(last[1])


## The basis for one of the clip's own bones.
##
## A LAYERED bone (the spine chain always, the arms when the clip says `"offset": true`) takes the
## posture's basis with the clip's euler applied on the LEFT of it, faded in with the weight -- so a
## flinch or a recoil rides on the aim instead of replacing it. Anything else is a pose of its own,
## blended out of the snapshot the clip started from (lead r4 items 4 and 6).
func _basis_for(bone_name: String, euler: Vector3) -> Basis:
	if not _layered(bone_name):
		var from: Vector3 = _snapshot.get(bone_name, _base(bone_name))
		return Basis.from_euler(euler.lerp(from, 1.0 - _blend_weight()))
	# The convention everywhere in this unit is `bone_basis = R(euler) * rest`, so the offset goes on
	# the LEFT of the posture's basis -- `base * R(euler)` would rotate the bone about its own head in
	# the rest frame instead, which is a different rotation entirely.
	var offset: Vector3 = (_outgoing.get(bone_name, Vector3.ZERO) as Vector3) \
			.lerp(euler, _offset_weight())
	_applied[bone_name] = offset
	return Basis.from_euler(offset) * (posture.written[bone_name] as Basis)


## Is this bone's clip key an OFFSET on the posture rather than a pose of its own?
##
## The spine chain always is (lead r4 item 6): a clip's spine keys are a flinch or a twist, and the
## aim and the counter-rotation have to survive them. An arm key is an offset when the clip says
## `"offset": true` -- a weapon clip's recoil layers on top of the aimed arms -- and a pose otherwise,
## which is what a melee swing needs.
func _layered(bone_name: String) -> bool:
	if posture == null or not posture.written.has(bone_name):
		return false
	if Hero3Posture.LAYERED.has(bone_name):
		return true
	return bool(_clip.get("offset", false)) and Hero3Aim.ARM_BONES.has(bone_name)


## The held-pose bones that sit UNDER a bone this clip owns. They have to be rewritten after it, in the
## same pass: a clip that writes Spine02 and R_Upperarm moves R_Hand -- and the 12 m blade on it --
## 43 deg off, which is how hit_knockdown put the saber tip 1.8 m under the floor (lead r4 item 7).
func _under_owned(bones: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if posture == null:
		return out
	for row: Dictionary in Hero3Posture.READY_POSE:
		var bone_name := String(row["bone"])
		if bones.has(bone_name):
			continue
		var idx := skeleton.find_bone(bone_name)
		var parent := skeleton.get_bone_parent(idx) if idx >= 0 else -1
		while parent >= 0:
			if bones.has(skeleton.get_bone_name(parent)):
				out.append(bone_name)
				break
			parent = skeleton.get_bone_parent(parent)
	return out


## How far a LAYERED offset has travelled from the outgoing clip's offset to this clip's own.
##
## Inside an entry ramp that is the RAMP's progress, not the blend weight: the blend window is for
## POSES, and an offset that cross-faded over 0.06 s out-ran the recoil it was supposed to be easing
## into -- charge_r -> fire_r moved the hand 0.74 m in a frame against fire_r's own 0.68 m.
func _offset_weight() -> float:
	if _entry > 0.0 and _frame < _entry:
		return _frame / _entry
	return _weight


## Which key the clip is read at. Inside the entry ramp that is always the END of the ramp: the ramp
## is a straight line from the snapshot to the pose the clip holds, so the in-between is supplied by
## the weight rather than by the authored keys.
func _entry_frame() -> float:
	return maxf(_frame, _entry)


## How far the clip has taken the bone from the snapshot: the blend weight normally, and the entry
## ramp's own progress while the ramp is still running (whichever is smaller).
func _blend_weight() -> float:
	if _entry > 0.0 and _frame < _entry:
		return minf(_weight, _frame / _entry)
	return _weight


## Remember where every bone this clip owns is RIGHT NOW, so the blend-in starts from the pose the
## mech is actually in. Chained combos are the reason: melee_l1 -> l2 at l1's cancel frame used to
## snap the hand back toward the ready pose and then out into the new swing, on the exact frame the
## player pressed the button (lead r4 item 4, `probe_idle_chain.gd`).
func _snapshot_pose(clip: Dictionary, outgoing: Array[String]) -> void:
	_snapshot.clear()
	_handover.clear()
	if skeleton == null:
		return
	var wanted := {}
	for bone_name: String in clip.get("bones", {}):
		wanted[bone_name] = false
	for bone_name in outgoing:
		if not wanted.has(bone_name):
			wanted[bone_name] = true
	for bone_name: String in wanted:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		var rest := ik.rest_of(bone_name).basis
		var euler := (skeleton.get_bone_global_pose(idx).basis * rest.inverse()).get_euler()
		if bool(wanted[bone_name]):
			_handover[bone_name] = euler
		else:
			_snapshot[bone_name] = euler


## The euler at `frame` on one track, linearly interpolated between the surrounding keys.
func _sample(keys: Array, frame: float) -> Vector3:
	var key := _sample_key(keys, frame)
	return Vector3.ZERO if key.is_empty() else _euler(key)


## The whole key at `frame`, element-wise interpolated: a bone key is `[frame, x, y, z]`, a root key
## is `[frame, dx, dy, dz, pitch, roll]`, a foot key is `[frame, x, y, z]`.
func _sample_key(keys: Array, frame: float) -> Array:
	if keys.is_empty():
		return []
	var first: Array = keys[0]
	if frame <= float(first[0]):
		return first
	var last: Array = keys[keys.size() - 1]
	if frame >= float(last[0]):
		return last
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if frame <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			var k := 0.0 if span <= 0.0 else (frame - float(a[0])) / span
			return _lerp_key(a, b, k)
	return last


func _lerp_key(a: Array, b: Array, k: float) -> Array:
	var out := a.duplicate()
	for i in range(1, a.size()):
		out[i] = lerpf(float(a[i]), float(b[i]), k)
	return out


func _euler(key: Array) -> Vector3:
	return Vector3(float(key[1]), float(key[2]), float(key[3]))


## Where a bone sits when no clip drives it, and the fallback blend source for a bone the skeleton
## does not have (so a missing bone cannot silently snap to zero).
func _base(bone_name: String) -> Vector3:
	for row: Dictionary in Hero3Posture.READY_POSE:
		if String(row["bone"]) == bone_name:
			return row["euler"]
	return Vector3.ZERO
