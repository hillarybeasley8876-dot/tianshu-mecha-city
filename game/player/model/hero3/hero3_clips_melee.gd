class_name Hero3ClipsMelee
extends RefCounted
## The melee clips (hero-v3, lead r3 block B item B3).
##
## Every frame count here is `melee_table.gd`'s, and `tests/test_hero3_melee.gd` asserts they still
## agree -- the table is the combat truth and this file only decides what the mech LOOKS like while
## it happens. The shape of a swing is:
##
##   frames [0, startup]        anticipation: the chest and arm wind up AWAY from the swing, mostly
##                              by raising the blade, so the horizontal sweep barely moves
##   frames [startup+1, +active] the committed swing: the chest untwists and the shoulder crosses,
##                              which is where the whole sweep angle lives
##   frames [.., frames]        a held follow-through, then a settle back toward the guard
##
## The blade is bone-attached to `R_Hand` (`saber_r`), so it never leaves the hand: there is no
## second blade to place and nothing to teleport along an arc.

const L1 := &"melee_l1"
const L2 := &"melee_l2"
const L3 := &"melee_l3"
const LUNGE := &"lunge"
const CHARGE_SLASH := &"charge_slash"
const AIR_L1 := &"air_l1"
const AIR_L2 := &"air_l2"
const RETURN_CUT := &"return_cut"
const RAM_KICK := &"ram_kick"
const EXECUTION := &"execution"
## The blade's elevation above horizontal, in degrees: carried at the guard, raised over the shoulder
## in the wind-up, flat through the swing. `Hero3ClipPlayer._aim_blade` owns the azimuth.
const GUARD_ELEV := 15.0
const RAISED_ELEV := 55.0

static func all() -> Array:
	return [
	_slash(L1, 29.0, 9.0, 4.0, 1.0, 1.00),
	_slash(L2, 28.0, 8.0, 4.0, -1.0, 1.00),
	_slash(L3, 48.0, 14.0, 6.0, 1.0, 1.45),
	_slash(AIR_L1, 26.0, 8.0, 4.0, 1.0, 0.90),
	_slash(AIR_L2, 26.0, 8.0, 4.0, -1.0, 1.05),
	_slash(RETURN_CUT, 32.0, 6.0, 6.0, -1.0, 1.30),
	_slash(CHARGE_SLASH, 48.0, 10.0, 8.0, 1.0, 1.55),
	_thrust(LUNGE, 60.0, 6.0, 42.0),
	_kick(RAM_KICK, 32.0, 6.0, 6.0),
	_execution(EXECUTION, 96.0),
]


## The swing plane's tilt for this move, straight from `melee_table.gd` so the animation and the
## hitbox cannot drift apart.
static func _tilt(id: StringName) -> float:
	var table := load("res://combat/melee/melee_table.gd") as GDScript
	return table.tilt_deg(id) if table != null else 0.0


## A horizontal slash. `dir` is +1 for a right-to-left swing and -1 for the mirror; `power` scales
## the arc, from a light 120 deg jab to the charged 210 deg sweep.
##
## Every bone in a chain gets the SAME shoulder rotation plus its own small delta, because a clip
## writes ABSOLUTE world bases (`Basis.from_euler(euler) * rest`, the convention `READY_POSE` uses)
## rather than local ones: a bone does not inherit its parent's rotation, so an arm that raised
## without raising its forearm would come apart at the elbow.
##
## `up` puts the arm over the shoulder -- the rest pose hangs it 64 deg below horizontal, so a Y
## rotation on its own only spins the arm about its own axis and the tip barely moves. `across` is
## the same arm swung forward and over, and the difference between the two yaws IS the sweep.
static func _slash(id: StringName, frames: float, startup: float, active: float, dir: float,
		power: float) -> Dictionary:
	var wind := startup
	var hit := startup + active
	var s := dir
	var guard := Vector3(-0.28, 0.0, -0.16)
	var up := Vector3(-1.75, -0.55 * s * power, 0.0)
	# The across-yaw is 0.80 of what it was: at the full 1.90 the gauntlet plate crossed the
	# forearm plate by 0.198 m at the follow-through (lead r5 item 9, `tests/probe_clear.gd`).
	var across := Vector3(-1.15, 1.52 * s * power, 0.0)
	var elbow_guard := Vector3(-0.14, 0.0, 0.0)
	var elbow_up := Vector3(-0.55, 0.0, 0.0)
	var elbow_across := Vector3(-0.10, 0.0, 0.0)
	# The WRIST is not keyed at all: `Hero3ClipPlayer._aim_blade` points the blade radially outward
	# from the hand for the whole clip and the `"elev"` track gives its elevation. An authored wrist
	# angle can only sweep the blade TANGENTIALLY, which put the steel tip 7-9 m from the axis while
	# the hitbox reaches 16-22 m (lead r4 item 7).
	# the left arm counterbalances: a third of the swing, mirrored, so the mech does not windmill
	var l_guard := Vector3(-0.24, 0.0, 0.16)
	var l_up := Vector3(-0.70, -0.20 * s, 0.30)
	var l_across := Vector3(-0.45, 0.65 * s, 0.10)
	return {
		"id": id, "frames": frames, "layer": &"upper",
		"startup": startup, "active": active, "recovery": frames - startup - active,
		# The blade points radially OUTWARD for the whole active window, so the visible steel covers
		# the hitbox radius instead of sweeping tangentially across it (lead r4 item 7). `tilt` is the
		# swing plane from `melee_table.gd`; the hand's azimuth is read at run time.
		"blade": [wind + 1.0, hit + 1.0], "tilt": _tilt(id),
		"elev": [[0, GUARD_ELEV], [wind, RAISED_ELEV], [wind + 1.0, RAISED_ELEV],
				[hit, 0.0], [hit + 1.0, 0.0], [frames, GUARD_ELEV]],
		"tracks": [
			Hero3Clips.track("Spine01", [
					Hero3Clips.key(0, Vector3.ZERO),
					Hero3Clips.key(wind, Vector3(-0.10, -0.30 * s * power, 0.0)),
					Hero3Clips.key(wind + 1.0, Vector3(-0.10, -0.30 * s * power, 0.0)),
					Hero3Clips.key(hit, Vector3(0.06, 0.34 * s * power, 0.0)),
					Hero3Clips.key(hit + 1.0, Vector3(0.06, 0.34 * s * power, 0.0)),
					Hero3Clips.key(frames, Vector3(0.0, 0.05 * s, 0.0))]),
			Hero3Clips.track("Spine02", [
					Hero3Clips.key(0, Vector3.ZERO),
					Hero3Clips.key(wind, Vector3(-0.08, -0.26 * s * power, 0.0)),
					Hero3Clips.key(wind + 1.0, Vector3(-0.08, -0.26 * s * power, 0.0)),
					Hero3Clips.key(hit, Vector3(0.05, 0.30 * s * power, 0.0)),
					Hero3Clips.key(hit + 1.0, Vector3(0.05, 0.30 * s * power, 0.0)),
					Hero3Clips.key(frames, Vector3(0.0, 0.04 * s, 0.0))]),
			Hero3Clips.track("R_Clavicle", [
					Hero3Clips.key(0, Vector3(0.0, -0.10, 0.0)),
					Hero3Clips.key(wind, up + Vector3(0.0, 0.10, 0.0)),
					Hero3Clips.key(wind + 1.0, up + Vector3(0.0, 0.10, 0.0)),
					Hero3Clips.key(hit, across + Vector3(0.0, 0.10, 0.0)),
					Hero3Clips.key(hit + 1.0, across + Vector3(0.0, 0.10, 0.0)),
					Hero3Clips.key(frames, Vector3(0.0, -0.10, 0.0))]),
			Hero3Clips.track("R_Upperarm", [
					Hero3Clips.key(0, guard), Hero3Clips.key(wind, up), Hero3Clips.key(wind + 1.0, up),
					Hero3Clips.key(hit, across), Hero3Clips.key(hit + 1.0, across),
					Hero3Clips.key(frames, guard)]),
			Hero3Clips.track("R_Forearm", [
					Hero3Clips.key(0, guard + elbow_guard),
					Hero3Clips.key(wind, up + elbow_up), Hero3Clips.key(wind + 1.0, up + elbow_up),
					Hero3Clips.key(hit, across + elbow_across),
					Hero3Clips.key(hit + 1.0, across + elbow_across),
					Hero3Clips.key(frames, guard + elbow_guard)]),
			Hero3Clips.track("L_Upperarm", [
					Hero3Clips.key(0, l_guard), Hero3Clips.key(wind, l_up), Hero3Clips.key(wind + 1.0, l_up),
					Hero3Clips.key(hit, l_across), Hero3Clips.key(hit + 1.0, l_across),
					Hero3Clips.key(frames, l_guard)]),
			Hero3Clips.track("L_Forearm", [
					Hero3Clips.key(0, l_guard + Vector3(-0.28, 0.0, 0.0)),
					Hero3Clips.key(wind, l_up + Vector3(-0.45, 0.0, 0.0)),
					Hero3Clips.key(wind + 1.0, l_up + Vector3(-0.45, 0.0, 0.0)),
					Hero3Clips.key(hit, l_across + Vector3(-0.20, 0.0, 0.0)),
					Hero3Clips.key(hit + 1.0, l_across + Vector3(-0.20, 0.0, 0.0)),
					Hero3Clips.key(frames, l_guard + Vector3(-0.28, 0.0, 0.0))]),
		],
	}


## The lunge is a THRUST, not a sweep: the arm drives straight forward and holds for the whole
## 42-frame active window while the mech covers 24-80 m. The blade's azimuth barely moves, which is
## correct -- the reach is the attack, not the arc.
static func _thrust(id: StringName, frames: float, startup: float, active: float) -> Dictionary:
	var wind := startup
	var hit := startup + 4.0
	var hold := startup + active
	# the pose is held one frame either side of the active window, so every degree of blade travel
	# lands inside it (see the sweep gate in tests/test_hero3_melee.gd)
	var release := wind + 1.0
	var settle := hold + 1.0
	return {
		"id": id, "frames": frames, "layer": &"upper",
		"startup": startup, "active": active, "recovery": frames - startup - active,
		"blade": [wind + 1.0, hold + 1.0], "tilt": _tilt(id),
		"elev": [[0, GUARD_ELEV], [wind, 8.0], [release, 8.0], [hit, 0.0], [hold, 0.0],
				[settle, 0.0], [frames, GUARD_ELEV]],
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [wind, 0.10, -0.22, 0.0], [release, 0.10, -0.22, 0.0],
					[hit, -0.14, 0.16, 0.0], [hold, -0.16, 0.18, 0.0], [settle, -0.16, 0.18, 0.0], [frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [wind, 0.08, -0.18, 0.0], [release, 0.08, -0.18, 0.0],
					[hit, -0.12, 0.14, 0.0], [hold, -0.14, 0.16, 0.0], [settle, -0.14, 0.16, 0.0], [frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Clavicle", [[0, 0.0, -0.10, 0.0], [wind, 0.0, -0.24, 0.0], [release, 0.0, -0.24, 0.0],
					[hit, 0.0, 0.06, 0.0], [hold, 0.0, 0.06, 0.0], [settle, 0.0, 0.06, 0.0], [frames, 0.0, -0.10, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [wind, -0.50, -0.20, -0.30], [release, -0.50, -0.20, -0.30],
					[hit, -1.32, 0.10, 0.06], [hold, -1.38, 0.10, 0.06], [settle, -1.38, 0.10, 0.06],
					[frames, -0.28, 0.0, -0.16]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [wind, -1.10, 0.0, 0.0], [release, -1.10, 0.0, 0.0],
					[hit, -0.08, 0.0, 0.0], [hold, -0.06, 0.0, 0.0], [settle, -0.06, 0.0, 0.0], [frames, -0.42, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [wind, -0.30, 0.0, 0.34], [release, -0.30, 0.0, 0.34],
					[hit, -0.55, 0.0, 0.20], [hold, -0.58, 0.0, 0.20], [settle, -0.58, 0.0, 0.20],
					[frames, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [wind, -0.80, 0.0, 0.0], [release, -0.80, 0.0, 0.0],
					[hit, -1.05, 0.0, 0.0], [hold, -1.05, 0.0, 0.0], [settle, -1.05, 0.0, 0.0], [frames, -0.52, 0.0, 0.0]]),
		],
	}


## The ram kick is a FULL clip: it takes the legs. The right leg chambers and drives forward through
## the active window, the left leg and the root take the recoil.
static func _kick(id: StringName, frames: float, startup: float, active: float) -> Dictionary:
	var wind := startup
	var hit := startup + active
	var release := wind + 1.0
	var settle := hit + 1.0
	# the blade sweeps down and across with the kick, using the same raised-arm shape as a slash so
	# the sweep lands inside the active window instead of smearing into the recovery
	var guard := Vector3(-0.28, 0.0, -0.16)
	var up := Vector3(-1.20, -0.30, 0.0)
	var across := Vector3(-0.85, 1.05, 0.0)
	return {
		"id": id, "frames": frames, "layer": &"full",
		"startup": startup, "active": active, "recovery": frames - startup - active,
		# The root takes the drive and the recoil; the SUPPORT leg is a foot target so its sole stays
		# on the floor. Only the KICKING leg keeps FK keys, which is the one place the lead allows
		# them (lead r4 item 3): a leg in the air is a pose, not something to solve for.
		"blade": [wind + 1.0, hit + 1.0], "tilt": _tilt(id),
		"elev": [[0, GUARD_ELEV], [wind, 30.0], [release, 30.0], [hit, 0.0], [settle, 0.0],
				[frames, GUARD_ELEV]],
		"root": [[0, 0.0, 0.0, 0.0, 0.0, 0.0], [wind, 0.0, -0.45, 0.0, 0.10, 0.0],
				[release, 0.0, -0.45, 0.0, 0.10, 0.0], [hit, 0.0, -0.20, 0.0, -0.22, 0.0],
				[settle, 0.0, -0.20, 0.0, -0.22, 0.0], [frames, 0.0, 0.0, 0.0, 0.0, 0.0]],
		"feet": {"L": [[0, -2.13, 0.0, -0.40], [wind, -2.20, 0.0, 0.55],
				[release, -2.20, 0.0, 0.55], [hit, -2.30, 0.0, 1.40],
				[settle, -2.30, 0.0, 1.40], [frames, -2.13, 0.0, -0.40]]},
		"tracks": [
			Hero3Clips.track("Spine01", [
					Hero3Clips.key(0, Vector3.ZERO), Hero3Clips.key(wind, Vector3(0.12, -0.14, 0.0)),
					Hero3Clips.key(release, Vector3(0.12, -0.14, 0.0)),
					Hero3Clips.key(hit, Vector3(-0.16, 0.16, 0.0)),
					Hero3Clips.key(settle, Vector3(-0.16, 0.16, 0.0)),
					Hero3Clips.key(frames, Vector3.ZERO)]),
			Hero3Clips.track("Spine02", [
					Hero3Clips.key(0, Vector3.ZERO), Hero3Clips.key(wind, Vector3(0.10, -0.12, 0.0)),
					Hero3Clips.key(release, Vector3(0.10, -0.12, 0.0)),
					Hero3Clips.key(hit, Vector3(-0.13, 0.14, 0.0)),
					Hero3Clips.key(settle, Vector3(-0.13, 0.14, 0.0)),
					Hero3Clips.key(frames, Vector3.ZERO)]),
			Hero3Clips.track("R_Upperarm", [
					Hero3Clips.key(0, guard), Hero3Clips.key(wind, up),
					Hero3Clips.key(release, up), Hero3Clips.key(hit, across),
					Hero3Clips.key(settle, across), Hero3Clips.key(frames, guard)]),
			Hero3Clips.track("R_Forearm", [
					Hero3Clips.key(0, guard + Vector3(-0.14, 0.0, 0.0)),
					Hero3Clips.key(wind, up + Vector3(-0.45, 0.0, 0.0)),
					Hero3Clips.key(release, up + Vector3(-0.45, 0.0, 0.0)),
					Hero3Clips.key(hit, across + Vector3(-0.10, 0.0, 0.0)),
					Hero3Clips.key(settle, across + Vector3(-0.10, 0.0, 0.0)),
					Hero3Clips.key(frames, guard + Vector3(-0.14, 0.0, 0.0))]),
			Hero3Clips.track("R_Thigh", [
					Hero3Clips.key(0, Vector3.ZERO), Hero3Clips.key(wind, Vector3(0.70, 0.0, 0.10)),
					Hero3Clips.key(release, Vector3(0.70, 0.0, 0.10)),
					Hero3Clips.key(hit, Vector3(-0.85, 0.0, 0.06)),
					Hero3Clips.key(settle, Vector3(-0.85, 0.0, 0.06)),
					Hero3Clips.key(frames, Vector3.ZERO)]),
			Hero3Clips.track("R_Calf", [
					Hero3Clips.key(0, Vector3.ZERO), Hero3Clips.key(wind, Vector3(1.15, 0.0, 0.0)),
					Hero3Clips.key(release, Vector3(1.15, 0.0, 0.0)),
					Hero3Clips.key(hit, Vector3(0.12, 0.0, 0.0)),
					Hero3Clips.key(settle, Vector3(0.12, 0.0, 0.0)),
					Hero3Clips.key(frames, Vector3.ZERO)]),
			Hero3Clips.track("R_Foot", [
					Hero3Clips.key(0, Vector3.ZERO), Hero3Clips.key(wind, Vector3(-0.35, 0.0, 0.0)),
					Hero3Clips.key(release, Vector3(-0.35, 0.0, 0.0)),
					Hero3Clips.key(hit, Vector3(0.30, 0.0, 0.0)),
					Hero3Clips.key(settle, Vector3(0.30, 0.0, 0.0)),
					Hero3Clips.key(frames, Vector3.ZERO)]),
			Hero3Clips.track("L_Upperarm", [
					Hero3Clips.key(0, Vector3(-0.24, 0.0, 0.16)),
					Hero3Clips.key(wind, Vector3(-0.55, -0.10, 0.34)),
					Hero3Clips.key(release, Vector3(-0.55, -0.10, 0.34)),
					Hero3Clips.key(hit, Vector3(-0.40, 0.30, 0.12)),
					Hero3Clips.key(settle, Vector3(-0.40, 0.30, 0.12)),
					Hero3Clips.key(frames, Vector3(-0.24, 0.0, 0.16))]),
		],
	}


## The execution is a long two-handed overhead: raise, hold, drive down, hold, recover.
static func _execution(id: StringName, frames: float) -> Dictionary:
	return {
		"id": id, "frames": frames, "layer": &"upper",
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [24, -0.24, 0.0, 0.0],
					[40, -0.30, 0.0, 0.0], [46, 0.34, 0.0, 0.0], [70, 0.30, 0.0, 0.0],
					[frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [24, -0.20, 0.0, 0.0],
					[40, -0.26, 0.0, 0.0], [46, 0.30, 0.0, 0.0], [70, 0.26, 0.0, 0.0],
					[frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Clavicle", [[0, 0.0, -0.10, 0.0], [40, 0.0, -0.24, 0.0],
					[46, 0.0, 0.04, 0.0], [frames, 0.0, -0.10, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [24, -1.55, 0.0, -0.10],
					[40, -1.85, 0.0, -0.06], [46, 0.30, 0.0, 0.02], [70, 0.26, 0.0, 0.02],
					[frames, -0.28, 0.0, -0.16]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [40, -0.95, 0.0, 0.0],
					[46, -0.10, 0.0, 0.0], [70, -0.14, 0.0, 0.0], [frames, -0.42, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [40, -1.60, 0.0, 0.08],
					[46, 0.24, 0.0, 0.04], [70, 0.20, 0.0, 0.04], [frames, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [40, -1.00, 0.0, 0.0],
					[46, -0.20, 0.0, 0.0], [frames, -0.52, 0.0, 0.0]]),
		],
	}

