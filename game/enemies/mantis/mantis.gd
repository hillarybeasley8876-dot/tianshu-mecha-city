class_name Mantis
extends EnemyBase
## 镰影 Mantis — 14 m duelist (SPEC §7). Three-hit parryable combo (white glint 0.35 s before each
## swing), an unblockable red grab (0.6 s tell) and a sidestep when the player aims at it. Hunts in
## pairs, so the combo pressure comes from two directions.

const COMBO_1 := {
	"id": &"mantis_slash_1", "kind": EnemyAttack.PARRYABLE, "telegraph": 0.40, "active": 0.14,
	"recover": 0.34, "damage": 280.0, "impact": 225.0, "knockback": 8.0, "range_min": 0.0,
	"range_max": 34.0, "arc_deg": 120.0, "cooldown": 0.9, "weight": 1.4, "anim": &"attack_1",
}
const COMBO_2 := {
	"id": &"mantis_slash_2", "kind": EnemyAttack.PARRYABLE, "telegraph": 0.40, "active": 0.14,
	"recover": 0.34, "damage": 225.0, "impact": 180.0, "knockback": 8.0, "range_min": 0.0,
	"range_max": 34.0, "arc_deg": 140.0, "cooldown": 0.9, "weight": 1.2, "anim": &"attack_2",
}
const COMBO_3 := {
	"id": &"mantis_slash_3", "kind": EnemyAttack.PARRYABLE, "telegraph": 0.48, "active": 0.2,
	"recover": 0.6, "damage": 565.0, "impact": 400.0, "knockback": 16.0, "range_min": 0.0,
	"range_max": 36.0, "arc_deg": 200.0, "cooldown": 1.4, "weight": 0.9, "anim": &"attack_3",
}
const GRAB := {
	"id": &"mantis_grab", "kind": EnemyAttack.UNBLOCKABLE, "telegraph": 0.6, "active": 0.24,
	"recover": 0.9, "damage": 970.0, "impact": 525.0, "knockback": 22.0, "range_min": 0.0,
	"range_max": 30.0, "arc_deg": 80.0, "cooldown": 6.0, "weight": 0.5, "lunge_speed": 30.0,
	"anim": &"grab",
}

const SIDESTEP_COOLDOWN := 2.6
const SIDESTEP_TIME := 0.30  ## the slide lasts long enough to actually break the shot line
const SIDESTEP_SPEED := 1.6   ## × move_speed
const AIM_DOT := 0.93   ## the player is looking almost straight at it

var _table: Array[EnemyAttack] = []
var _sidestep_left: float = 0.0
var _slide_left: float = 0.0
var _slide_dir: Vector3 = Vector3.ZERO
var _combo_step: int = 0


func _ready() -> void:
	enemy_type = EnemyTypes.MANTIS
	circle_speed = 0.45
	_table = EnemyAttack.make_all([COMBO_1, COMBO_2, COMBO_3, GRAB])
	super._ready()


func attacks() -> Array[EnemyAttack]:
	return _table


## Combo: after a parryable slash, the next pick is the following step of the 3-hit string.
func choose_attack() -> EnemyAttack:
	if _combo_step > 0 and _combo_step < 3:
		_combo_step += 1
		return _table[_combo_step - 1]
	var a := EnemyStrike.choose(_table)
	_combo_step = 1 if a != null and a.kind == EnemyAttack.PARRYABLE else 0
	return a


func attack_recover(attack: EnemyAttack, dt: float) -> void:
	super.attack_recover(attack, dt)
	if state() != EnemyBrain.ATTACK:
		_combo_step = 0


func on_spawned() -> void:
	_slide_left = 0.0
	_sidestep_left = 0.0


## Sidesteps a aimed shot (SPEC §7): reads the player's facing and slides off the line.
## The slide owns the mantis's horizontal velocity for SIDESTEP_TIME — a single `dash_along` call
## moved it about 3 cm, because the brain's steering cancelled it on the very next tick (audit #10).
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not alive or is_paused():
		return
	if _slide_left > 0.0:
		_slide_left -= delta
		var speed := move_speed * SIDESTEP_SPEED * status.slow_factor
		velocity.x = _slide_dir.x * speed
		velocity.z = _slide_dir.z * speed
		return
	_sidestep_left = maxf(0.0, _sidestep_left - delta)
	if _sidestep_left > 0.0 or status.is_staggered():
		return
	var player := target()
	if player == null or not (&"facing" in player):
		return
	var to_me := (global_position - player.global_position).normalized()
	var facing: Basis = player.call(&"facing")
	if (-facing.z).dot(to_me) < AIM_DOT:
		return
	_slide_dir = Vector3.UP.cross(to_me).normalized() * (1.0 if randf() < 0.5 else -1.0)
	_slide_left = SIDESTEP_TIME
	play_action(&"sidestep")
	_sidestep_left = SIDESTEP_COOLDOWN
