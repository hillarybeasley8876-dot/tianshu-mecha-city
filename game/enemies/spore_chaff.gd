class_name SporeChaff
extends Area3D
## Spitter spore-chaff cloud (enemies-owned). Group `&"chaff"`: missile code (weapons unit) queries
## the group and spends charges here instead of tracking a target — SPEC §7 "spore-chaff cloud eats
## 4 missiles". API for that unit: `charges_left()`, `consume_missile() -> bool`, `covers(point)`.

const CHARGES := 4
const LIFETIME := 8.0
const RADIUS := 26.0        ## metres; wide enough to screen the spitter's back

var _charges: int = CHARGES
var _life: float = 0.0


static func spawn(parent: Node, at: Vector3, source: Node) -> SporeChaff:
	if parent == null or not is_instance_valid(parent):
		push_error("SporeChaff: no parent to spawn into")
		return null
	var cloud := SporeChaff.new()
	cloud.name = "Chaff"
	cloud.position = at
	parent.add_child(cloud)
	cloud._watch(source)
	return cloud


func _init() -> void:
	add_to_group(&"chaff")
	collision_layer = Layers.TRIGGER
	collision_mask = 0
	monitoring = false
	monitorable = true
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	cs.shape = sphere
	add_child(cs)


## `&"owner"` is published only while the spitter lives, so a missile that reads it back can never
## be handed a freed node (the same rule EnemyProjectile follows).
func _watch(source: Node) -> void:
	if source == null or not is_instance_valid(source):
		return
	set_meta(&"owner", source)
	source.tree_exiting.connect(_on_source_gone, CONNECT_ONE_SHOT)


func _on_source_gone() -> void:
	if has_meta(&"owner"):
		remove_meta(&"owner")


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = RADIUS
	m.height = RADIUS * 2.0
	mesh.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.78, 0.25, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color("9bff3a")
	mat.emission_energy_multiplier = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _process(delta: float) -> void:
	_life += delta
	if _life > LIFETIME or _charges <= 0:
		queue_free()


## True when a missile at `point` is inside the cloud.
func covers(point: Vector3) -> bool:
	return _charges > 0 and global_position.distance_to(point) <= RADIUS


## A missile flew in: spend a charge. Returns false when the cloud is spent.
func consume_missile() -> bool:
	if _charges <= 0:
		return false
	_charges -= 1
	if _charges <= 0:
		queue_free()
	return true


func charges_left() -> int:
	return _charges
