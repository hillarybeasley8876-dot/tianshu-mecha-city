class_name DefenseTable
extends RefCounted
## Mirror Guard (镜返盾) numbers, skills-catalog §4.4 "S5", scaled for our 16 m hero (SPEC scale
## rule: reach and radii ×2, times / frames / costs unchanged). Frames are 60 fps; `ticks()`
## doubles them for the 120 Hz simulation.

const REF_FPS := 60.0
const PHYSICS_HZ := 120.0

## Perfect parry: the first 10 f (167 ms) of a guard. Sekiro is 12 f, DMC 6 f — this sits between.
const PERFECT_FRAMES := 10.0
const PERFECT_SPAM_FRAMES := 5.0    ## re-pressing within 0.5 s of a release shrinks the window
const SPAM_WINDOW := 0.5
const MIN_GUARD_FRAMES := 18.0      ## the guard cannot be shorter than this, however brief the tap

## Perfect parry payoffs.
const PARRY_STABILITY := 600.0      ## impact dealt back to a melee attacker
const PARRY_RECOIL := 0.6          ## s the attacker is stuck in its recovery
const PARRY_HITSTOP_FRAMES := 8.0  ## local hit-stop on BOTH actors
const PARRY_EN := 150.0
const PARRY_OD := 4.0
const RETURN_CUT_WINDOW := 0.8

## Held block: front 140°, −70 % damage, 60 EN/s and 25 EN per 100 damage absorbed.
const BLOCK_ARC_DEG := 140.0
const BLOCK_REDUCTION := 0.70
const BLOCK_EN_PER_SEC := 60.0
const BLOCK_EN_PER_100 := 25.0
const GUARD_BREAK_TIME := 1.0       ## EN 0 under the shield: this long stunned and open

## Catch field: hold ≥0.3 s and shots in a 12 m frontal hemisphere freeze and orbit.
const CATCH_HOLD := 0.3
const CATCH_RADIUS := 12.0          ## 6 m in the dossier, ×2
const CATCH_ARC_DEG := 180.0        ## frontal hemisphere
const CATCH_MAX := 24
const CATCH_MAX_TIME := 3.0
const CATCH_EN_PER_SEC := 140.0
const CATCH_ORBIT_RADIUS := 9.0
const CATCH_ORBIT_HEIGHT := 6.0
const CATCH_ORBIT_SPEED := 2.4      ## rad/s the frozen rounds spin at
const RELEASE_CONE_DEG := 20.0
const REFLECT_MULT := 1.35          ## skills-catalog §4.7: caught rounds come back at 135 %
const REFLECT_SPEED := 120.0       ## m/s the returned rounds fly at (dossier keeps their speed)

## The shield sits on the left forearm (`shield_l` socket). r7: the panel used to be 13 m across,
## which is wider than the hero's own chest and covered both fighters — it read as a tile over the
## screen rather than a guard. 4.6 m covers the mech's front (chest and head of a 16 m hero) and
## nothing else. `PANEL_BULGE` is how far the middle of the cap stands proud of its rim, so the panel
## is a curved shell and not a flat plane.
const PANEL_RADIUS := 4.6
const PANEL_BULGE := 1.1
const PANEL_OFFSET := 4.2
const PANEL_RINGS := 5            ## radial subdivisions of the cap
const PANEL_SEGMENTS := 24        ## 4 per hex side
const PERFECT_COLOR := Color("fff2c0")   ## white-gold ring on a perfect parry
const PERFECT_RING_TIME := 0.35
## The ring is a vertical shockwave standing between the two fighters, not a halo over the head:
## it snaps from nothing to 18 m across in 0.1 s and fades over the rest of PERFECT_RING_TIME.
const PERFECT_RING_RADIUS := 18.0
const PERFECT_RING_GROW := 0.1
const PERFECT_SPARKS := 40


static func ticks(frames: float) -> int:
	return maxi(int(round(frames * PHYSICS_HZ / REF_FPS)), 0)


static func seconds(frames: float) -> float:
	return frames / REF_FPS


## How wide the perfect window is for this press: 5 f when the player is mashing (anti-mash).
static func perfect_ticks(spamming: bool) -> int:
	return ticks(PERFECT_SPAM_FRAMES if spamming else PERFECT_FRAMES)
