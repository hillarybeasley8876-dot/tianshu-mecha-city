class_name AnchorFx
extends RefCounted
## The Skyhook's look, split out of skyhook_anchor.gd: the latch bite and the world-space speed lines
## the mech drags while it reels in. The cable itself is `cable_visual.gd`.
##
## Static and null-tolerant on `vfx`, so the grapple still works when the effects node is missing.

const LATCH_COLOR := Color(1.0, 0.85, 0.45)
const CABLE_STREAK := Color(0.6, 0.94, 1.0)
const STREAK_GAP := 0.05        ## seconds between ribbons while reeling
const STREAK_MIN_SPEED := 20.0  ## below this the reel does not read as speed yet


## The bite: a spark burst, a short white flash and a small cyan pop around the hook, so the latch
## reads at 120 m as an event rather than a change of cable length (r1 review).
static func latch(from: Node, vfx: SkillVfx, at: Vector3, size: float) -> void:
	SkillFx.spawn(from, &"spark_burst", at, Vector3.UP, size)
	SkillFx.flash(from, at, LATCH_COLOR, 3.0, 30.0, 3.0)
	if vfx == null:
		return
	vfx.shell().fire(at, 0.3, 5.0 * size, 0.22, Color(0.5, 0.9, 1.0), Color(1.0, 0.95, 0.8),
			2.6, 1.8)


## Two short ribbons opposite the pull, dropped every few frames so a 90 m/s reel reads as speed from
## the gameplay camera too (r1 review). They come from the ribbon pool, never the shared beam pool the
## cable itself is holding open (audit #6).
static func reel_streaks(vfx: SkillVfx, chest: Vector3, velocity: Vector3) -> void:
	if vfx == null:
		return
	var speed := velocity.length()
	if speed < STREAK_MIN_SPEED:
		return
	var back := -velocity / speed
	var side := back.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	for s: float in [-1.0, 1.0]:
		var at := chest + side * s * 6.0 + Vector3.UP * (2.0 if s > 0.0 else -3.0)
		vfx.trail().flash(at, at + back * speed * 0.28, 0.9, CABLE_STREAK, 0.14, 2.2, 0.8)
