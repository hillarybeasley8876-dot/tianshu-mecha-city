class_name Hero3Pelvis
extends RefCounted
## How high the Tianshu mech's hips ride (hero-v3, lead r3 item A1).
##
## The first accepted walk had a 2.2 m W-shaped bob with 8 local minima in 3.8 steps, because the
## pelvis followed the FURTHEST foot: during double support the two feet are symmetric about the hip,
## so their maximum distance dips in the middle of the window and the hips rose and fell again inside
## every step. That is the "gui nve" the user complained about.
##
## The height here is a curve of the PHASE CLOCK alone. `w` runs 0..1 over one step, starting at the
## instant the incoming foot touches down:
##   [0, DS]     double support -- held flat at the reach-limited depth
##   [DS, TOP]   rising to the mid-stance crouch as the planted foot comes under the hip
##   [TOP, 1]    sinking again, anticipating the next plant
## Both ends of the flat bottom carry the same value, so the curve closes on itself: exactly one
## trough and one crest per step, MID_DROP to DEEP_DROP apart.

## Metres below the rest hip (8.60 m). MID_DROP is the mid-stance crouch that puts the knee at
## 50-60 deg; DEEP_DROP is the reach-limited depth at double support. The dip between them is 0.55 m.
const MID_DROP := 0.28
const DEEP_DROP := 0.90
## The floor is solved for a STRAIGHT leg, which is the IK singularity: the solver clamps the knee at
## 8 deg of bend, so a target placed at exactly the straight-leg depth misses by a few centimetres
## and the sole sinks with it. This is the bend the floor is solved for instead.
const REACH_CLEARANCE := 0.12
## `--hero3-notrim` restores the pre-r9 mid-stance crouch, so the BEFORE films are the gait that
## shipped and not this one with a different hip height. Metres ADDED to MID_DROP.
static var drop_bias := 0.0
## Pelvis sway over the planted foot, and the torso counter-rotation it feeds.
const SWAY_WALK := 0.40
const SWAY_RUN := 0.30
const TORSO_COUNTER_DEG := 6.0


## The drop in metres at a given phase. `duty` sets where double support ends and where mid-stance
## falls, so the same curve serves the walk and the bound.
static func curve(phase: float, duty: float, moving: float) -> float:
	var ds := maxf(2.0 * duty - 1.0, 0.0)
	var top := clampf(duty, ds + 0.05, 0.95)
	var w := fposmod((phase - (1.0 - duty)) * 2.0, 1.0)
	var g := 1.0
	if w >= ds and w < top:
		g = 1.0 - smoothstep(ds, top, w)
	elif w >= top:
		g = smoothstep(top, 1.0, w)
	return (MID_DROP + drop_bias + (DEEP_DROP - MID_DROP) * g) * moving


## The depth the pelvis would need RIGHT NOW for a straight leg to hold every foot it is holding.
## `legs` is one `{flat, ankle_y, weight}` per leg: the horizontal hip-to-ankle distance, the ankle's
## height, and how much this foot constrains the hips (a swinging foot only matters near touchdown).
## The phase curve is deeper than this everywhere in a steady gait, so this is a safety floor for
## direction changes, turns and the standing start -- never the shape of the walk.
static func need(rest_hip: float, leg_len: float, legs: Array) -> float:
	var worst := 0.0
	for leg: Dictionary in legs:
		var weight := float(leg["weight"])
		if weight <= 0.0:
			continue
		var flat := float(leg["flat"])
		var vertical := sqrt(maxf(leg_len * leg_len - flat * flat, 0.0))
		worst = maxf(worst, weight * (rest_hip - float(leg["ankle_y"]) - vertical + REACH_CLEARANCE))
	return maxf(worst, 0.0)


## The pelvis leans over whichever foot is carrying the weight. Derived from the phase clock so it is
## a smooth sinusoid rather than a step, and scaled by speed so a standing mech does not sway.
static func sway(phase: float, duty: float, moving: float, run_t: float, air: float) -> float:
	var amount := lerpf(SWAY_WALK, SWAY_RUN, run_t) * moving
	return -amount * cos(TAU * (phase - (1.0 - duty) * 0.5)) * (1.0 - air)


## How far the torso counter-rotates against the pelvis this instant, in radians.
static func counter(phase: float, moving: float, air: float) -> float:
	return deg_to_rad(TORSO_COUNTER_DEG) * sin(TAU * phase) * moving * (1.0 - air)
