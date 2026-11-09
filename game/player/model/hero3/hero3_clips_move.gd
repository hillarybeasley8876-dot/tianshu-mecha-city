class_name Hero3ClipsMove
extends RefCounted
## The movement clips (hero-v3, lead r3 block B).
##
## ALL UPPER-BODY. The legs of a dash, a slide and a landing are not this file's business: the game
## sends those as `set_locomotion` states and never calls `play_action` for them, so the stance is
## `Hero3Skate`'s (lead r4 item 2) and the air pose is `Hero3Air`'s. A clip that also folded the legs
## with FK keys fought both and lifted the feet off the floor.

const DASH_F := &"dash_f"
const DASH_B := &"dash_b"
const DASH_L := &"dash_l"
const DASH_R := &"dash_r"
const SLIDE := &"slide"
const JUMP := &"jump"
const FALL := &"fall"
const HOVER := &"hover"
const FLY := &"fly"
const LAND_LIGHT := &"land_light"
const LAND_HEAVY := &"land_heavy"
const PLUNGE_DIVE := &"plunge_dive"
const PLUNGE_LAND := &"plunge_land"

static func all() -> Array:
	return [
	_dash(DASH_F, Vector3(0.0, 0.0, -1.0), 0.34),
	_dash(DASH_B, Vector3(0.0, 0.0, 1.0), -0.26),
	_dash(DASH_L, Vector3(-1.0, 0.0, 0.0), 0.20),
	_dash(DASH_R, Vector3(1.0, 0.0, 0.0), 0.20),
	_slide(),
	_jump(),
	_fall(),
	_air(HOVER, 48.0, -0.10, 0.0, true),
	_air(FLY, 48.0, -0.26, 0.10, true),
	_land(LAND_LIGHT, 18.0, -0.13, 0.34),
	_land(LAND_HEAVY, 28.0, -0.30, 0.62),
	_plunge(PLUNGE_DIVE, 36.0, true),
	_plunge(PLUNGE_LAND, 40.0, false),
]


## A thruster dash: the body pitches into the travel direction and the arms pull in. `lean` is the
## pitch in radians, signed so a backward dash leans back.
##
## UPPER-BODY ONLY (lead r4 item 2/3): the legs of a dash are the SKATE's, driven by the move state,
## not folded by FK keys. FK leg keys with the pelvis at standing height lifted both feet off the
## floor -- dash_f's lower ankle reached 3.5 m at frame 4.
static func _dash(id: StringName, _dir: Vector3, lean: float) -> Dictionary:
	var side := -signf(_dir.x)
	return {
		"id": id, "frames": 22.0, "layer": &"upper",
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [5, lean, 0.0, 0.0],
					[14, lean * 0.8, 0.0, 0.0], [22, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [5, lean * 0.7, 0.0, 0.0],
					[14, lean * 0.55, 0.0, 0.0], [22, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [5, -0.60, 0.0, 0.30],
					[14, -0.50, 0.0, 0.26], [22, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16],
					[5, -0.60, 0.0, -0.30 - 0.10 * side], [14, -0.50, 0.0, -0.26],
					[22, -0.28, 0.0, -0.16]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [5, -1.05, 0.0, 0.0],
					[22, -0.52, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [5, -1.05, 0.0, 0.0],
					[22, -0.42, 0.0, 0.0]]),
		],
	}


## A slide: the mech drops onto its back leg and skids. The torso and the arms only -- the stance
## itself is `Hero3Skate`'s `slide` entry, which owns the staggered feet and the 1.3 m pelvis drop.
static func _slide() -> Dictionary:
	return {
		"id": SLIDE, "frames": 40.0, "layer": &"upper", "loop": true, "loop_from": 6.0,
		"entry": 6.0,
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [6, 0.34, 0.0, 0.0],
					[28, 0.30, 0.0, 0.0], [40, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [6, 0.26, 0.0, 0.0],
					[28, 0.22, 0.0, 0.0], [40, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [6, -0.85, 0.0, 0.45],
					[28, -0.80, 0.0, 0.42], [40, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [6, 0.30, 0.0, -0.40],
					[28, 0.26, 0.0, -0.38], [40, -0.28, 0.0, -0.16]]),
		],
	}


## The launch: a crouch and a push. The legs are the gait's business once airborne, so this only
## takes the torso and the arms.
static func _jump() -> Dictionary:
	return {
		"id": JUMP, "frames": 26.0, "layer": &"upper",
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [6, 0.26, 0.0, 0.0],
					[12, -0.20, 0.0, 0.0], [26, -0.10, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [6, 0.20, 0.0, 0.0],
					[12, -0.16, 0.0, 0.0], [26, -0.08, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [6, 0.35, 0.0, 0.30],
					[12, -1.15, 0.0, 0.34], [26, -0.95, 0.0, 0.30]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [6, 0.35, 0.0, -0.30],
					[12, -1.15, 0.0, -0.34], [26, -0.95, 0.0, -0.30]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [12, -0.75, 0.0, 0.0],
					[26, -0.70, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [12, -0.75, 0.0, 0.0],
					[26, -0.70, 0.0, 0.0]]),
		],
	}


## A held airborne posture: arms out for balance, chest pitched by `lean`. Frames [0, 8) are the entry
## off the ground pose, and a looping clip cycles from there (`loop_from`).
static func _air(id: StringName, frames: float, lean: float, roll: float, loop: bool = false) -> Dictionary:
	return {
		"id": id, "frames": frames, "layer": &"upper", "loop": loop, "loop_from": 8.0,
		"entry": 8.0,
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [8, lean, 0.0, roll],
					[frames, lean, 0.0, roll]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [8, lean * 0.7, 0.0, roll * 0.7],
					[frames, lean * 0.7, 0.0, roll * 0.7]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [8, -0.62, 0.0, 0.22],
					[frames, -0.62, 0.0, 0.22]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [8, -0.62, 0.0, -0.22],
					[frames, -0.62, 0.0, -0.22]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [8, -0.85, 0.0, 0.0],
					[frames, -0.85, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [8, -0.85, 0.0, 0.0],
					[frames, -0.85, 0.0, 0.0]]),
		],
	}


## Falling (lead r5 "weight"): a machine BRACING, not a body dangling. The torso curls slightly
## forward over tucked arms held close and low, so the silhouette is compact and the shoulders are
## squared -- the legs reaching for the ground past ~15 m/s down are `Hero3Air.brace`'s business.
## `lean`, `fold` and `spread` are PARAMETERS so `probe_fall.gd` can sweep them against the
## interpenetration gate instead of the numbers being guessed one capture at a time (lead r8: the
## r7 values drove the left clavicle 1.5 m through the shoulder and nothing measured it, because no
## pose in the gate had ever played an air clip).
## The defaults are the SWEEP RESULT, not taste: `probe_fall.gd` measures every combination against
## `test_hero3_pieces` and this one is the only arm set in the family that crosses nothing. The r7
## numbers (lean -0.20, fold -1.35, spread 0.62, swing -0.42) drove the left clavicle 1.5 m through the
## shoulder -- `test_hero3_pieces` had never played an air clip, so nothing had ever measured it.
static func _fall(lean: float = -0.12, fold: float = -0.75, spread: float = 0.18,
		swing: float = -0.36) -> Dictionary:
	return {
		"id": FALL, "frames": 40.0, "layer": &"upper", "loop": true, "loop_from": 8.0,
		"entry": 8.0,
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [8, lean, 0.0, 0.0],
					[40, lean, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [8, lean * 0.8, 0.0, 0.0],
					[40, lean * 0.8, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [8, swing, 0.0, spread],
					[40, swing, 0.0, spread]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [8, swing - 0.04, 0.0, -spread],
					[40, swing - 0.04, 0.0, -spread]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [8, fold, 0.0, 0.0],
					[40, fold, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [8, fold, 0.0, 0.0],
					[40, fold, 0.0, 0.0]]),
		],
	}


## A landing: the torso absorbs and the arms come DOWN and OUT to brace. The legs and the pelvis dip
## belong to the gait's landing state (`Hero3Air`, lead r5 "weight").
##
## `pitch` is the forward lean of Spine01 in radians (NEGATIVE: a positive pitch about +X tips the up
## axis backward, `Hero3Posture.apply_pelvis` says so) and `spread` how far the upperarms swing out, so
## a heavy landing reads as ~12 deg of torso over a held brace while a light one barely moves. The
## keys are DROP (3 frames, matching `Hero3Air.DROP_T`), HOLD (6 frames) and then a long ease back:
## the profile is the pelvis curve's, so the torso and the knees arrive and leave together.
const LAND_DROP := 3.0
const LAND_HOLD := 9.0

static func _land(id: StringName, frames: float, pitch: float, spread: float) -> Dictionary:
	var hold := LAND_DROP + LAND_HOLD
	var ease := (frames - hold) * 0.45 + hold
	# the arms go DOWN as well as out: the upperarm's x is its forward swing, so less negative is lower
	var down := -0.24 + spread * 0.30
	return {
		"id": id, "frames": frames, "layer": &"upper",
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [LAND_DROP, pitch, 0.0, 0.0],
					[hold, pitch, 0.0, 0.0], [ease, pitch * 0.3, 0.0, 0.0],
					[frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [LAND_DROP, pitch * 0.7, 0.0, 0.0],
					[hold, pitch * 0.7, 0.0, 0.0], [ease, pitch * 0.2, 0.0, 0.0],
					[frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [LAND_DROP, down, 0.0, spread],
					[hold, down, 0.0, spread], [frames, -0.24, 0.0, 0.16]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [LAND_DROP, down, 0.0, -spread],
					[hold, down, 0.0, -spread], [frames, -0.28, 0.0, -0.16]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [LAND_DROP, -1.25, 0.0, 0.0],
					[hold, -1.25, 0.0, 0.0], [frames, -0.52, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [LAND_DROP, -1.25, 0.0, 0.0],
					[hold, -1.25, 0.0, 0.0], [frames, -0.42, 0.0, 0.0]]),
		],
	}


## The plunge: a head-first dive, and the slam that ends it.
static func _plunge(id: StringName, frames: float, diving: bool) -> Dictionary:
	var lean := -0.55 if diving else 0.50
	return {
		"id": id, "frames": frames, "layer": &"upper", "loop": diving, "loop_from": 8.0,
		"entry": 8.0,
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [8, lean, 0.0, 0.0],
					[frames, lean, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [8, lean * 0.7, 0.0, 0.0],
					[frames, lean * 0.7, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [8, -1.70, 0.0, 0.16],
					[frames, -1.70 if diving else -0.24, 0.0, 0.16]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [8, -1.70, 0.0, -0.16],
					[frames, -1.70 if diving else -0.28, 0.0, -0.16]]),
			Hero3Clips.track("L_Forearm", [[0, -0.52, 0.0, 0.0], [8, -0.20, 0.0, 0.0],
					[frames, -0.20 if diving else -0.52, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [8, -0.20, 0.0, 0.0],
					[frames, -0.20 if diving else -0.42, 0.0, 0.0]]),
		],
	}
