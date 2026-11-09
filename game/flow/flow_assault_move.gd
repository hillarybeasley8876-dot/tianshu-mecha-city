class_name FlowAssaultMove
extends RefCounted
## Where the E2E bot goes when it cannot shoot (split out of `FlowDebugAssault`). It owns the three
## moves the bot has: orbit a Hive Spire to a stand the lens can see from, stand off the Brood Titan
## on the Crown's open deck, and drop straight down onto a pack of rippers. It reads the world
## through `FlowAssaultTargets` and never touches the camera or the trigger.

const MOVE_EVERY := 1.2           ## s between repositioning moves
const PERCH_HEIGHT := 22.0        ## m above the target, so a container yard cannot block the shot
## How far off the titan the bot stands on the Crown when it has to close the distance.
const BOSS_STANDOFF := 38.0

var targets: FlowAssaultTargets = null
var _move_t: float = 0.0


func setup(eyes: FlowAssaultTargets) -> void:
	targets = eyes


func cool(delta: float) -> void:
	_move_t = maxf(_move_t - delta, 0.0)


## Nothing in sight: move. A mech the rippers cannot reach — on a container stack, behind a wall, out
## of range — would otherwise stand there for ever while the arena waits for a wave to die. The
## cooldown alone paces it: waiting for `is_grounded` as well used to freeze the bot for good the
## moment it was placed on a firing position with no floor under it.
## Returns true when a repositioning pass actually ran, so the caller can reset its own aim counter
## (a place the bot has just left is a place it has to start aiming from scratch).
func reposition(player: Node3D) -> bool:
	if _move_t > 0.0:
		return false
	_move_t = MOVE_EVERY
	# This position has just been proved useless (the camera cannot see the target from here): strike
	# it off, or the search hands back the same spot every 1.2 s for the whole beat.
	targets.mark_bad(player.global_position)
	var from := player.global_position
	print("E2EMOVE leaving %.0f,%.0f,%.0f (blind spots %d)" % [from.x, from.y, from.z,
			targets.bad_count()])
	var best := targets.nearest(player)
	if best == null:
		return true
	if targets.spire != null:
		_orbit(player, best)
	elif targets.arena_id == &"boss":
		_stand_off_boss(player, best)
	else:
		_perch(player, best)
	return true


## Orbit the trunk to a stand the lens can see the target from, or — when the whole ring has been
## struck off — forget the blind spots and search it again.
func _orbit(player: Node3D, best: Targetable) -> void:
	var spot := targets.firing_spot(best)
	if spot == Vector3.INF and targets.bad_count() >= FlowAssaultTargets.BAD_SPOTS:
		print("E2ESPOT none of the %d candidates can see the target — clearing %d blind spots"
				% [targets.ring_size(), targets.bad_count()])
		targets.clear_bad()
		spot = targets.firing_spot(best)
	if spot == Vector3.INF:
		return
	player.call(&"debug_teleport", [spot.x, spot.y, spot.z], 0.0)
	print("E2ESPOT at %.0f,%.0f,%.0f" % [spot.x, spot.y, spot.z])


## The Crown is one open deck: stand off on it, not above it — and at the TITAN's own height, not the
## height of the core the bot was chasing. A mech placed 6 m over a core 40 m up the beast's chest is
## a mech in mid-air over the rim, and it falls off the Crown.
func _stand_off_boss(player: Node3D, best: Targetable) -> void:
	var away := _away_from(player, best)
	var titan := targets.boss_of(best)
	var feet := titan.global_position.y if titan != null else best.global_position.y
	var deck := Vector3(best.global_position.x, feet, best.global_position.z) \
			+ away.normalized() * BOSS_STANDOFF + Vector3.UP * 6.0
	player.call(&"debug_teleport", [deck.x, deck.y, deck.z], 0.0)
	print("E2ECHASE boss blocked by %s -> standing off at %.0f,%.0f,%.0f"
			% [targets.blocker(FlowDebugView.eye(), best.global_position), deck.x, deck.y, deck.z])


## Straight down onto the target's own airspace: a container yard blocks every horizontal line, and
## dropping in on the pack is what makes it notice the mech at all.
func _perch(player: Node3D, best: Targetable) -> void:
	var at := best.global_position + _away_from(player, best).normalized() * 12.0 \
			+ Vector3.UP * PERCH_HEIGHT
	player.call(&"debug_teleport", [at.x, at.y, at.z], 0.0)
	var eye := FlowDebugView.eye()
	print("E2ECHASE %.0f m blocked by %s -> moving to %.0f,%.0f,%.0f"
			% [eye.distance_to(best.global_position),
			targets.blocker(eye, best.global_position),
			at.x, at.y, at.z])


## The flat direction from the target back to the mech, never zero.
func _away_from(player: Node3D, best: Targetable) -> Vector3:
	var away := player.global_position - best.global_position
	away.y = 0.0
	return Vector3.FORWARD if away.length_squared() < 1.0 else away
