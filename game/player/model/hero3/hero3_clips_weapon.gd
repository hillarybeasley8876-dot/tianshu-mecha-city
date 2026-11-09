class_name Hero3ClipsWeapon
extends RefCounted
## The weapon clips (hero-v3, lead r3 block B / r4 items 6 and 8). All upper-body, so the mech keeps
## walking while it shoots.
##
## Every one of these is `"offset": true`: its keys are OFFSETS on the posture, not poses. The aim
## solver puts the rifle on the aim line and these layer the recoil, the spin and the reload on top of
## it (lead r4 item 6) -- a clip that wrote the arms absolutely threw the rifle off the target the
## moment the player pulled the trigger, and the rifle fires every 0.25 s.
##
## So the offsets are authored around ZERO: `[0, 0, 0]` means "leave the arm where the aim solver put
## it". `WELL_THROW` is the exception and is not an offset -- a two-handed throw is a pose of its own,
## not something layered on a rifle the mech is holding.

const FIRE_R := &"fire_r"
const CHARGE_R := &"charge_r"
const GATLING_SPIN := &"gatling_spin"
const RELOAD := &"reload"
const MISSILE_LAUNCH := &"missile_launch"
const ANCHOR_FIRE := &"anchor_fire"
const FINS_SEND := &"fins_send"
const BURST := &"burst"
const WELL_THROW := &"well_throw"
const LANCE_FIRE := &"lance_fire"

static func all() -> Array:
	return [
	_fire(FIRE_R, 14.0, 0.22),
	{
		## The charge: the mech braces, the spine winds, and the shot at frame 40 throws it back.
		"id": CHARGE_R, "frames": 46.0, "layer": &"upper", "offset": true,
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [8, 0.03, -0.04, 0.0],
					[34, 0.04, -0.05, 0.0], [40, -0.16, 0.06, 0.0], [46, 0.0, 0.0, 0.0]]),
			## The brace is in the SHOULDERS and the spine, not the arms. The rifle is already on the aim
			## and every radian the charge winds an arm up by is a radian the shot has to unwind through
			## on top of its own recoil -- which is how charge_r -> fire_r moved the hand faster than
			## fire_r's own recoil (lead r4 item 4).
			Hero3Clips.track("R_Clavicle", [[0, 0.0, 0.0, 0.0], [8, 0.0, -0.04, 0.0],
					[34, 0.0, -0.05, 0.0], [46, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, 0.0, 0.0, 0.0], [34, 0.0, 0.0, 0.0],
					[40, 0.30, 0.0, 0.0], [46, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Clavicle", [[0, 0.0, 0.0, 0.0], [8, 0.0, 0.04, 0.0],
					[34, 0.0, 0.05, 0.0], [46, 0.0, 0.0, 0.0]]),
		],
	},
	{
		## Frames [0, 8) are the entry; the spin cycle proper runs 8..44 and is a small tremor.
		"id": GATLING_SPIN, "frames": 44.0, "layer": &"upper", "loop": true, "loop_from": 8.0,
		"entry": 8.0, "offset": true,
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [8, 0.06, -0.10, 0.0],
					[26, 0.08, -0.12, 0.0], [44, 0.06, -0.10, 0.0]]),
			Hero3Clips.track("R_Clavicle", [[0, 0.0, 0.0, 0.0], [8, 0.0, -0.10, 0.0],
					[44, 0.0, -0.10, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, 0.0, 0.0, 0.0], [8, 0.0, 0.0, -0.04],
					[17, 0.03, 0.0, -0.06], [26, 0.0, 0.0, -0.04], [35, 0.03, 0.0, -0.06],
					[44, 0.0, 0.0, -0.04]]),
			Hero3Clips.track("R_Forearm", [[0, 0.0, 0.0, 0.0], [8, -0.13, 0.0, 0.0],
					[44, -0.13, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, 0.0, 0.0, 0.0], [8, -0.10, 0.0, 0.18],
					[44, -0.10, 0.0, 0.18]]),
			Hero3Clips.track("L_Forearm", [[0, 0.0, 0.0, 0.0], [8, -0.18, 0.0, 0.0],
					[44, -0.18, 0.0, 0.0]]),
		],
	},
	{
		## The reload: the left hand leaves the foregrip, goes down to the magazine and comes back.
		"id": RELOAD, "frames": 52.0, "layer": &"upper", "offset": true,
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [10, 0.12, -0.18, 0.0],
					[34, 0.14, -0.20, 0.0], [52, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, 0.0, 0.0, 0.0], [10, 0.30, 0.0, -0.18],
					[34, 0.32, 0.0, -0.18], [52, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, 0.0, 0.0, 0.0], [10, -0.55, 0.0, 0.0],
					[22, -0.85, 0.0, 0.0], [34, -0.50, 0.0, 0.0], [52, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, 0.0, 0.0, 0.0], [10, -0.60, 0.0, 0.30],
					[34, -0.60, 0.0, 0.30], [52, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Forearm", [[0, 0.0, 0.0, 0.0], [16, -0.95, 0.0, 0.0],
					[28, -0.60, 0.0, 0.0], [52, 0.0, 0.0, 0.0]]),
		],
	},
	_shoulder(MISSILE_LAUNCH, 40.0, 0.55, 0.30),
	_shoulder(ANCHOR_FIRE, 54.0, 0.85, 0.55),
	_shoulder(FINS_SEND, 44.0, 0.30, 0.70),
	## `hold` is in units of 24 frames, and burst's 0.20 was a 4.8-frame hold -- the pods opened and
	## closed again inside five frames, which is a twitch (lead r4 item 8).
	_shoulder(BURST, 38.0, 0.65, 0.45),
	_shoulder(LANCE_FIRE, 58.0, 0.95, 0.45),
	{
		## The wind-up is the key pose and it is HELD: f19 repeats f12, so the mech sits cocked for
		## seven frames before the throw. Without it the cocked pose was a single key between f0 and
		## f22 and was never on screen long enough to read (lead r4 item 8).
		"id": WELL_THROW, "frames": 48.0, "layer": &"upper",
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [12, 0.20, -0.34, 0.0],
					[19, 0.20, -0.34, 0.0], [22, -0.26, 0.40, 0.0], [34, 0.10, 0.16, 0.0],
					[48, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [12, 0.16, -0.28, 0.0],
					[19, 0.16, -0.28, 0.0], [22, -0.22, 0.34, 0.0], [34, 0.08, 0.12, 0.0],
					[48, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, -0.28, 0.0, -0.16], [12, -0.30, -0.55, -0.30],
					[19, -0.30, -0.55, -0.30], [22, -1.55, 0.40, 0.10], [34, -1.10, 0.20, 0.05],
					[48, -0.28, 0.0, -0.16]]),
			Hero3Clips.track("R_Forearm", [[0, -0.42, 0.0, 0.0], [12, -1.40, 0.0, 0.0],
					[19, -1.40, 0.0, 0.0], [22, -0.15, 0.0, 0.0], [48, -0.42, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, -0.24, 0.0, 0.16], [12, -0.55, 0.0, 0.40],
					[19, -0.55, 0.0, 0.40], [22, -0.95, 0.0, 0.30], [48, -0.24, 0.0, 0.16]]),
		],
	},
]


## A rifle shot: the weapon is already up (the aim solver put it there), so this is recoil and
## recovery. The rifle fires every 0.25 s and has to feel like it KICKS: on a 16 m machine seen from
## 40 m the old 0.55 m of hand travel was invisible (lead r4 item 8), so the hand now comes back
## along the barrel and the chest pitches back with it.
static func _fire(id: StringName, frames: float, kick: float) -> Dictionary:
	return {
		"id": id, "frames": frames, "layer": &"upper", "offset": true,
		"tracks": [
			## The chest pitches back 4-6 deg (lead r4 item 8): enough to read as a kick from 40 m, not so
			## much that the rifle leaves the target. The ARM does the rest of the work.
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [2, kick * 0.5, 0.0, 0.0],
					[frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [2, kick * 0.4, 0.0, 0.0],
					[frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Clavicle", [[0, 0.0, 0.0, 0.0], [2, 0.0, -kick * 0.6, 0.0],
					[frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, 0.0, 0.0, 0.0], [2, kick * 2.6, 0.0, 0.0],
					[frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, 0.0, 0.0, 0.0], [2, kick * 1.4, 0.0, 0.0],
					[frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, 0.0, 0.0, 0.0], [2, kick * 1.8, 0.0, 0.0],
					[frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Forearm", [[0, 0.0, 0.0, 0.0], [2, kick * 1.0, 0.0, 0.0],
					[frames, 0.0, 0.0, 0.0]]),
		],
	}


## A shoulder-mounted launch: the pod racks rise, hold, and fire. `lift` is how far the shoulders
## open, `hold` how long the pose is kept before it drops back. Offsets like the rest of the family --
## the mech keeps the rifle up while the pods open.
static func _shoulder(id: StringName, frames: float, lift: float, hold: float) -> Dictionary:
	var open := 10.0
	var fire := open + maxf(hold, 0.1) * 24.0
	return {
		"id": id, "frames": frames, "layer": &"upper", "offset": true,
		"tracks": [
			Hero3Clips.track("Spine01", [[0, 0.0, 0.0, 0.0], [open, -0.14, 0.0, 0.0],
					[fire, -0.16, 0.0, 0.0], [fire + 3.0, 0.10, 0.0, 0.0], [frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("Spine02", [[0, 0.0, 0.0, 0.0], [open, -0.12, 0.0, 0.0],
					[fire, -0.14, 0.0, 0.0], [fire + 3.0, 0.08, 0.0, 0.0], [frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Clavicle", [[0, 0.0, 0.0, 0.0], [open, 0.0, lift * 0.4, 0.0],
					[fire, 0.0, lift * 0.4, 0.0], [frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Clavicle", [[0, 0.0, 0.0, 0.0], [open, 0.0, -lift * 0.4, 0.0],
					[fire, 0.0, -lift * 0.4, 0.0], [frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Upperarm", [[0, 0.0, 0.0, 0.0], [open, -lift, 0.0, lift * 0.5],
					[fire, -lift, 0.0, lift * 0.5], [frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Upperarm", [[0, 0.0, 0.0, 0.0], [open, -lift, 0.0, -lift * 0.5],
					[fire, -lift, 0.0, -lift * 0.5], [frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("L_Forearm", [[0, 0.0, 0.0, 0.0], [open, -lift * 0.8, 0.0, 0.0],
					[fire, -lift * 0.8, 0.0, 0.0], [frames, 0.0, 0.0, 0.0]]),
			Hero3Clips.track("R_Forearm", [[0, 0.0, 0.0, 0.0], [open, -lift * 0.8, 0.0, 0.0],
					[fire, -lift * 0.8, 0.0, 0.0], [frames, 0.0, 0.0, 0.0]]),
		],
	}
