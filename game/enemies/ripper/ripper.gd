class_name Ripper
extends EnemyBase
## 裂爪 Ripper — 6 m swarmer (SPEC §7). Packs of 6–16 that flank and close; leap-bite is parryable
## with a 0.45 s crouch telegraph; one rifle shot kills it (400 HP against the rifle's 700).
## Circles fast so a pack surrounds the player instead of queueing behind each other.

const LEAP := {
	"id": &"ripper_leap_bite", "kind": EnemyAttack.PARRYABLE, "telegraph": 0.45, "active": 0.30,
	"recover": 0.55, "damage": 125.0, "impact": 75.0, "knockback": 10.0, "range_min": 0.0,
	"range_max": 40.0, "arc_deg": 90.0, "cooldown": 1.6, "weight": 1.0, "lunge_speed": 46.0,
	"anim": &"leap",
}
const BITE := {
	"id": &"ripper_bite", "kind": EnemyAttack.PARRYABLE, "telegraph": 0.40, "active": 0.16,
	"recover": 0.5, "damage": 100.0, "impact": 56.0, "knockback": 7.0, "range_min": 0.0,
	"range_max": 16.0, "arc_deg": 130.0, "cooldown": 1.1, "weight": 1.2, "anim": &"attack_1",
}

var _table: Array[EnemyAttack] = []


func _ready() -> void:
	enemy_type = EnemyTypes.RIPPER
	circle_speed = 0.9
	_table = EnemyAttack.make_all([LEAP, BITE])
	super._ready()


func attacks() -> Array[EnemyAttack]:
	return _table


## Flanking: each ripper keeps its own bearing around the player and closes to bite range, so a
## pack arrives from several sides at once (SPEC §7 "flank").
func desired_point(flank: float) -> Vector3:
	var hunt := perception.hunt_point()
	if not perception.has_hunt_point():
		return global_position
	return hunt + Vector3(cos(flank), 0.0, sin(flank)) * engage_range


## Leap-bite: crouch (the telegraph), then cover the gap during the active window.
func attack_active(attack: EnemyAttack, dt: float, hit_done: bool) -> void:
	if attack.id != &"ripper_leap_bite":
		super.attack_active(attack, dt, hit_done)
		return
	var to := target_centre() - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > engage_range * 0.6 and not hit_done:
		loco.dash_along(to, attack.lunge_speed, dt)
		if is_on_floor() and velocity.y <= 0.0:
			velocity.y = 18.0   ## a real leap, so the bite reads as a pounce
	else:
		loco.decelerate(dt)
