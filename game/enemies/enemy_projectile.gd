class_name EnemyProjectile
extends Area3D
## Pooled enemy shot (enemies-owned): acid arcs, spore bolts, harrier bursts. Lives on
## Layers.ENEMY_SHOT and queries Layers.MASK_ENEMY_ATTACK, so the player's barrier absorbs it
## before the hurtbox (CONTRACTS §3). Metadata the catch field reads:
##   set_meta(&"reflectable", bool) — Mirror Guard's catch field can return it
##   set_meta(&"owner", Node)       — the monster that fired it (Node.owner is reserved by the engine)
##   set_meta(&"hit", HitInfo)      — the damage packet, reused on reflect
## The metadata is a *contract*, so it stays honest: it is written on `launch` and removed on
## `deactivate`, never left pointing at a pooled shot or a freed shooter. Our own code reads the
## typed fields below instead, so a released shot can never hand us a stale packet.

const RADIUS := 1.2
const GRAVITY := 40.0          ## lobs arc; flat shots ignore it when `ballistic`
const LIFETIME := 6.0

var velocity: Vector3 = Vector3.ZERO
var ballistic: bool = false    ## true = flies straight (harrier burst), false = arcs (spitter acid)
var _life: float = 0.0
var _active: bool = false
var _packet: HitInfo = null    ## the live damage packet; null while pooled
var _shooter: Node = null
var _reflectable: bool = false
var _reflected: bool = false
var _blast: float = 0.0
var _shape: CollisionShape3D
var _mesh: MeshInstance3D
## Near-miss beat (juice §11.3): one per flight, fired at the closest point of the path.
var _near: EnemyNearMiss.Tracker = EnemyNearMiss.Tracker.new()


func _init() -> void:
	collision_layer = 0        ## a pooled shot is invisible to the physics world (see deactivate)
	collision_mask = 0
	monitoring = false
	monitorable = true
	_shape = CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = RADIUS
	_shape.shape = s
	add_child(_shape)
	_mesh = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = RADIUS
	m.height = RADIUS * 2.0
	_mesh.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("9bff3a")
	mat.emission_enabled = true
	mat.emission = Color("9bff3a")
	mat.emission_energy_multiplier = 3.2
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


## `arc` true = gravity-bound lob (spitter acid), false = flat burst (harrier).
func launch(at: Vector3, vel: Vector3, hit: HitInfo, shooter: Node, reflectable: bool,
		arc: bool, blast_radius: float = 0.0) -> void:
	global_position = at
	velocity = vel
	ballistic = not arc
	_life = 0.0
	_active = true
	visible = true
	collision_layer = Layers.ENEMY_SHOT
	_packet = hit
	_shooter = shooter
	_reflectable = reflectable
	_reflected = false
	_blast = blast_radius
	_near.reset(hit.weapon if hit != null else &"", RADIUS)
	_publish()
	set_physics_process(true)
	set_process(true)


func is_active() -> bool:
	return _active


## Idle process runs even while physics is off, which is the only way to notice the catch field
## freezing this round (`set_physics_process(false)`, combat/defense/catch_field.gd:96). A round the
## field held never counts as a near miss (lead decision, r16 Round 2).
func _process(_delta: float) -> void:
	if _active and not is_physics_processing():
		_near.held()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_life += delta
	if _life > LIFETIME:
		EnemyProjectilePool.release(self)
		return
	var from := global_position
	if not ballistic:
		velocity.y -= GRAVITY * delta
	var to := from + velocity * delta
	if _trace(from, to):
		return
	global_position = to
	# Only segments the shot SURVIVED count: a hurtbox contact and a damaging detonation both end
	# the round at its closest point, and neither may read as a near miss.
	_near.sweep(from, to)


## Sweeps the segment against MASK_ENEMY_ATTACK so a fast shot cannot tunnel past the player.
func _trace(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, to)
	params.collision_mask = Layers.MASK_PLAYER_ATTACK if is_reflected() else Layers.MASK_ENEMY_ATTACK
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var results := space.intersect_shape(params, 6)
	if results.is_empty():
		return false
	var blocked := false
	for r: Dictionary in results:
		var col: Object = r.get("collider")
		if col is Hurtbox:
			var box := col as Hurtbox
			var copy: HitInfo = _packet.duplicate_hit() if _packet != null else HitInfo.new()
			copy.position = box.global_position
			copy.knockback = velocity.normalized() * copy.knockback.length()
			box.apply(copy)
			_near.contact()
			EnemyProjectilePool.release(self)
			return true
		# The player's barrier absorbs a round before its hurtbox does (CONTRACTS §3): a blocked
		# round is not a near miss, it is a block.
		if col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & Layers.BARRIER) != 0:
			blocked = true
	if blocked:
		_near.contact()
	_detonate(to)
	return true


func _detonate(at: Vector3) -> void:
	if _packet != null and _blast > 0.0:
		if EnemyBlast.apply(get_world_3d(), at, _blast, _packet, self) > 0:
			_near.contact()
	EnemyProjectilePool.release(self)


## The catch field (Mirror Guard) calls this to send a caught shot back at the monsters.
func reflect(new_velocity: Vector3, by: Node) -> void:
	if _packet != null:
		var copy := _packet.duplicate_hit()
		copy.source = by
		copy.amount *= 1.35   ## skills-catalog §4.7: caught rounds come back at 135 %
		_packet = copy
	_shooter = by
	_reflected = true
	_reflectable = false
	_near.reflected()
	_publish()
	velocity = new_velocity
	ballistic = true
	collision_layer = Layers.PLAYER_SHOT
	_life = 0.0
	set_physics_process(true)


func is_reflected() -> bool:
	return _reflected


## The metadata contract with the catch field / Mirror Guard. `owner` is only published while the
## shooter is still alive: the shot listens for the shooter leaving the tree and withdraws the entry
## itself, so a reflect never has to reason about a freed monster.
func _publish() -> void:
	if not _active:
		return
	set_meta(&"hit", _packet)
	set_meta(&"reflectable", _reflectable)
	set_meta(&"reflected", _reflected)
	set_meta(&"blast_radius", _blast)
	if _shooter != null and is_instance_valid(_shooter):
		set_meta(&"owner", _shooter)
		if not _shooter.tree_exiting.is_connected(_on_shooter_gone):
			_shooter.tree_exiting.connect(_on_shooter_gone, CONNECT_ONE_SHOT)
	elif has_meta(&"owner"):
		remove_meta(&"owner")


func _on_shooter_gone() -> void:
	_shooter = null
	if has_meta(&"owner"):
		remove_meta(&"owner")


## Back to the pool: nothing about a released shot may still look like a live one to anyone else.
## The collision shape comes out of the physics world, the process stops (the catch field's freeze
## sets it too, so a caught round must be re-enabled here or it never flies again), and every piece
## of metadata is withdrawn.
func deactivate() -> void:
	_near.finish()   ## the round is over: a lob that never receded gets its beat here
	_active = false
	visible = false
	velocity = Vector3.ZERO
	collision_layer = 0
	set_process(false)
	if _shooter != null and is_instance_valid(_shooter) \
			and _shooter.tree_exiting.is_connected(_on_shooter_gone):
		_shooter.tree_exiting.disconnect(_on_shooter_gone)
	_packet = null
	_shooter = null
	_reflectable = false
	_reflected = false
	_blast = 0.0
	for key: StringName in [&"hit", &"owner", &"reflectable", &"reflected", &"blast_radius"]:
		if has_meta(key):
			remove_meta(key)
	set_physics_process(false)
