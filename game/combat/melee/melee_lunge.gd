class_name MeleeLunge
extends RefCounted
## The Dawn Edge's two movement verbs (skills-catalog §4.3): the 6 m step-in that opens the ground
## string, and the homing lunge that closes 24–80 m at 110 m/s on a hard-locked target. Both drive
## the player through `player.lunge_to` (CONTRACTS §5), which MechLocomotion integrates.
##
## Homing is 120°/s: the travel direction is steered toward the locked target and the lunge is
## re-issued every tick with the time that is left, because MechLocomotion only takes a point.

var player: Node = null
var strike: MeleeStrike = null

var target: Node3D = null
var time_left: float = 0.0


func _init(player_: Node, strike_: MeleeStrike) -> void:
	player = player_
	strike = strike_


## A hard lock inside 24–80 m with 140 EN in the tank arms the lunge.
func ready() -> bool:
	return target_in_band() != null and energy() >= MeleeTable.LUNGE_EN


func target_in_band() -> Node3D:
	var t := strike.hard_target()
	if t == null or not is_instance_valid(t):
		return null
	var d := strike.flat_distance(t.global_position)
	return t if d >= MeleeTable.LUNGE_MIN and d <= MeleeTable.LUNGE_MAX else null


func begin() -> void:
	target = target_in_band()
	time_left = MeleeTable.LUNGE_TIME


func clear() -> void:
	target = null
	time_left = 0.0


## L1's 6 m step-in (3 m in the dossier, ×2): MechLocomotion stops `lunge_arrive` metres short, so
## the order aims past the step distance.
func step_in(metres: float) -> void:
	if player == null or not player.has_method(&"lunge_to"):
		return
	var to: Vector3 = strike.pivot() + (-strike.facing().z) * (metres + 4.0)
	player.call(&"lunge_to", to, 60.0, 0.18)


## One tick of homing travel, in player time (CONTRACTS §3): the 0.7 s budget freezes in a hit-stop
## and runs at full speed through witch time. Returns false when the lunge is over.
func advance(delta: float) -> bool:
	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0 or target == null or not is_instance_valid(target) \
			or player == null or not player.has_method(&"lunge_to") or not (player is Node3D):
		return false
	var body := player as Node3D
	var to := target.global_position - body.global_position
	to.y = 0.0
	if to.length() < MeleeTable.LUNGE_STOP:
		return false
	var current := -strike.facing().z
	var max_turn := deg_to_rad(MeleeTable.LUNGE_HOMING_DEG) * delta
	var angle := current.signed_angle_to(to.normalized(), Vector3.UP)
	var dir := current.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn))
	body.look_at(body.global_position + dir, Vector3.UP)
	player.call(&"lunge_to", body.global_position + dir * to.length(),
			MeleeTable.LUNGE_SPEED, time_left)
	return true


func energy() -> float:
	var v: Variant = player.get(&"energy") if player != null else null
	return float(v) if v is float or v is int else 0.0
