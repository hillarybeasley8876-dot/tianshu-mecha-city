class_name BossCore
extends Node3D
## One of the Brood Titan's three weak cores (boss unit). A core is its own damage pool with its own
## Hurtbox (so the aim system can lock it and the player can shoot it) and its own violet Targetable.
##
## The Hurtbox's nearest `take_hit` ancestor is this node, so a hit lands here first: the core takes
## ×2.5 of the incoming amount off its own pool and then forwards the hit to the titan, which counts
## ×1.0 of the same amount against the 150k main pool (SPEC §7.1). When the pool empties the titan
## staggers and loses the attack this core was feeding.

signal shattered(core: BossCore)

const VIOLET := Color(0.69, 0.30, 1.0)
const BROKEN_COLOUR := Color(0.22, 0.12, 0.30)
## Emission pulse rate (Hz) of an intact core — the "shoot me" tell at 60 m scale.
const PULSE_HZ := 1.1

var id: StringName = &"core"
var part: StringName = &"core_chest"
var label: String = "核"
var removes: StringName = &""
var hp: float = BossTuning.CORE_HP
var hp_max: float = BossTuning.CORE_HP
var broken: bool = false

var _titan: Node = null
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _hurtbox: Hurtbox
var _lock: Targetable
var _pulse: float = 0.0


static func make(titan: Node, row: Dictionary) -> BossCore:
	var core := BossCore.new()
	core.name = "Core_" + String(row.get("id", &"core"))
	core._titan = titan
	core.id = row.get("id", &"core")
	core.part = row.get("part", &"core_chest")
	core.label = String(row.get("label", "核"))
	core.removes = row.get("removes", &"")
	core.position = row.get("pos", Vector3.ZERO)
	return core


func _ready() -> void:
	add_to_group(&"boss_core")
	hp = hp_max
	_build()


func _build() -> void:
	var shape := SphereShape3D.new()
	shape.radius = BossTuning.CORE_RADIUS
	_hurtbox = Hurtbox.new()
	_hurtbox.name = "Hurtbox_" + String(part)
	_hurtbox.part = part
	_hurtbox.is_weak_point = true
	_hurtbox.collision_layer = Layers.ENEMY_HURTBOX
	_hurtbox.collision_mask = 0
	var box_shape := CollisionShape3D.new()
	box_shape.shape = shape
	_hurtbox.add_child(box_shape)
	add_child(_hurtbox)

	_lock = Targetable.new()
	_lock.name = "Lock_" + String(part)
	# Weak points out-prioritise the titan's own body lock point (EnemyBodyBuilder uses 1 + mass*0.1).
	_lock.priority = 50.0
	_lock.radius = BossTuning.CORE_RADIUS
	_lock.is_weak_point = true
	add_child(_lock)

	_mesh = MeshInstance3D.new()
	_mesh.name = "Glow"
	var sphere := SphereMesh.new()
	sphere.radius = BossTuning.CORE_RADIUS * 0.82
	sphere.height = BossTuning.CORE_RADIUS * 1.64
	sphere.radial_segments = 12
	sphere.rings = 6
	_mesh.mesh = sphere
	_material = StandardMaterial3D.new()
	_material.albedo_color = VIOLET
	_material.emission_enabled = true
	_material.emission = VIOLET
	_material.emission_energy_multiplier = 6.0
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


## A hit on the core. Returns true when it broke on this hit.
func take_hit(hit: HitInfo) -> bool:
	if broken or _titan == null or not is_instance_valid(_titan):
		return false
	hp = maxf(0.0, hp - hit.amount * BossTuning.CORE_POOL_MULT)
	# The core already took its ×2.5. EnemyDamage would apply SPEC's global weak-point ×2.5 again
	# against the main pool, so the flag is cleared here and the crit is set by hand: a core hit is
	# exactly ×1.0 on the main pool and ×2.5 on this pool (SPEC §7.1).
	hit.weak_point = false
	hit.crit = true
	_titan.call(&"take_hit", hit)
	if hp > 0.0:
		return false
	_shatter()
	return true


func _shatter() -> void:
	broken = true
	hp = 0.0
	# Nothing left to shoot: a broken core must stop being a lock point and a damage sponge.
	_hurtbox.collision_layer = 0
	_lock.priority = 0.0
	_lock.is_weak_point = false
	_lock.visible = false
	_material.albedo_color = BROKEN_COLOUR
	_material.emission = BROKEN_COLOUR
	_material.emission_energy_multiplier = 0.2
	var vfx := _vfx()
	if vfx != null:
		vfx.call(&"spawn", &"kill_large", global_position, Vector3.UP, 2.0)
	Feel.play(&"boss_stagger", global_position, 0.8)
	Audio.play(&"boss_stagger", global_position)
	shattered.emit(self)

## Restored when the player respawns at a phase checkpoint: the cores of the phases still to come
## come back whole (SPEC §7.1).
func restore() -> void:
	broken = false
	hp = hp_max
	_hurtbox.collision_layer = Layers.ENEMY_HURTBOX
	_lock.priority = 50.0
	_lock.is_weak_point = true
	_lock.visible = true
	_material.albedo_color = VIOLET
	_material.emission = VIOLET
	_material.emission_energy_multiplier = 6.0
	_mesh.visible = true


func _process(delta: float) -> void:
	if broken:
		return
	_pulse += delta * PULSE_HZ * TAU
	var k := 0.5 + 0.5 * sin(_pulse)
	_material.emission_energy_multiplier = lerpf(4.0, 9.0, k)
	_mesh.scale = Vector3.ONE * lerpf(0.94, 1.06, k)


func ratio() -> float:
	return clampf(hp / maxf(hp_max, 1.0), 0.0, 1.0)


## CONTRACTS §4: a core is what `Events.hit_landed` names as the receiver of a core hit, so it answers
## the damageable-actor queries for itself. `skill_system._on_hit_landed` asks `is_alive()` of every
## receiver; without these every core hit logged "Nonexistent function 'is_alive'" and skipped the
## skill's on-hit hook (flow's boss -> victory run).
func is_alive() -> bool:
	return not broken


func get_team() -> int:
	return 1


func hud_state() -> Dictionary:
	return {"name": label, "part": part, "hp": hp, "hp_max": hp_max, "broken": broken}


func _vfx() -> Node:
	return get_tree().get_first_node_in_group(&"vfx_library")
