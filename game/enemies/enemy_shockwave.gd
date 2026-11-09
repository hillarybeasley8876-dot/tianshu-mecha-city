class_name EnemyShockwave
extends Node3D
## Juggernaut ground-slam ring (enemies-owned). Expands outward at a fixed speed; the player jumps
## over it — anything whose feet are above `CLEAR_HEIGHT` when the ring passes is safe. Damages at
## most once per victim. A visible torus keeps the tell readable (SPEC §7: "jump it").

const SPEED := 60.0            ## m/s outward
const BAND := 6.0              ## half-thickness of the damaging band (m)
const CLEAR_HEIGHT := 6.0      ## feet higher than this clear the ring (mech jump apex is 8 m)
const MAX_LIFE := 4.0

var radius: float = 0.0
var max_radius: float = 120.0
var damage: float = 900.0
var impact: float = 400.0
var knockback: float = 26.0
var source: Node = null

var _life: float = 0.0
var _hit: Array[Node] = []
var _mesh: MeshInstance3D


static func spawn(parent: Node, at: Vector3, attack: EnemyAttack) -> EnemyShockwave:
	if parent == null or not is_instance_valid(parent):
		push_error("EnemyShockwave: no parent to spawn into")
		return null
	var ring := EnemyShockwave.new()
	ring.name = "EnemyShockwave"
	ring.max_radius = maxf(attack.shockwave_radius, 20.0)
	ring.damage = attack.damage
	ring.impact = attack.impact
	ring.knockback = attack.knockback
	ring.source = null
	ring.position = at
	parent.add_child(ring)
	ring.source = parent
	Feel.play(&"shockcore", at, 0.8)
	Audio.play(&"juggernaut_slam", at)
	return ring


func _ready() -> void:
	# In its own group so the HUD, audio and any test can find the live ring without walking the tree.
	add_to_group(&"enemy_shockwave")
	_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 1.0
	_mesh.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ff7a2a")
	mat.emission_enabled = true
	mat.emission = Color("ff5a1a")
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	_life += delta
	radius += SPEED * delta
	_mesh.scale = Vector3(radius, maxf(radius * 0.06, 1.5), radius)
	_sweep()
	if radius >= max_radius or _life > MAX_LIFE:
		queue_free()


## Damages victims standing in the band that have not been hit by this ring yet. The wave front is
## sampled at four points around the ring (the player is the only real target, so this is enough and
## costs four cheap queries instead of a ring mesh query).
func _sweep() -> void:
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BAND
	params.shape = sphere
	params.collision_mask = Layers.MASK_ENEMY_ATTACK
	params.collide_with_areas = true
	params.collide_with_bodies = true
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var at := global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
		params.transform = Transform3D(Basis.IDENTITY, at)
		for r: Dictionary in space.intersect_shape(params, 8):
			var col: Object = r.get("collider")
			if not (col is Hurtbox):
				continue
			var box := col as Hurtbox
			var victim := box.actor() as Node3D
			if victim == null or victim in _hit:
				continue
			if victim.global_position.y - global_position.y > CLEAR_HEIGHT:
				continue
			_hit.append(victim)
			var hit := HitInfo.make(damage, HitInfo.CRUSH, source, &"juggernaut_slam")
			hit.stagger = impact
			hit.unblockable = true
			hit.position = box.global_position
			hit.knockback = (victim.global_position - global_position).normalized() * knockback
			box.apply(hit)
