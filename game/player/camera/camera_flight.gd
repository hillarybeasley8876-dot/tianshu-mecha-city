extends Node
## Flight framing (camera-aim, lead r7 item 3). A flying mech leaves the ground plane fast — 50 m/s
## cruise, 84 m/s assault, 20 m/s climb, 95 m/s dive — and every number in the ground rig was solved
## for a mech that skates at 16–42 m/s along a street. This channel engages while
## `PlayerMech.is_flying()` and spends ONE 0→1 factor on four things:
##
##   * a velocity lead on the follow pivot that cancels the critically damped spring's steady-state
##     ramp lag (2v/ω — 24 m at 84 m/s on the boost spring), so the pivot sits ON the hero instead of
##     trailing it. That is also what keeps the arm's occlusion probe spanning camera → hero rather
##     than camera → where the hero used to be;
##   * a dead-zone pitch follow: the hero may sit DEAD of the frame's half-height off the view axis
##     before the view eases back, so the player's own aim is never fought inside the band;
##   * a speed-scaled arm, so an 84 m/s jet does not sweep the world past at a walk's rate;
##   * a faster arm push-out (through `CameraArm.set_push_bonus`), because a pillar passed at 84 m/s is
##     gone in 0.05 s and the SPEC §5 recovery rate of 10 m/s would leave the hero small for 4 s.
##
## Everything is multiplied by the factor, so touchdown hands the street rig straight back.

const ENGAGE := 0.30       ## s the flight framing takes to come in
const RELEASE := 0.45      ## s it takes to leave again
const OMEGA := 9.0         ## rad/s follow spring while flying (ground: 10 walking, 7 boosting)
const DEAD := 0.12         ## fraction of the frame's half-height the hero may sit off the view axis
const PITCH_RATE := 70.0   ## deg/s at full excess, scaled down to 0 at the edge of the band
const ARM_FLY := 44.0      ## m, the arm while flying at cruise
const ARM_FAST := 52.0     ## m, the arm at SPEED_FAST
const SPEED_SLOW := 25.0   ## m/s at or below which the arm stays at ARM_FLY
const SPEED_FAST := 84.0   ## = MechTuning.flight_boost_speed
const PUSH := 60.0         ## m/s of extra arm push-out while flying (SPEC §5 recovery is 10 m/s)

var _t: float = 0.0
var _vel: Vector3 = Vector3.ZERO
var _speed: float = 0.0


## `player` is `Game.player`; a stand-in without `is_flying()` simply never engages the channel.
func update(delta: float, player: Node3D) -> void:
	var flying := player != null and player.has_method(&"is_flying") \
			and bool(player.call(&"is_flying"))
	_t = move_toward(_t, 1.0 if flying else 0.0, delta / (ENGAGE if flying else RELEASE))
	if player == null:
		_vel = Vector3.ZERO
		_speed = 0.0
		return
	var v: Variant = player.get(&"velocity")
	_vel = v as Vector3 if v is Vector3 else Vector3.ZERO
	_speed = _vel.length()


## 0 = the street rig, 1 = full flight framing. The rig multiplies every contribution by this.
func value() -> float:
	return _t


func omega() -> float:
	return OMEGA


## Seconds of velocity lead that cancels the spring's ramp lag exactly (2/ω for a critically damped
## spring tracking a constant velocity).
func lead() -> float:
	return 2.0 / OMEGA


func velocity() -> Vector3:
	return _vel


func speed() -> float:
	return _speed


## Arm length while flying: ARM_FLY at cruise, opening to ARM_FAST at the assault speed.
func arm() -> float:
	return lerpf(ARM_FLY, ARM_FAST, clampf((_speed - SPEED_SLOW) / (SPEED_FAST - SPEED_SLOW), 0.0, 1.0))


## Extra arm push-out in m/s, so the view recovers from a pillar at flight speed instead of creeping.
func push_bonus() -> float:
	return PUSH * _t


## Degrees per second the view should turn to bring the hero back inside the dead-zone band; positive
## is "look up". Zero while the hero is inside the band, so the player's own pitch is untouched there.
func pitch_rate(cam: Camera3D, chest: Vector3, pitch_deg: float) -> float:
	if _t <= 0.0 or cam == null:
		return 0.0
	var to := chest - cam.global_position
	var flat := Vector2(to.x, to.z).length()
	if flat < 0.01 and absf(to.y) < 0.01:
		return 0.0
	var err := rad_to_deg(atan2(to.y, flat)) - pitch_deg
	var frac := clampf(err / maxf(cam.fov * 0.5, 1.0), -2.0, 2.0)
	if absf(frac) <= DEAD:
		return 0.0
	var excess := clampf((absf(frac) - DEAD) / (1.0 - DEAD), 0.0, 1.0)
	return signf(frac) * PITCH_RATE * excess * _t
