class_name SkillContext
extends RefCounted
## Everything a skill needs from the mech and the world, in one small object, so the skill scripts
## never touch PlayerMech / AimSystem directly (and never form a cyclic reference with the SkillSystem
## that owns them). The SkillSystem refreshes the fields every physics tick.
##
## Null-tolerant on purpose: while the mech, aim and hero-model units are still landing, sockets fall
## back to the chest, aim direction to the body's forward axis and target scans to the `&"enemy"`
## group — so the component runs standalone in tests and in the capture range.
##
## `damage_mult` / `impact_mult` carry the transient buffs (Ambush window, Zenith Overdrive); the
## SkillSystem writes them and every skill reads them through `scale_damage` / `scale_impact`.

const CHEST_HEIGHT := 11.5       ## chest pivot of the 16 m hero, measured from the FEET (SPEC §5)
const BOSS_HP := 20000.0          ## [tuning] SPEC §7: the Brood Titan is the only archetype this big
const BOSS_TYPES: Array[StringName] = [&"titan", &"brood_titan"]
const DEFAULT_CAPSULE_HEIGHT := 15.0
const DEFAULT_CAPSULE_RADIUS := 3.5

var player: Node = null
var model: Node = null            ## HeroModel (player.model()) or null
var aim: Node = null              ## AimSystem (player.aim()) or null
var tuning: SkillTuning = null
var vfx: SkillVfx = null        ## the skills' own pooled signature effects (never the fx unit's)
var damage_mult: float = 1.0      ## Overdrive +25 %, Rift Step Ambush +50 %
var impact_mult: float = 1.0      ## Overdrive +30 %, Ambush +100 %

var _exclude: Array[RID] = []


func _init(tuning_: SkillTuning = null) -> void:
	tuning = tuning_ if tuning_ != null else SkillTuning.new()


func refresh(p: Node) -> void:
	if p == null or not is_instance_valid(p):
		return
	player = p
	if model == null and p.has_method(&"model"):
		model = p.call(&"model")
	if aim == null and p.has_method(&"aim"):
		aim = p.call(&"aim")
	_exclude.clear()
	if p is CollisionObject3D:
		_exclude.append((p as CollisionObject3D).get_rid())
		for n in p.find_children("*", "CollisionObject3D", true, false):
			_exclude.append((n as CollisionObject3D).get_rid())


# --- geometry ------------------------------------------------------------------------------------

## The mech's own `MechTuning`, or null before it resolves. The skills read their numbers from
## `SkillTuning`; this is only for the few costs the MECH owns (dash cost, EN regen rate), which two
## callers need and neither should re-derive the lookup for.
func mech_tuning() -> Object:
	if player == null or not is_instance_valid(player):
		return null
	return player.get(&"tuning") as Object


## Is the mech on the deck right now? Defaults to grounded, the same assumption the regen rates make.
func grounded() -> bool:
	if player == null or not player.has_method(&"is_grounded"):
		return true
	return bool(player.call(&"is_grounded"))


func origin() -> Vector3:
	if player != null and is_instance_valid(player) and player is Node3D:
		return (player as Node3D).global_position
	return Vector3.ZERO


## Half the mech's capsule height: the body origin is the capsule CENTRE (CONTRACTS §5), so this is
## the distance from the origin down to the feet. Read from MechTuning, never allocated per call.
func half_height() -> float:
	var t: Variant = player.get(&"tuning") if player != null else null
	var h := float(t.get(&"capsule_height")) if t != null else DEFAULT_CAPSULE_HEIGHT
	return maxf(h, DEFAULT_CAPSULE_RADIUS * 2.0) * 0.5


## Where the mech's feet are. Every height in the dossiers (the 16 m Plunge gate, the chest pivot, the
## landing test) is measured from the feet, while the body origin is the capsule centre — mixing the
## two is what put the chest 3 m above the crest (audit #7).
func feet() -> Vector3:
	return origin() - Vector3.UP * half_height()


## The chest pivot, 11.5 m above the FEET (= 4 m above the capsule centre of the 16 m hero).
func chest() -> Vector3:
	return feet() + Vector3.UP * CHEST_HEIGHT


## Global position of a model socket, with a chest-height fallback when the model is not in yet.
func socket(nm: StringName) -> Vector3:
	var n := socket_node(nm)
	return n.global_position if n != null else chest()


## The socket node itself (null when the model is not in yet), for code that needs its children.
func socket_node(nm: StringName) -> Node3D:
	if model != null and is_instance_valid(model) and model.has_method(&"socket"):
		return model.call(&"socket", nm) as Node3D
	return null


func facing() -> Vector3:
	if player != null and is_instance_valid(player) and player is Node3D:
		return -(player as Node3D).global_basis.z.normalized()
	return Vector3.FORWARD


## Horizontal speed of the mech, in m/s. Read straight off the body when it is a CharacterBody3D,
## so effects that only make sense in motion (the overdrive afterimages) can gate on it.
func planar_speed() -> float:
	if player == null or not is_instance_valid(player) or not (player is CharacterBody3D):
		return 0.0
	var v: Vector3 = (player as CharacterBody3D).velocity
	v.y = 0.0
	return v.length()


## Horizontal camera basis so stick directions mean the same thing in 1st and 3rd person.
func move_basis() -> Basis:
	var rig: Node = Game.camera_rig
	if rig != null and is_instance_valid(rig) and rig.has_method(&"yaw_basis"):
		return rig.call(&"yaw_basis")
	if player != null and is_instance_valid(player) and player is Node3D:
		return (player as Node3D).global_basis
	return Basis.IDENTITY


## Where the crosshair points (AimSystem, else a point 1,500 m down the body's forward axis).
func aim_point() -> Vector3:
	if aim != null and is_instance_valid(aim) and aim.has_method(&"aim_point"):
		return aim.call(&"aim_point")
	return chest() + facing() * 1500.0


func aim_dir_from(from: Vector3) -> Vector3:
	if aim != null and is_instance_valid(aim) and aim.has_method(&"aim_dir_from"):
		var d: Vector3 = aim.call(&"aim_dir_from", from)
		if d.length_squared() > 0.0001:
			return d.normalized()
	var d2 := aim_point() - from
	return d2.normalized() if d2.length_squared() > 0.0001 else facing()


func aim_node() -> Node3D:
	return aim as Node3D if aim != null and is_instance_valid(aim) else null


## The mech's collision capsule, read from MechTuning when it is available so a blink never drops the
## hero into geometry sized for a different body.
func capsule() -> CapsuleShape3D:
	var shape := CapsuleShape3D.new()
	var t: Variant = player.get(&"tuning") if player != null else null
	shape.radius = float(t.get(&"capsule_radius")) if t != null else DEFAULT_CAPSULE_RADIUS
	shape.height = maxf(float(t.get(&"capsule_height")) if t != null else DEFAULT_CAPSULE_HEIGHT,
			shape.radius * 2.0)
	return shape


## Is `at` (a body origin) clear of scenery for the mech's capsule?
func space_free(at: Vector3) -> bool:
	var space := _space()
	if space == null:
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule()
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = Layers.WORLD | Layers.PROPS
	q.exclude = _exclude
	return space.intersect_shape(q, 1).is_empty()


## Free space at `at`, else the nearest clear point on a ring of `steps` samples around it — the
## 8-point fallback the dossier asks for (skills-catalog §4.4 S1 "Godot").
func resolve_free_space(at: Vector3, ring_radius: float, steps: int = 8) -> Vector3:
	if space_free(at):
		return at
	var step := TAU / float(maxi(steps, 1))
	for i in steps:
		var a := float(i) * step
		for lift: float in [0.0, 6.0, -6.0]:
			var probe := at + Vector3(cos(a), 0.0, sin(a)) * ring_radius + Vector3.UP * lift
			if space_free(probe):
				return probe
	return at


## Height of the surface under `at` (WORLD | PROPS), or -INF when there is nothing below.
func ground_y(at: Vector3) -> float:
	var space := _space()
	if space == null:
		return -INF
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0,
			at + Vector3.DOWN * 1200.0, Layers.MASK_SIGHT, _exclude)
	var hit := space.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if hit else -INF


## `at` snapped down onto the surface below it; unchanged when there is nothing under it (tests, air).
func ground_point(at: Vector3) -> Vector3:
	var y := ground_y(at)
	return Vector3(at.x, y, at.z) if is_finite(y) else at


## Same, but only when the surface is within `max_drop` of `at`: an airborne burst 150 m over the
## street must not stamp its ring, dust and decal on that street (audit #12). Returns `at` unchanged
## when there is no surface that close, which the callers test with `ground != at`.
func ground_near(at: Vector3, max_drop: float) -> Vector3:
	var y := ground_y(at)
	if not is_finite(y) or at.y - y > max_drop:
		return at
	return Vector3(at.x, y, at.z)


func has_los(from: Vector3, to: Vector3) -> bool:
	var space := _space()
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_SIGHT, _exclude)
	return space.intersect_ray(q).is_empty()


## Live enemy shots inside `radius`: the shots are Area3D on `Layers.ENEMY_SHOT` (enemies-owned), so
## this is a plain sphere query with `collide_with_areas` — no coupling to their pool internals.
func enemy_shots_in_radius(center: Vector3, radius: float) -> Array[Node]:
	var out: Array[Node] = []
	var space := _space()
	if space == null:
		return out
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = Layers.ENEMY_SHOT
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for r in space.intersect_shape(q, 64):
		var n := r["collider"] as Node
		if n != null and n.has_method(&"is_active") and bool(n.call(&"is_active")):
			out.append(n)
	return out


func _space() -> PhysicsDirectSpaceState3D:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return null
	return (player as Node3D).get_world_3d().direct_space_state


# --- targets -------------------------------------------------------------------------------------

## The lock-on target's actor: hard lock first, then the soft lock under the reticle. Null when the
## player is not locked onto anything.
func lock_target() -> Node3D:
	for getter: StringName in [&"hard_target", &"soft_target"]:
		if aim == null or not is_instance_valid(aim) or not aim.has_method(getter):
			continue
		var t := aim.call(getter) as Node3D
		if t != null and is_instance_valid(t):
			var actor := _actor_of(t)
			if actor != null and is_alive(actor):
				return actor
	return null


## A Targetable marker points at a hurtbox/Area3D; the damageable root is the nearest ancestor.
func _actor_of(n: Node) -> Node3D:
	var node: Node = n
	while node != null:
		if node.has_method(&"take_hit"):
			return node as Node3D
		node = node.get_parent()
	return n as Node3D


func is_alive(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n.has_method(&"is_alive"):
		return bool(n.call(&"is_alive"))
	return true


## Alive enemies (group `&"enemy"`) whose centre is inside `radius` of `center`.
func enemies_in_radius(center: Vector3, radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return out
	var r2 := radius * radius
	for n in player.get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e == null or not is_alive(e):
			continue
		if center.distance_squared_to(centre_of(e)) <= r2:
			out.append(e)
	return out


## Centre of mass: the actor's origin plus half its body height when it publishes one.
func centre_of(n: Node3D) -> Vector3:
	var h: Variant = n.get(&"body_height")
	var height := float(h) if h != null else 8.0
	return n.global_position + Vector3.UP * height * 0.5


## SPEC §7: only the Brood Titan-class archetypes count as bosses for knockback, air-lock and pull.
func is_boss(n: Node3D) -> bool:
	if n == null:
		return false
	var t: Variant = n.get(&"enemy_type")
	if t != null and (t as StringName) in BOSS_TYPES:
		return true
	var m: Variant = n.get(&"hp_max")
	return m != null and float(m) >= BOSS_HP


## The Skyhook's light/heavy split: anything a 16 m mech can physically yank is light.
func is_heavy(n: Node3D) -> bool:
	if is_boss(n):
		return true
	var m: Variant = n.get(&"mass_kg")
	return m != null and float(m) >= 3.0


func is_staggered(n: Node3D) -> bool:
	var s: Variant = n.get(&"status")
	return s != null and (s as Object).has_method(&"is_staggered") \
			and bool((s as Object).call(&"is_staggered"))


func status_of(n: Node3D) -> Object:
	var s: Variant = n.get(&"status") if n != null else null
	return s as Object if s is Object else null


func consume_marks(n: Node3D) -> int:
	var s := status_of(n)
	if s == null or not s.has_method(&"consume_marks"):
		return 0
	return int(s.call(&"consume_marks"))


func marks_of(n: Node3D) -> int:
	var s := status_of(n)
	if s == null or not s.has_method(&"consume_marks"):
		return 0
	var m: Variant = s.get(&"marks")
	return int(m) if m != null else 0


# --- damage --------------------------------------------------------------------------------------

func scale_damage(amount: float) -> float:
	return amount * damage_mult


func scale_impact(amount: float) -> float:
	return amount * impact_mult


## Builds one HitInfo, delivers it to `enemy.take_hit` and returns the damage actually applied.
## Skills hit the actor root directly (they already know exactly which enemy they aimed at), so no
## hurtbox part / weak-point fields are filled — EnemyBase applies armour and combo scaling itself.
func damage(enemy: Node3D, amount: float, kind: StringName, weapon: StringName, impact: float,
		knockback: Vector3 = Vector3.ZERO, at: Vector3 = Vector3.ZERO) -> float:
	if enemy == null or not is_instance_valid(enemy) or not is_alive(enemy):
		return 0.0
	var hit := HitInfo.make(scale_damage(amount), kind, player, weapon)
	hit.stagger = scale_impact(impact)
	hit.knockback = knockback
	hit.position = at if at != Vector3.ZERO else centre_of(enemy)
	enemy.call(&"take_hit", hit)
	return hit.final_amount


## Knockback speed for an archetype class: full on the light ones, a shove on the heavies, nothing
## on a boss (skills-catalog §4.4 S6).
func knockback_for(enemy: Node3D, light: float, heavy: float, dir: Vector3) -> Vector3:
	if is_boss(enemy):
		return Vector3.ZERO
	return dir.normalized() * (heavy if is_heavy(enemy) else light)
