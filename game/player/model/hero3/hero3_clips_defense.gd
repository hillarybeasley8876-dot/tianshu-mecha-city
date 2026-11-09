class_name Hero3ClipsDefense
extends RefCounted
## The defensive clips (hero-v3, lead r3 block B). All upper-body: the guard is held while the legs
## keep walking, which is what a mech does and what a person's flailing arms never did.

const GUARD_UP := &"guard_up"
const PARRY := &"parry"
const CATCH_HOLD := &"catch_hold"
const CATCH_RELEASE := &"catch_release"
const WARD := &"ward"

static func all() -> Array:
	return [
	{
		## Frames [0, 10) are the ENTRY: the guard comes up from `Hero3Posture.READY_POSE` at an authored
		## speed instead of being dragged there by the 0.05 s blend window, and the loop proper starts
		## at `loop_from` (lead r4 item 4).
		"id": GUARD_UP, "frames": 24.0, "layer": &"upper", "loop": true, "loop_from": 10.0,
		"entry": 10.0,
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [10, 0.10, 0.16, 0.0],
					[24, 0.10, 0.16, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [10, 0.08, 0.14, 0.0],
					[24, 0.08, 0.14, 0.0]]),
			Hero3Clips.track("L_Clavicle", [[0, 0.0, 0.10, 0.0], [10, 0.0, 0.24, 0.0],
					[24, 0.0, 0.24, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [10, -0.95, 0.0, 0.42],
					[24, -0.95, 0.0, 0.42]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [10, -1.04, 0.0, 0.0],
					[24, -1.04, 0.0, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.06], [10, -0.52, 0.0, -0.14],
					[24, -0.52, 0.0, -0.14]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [10, -1.05, 0.0, 0.0],
					[24, -1.05, 0.0, 0.0]]),
		],
	},
	{
		## A parry is played OUT OF A GUARD, so it is authored around the guard's own pose and its
		## wind-up is an entry ramp: the deflection is a short outward slap off the block, not a
		## wind-up from the ready pose (lead r4 item 4 -- a 5 m wind-up thrown in 4 frames moved the
		## hand faster than the parry itself). It ends back on the guard, which is where the mech is
		## still standing when the parry finishes.
		"id": PARRY, "frames": 20.0, "layer": &"upper", "entry": 4.0,
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.10, 0.16, 0.0], [4, 0.10, 0.40, 0.0],
					[9, 0.10, 0.02, 0.0], [20, 0.10, 0.16, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.08, 0.14, 0.0], [4, 0.08, 0.34, 0.0],
					[9, 0.08, 0.02, 0.0], [20, 0.08, 0.14, 0.0]]),
			Hero3Clips.track("L_Clavicle", [[0, 0.0, 0.24, 0.0], [4, 0.0, 0.38, 0.0],
					[20, 0.0, 0.24, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.95, 0.0, 0.42], [4, -1.18, 0.0, 0.64],
					[9, -0.82, 0.0, 0.32], [20, -0.95, 0.0, 0.42]]),
			Hero3Clips.track("L_Forearm", [[0, -1.30, 0.0, 0.0], [4, -1.48, 0.0, 0.0],
					[9, -1.14, 0.0, 0.0], [20, -1.30, 0.0, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.52, 0.0, -0.34], [4, -0.64, 0.0, -0.44],
					[20, -0.52, 0.0, -0.34]]),
			Hero3Clips.track("R_Forearm", [[0, -1.05, 0.0, 0.0], [20, -1.05, 0.0, 0.0]]),
		],
	},
	{
		## The entry starts on the GUARD's own pose, because a catch is what a guard turns into: both
		## arms open forward off the block. It also names Spine02 and L_Clavicle for the same reason --
		## a bone the guard drove and the catch does not would snap back to the posture in one frame.
		"id": CATCH_HOLD, "frames": 30.0, "layer": &"upper", "loop": true, "loop_from": 10.0,
		"entry": 10.0,
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.10, 0.16, 0.0], [10, -0.14, 0.0, 0.0],
					[30, -0.14, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.08, 0.14, 0.0], [10, 0.0, 0.0, 0.0],
					[30, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Clavicle", [[0, 0.0, 0.24, 0.0], [10, 0.0, 0.10, 0.0],
					[30, 0.0, 0.10, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.95, 0.0, 0.42], [10, -1.35, 0.0, 0.30],
					[30, -1.35, 0.0, 0.30]]),
			Hero3Clips.track("L_Forearm", [[0, -1.30, 0.0, 0.0], [10, -1.15, 0.0, 0.0],
					[30, -1.15, 0.0, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.52, 0.0, -0.34], [10, -1.35, 0.0, -0.30],
					[30, -1.35, 0.0, -0.30]]),
			Hero3Clips.track("R_Forearm", [[0, -1.05, 0.0, 0.0], [10, -1.15, 0.0, 0.0],
					[30, -1.15, 0.0, 0.0]]),
		],
	},
	{
		"id": CATCH_RELEASE, "frames": 22.0, "layer": &"upper",
		"tracks": [
			Hero3Clips.track("Spine01", [[0, -0.14, 0.0, 0.0], [6, 0.22, 0.0, 0.0],
					[22, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [6, 0.12, 0.0, 0.0],
					[22, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Clavicle", [[0, 0.0, 0.10, 0.0], [22, 0.0, 0.10, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -1.35, 0.0, 0.30], [6, -0.55, 0.0, 0.55],
					[22, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("L_Forearm", [[0, -1.15, 0.0, 0.0], [6, -0.35, 0.0, 0.0],
					[22, -0.52, 0.0, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, -1.35, 0.0, -0.30], [6, -0.55, 0.0, -0.55],
					[22, -0.28, 0.0, -0.16]]),
			Hero3Clips.track("R_Forearm", [[0, -1.15, 0.0, 0.0], [6, -0.35, 0.0, 0.0],
					[22, -0.42, 0.0, 0.0]]),
		],
	},
	{
		"id": WARD, "frames": 54.0, "layer": &"upper",
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [10, -0.18, 0.0, 0.0],
					[30, -0.20, 0.0, 0.0], [54, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [10, -0.14, 0.0, 0.0],
					[30, -0.16, 0.0, 0.0], [54, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [10, -1.55, 0.0, 0.26],
					[30, -1.60, 0.0, 0.26], [54, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [10, -0.30, 0.0, 0.0],
					[30, -0.28, 0.0, 0.0], [54, -0.52, 0.0, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [10, -1.55, 0.0, -0.26],
					[30, -1.60, 0.0, -0.26], [54, -0.28, 0.0, -0.16]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [10, -0.30, 0.0, 0.0],
					[30, -0.28, 0.0, 0.0], [54, -0.42, 0.0, 0.0]]),
		],
	},
]
