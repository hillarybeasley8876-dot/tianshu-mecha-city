class_name Hero3ClipsReact
extends RefCounted
## The reaction clips (hero-v3, lead r3 block B / r4 item 3): what the mech does when it is hit,
## staggered or killed.
##
## These are the clips that used to FLOAT. They folded the thighs and calves with FK keys while the
## pelvis stayed at standing height, so both feet left the ground: death hung in the air with its
## lower ankle at 5.6 m, hit_knockdown at 4.2 m, hit_heavy at 3.5 m. `lead_death.jpg` and
## `lead_knock.jpg` show the mech folding its legs up behind it and hanging there, which is the
## opposite of impact.
##
## So a reaction keys the ROOT and the FEET, never the leg bones:
##   "root": [[frame, dx, dy, dz, pitch, roll], ...]  metres on the root's rest origin plus the pelvis
##                                                  pitch and roll, in radians
##   "feet": {"R": [[frame, x, y, z], ...], "L": [...]}  the SOLE, in model space relative to the
##                                                  model origin (between the feet at y = 0)
## `Hero3Gait` reads both and solves the legs through `Hero3LegIk`, so the soles are on the floor by
## construction. FK leg keys are for airborne poses only.
##
## The rest sole positions below are MEASURED (`tests/test_hero3_ik.gd`): the plant home is each hip
## head pushed STANCE_WIDTH outboard, x = +-2.13 m at z = -0.40 m.

const HIT_LIGHT := &"hit_light"
const HIT_HEAVY := &"hit_heavy"
const HIT_KNOCKDOWN := &"hit_knockdown"
const STAGGER := &"stagger"
const DEATH := &"death"
## The measured rest sole, per side, in model space.
const SOLE_R := Vector3(2.13, 0.0, -0.40)
const SOLE_L := Vector3(-2.13, 0.0, -0.40)

static func all() -> Array:
	return [
	_hit(HIT_LIGHT, 16.0, 0.40, 0.15, 0.10),
	_hit(HIT_HEAVY, 26.0, 1.00, 0.38, 0.26),
	_knockdown(),
	_stagger(),
	_death(),
	]


## A flinch: the pelvis dips by `dip` metres, the chest snaps back by `snap` radians on both spine
## links, and the arms come up by `lift`. The feet never move -- a hit rocks the mech, it does not
## pick it up.
static func _hit(id: StringName, frames: float, dip: float, snap: float, lift: float) -> Dictionary:
	return {
		"id": id, "frames": frames, "layer": &"full",
		"root": [[0, 0.0, 0.0, 0.0, 0.0, 0.0], [3, 0.0, -dip, 0.0, snap * 0.5, 0.0],
				[frames * 0.5, 0.0, -dip * 0.3, 0.0, -snap * 0.2, 0.0],
				[frames, 0.0, 0.0, 0.0, 0.0, 0.0]],
		"feet": planted(frames),
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [3, -snap, 0.0, 0.0],
					[frames * 0.5, snap * 0.35, 0.0, 0.0], [frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [3, -snap * 0.8, 0.0, 0.0],
					[frames * 0.5, snap * 0.3, 0.0, 0.0], [frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16],
					[3, -0.24 - lift * 2.0, 0.0, 0.16 + lift], [frames, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16],
					[3, -0.28 - lift * 2.0, 0.0, -0.16 - lift], [frames, -0.28, 0.0, -0.16]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [3, -0.52 - lift * 2.5, 0.0, 0.0],
					[frames, -0.52, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [3, -0.42 - lift * 2.5, 0.0, 0.0],
					[frames, -0.42, 0.0, 0.0]]),
		],
	}


## Knocked flat and back up: the pelvis drops 3.10 m inside eight frames, the torso throws back, the
## feet slide 3.4 m forward as the body goes down, and the mech climbs back to standing by the end.
##
## The numbers are MEASURED, not chosen (lead r5 item 9, `tests/probe_pieces.gd`): the first pass
## dropped the pelvis 3.80 m with the soles only 2.30 m forward, which folded the knee to 125 deg and
## drove the calf plate 0.707 m through the thigh. Sliding the feet further out holds the knee at
## 89 deg at the same depth and the gate reads clear.
static func _knockdown() -> Dictionary:
	return {
		"id": HIT_KNOCKDOWN, "frames": 62.0, "layer": &"full",
		"root": [[0, 0.0, 0.0, 0.0, 0.0, 0.0], [8, 0.0, -3.10, 0.0, 0.38, 0.0],
				[26, 0.0, -3.10, 0.0, 0.48, 0.0], [44, 0.0, -1.40, 0.0, 0.18, 0.0],
				[62, 0.0, 0.0, 0.0, 0.0, 0.0]],
		"feet": {
			"R": [[0, SOLE_R.x, 0.0, SOLE_R.z], [8, 2.30, 0.0, -3.80], [26, 2.45, 0.0, -3.80],
					[44, 2.30, 0.0, -1.90], [62, SOLE_R.x, 0.0, SOLE_R.z]],
			"L": [[0, SOLE_L.x, 0.0, SOLE_L.z], [8, -2.30, 0.0, -3.80], [26, -2.45, 0.0, -3.80],
					[44, -2.30, 0.0, -1.90], [62, SOLE_L.x, 0.0, SOLE_L.z]],
		},
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [8, 0.42, 0.0, 0.0],
					[26, 0.55, 0.0, 0.0], [44, -0.30, 0.0, 0.0], [62, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [8, 0.34, 0.0, 0.0],
					[26, 0.44, 0.0, 0.0], [44, -0.24, 0.0, 0.0], [62, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [8, -0.30, 0.0, 0.16],
					[26, -0.38, 0.0, 0.19], [62, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [8, -0.30, 0.0, -0.16],
					[26, -0.38, 0.0, -0.19], [62, -0.28, 0.0, -0.16]]),
		],
	}


## Two short stumble steps. This clip owns the ROOT ONLY, deliberately: the lurch drags the hips away
## from the world-locked plants, and the step planner answers with REAL steps (lead r4 item 3, "as
## real steps through the planner"). A clip that also owned the feet would just slide them.
static func _stagger() -> Dictionary:
	return {
		"id": STAGGER, "frames": 44.0, "layer": &"full",
		"root": [[0, 0.0, 0.0, 0.0, 0.0, 0.0], [6, 0.0, -0.34, 0.9, 0.14, 0.10],
				[18, 0.0, -0.20, 1.8, -0.08, -0.06], [30, 0.0, -0.38, 2.5, 0.12, 0.08],
				[44, 0.0, 0.0, 2.9, 0.0, 0.0]],
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [6, -0.34, 0.22, 0.0],
					[18, 0.20, -0.16, 0.0], [30, -0.12, 0.08, 0.0], [44, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [6, -0.28, 0.18, 0.0],
					[18, 0.16, -0.12, 0.0], [30, -0.10, 0.06, 0.0], [44, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [6, -0.70, 0.0, 0.50],
					[44, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [6, -0.70, 0.0, -0.50],
					[44, -0.28, 0.0, -0.16]]),
		],
	}


## Down to one knee, then over onto the floor. The pelvis reaches 2.80 m at the last frame and the
## clip HOLDS there (`"hold": true`), which is what `stop_action` is for.
##
## The arms barely move and that is measured, not lazy (lead r5 item 9, `tests/probe_clear.gd`): at
## the first pass's swing the pauldron plate crossed the upperarm plate by 0.92 m on the last frame.
static func _death() -> Dictionary:
	return {
		"id": DEATH, "frames": 96.0, "layer": &"full", "hold": true,
		"root": [[0, 0.0, 0.0, 0.0, 0.0, 0.0], [10, 0.0, -1.20, 0.0, 0.12, 0.0],
				[34, 0.0, -4.20, 0.0, 0.34, 0.12], [60, 0.0, -5.40, 0.0, 0.58, 0.34],
				[96, 0.0, -5.80, 0.0, 0.62, 0.46]],
		"feet": {
			"R": [[0, SOLE_R.x, 0.0, SOLE_R.z], [34, 2.20, 0.0, -0.95], [96, 2.35, 0.0, -2.40]],
			"L": [[0, SOLE_L.x, 0.0, SOLE_L.z], [10, -2.32, 0.0, -1.60],
					[34, -2.45, 0.0, -3.20], [96, -2.55, 0.0, -4.20]],
		},
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [10, -0.30, 0.0, 0.0],
					[34, 0.55, 0.0, 0.0], [60, 0.85, 0.0, 0.0], [96, 0.88, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [10, -0.24, 0.0, 0.0],
					[34, 0.42, 0.0, 0.0], [60, 0.66, 0.0, 0.0], [96, 0.70, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.14, 0.0, 0.16], [10, -0.36, 0.0, 0.32],
					[96, -0.12, 0.0, 0.60]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.17, 0.0, -0.16], [10, -0.36, 0.0, -0.32],
					[96, -0.12, 0.0, -0.60]]),
			Hero3Clips.track("L_Forearm", [[0, -0.26, 0.0, 0.0], [96, -0.13, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, -0.21, 0.0, 0.0], [96, -0.13, 0.0, 0.0]]),
		],
	}


## Both soles standing still for the whole clip: `[frame, x, y, z]` per side. Public because the
## other families' full clips (the rift) plant the same way.
static func planted(frames: float) -> Dictionary:
	return {
		"R": [[0, SOLE_R.x, 0.0, SOLE_R.z], [frames, SOLE_R.x, 0.0, SOLE_R.z]],
		"L": [[0, SOLE_L.x, 0.0, SOLE_L.z], [frames, SOLE_L.x, 0.0, SOLE_L.z]],
	}
