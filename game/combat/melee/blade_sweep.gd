class_name BladeSweep
extends Node3D
## Saber hit detection (skills-catalog §4.3 "ShapeCast3D box swept on each active frame"): the blade
## is a thin box pivoting around the mech's chest, rotated through the move's arc over its active
## window. One hit per actor per swing. Owns the HitInfo build so every melee move reports the same
## way (marks, primes, COLLAPSE detonators, hit markers).
##
## `begin()` starts a swing, `sample()` is called on every active physics tick, `end()` closes it.

signal landed(hit: HitInfo, receiver: Node)

var source: Node = null

var _cast: ShapeCast3D = null
var _hit_ids: Dictionary = {}      ## instance ids already hit by the current swing
var _damage_scale: float = 1.0
var _last_hit_usec: int = 0
var _last_hit_kind: StringName = &""
var hits_landed: int = 0


func _init() -> void:
	_cast = ShapeCast3D.new()
	_cast.name = "BladeCast"
	_cast.collision_mask = Layers.MASK_PLAYER_ATTACK
	_cast.collide_with_areas = true
	_cast.collide_with_bodies = false   ## hurtboxes are areas; scenery is handled by reach clamping
	_cast.enabled = false
	add_child(_cast)


## Keeps the swinger's own colliders out of the sweep (hurtboxes sit inside the player capsule).
func exclude_owner(owner_node: Node) -> void:
	if _cast == null or not (owner_node is CollisionObject3D):
		return
	_cast.add_exception(owner_node as CollisionObject3D)
	for n in owner_node.find_children("*", "CollisionObject3D", true, false):
		_cast.add_exception(n as CollisionObject3D)


## `damage_scale` covers the Ram Kick's ×2.5 vs a staggered target and any future buff.
func begin(damage_scale: float = 1.0) -> void:
	_hit_ids.clear()
	_damage_scale = damage_scale
	hits_landed = 0


func end() -> void:
	_hit_ids.clear()


## Sweeps the blade once, at `progress` 0..1 through the move's arc. Returns the actors hit.
func sample(move: StringName, pivot: Vector3, facing: Basis, progress: float) -> Array[Node]:
	var out: Array[Node] = []
	var space := _space()
	if space == null:
		return out
	_place(move, pivot, facing, progress)
	_cast.force_shapecast_update()
	for i in _cast.get_collision_count():
		var col: Object = _cast.get_collider(i)
		if col == null:
			continue
		var actor := _receive(move, col, _cast.get_collision_point(i), facing)
		if actor != null:
			out.append(actor)
	return out


## Pivots the blade box to its place on the arc: `progress` 0 = one end of the sweep, 1 = the other.
## The box is the blade's swept volume — `BLADE_WIDTH` across, `BLADE_SPAN` tall so it covers a 6 m
## Ripper and a 22 m Juggernaut alike, and `reach` deep from the pivot outward.
func _place(move: StringName, pivot: Vector3, facing: Basis, progress: float) -> void:
	var reach := MeleeTable.field(move, "reach", 18.0)
	var dir := MeleeTable.blade_dir(move, facing, progress)
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(dir, up), pivot)
	var box := BoxShape3D.new()
	box.size = Vector3(MeleeTable.BLADE_WIDTH, MeleeTable.BLADE_SPAN, reach)
	_cast.shape = box
	# the box straddles the arc from the pivot outward; the sweep itself adds one tick of travel
	_cast.position = Vector3(0.0, 0.0, -reach * 0.5)
	_cast.target_position = Vector3(0.0, 0.0, -reach * 0.08)


func _receive(move: StringName, col: Object, point: Vector3, facing: Basis) -> Node:
	var actor: Node = null
	if col is Hurtbox:
		actor = (col as Hurtbox).actor()
	elif col is Node and (col as Node).has_method(&"take_hit"):
		actor = col as Node
	if actor == null or actor == source or _hit_ids.has(actor.get_instance_id()):
		return null
	if actor.has_method(&"is_alive") and not bool(actor.call(&"is_alive")):
		return null
	_hit_ids[actor.get_instance_id()] = true
	var hit := build_hit(move, point, facing, _damage_scale)
	if col is Hurtbox:
		if (col as Hurtbox).apply(hit) == null:
			return null
	else:
		actor.call(&"take_hit", hit)
	_last_hit_usec = Time.get_ticks_usec()
	_last_hit_kind = _marker_kind(hit)
	hits_landed += 1
	Events.hit_landed.emit(hit, actor)
	landed.emit(hit, actor)
	if MeleeTable.flag(move, "detonate"):
		detonate_prime(actor)
	return actor


## The HitInfo every melee move sends: damage / impact / knockback from the table, plus the FEEL row
## the move owns (FEEL.md melee_*, lunge_hit, charge_slash, finisher) played by the caller.
func build_hit(move: StringName, point: Vector3, facing: Basis, scale: float = 1.0) -> HitInfo:
	var hit := HitInfo.make(MeleeTable.field(move, "damage") * scale, HitInfo.MELEE,
			source, move)
	hit.stagger = MeleeTable.field(move, "impact") * scale
	hit.position = point
	hit.normal = -facing.z
	hit.knockback = -facing.z * MeleeTable.field(move, "knockback")
	return hit


## skills-catalog §4.6 JACKPOT and the HUD hit markers (CONTRACTS §4).
func _marker_kind(hit: HitInfo) -> StringName:
	if hit.finisher:
		return &"kill"
	return &"stagger" if hit.stagger >= 480.0 else &"normal"


func _space() -> PhysicsDirectSpaceState3D:
	var w := get_world_3d()
	return w.direct_space_state if w != null else null


static func detonate_prime(receiver: Node) -> void:
	if is_instance_valid(receiver) and receiver.has_method(&"detonate_primed"):
		receiver.call(&"detonate_primed")


func last_hit_usec_value() -> int:
	return _last_hit_usec


func last_hit_kind() -> StringName:
	return _last_hit_kind
