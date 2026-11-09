class_name Spitter
extends EnemyBase
## 酸巢 Spitter — 12 m artillery (SPEC §7). Holds 150–300 m, prefers high ground, lobs acid arcs the
## Mirror Guard catch field can return, and puffs a spore-chaff cloud that eats 4 missiles. Weak sac
## on the back (×2.5). Its attacks are RANGED: they take a ranged attack token, so at most two
## spitters can volley at once and the player is never buried in arcs.

const LOB := {
	"id": &"spitter_acid_lob", "kind": EnemyAttack.RANGED, "telegraph": 0.6, "active": 0.2,
	"recover": 0.9, "damage": 320.0, "impact": 188.0, "knockback": 12.0, "range_min": 60.0,
	"range_max": 320.0, "arc_deg": 60.0, "cooldown": 3.2, "weight": 1.0, "reflectable": true,
	"blast_radius": 12.0, "projectile_speed": 110.0, "hit_kind": HitInfo.EXPLOSIVE, "anim": &"lob",
}
const CHAFF := {
	"id": &"spitter_chaff", "kind": EnemyAttack.RANGED, "telegraph": 0.45, "active": 0.15,
	"recover": 0.7, "damage": 0.0, "impact": 0.0, "knockback": 0.0, "range_min": 0.0,
	"range_max": 340.0, "arc_deg": 360.0, "cooldown": 12.0, "weight": 0.25, "anim": &"chaff",
}

const STANDOFF_MIN := 150.0   ## SPEC §7: keeps 150–300 m away
const STANDOFF_MAX := 300.0
const HIGH_GROUND_EVERY := 4.0

var _table: Array[EnemyAttack] = []
var _ground_left: float = 0.0
var _high_point: Vector3 = Vector3.ZERO
var _has_high: bool = false


func _ready() -> void:
	enemy_type = EnemyTypes.SPITTER
	circle_speed = 0.12
	_table = EnemyAttack.make_all([LOB, CHAFF])
	super._ready()
	engage_range = STANDOFF_MAX   ## it opens fire anywhere inside its stand-off band


func attacks() -> Array[EnemyAttack]:
	return _table


func token_kind() -> StringName:
	return AttackTokenPool.RANGED


## Artillery stand-off: back off when the player closes inside 150 m, close in past 300 m, and
## otherwise hold the ring and drift toward high ground.
func desired_point(flank: float) -> Vector3:
	var hunt := perception.hunt_point()
	if not perception.has_hunt_point():
		return global_position
	var away := global_position - hunt
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.FORWARD
	var dist := away.length()
	var want: float = clampf(dist, STANDOFF_MIN, STANDOFF_MAX)
	var point := hunt + away.normalized() * want
	if _has_high:
		point = Vector3(point.x, _high_point.y, point.z)
	return point


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not alive or is_paused():
		return
	_ground_left -= delta
	if _ground_left <= 0.0:
		_ground_left = HIGH_GROUND_EVERY
		_find_high_ground()


## Cheap high-ground search: sample the navmesh map ahead and keep the highest reachable point.
## Queries before the map's first synchronisation are engine errors, so the spitter asks its own
## agent class map (CONTRACTS §7) and stays put until that map is ready.
func _find_high_ground() -> void:
	var map := EnemyTypes.nav_map_for(self, enemy_type)
	if not EnemyTypes.map_ready(map):
		_has_high = false
		_high_point = global_position
		return
	var from := global_position
	var dir := -global_transform.basis.z
	var best := from
	for i in 3:
		var probe := from + dir.rotated(Vector3.UP, (float(i) - 1.0) * 0.6) * 90.0
		var snapped := NavigationServer3D.map_get_closest_point(map, probe)
		if snapped.y > best.y:
			best = snapped
	_has_high = best.y > from.y + 2.0
	_high_point = best


func attack_started(attack: EnemyAttack) -> void:
	if attack.id == &"spitter_chaff":
		SporeChaff.spawn(get_parent(), global_position + Vector3.UP * body_height * 0.8, self)
