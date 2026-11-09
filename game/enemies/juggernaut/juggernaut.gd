class_name Juggernaut
extends EnemyBase
## 裂山 Juggernaut — 22 m brute (SPEC §7). Unblockable charge (0.7 s roar + ground glow) and a
## ground-slam shockwave ring you jump over. Front armour plates take ×0.15 and break off one by one;
## the glowing weak point on its back takes ×2.5. Slow turn rate on purpose: getting behind it is the
## whole fight.

const CHARGE := {
	"id": &"juggernaut_charge", "kind": EnemyAttack.UNBLOCKABLE, "telegraph": 0.7, "active": 1.4,
	"recover": 1.3, "damage": 1295.0, "impact": 875.0, "knockback": 40.0, "range_min": 80.0,
	"range_max": 260.0, "arc_deg": 70.0, "cooldown": 8.0, "weight": 1.0, "lunge_speed": 60.0,
	"anim": &"charge",
}
const SLAM := {
	"id": &"juggernaut_slam", "kind": EnemyAttack.UNBLOCKABLE, "telegraph": 0.75, "active": 0.25,
	"recover": 1.6, "damage": 970.0, "impact": 500.0, "knockback": 26.0, "range_min": 0.0,
	"range_max": 70.0, "arc_deg": 360.0, "cooldown": 5.0, "weight": 1.8, "shockwave_radius": 120.0,
	"hit_kind": HitInfo.CRUSH, "anim": &"slam",
}
const SWIPE := {
	"id": &"juggernaut_swipe", "kind": EnemyAttack.PARRYABLE, "telegraph": 0.45, "active": 0.2,
	"recover": 0.8, "damage": 665.0, "impact": 375.0, "knockback": 24.0, "range_min": 0.0,
	"range_max": 48.0, "arc_deg": 160.0, "cooldown": 2.4, "weight": 0.8, "anim": &"attack_1",
}

## Front plates break after this much damage lands on them; each break exposes more of the body.
const PLATE_HP := 900.0

var _table: Array[EnemyAttack] = []
var _plate_hp: float = PLATE_HP
var _plates: int = 3
## Latch: `attack_windup` runs every tick, and a one-shot restarted each tick never advances past
## its first frame (lead r10). The roar is fired once per charge windup.
var _roared: bool = false


func _ready() -> void:
	enemy_type = EnemyTypes.JUGGERNAUT
	circle_speed = 0.22
	_table = EnemyAttack.make_all([CHARGE, SLAM, SWIPE])
	super._ready()


func attacks() -> Array[EnemyAttack]:
	return _table


## Charge only to close a real gap, slam when close: the ring forces the player to jump and is the
## brute's signature move, so it has to be the common case inside 70 m, not a rare roll. The swipe
## is the low-weight punish for standing still.
func choose_attack() -> EnemyAttack:
	var dist := global_position.distance_to(target_centre())
	if dist > CHARGE["range_min"]:
		return _table[0]
	return EnemyStrike.choose([_table[1], _table[2]])


## The charge announces itself with the 0.7 s roar windup SPEC §7 asks for: the clip is 2.75 s, so
## it is started at the top of the windup and the charge clip takes the player back the moment the
## dash begins — the tell (and its timing) is unchanged, only what the body does during it.
func begin_telegraph(attack: EnemyAttack) -> void:
	_roared = false
	super.begin_telegraph(attack)


func attack_windup(attack: EnemyAttack, dt: float) -> void:
	if attack.id == &"juggernaut_charge":
		loco.decelerate(dt)
		face_dir(target_centre() - global_position, dt)
		if not _roared:
			_roared = true
			play_action(&"roar")
		return
	super.attack_windup(attack, dt)


## The brain plays the attack clip once at telegraph start, before this type has had a chance to
## roar over it; the dash therefore re-arms the charge clip itself, or the brute slides 260 m in a
## roar pose.
func attack_started(attack: EnemyAttack) -> void:
	if attack.id == &"juggernaut_charge":
		play_action(attack.anim)
	super.attack_started(attack)


func attack_active(attack: EnemyAttack, dt: float, hit_done: bool) -> void:
	if attack.id == &"juggernaut_charge" and not hit_done:
		loco.dash_along(-global_transform.basis.z, attack.lunge_speed, dt)
		return
	super.attack_active(attack, dt, hit_done)


## Front armour: hits on the plate (or the body behind it) chip the plate away. Each break hides a
## plate mesh and opens that side up to full damage.
func take_hit(hit: HitInfo) -> void:
	if alive and _plates > 0 and hit.hurtbox_part in [&"plate", &"body"]:
		_plate_hp -= hit.amount
		if _plate_hp <= 0.0:
			_break_plate()
	super.take_hit(hit)


func _break_plate() -> void:
	_plate_hp = PLATE_HP
	_plates -= 1
	if model != null and model.has_method(&"break_plate"):
		model.call(&"break_plate")
	if _plates <= 0:
		var hb := get_node_or_null(^"Hurtbox_plate") as Hurtbox
		if hb != null:
			hb.collision_layer = 0   ## nothing left to bounce shots off
	Feel.play(&"stagger_enemy", global_position, 0.7)
	Audio.play(&"juggernaut_plate_break", global_position)


func plates_left() -> int:
	return _plates


func hud_state() -> Dictionary:
	var s := super.hud_state()
	s["plates"] = _plates
	return s
