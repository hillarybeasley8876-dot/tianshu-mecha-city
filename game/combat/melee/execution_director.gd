class_name ExecutionDirector
extends Node
## Core Rend (skills-catalog §4.6): a melee press on a staggered enemy inside 14 m and ±60° plays an
## invulnerable mini-cinematic — the model snaps to the victim, the camera cuts to 2–3 TPS shots, the
## enemy takes `execute_hit`, the core ruptures for 1,200 / 1,000 in 20 m and the player banks
## +300 EN, +8 % OD and +5 % HP. JACKPOT (a boss or brute killed by the Lance or rifle stage 2) is
## reported here so the melee system can show the HUD flag.

const RUPTURE_DAMAGE := 1200.0
const RUPTURE_IMPACT := 1000.0
const RUPTURE_RADIUS := 20.0     ## 10 m in the dossier, ×2 for our 16 m hero
const REWARD_EN := 300.0
const REWARD_OD := 8.0
const REWARD_HP := 0.05          ## fraction of hp_max
const JACKPOT_SCALE := 0.2
const JACKPOT_TIME := 0.5

## Duration and damage by enemy class (skills-catalog §4.6). A Colossus survives at 12 % max HP.
const CLASSES: Dictionary = {
	&"light": {"duration": 0.9, "damage": 4000.0, "hp_fraction": 1.0},
	&"brute": {"duration": 1.8, "damage": 9000.0, "hp_fraction": 1.0},
	&"colossus": {"duration": 2.4, "damage": 0.0, "hp_fraction": 0.12},
}

## Cinematic shots per class, in the DUEL FRAME (CONTRACTS §5 / camera_cinematic.gd): the origin is
## the midpoint of player and victim, −Z points player → victim, +Y is up, +X is right. So +Z is
## behind the player, −Z past the victim, and X = 0 is the line between them.
##
## `at` is a fraction of the class duration. `look` names a point: `mid` between the fighters,
## `core` the victim's core, `hero` the player's chest. The rig resolves each shot against
## collision, so these are composition, not safety.
const SHOTS: Dictionary = {
	&"light": [
		{"at": 0.0, "offset": Vector3(34.0, 9.0, 0.0), "look": &"mid", "fov": 50.0},
		{"at": 0.5, "offset": Vector3(17.0, 6.0, -11.0), "look": &"core", "fov": 56.0},
	],
	&"brute": [
		{"at": 0.0, "offset": Vector3(40.0, 10.0, 0.0), "look": &"mid", "fov": 48.0},
		{"at": 0.35, "offset": Vector3(-11.0, 4.0, 18.0), "look": &"core", "fov": 52.0},
		{"at": 0.68, "offset": Vector3(18.0, 8.0, -12.0), "look": &"core", "fov": 58.0},
	],
	&"colossus": [
		{"at": 0.0, "offset": Vector3(52.0, 16.0, 6.0), "look": &"mid", "fov": 46.0},
		{"at": 0.36, "offset": Vector3(-18.0, 8.0, 32.0), "look": &"core", "fov": 52.0},
		{"at": 0.7, "offset": Vector3(26.0, 12.0, -20.0), "look": &"core", "fov": 58.0},
	],
}
const CORE_FRACTION := 0.55   ## the core sits this far up the victim's AABB
## The `core` look point is pulled this far back toward the frame origin, so the shot still leans on
## the victim's core while the hero stays inside the frustum (the r1 framing test).
const CORE_BIAS := 0.5

var active: bool = false
var jackpot: bool = false
var jackpots: int = 0

var _player: Node3D = null
var _victim: Node = null
var _left: float = 0.0
var _duration: float = 0.0
var _ruptured: bool = false
var _model: Node = null

signal started(victim: Node, duration: float)
signal finished(victim: Node)


func setup(player: Node3D, model: Node) -> void:
	_player = player
	_model = model
	if not Events.enemy_killed.is_connected(_on_enemy_killed):
		Events.enemy_killed.connect(_on_enemy_killed)


## Which Core Rend profile an enemy gets: the brute family is 1.8 s, a boss 2.4 s, everything else
## 0.9 s. Reads `enemy_type` when the archetype exposes it (CONTRACTS §6).
static func class_of(enemy: Node) -> StringName:
	var actor := actor_of(enemy)
	if actor == null:
		return &"light"
	if actor.get(&"enemy_type") == &"juggernaut":
		return &"brute"
	if actor.has_method(&"is_boss") and bool(actor.call(&"is_boss")):
		return &"colossus"
	return &"light"


## The actor behind a lock-on point. `AimSystem.hard_target()` hands out a `Targetable` marker
## (CONTRACTS §4), not the enemy itself, so every entry point here resolves it first — without this
## the Core Rend never fires in the real game, only in a rig that returns the enemy directly.
static func actor_of(node: Node) -> Node:
	if node == null:
		return null
	if node.has_method(&"is_executable") or node.has_method(&"take_hit"):
		return node
	if node.has_method(&"actor"):
		var a: Variant = node.call(&"actor")
		if a is Node:
			return a as Node
	return node


## True when `target` can be executed right now (staggered, alive, 14 m, ±60°): the gate the melee
## system checks on every press. Accepts a `Targetable` or an actor.
func available(target: Node) -> bool:
	var enemy := actor_of(target)
	if active or enemy == null or not is_instance_valid(enemy) or _player == null:
		return false
	if not enemy.has_method(&"is_executable"):
		return false
	return bool(enemy.call(&"is_executable", _player))


## Plays the whole Core Rend. Returns false when the gate refuses.
func start(target: Node) -> bool:
	var enemy := actor_of(target)
	if not available(enemy):
		return false
	var cls := class_of(enemy)
	var row: Dictionary = CLASSES[cls]
	_duration = float(row["duration"])
	_left = _duration
	_ruptured = false
	_victim = enemy
	active = true
	_grant_invulnerability()
	_face_victim(enemy)
	if _model != null and _model.has_method(&"play_action"):
		_model.call(&"play_action", &"execution", 0.05)
	_cut_camera(enemy, _duration)
	_damage(enemy, row)
	started.emit(enemy, _duration)
	Events.melee_swing.emit(&"execution", 1)
	return true


## The cut runs on player time (CONTRACTS §3): a hit-stop during the finisher holds the shot, and
## witch time does not stretch a 0.9 s execution into a crawl.
func _physics_process(delta: float) -> void:
	if not active:
		return
	_left -= Feel.player_delta(delta)
	if not _ruptured and _left <= _duration * 0.55:
		_rupture()
	if _left <= 0.0:
		_finish()


func _finish() -> void:
	var victim := _victim
	active = false
	_victim = null
	_left = 0.0
	if not _ruptured:
		_rupture()
	finished.emit(victim)


func cancel() -> void:
	if active:
		_left = 0.0
		_finish()


func victim() -> Node:
	return _victim


func progress() -> float:
	if not active or _duration <= 0.0:
		return 0.0
	return clampf(1.0 - _left / _duration, 0.0, 1.0)


func _grant_invulnerability() -> void:
	if _player != null and _player.has_method(&"invulnerable_for"):
		## juice §5: invulnerable for the whole lock, plus the finisher's own tail.
		_player.call(&"invulnerable_for", _duration + 0.25)


func _face_victim(enemy: Node) -> void:
	if _player == null or not (enemy is Node3D):
		return
	var to: Vector3 = (enemy as Node3D).global_position - _player.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return
	if _player.has_method(&"lock_movement"):
		_player.call(&"lock_movement", _duration * 0.6, false)
	_player.look_at(_player.global_position + to, Vector3.UP)


## Two to three third-person shots in the duel frame (CONTRACTS §5): a side wide with both mechs,
## a low over-the-hero angle on the victim's core, and — for the big classes — a close impact shot
## as the core ruptures. The rig turns these into world transforms and keeps them out of geometry.
func _cut_camera(enemy: Node, duration: float) -> void:
	var rig: Node = Game.camera_rig
	if rig == null or not rig.has_method(&"request_cinematic"):
		return
	var shots := shots_for(class_of(enemy), duration, _frame(enemy), _core(enemy),
			_player_chest())
	## CONTRACTS §5 per-request clock: the cut must run on PLAYER time, or the `finisher` slow-mo every
	## execution plays ends the shot list ~0.3 s before the execution it is framing (and the `core` shot
	## lands before the rupture). Rigs older than that argument only take (shots, duration).
	if int(rig.get_method_argument_count(&"request_cinematic")) >= 3:
		rig.call(&"request_cinematic", shots, duration, &"player")
	else:
		rig.call(&"request_cinematic", shots, duration)


## The shot list for a class: `at` scaled to `duration` and every named look point resolved into
## duel-frame coordinates. Public and static so the framing test can walk every shot of every class
## against the same frame the rig builds.
static func shots_for(cls: StringName, duration: float, frame: Transform3D, core: Vector3,
		hero: Vector3) -> Array[Dictionary]:
	var inv := frame.affine_inverse()
	var core_local := (inv * core).lerp(Vector3.ZERO, CORE_BIAS)
	var out: Array[Dictionary] = []
	for row: Dictionary in SHOTS.get(cls, SHOTS[&"light"]):
		out.append({
			"t": float(row["at"]) * duration,
			"offset": row["offset"] as Vector3,
			"look": look_point(row["look"] as StringName, core_local, inv * hero),
			"fov": float(row["fov"]),
		})
	return out


## A named look point, in duel-frame coordinates.
static func look_point(tag: StringName, core_local: Vector3, hero_local: Vector3) -> Vector3:
	match tag:
		&"core":
			return core_local
		&"hero":
			return hero_local
		_:
			return Vector3.ZERO


## The duel frame for two world positions (CONTRACTS §5): midpoint origin, −Z player → victim.
## The camera rig builds the identical frame from the live actors; this copy is what lets the
## framing test place a camera without booting a rig.
static func duel_frame(a: Vector3, b: Vector3, fallback_forward: Vector3 = Vector3.FORWARD) \
		-> Transform3D:
	var forward := b - a
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = fallback_forward
		forward.y = 0.0
		if forward.length_squared() < 0.01:
			forward = Vector3.FORWARD
	var z := -forward.normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Transform3D(Basis(x, Vector3.UP, z), (a + b) * 0.5)


func _frame(enemy: Node) -> Transform3D:
	if not (enemy is Node3D) or _player == null:
		return Transform3D.IDENTITY
	return duel_frame((_player as Node3D).global_position, (enemy as Node3D).global_position,
			-(_player as Node3D).global_basis.z)


func _player_chest() -> Vector3:
	return (_player as Node3D).global_position + Vector3.UP * 2.0 if _player is Node3D \
			else Vector3.ZERO


## The victim's core: this far up its AABB, which is where `execute_hit` ruptures it.
func _core(enemy: Node) -> Vector3:
	if not (enemy is Node3D):
		return Vector3.ZERO
	var box := _aabb(enemy as Node3D)
	return Vector3(box.get_center().x, box.position.y + box.size.y * CORE_FRACTION,
			box.get_center().z)


## World bounds of an actor from its meshes, falling back to a 12 m box around its origin.
static func _aabb(node: Node3D) -> AABB:
	var body := node
	if node.has_method(&"model"):
		var model := node.call(&"model") as Node3D
		if model != null:
			body = model
	var out := AABB()
	var found := false
	for child in body.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		out = box if not found else out.merge(box)
		found = true
	return out if found else AABB(node.global_position - Vector3(6, 6, 6), Vector3(12, 12, 12))


func _damage(enemy: Node, row: Dictionary) -> void:
	if not enemy.has_method(&"execute_hit"):
		return
	var dmg := float(row["damage"])
	var frac := float(row["hp_fraction"])
	if frac < 1.0:
		dmg = maxf(dmg, _num(enemy, &"hp_max") * frac)
	enemy.call(&"execute_hit", _player, dmg)
	_rewards()


func _rewards() -> void:
	if _player == null:
		return
	if _player.has_method(&"add_energy"):
		_player.call(&"add_energy", REWARD_EN)
	if _player.has_method(&"add_overdrive"):
		_player.call(&"add_overdrive", REWARD_OD)
	if _player.has_method(&"heal"):
		_player.call(&"heal", _num(_player, &"hp_max") * REWARD_HP)


static func _num(node: Node, property: StringName) -> float:
	var v: Variant = node.get(property)
	return float(v) if v is float or v is int else 0.0


## The core ruptures as a living bomb: 1,200 / 1,000 in 20 m (skills-catalog §4.6).
func _rupture() -> void:
	_ruptured = true
	if _victim == null or not is_instance_valid(_victim) or not (_victim is Node3D):
		return
	var center: Vector3 = (_victim as Node3D).global_position
	_blast(center)
	Feel.play(&"finisher", center, 1.0)


func _blast(center: Vector3) -> void:
	var space := _space()
	if space == null:
		return
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RUPTURE_RADIUS
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = Layers.MASK_PLAYER_ATTACK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.exclude = _exclusions()
	var seen: Dictionary = {}
	if _victim != null and is_instance_valid(_victim):
		seen[_victim.get_instance_id()] = true
	for r: Dictionary in space.intersect_shape(params, 24):
		var col: Object = r["collider"]
		if not (col is Hurtbox):
			continue
		var box := col as Hurtbox
		var actor := box.actor()
		if actor == null or seen.has(actor.get_instance_id()):
			continue
		seen[actor.get_instance_id()] = true
		var falloff := clampf(1.0 - center.distance_to(box.global_position) / RUPTURE_RADIUS, 0.0, 1.0)
		if falloff <= 0.0:
			continue
		var hit := HitInfo.make(RUPTURE_DAMAGE * falloff, HitInfo.EXPLOSIVE, _player, &"core_rupture")
		hit.stagger = RUPTURE_IMPACT * falloff
		hit.position = box.global_position
		hit.normal = (box.global_position - center).normalized()
		if box.apply(hit) != null:
			Events.hit_landed.emit(hit, actor)


func _exclusions() -> Array[RID]:
	var out: Array[RID] = []
	for n: Node in [_player, _victim]:
		if n is CollisionObject3D and is_instance_valid(n):
			out.append((n as CollisionObject3D).get_rid())
			for c in n.find_children("*", "CollisionObject3D", true, false):
				out.append((c as CollisionObject3D).get_rid())
	return out


func _space() -> PhysicsDirectSpaceState3D:
	if _player == null or not is_instance_valid(_player):
		return null
	var w := _player.get_world_3d()
	return w.direct_space_state if w != null else null


## skills-catalog §4.6 JACKPOT: a brute or boss killed by the Lance or a rifle stage-2 shot gets
## 0.5 s at time scale 0.2 plus a callout. Every other kill leaves the flag alone.
const JACKPOT_WEAPONS: Array[StringName] = [&"zenith_lance", &"beam_rifle_stage2"]

func _on_enemy_killed(enemy: Node, hit: HitInfo) -> void:
	if enemy == null or hit == null or not JACKPOT_WEAPONS.has(hit.weapon):
		return
	var cls := class_of(enemy)
	if cls != &"brute" and cls != &"colossus":
		return
	note_jackpot()


func note_jackpot() -> void:
	jackpot = true
	jackpots += 1
	Feel.play(&"jackpot", _player.global_position if _player != null else Vector3.INF, 1.0)
	Feel.slow_mo(JACKPOT_SCALE, JACKPOT_TIME, 0.05, 0.2, false)


func clear_jackpot() -> void:
	jackpot = false
