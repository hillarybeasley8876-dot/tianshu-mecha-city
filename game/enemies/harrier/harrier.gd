class_name Harrier
extends EnemyBase
## 鸣翼 Harrier — 16 m flyer (SPEC §7). Circles at 60–120 m, makes strafing runs with a flat burst and
## dive-bombs (unblockable, 0.5 s screech). Grapple-able (the Skyhook finds its `Targetable`). Never
## touches the navmesh: it steers in 3D with obstacle whiskers (EnemyLocomotion).

const STRAFE := {
	"id": &"harrier_strafe", "kind": EnemyAttack.RANGED, "telegraph": 0.5, "active": 0.55,
	"recover": 0.7, "damage": 160.0, "impact": 88.0, "knockback": 8.0, "range_min": 30.0,
	"range_max": 140.0, "arc_deg": 70.0, "cooldown": 2.6, "weight": 1.2, "reflectable": true,
	"projectile_speed": 220.0, "hit_kind": HitInfo.BALLISTIC, "anim": &"strafe",
}
const DIVE := {
	"id": &"harrier_dive_bomb", "kind": EnemyAttack.UNBLOCKABLE, "telegraph": 0.65, "active": 0.7,
	"recover": 1.0, "damage": 755.0, "impact": 475.0, "knockback": 26.0, "range_min": 0.0,
	"range_max": 150.0, "arc_deg": 200.0, "cooldown": 7.0, "weight": 0.7, "lunge_speed": 95.0,
	"blast_radius": 0.0, "anim": &"dive",
}

const ORBIT_MIN := 60.0    ## SPEC §7: circle at 60–120 m
const ORBIT_MAX := 120.0
const CRUISE_HEIGHT := 45.0
const DIVE_TRIGGER := 0.25  ## chance per attack pick once it is overhead

var _table: Array[EnemyAttack] = []


func _ready() -> void:
	enemy_type = EnemyTypes.HARRIER
	is_flyer = true
	circle_speed = 0.55
	_table = EnemyAttack.make_all([STRAFE, DIVE])
	super._ready()


func attacks() -> Array[EnemyAttack]:
	return _table


func token_kind() -> StringName:
	return AttackTokenPool.RANGED


## Orbits the player at 60–120 m and above the deck, so a run always comes in from a new bearing.
func desired_point(flank: float) -> Vector3:
	var hunt := perception.hunt_point()
	if not perception.has_hunt_point():
		return global_position
	var want: float = lerpf(ORBIT_MIN, ORBIT_MAX, 0.5 + 0.5 * sin(flank * 0.7))
	var at := hunt + Vector3(cos(flank), 0.0, sin(flank)) * want
	return Vector3(at.x, hunt.y + CRUISE_HEIGHT, at.z)


func choose_attack() -> EnemyAttack:
	if randf() < DIVE_TRIGGER:
		return _table[1]
	return _table[0]


func attack_windup(attack: EnemyAttack, dt: float) -> void:
	if attack.id == &"harrier_dive_bomb":
		# Climb and line up during the screech: the tell is the sound plus the nose dropping.
		loco.steer_to(target_centre() + Vector3.UP * 30.0, 0.7, dt)
		face_dir_3d(target_centre() - global_position, dt)
		return
	super.attack_windup(attack, dt)


func attack_active(attack: EnemyAttack, dt: float, hit_done: bool) -> void:
	if attack.id != &"harrier_dive_bomb":
		loco.steer_to(target_centre(), 0.8, dt)
		face_dir_3d(velocity, dt)
		return
	var to := target_centre() - global_position
	if to.length() > 12.0 and not hit_done:
		loco.dash_along(to, attack.lunge_speed, dt)
		face_dir_3d(to, dt)
	else:
		loco.decelerate(dt)


func attack_recover(attack: EnemyAttack, dt: float) -> void:
	if attack.id == &"harrier_dive_bomb":
		loco.steer_to(global_position + Vector3.UP * 60.0, 0.9, dt)   ## pull up and out
		face_dir_3d(velocity, dt)
		return
	super.attack_recover(attack, dt)
