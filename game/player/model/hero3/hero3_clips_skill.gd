class_name Hero3ClipsSkill
extends RefCounted
## The skill clips that are not weapons or melee (hero-v3, lead r3 block B): the overdrive ignition
## and the two halves of the rift step.
##
## `OVERDRIVE_IGNITE` HOLDS its key pose (lead r4 item 8). Every key used to be a different value, so
## the arms swept up to full extension at f30 and straight back down and the pose was never on screen
## for more than a frame. f38 now repeats f30, which parks the mech at full extension for eight
## frames -- the pose the cast is FOR.

const OVERDRIVE_IGNITE := &"overdrive_ignite"
const RIFT_OUT := &"rift_out"
const RIFT_IN := &"rift_in"

static func all() -> Array:
	return [
	{
		"id": OVERDRIVE_IGNITE, "frames": 66.0, "layer": &"upper",
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [14, 0.26, 0.0, 0.0],
					[30, -0.34, 0.0, 0.0], [38, -0.34, 0.0, 0.0], [50, -0.20, 0.0, 0.0],
					[66, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [14, 0.22, 0.0, 0.0],
					[30, -0.30, 0.0, 0.0], [38, -0.30, 0.0, 0.0], [50, -0.16, 0.0, 0.0],
					[66, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Clavicle", [[0, 0.0, 0.10, 0.0], [14, 0.0, 0.34, 0.0],
					[30, 0.0, 0.40, 0.0], [38, 0.0, 0.40, 0.0], [66, 0.0, 0.10, 0.0]]),
			Hero3Clips.track("R_Clavicle", [[0, 0.0, -0.10, 0.0], [14, 0.0, -0.34, 0.0],
					[30, 0.0, -0.40, 0.0], [38, 0.0, -0.40, 0.0], [66, 0.0, -0.10, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [14, -0.55, 0.0, 0.45],
					[30, -1.05, 0.0, 0.62], [38, -1.05, 0.0, 0.62], [50, -0.85, 0.0, 0.50],
					[66, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [14, -0.55, 0.0, -0.45],
					[30, -1.05, 0.0, -0.62], [38, -1.05, 0.0, -0.62], [50, -0.85, 0.0, -0.50],
					[66, -0.28, 0.0, -0.16]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [30, -1.35, 0.0, 0.0],
					[38, -1.35, 0.0, 0.0], [66, -0.52, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [30, -1.35, 0.0, 0.0],
					[38, -1.35, 0.0, 0.0], [66, -0.42, 0.0, 0.0]]),
		],
	},
	{
		## A blink out: the mech compresses into a crouch and goes. Root and feet, not leg keys -- the
		## crouch is the PELVIS going down while the soles stay on the floor (lead r4 item 3).
		"id": RIFT_OUT, "frames": 30.0, "layer": &"full",
		"root": [[0, 0.0, 0.0, 0.0, 0.0, 0.0], [8, 0.0, -1.25, 0.0, 0.22, 0.0],
				[16, 0.0, -0.70, 0.0, -0.14, 0.0], [30, 0.0, 0.0, 0.0, 0.0, 0.0]],
		"feet": Hero3ClipsReact.planted(30.0),
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [8, 0.30, 0.0, 0.0],
					[16, -0.20, 0.0, 0.0], [30, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [8, 0.24, 0.0, 0.0],
					[16, -0.16, 0.0, 0.0], [30, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [8, -1.20, 0.0, 0.35],
					[30, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [8, -1.20, 0.0, -0.35],
					[30, -0.28, 0.0, -0.16]]),
		],
	},
	{
		## The arrival: it lands in the crouch the blink left it in and stands up out of it.
		"id": RIFT_IN, "frames": 34.0, "layer": &"full",
		"root": [[0, 0.0, -1.40, 0.0, 0.26, 0.0], [10, 0.0, -0.55, 0.0, -0.10, 0.0],
				[22, 0.0, -0.90, 0.0, 0.12, 0.0], [34, 0.0, 0.0, 0.0, 0.0, 0.0]],
		"feet": Hero3ClipsReact.planted(34.0),
		"tracks": [
			Hero3Clips.track("Spine01", [[0, -0.24, 0.0, 0.0], [10, 0.28, 0.0, 0.0],
					[22, 0.10, 0.0, 0.0], [34, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, -0.20, 0.0, 0.0], [10, 0.22, 0.0, 0.0],
					[22, 0.08, 0.0, 0.0], [34, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -1.30, 0.0, 0.30], [10, -0.50, 0.0, 0.45],
					[34, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("R_Upperarm", [[0, -1.30, 0.0, -0.30], [10, -0.50, 0.0, -0.45],
					[34, -0.28, 0.0, -0.16]]),
		],
	},
]
