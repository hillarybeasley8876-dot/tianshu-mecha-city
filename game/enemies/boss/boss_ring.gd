class_name TitanRing
extends Node3D
## The Brood Titan's stomp shockwave (boss unit): a ground ring that expands 0 → `max_radius` and is
## jumped or dashed over. The enemies unit's EnemyShockwave is hard-wired to 60 m/s and the
## `juggernaut_slam` feel ids, both wrong for a 60 m colossus, so the titan gets its own.
##
## juice §11.1 / SPEC §7: the ring is the tell AND the hazard — it is visible from the moment the
## foot lifts, so a player who reads the stomp windup has the whole 0.9 s plus the travel time.

const SPEED := 45.0            ## m/s outward — 80 m takes 1.8 s, long enough to react and jump
const BAND := 12.0             ## half-thickness of the damaging band (m); a 60 m foot makes a wide front
const PROBES := 16             ## sample points around the front
const CLEAR_HEIGHT := 6.0      ## feet higher than this clear the ring (jump apex is 8 m)
const MAX_LIFE := 6.0
const COLOUR := Color(0.69, 0.30, 1.0)

var radius: float = 0.0
var max_radius: float = BossTuning.STOMP["shockwave_radius"]
var damage: float = BossTuning.STOMP["damage"]
var impact: float = BossTuning.STOMP["impact"]
var knockback: float = BossTuning.STOMP["knockback"]
var source: Node = null

var _life: float = 0.0
var _hit: Array[Node] = []
var _mesh: MeshInstance3D


## Spawns the ring into `parent` at `at`. Returns null (with a readable error) without a parent.
static func spawn(parent: Node, at: Vector3, attack: EnemyAttack, from: Node) -> TitanRing:
	if parent == null or not is_instance_valid(parent):
		push_error("TitanRing: no parent to spawn the stomp ring into")
		return null
	var ring := TitanRing.new()
	ring.name = "TitanRing"
	ring.max_radius = maxf(attack.shockwave_radius, 20.0)
	ring.damage = attack.damage
	ring.impact = attack.impact
	ring.knockback = attack.knockback
	ring.source = from
	ring.position = at
	parent.add_child(ring)
	Feel.play(&"land_heavy", at, 1.6)
	Feel.shake(0.45, at)
	Audio.play(&"titan_step_far", at)
	return ring


func _ready() -> void:
	add_to_group(&"enemy_shockwave")
	_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 8
	_mesh.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOUR
	mat.emission_enabled = true
	mat.emission = COLOUR
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	_life += delta
	radius += SPEED * delta
	_mesh.scale = Vector3(radius, maxf(radius * 0.10, 2.0), radius)
	_sweep()
	if radius >= max_radius or _life > MAX_LIFE:
		queue_free()


## Damages anything standing in the band that this ring has not hit yet and whose feet are not above
## CLEAR_HEIGHT over the deck under them. PROBES points around the front are enough: the player is the
## only real target and the arena is a flat disc, so a full ring query would cost more than it finds.
func _sweep() -> void:
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BAND
	params.shape = sphere
	params.collision_mask = Layers.MASK_ENEMY_ATTACK
	params.collide_with_areas = true
	params.collide_with_bodies = true
	for i in PROBES:
		var angle := TAU * float(i) / float(PROBES)
		var at := global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
		params.transform = Transform3D(Basis.IDENTITY, at)
		for r: Dictionary in space.intersect_shape(params, 8):
			var col: Object = r.get("collider")
			if not (col is Hurtbox):
				continue
			_damage(col as Hurtbox)


func _damage(box: Hurtbox) -> void:
	var victim := box.actor() as Node3D
	if victim == null or victim in _hit:
		return
	if victim.global_position.y - _floor_under(victim) > CLEAR_HEIGHT:
		return
	_hit.append(victim)
	var hit := HitInfo.make(damage, HitInfo.CRUSH, source, &"titan_stomp")
	hit.stagger = impact
	hit.unblockable = true
	hit.position = box.global_position
	hit.knockback = (victim.global_position - global_position).normalized() * knockback
	box.apply(hit)


## The deck surface under `victim`. The Crown is a stepped ziggurat, so the ring's own height is not
## the right reference: "clear of the ring" means clear of the floor you are standing on.
func _floor_under(victim: Node3D) -> float:
	var arena := get_tree().get_first_node_in_group(&"boss_arena") as BossArena
	if arena == null:
		return global_position.y
	return arena.floor_y_at(victim.global_position)
