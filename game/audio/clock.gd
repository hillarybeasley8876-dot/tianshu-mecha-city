class_name AudioClock
extends RefCounted
## The audio unit's single clock (CONTRACTS §3): unscaled *game* seconds, never the wall clock.
##
## Rate limits, voice ages, loop release and stinger spacing all run on this. A wall clock reads
## ~70 ms per frame under `tools/godot.sh movie` (and ~5 ms per frame in a fast headless test), so
## every interval measured on it shrinks or stretches with the capture speed: the gatling released
## its loop between rounds, the cockpit voice overlapped itself, stingers stacked.
##
## Feel.real_now() is the same clock the rest of the game uses: it equals wall time in live play and
## stays correct under --fixed-fps and Movie Maker.

## Isolated tool scenes may run without Feel in the tree; physics frames are still game time there.
static func now() -> float:
	if Feel != null and Feel.is_inside_tree():
		return Feel.real_now()
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


## Seconds since a stamp from this clock, clamped so a clock that stepped backwards never inflates
## an age (steal scores and interval checks both subtract).
static func since(stamp: float) -> float:
	return maxf(now() - stamp, 0.0)
