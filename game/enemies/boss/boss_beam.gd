class_name TitanBeam
extends Node3D
## The Brood Titan's beam breath (boss unit): a 1.4 s inhale, then a 4 s beam that sweeps
## `BEAM_SWEEP_DEG` across the crown deck. Unblockable — the counters are vertical (fly over/under it,
## the beam sits at mouth height) and the arena's Ø80 central core, whose shadow is the blind spot.
##
## juice §11.1: a 1.4 s windup with a crown glow and a rising whine, then an attack that is constant
## for its whole duration, then a 2 s recovery that IS the punish window.

const COLOUR := Color(0.85, 0.35, 1.0)
const CORE_COLOUR := Color(1.0, 0.92, 1.0)
## The beam is a rectangle, not a cylinder: thin vertically, wide horizontally, so "get above it" is a
## real option for a mech that can fly.
const THICKNESS := 10.0

var damage: float = BossTuning.BEAM["damage"]
var source: Node = null
var running: bool = false

var _life: float = 0.0
var _tick_left: float = BossTuning.BEAM_TICK
var _start_yaw: float = 0.0
var _hit_this_tick: Array[Node] = []
var _body: MeshInstance3D
var _core: MeshInstance3D
var _light: OmniLight3D


## Spawns the beam at the titan's mouth, aimed along `yaw` (radians, world). Returns null without a
## parent — never a silently missing hazard.
static func spawn(parent: Node, at: Vector3, yaw: float, from: Node) -> TitanBeam:
	if parent == null or not is_instance_valid(parent):
		push_error("TitanBeam: no parent to spawn the beam into")
		return null
	var beam := TitanBeam.new()
	beam.name = "TitanBeam"
	beam.source = from
	beam.position = at
	beam._start_yaw = yaw
	beam.rotation.y = yaw
	parent.add_child(beam)
	return beam


func _ready() -> void:
	add_to_group(&"titan_beam")
	_body = _quad(COLOUR, Vector3(BossTuning.BEAM_WIDTH, THICKNESS, BossTuning.BEAM_LENGTH), 4.0)
	_core = _quad(CORE_COLOUR, Vector3(BossTuning.BEAM_WIDTH * 0.4, THICKNESS * 0.4,
			BossTuning.BEAM_LENGTH), 9.0)
	# The beam is a moving VFX, so it lights the deck but casts no shadows (godot-tech §8).
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = COLOUR
	_light.light_energy = 6.0
	_light.omni_range = 90.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.0, -BossTuning.BEAM_LENGTH * 0.5)
	add_child(_light)


func _quad(colour: Color, size: Vector3, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	# The box is authored along -Z from the mouth; the centre sits half a beam down the axis.
	mi.position = Vector3(0.0, 0.0, -size.z * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.55
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func start() -> void:
	running = true
	_life = 0.0
	Audio.play(&"titan_breath_beam", global_position)


func stop() -> void:
	running = false
	queue_free()


func _physics_process(delta: float) -> void:
	if not running:
		return
	_life += delta
	var active: float = BossTuning.BEAM["active"]
	var k: float = clampf(_life / active, 0.0, 1.0)
	# Constant sweep across the deck (juice: "the attack itself is near-instant and constant").
	rotation.y = _start_yaw + deg_to_rad(BossTuning.BEAM_SWEEP_DEG) * (k - 0.5)
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = BossTuning.BEAM_TICK
		_hit_this_tick.clear()
		_sweep()
	if _life >= active:
		stop()


## One damage tick: everything whose body is inside the beam volume. A victim standing in the shadow
## of the arena's central core (between the mouth and them, within the core radius) is safe — that is
## what the Ø80 cover is for (brief §3 "dodge ... by the core-side blind spot").
func _sweep() -> void:
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BossTuning.BEAM_WIDTH, THICKNESS, BossTuning.BEAM_LENGTH)
	params.shape = box
	params.transform = global_transform * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 0.0, -BossTuning.BEAM_LENGTH * 0.5))
	params.collision_mask = Layers.MASK_ENEMY_ATTACK
	params.collide_with_areas = true
	params.collide_with_bodies = true
	for r: Dictionary in space.intersect_shape(params, 8):
		var col: Object = r.get("collider")
		if not (col is Hurtbox):
			continue
		var hurt := col as Hurtbox
		var victim := hurt.actor() as Node3D
		if victim == null or victim in _hit_this_tick or _in_blind_spot(victim):
			continue
		_hit_this_tick.append(victim)
		var hit := HitInfo.make(damage, HitInfo.CRUSH, source, &"titan_beam")
		hit.unblockable = true
		hit.position = hurt.global_position
		hit.knockback = (victim.global_position - global_position).normalized() \
				* BossTuning.BEAM["knockback"]
		hurt.apply(hit)
		Feel.play(&"hurt_light", victim.global_position, 0.4)


## True when the arena core stands between the mouth and `victim`, close enough to shield them.
func _in_blind_spot(victim: Node3D) -> bool:
	var arena := get_tree().get_first_node_in_group(&"boss_arena") as Node3D
	if arena == null:
		return false
	var mouth := global_position
	var to := victim.global_position - mouth
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 1.0:
		return false
	var centre := arena.global_position
	var along := (Vector2(centre.x - mouth.x, centre.z - mouth.z)).dot(Vector2(flat.x, flat.z).normalized())
	if along <= 0.0 or along >= flat.length():
		return false   ## the core is behind the mouth or behind the victim: not between them
	var nearest := Vector2(mouth.x, mouth.z) + Vector2(flat.x, flat.z).normalized() * along
	var miss := Vector2(centre.x, centre.z).distance_to(nearest)
	return miss <= BossTuning.CORE_COVER_RADIUS and absf(victim.global_position.y - centre.y) \
			<= BossTuning.BEAM_BLIND_HEIGHT
