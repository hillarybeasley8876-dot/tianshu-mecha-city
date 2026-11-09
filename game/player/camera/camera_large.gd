extends Node
## Large-target framing (camera-aim, CONTRACTS §5). A hard lock on an actor that reports
## `framing_height() >= 30 m` (the boss: 60) is a different shot: at the 42 m street arm and the −6°
## street pitch a 60 m titan is cropped to its shins and the reticle sits on its knees.
##
## The channel owns ONE 0→1 factor, eased in when such a lock lands and out when it drops. The rig
## spends it on three numbers:
##   - arm 42 → 64 m, so both actors fit across the frame,
##   - pivot +14 m, because a +12° look-up at a 64 m arm would otherwise put the camera UNDER the
##     street (64 · sin 12° = 13.3 m below the 12.5 m pivot),
##   - lock-tracked pitch +12° (CONTRACTS "raises the default pitch by ≈ +12°"), which lifts the frame
##     from the locked core toward the boss's head and drops the hero to the bottom edge.
## Nothing here touches FOV: the arm does the widening, and the FOV channel belongs to the player.

const MIN_HEIGHT := 30.0     ## m: below this the ordinary street framing already fits the actor
const ARM := 64.0            ## CONTRACTS §5 "≈ 64 m"
const PITCH_DEG := 12.0      ## CONTRACTS §5 "raises the default pitch by ≈ +12°"
const PIVOT_LIFT := 14.0     ## m, keeps the camera above the street while it looks up
const EASE_IN := 0.45        ## s to full large framing
const EASE_OUT := 0.70       ## s back to street framing when the lock drops
## The arm's occlusion recovery is 10 m/s (SPEC §5), i.e. 2.2 s for the 22 m a lock-on asks for. The rig
## adds this for as long as the factor is non-zero, so the push-out finishes with the 0.45 s ease.
const PUSH_BONUS := 38.0

var _t: float = 0.0


## `target` is the AimSystem's hard target (a Targetable) or null. Runs on the rig's real clock.
func update(delta: float, target: Node3D) -> void:
	var want := 1.0 if framing_height(target) >= MIN_HEIGHT else 0.0
	var span := EASE_IN if want > _t else EASE_OUT
	_t = move_toward(_t, want, delta / span)


## The actor's declared height in metres, 0 when it does not declare one. CONTRACTS §5 puts
## `framing_height()` on the ACTOR; a Targetable reaches it through `actor()` (core/targetable.gd).
func framing_height(target: Node3D) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	var actor: Node = target
	if target.has_method(&"actor"):
		actor = target.call(&"actor") as Node
	if actor == null or not actor.has_method(&"framing_height"):
		return 0.0
	return maxf(float(actor.call(&"framing_height")), 0.0)


func value() -> float:
	return _t


## True while any part of the large framing is applied (the arm may still be pushing out).
func active() -> bool:
	return _t > 0.0


func arm() -> float:
	return ARM


func pitch_offset() -> float:
	return PITCH_DEG * _t


func pivot_lift() -> float:
	return PIVOT_LIFT * _t


func push_bonus() -> float:
	return PUSH_BONUS if _t > 0.0 else 0.0


## Drop the framing at once (respawn, teleport, cinematic cut) instead of easing out.
func reset() -> void:
	_t = 0.0
