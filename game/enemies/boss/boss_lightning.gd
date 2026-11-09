class_name TitanLightning
extends Node3D
## Phase-3 storm strikes (boss unit). The titan calls a circle down onto the deck: a violet ground
## glyph and a rising whine for `telegraph` seconds, then a column that damages anything still inside.
##
## Two cues, never colour alone (SPEC §7.1 accessibility): a ground ring that closes inward and a
## distinct sound at the glyph, plus the sky flash through the `&"time_of_day"` environment hook
## (CONTRACTS §7 — `lightning_at`, a no-op when there is no environment).

const COLOUR := Color(0.78, 0.55, 1.0)
const COLUMN_HEIGHT := 260.0

var damage: float = BossTuning.LIGHTNING["damage"]
var impact: float = BossTuning.LIGHTNING["impact"]
var radius: float = BossTuning.LIGHTNING_RADIUS
var telegraph: float = BossTuning.LIGHTNING["telegraph"]
var source: Node = null

var _life: float = 0.0
var _struck: bool = false
var _ring: MeshInstance3D
var _column: MeshInstance3D
var _material: StandardMaterial3D


## One telegraphed circle at `at`. Returns null without a parent.
static func spawn(parent: Node, at: Vector3, from: Node, delay: float) -> TitanLightning:
	if parent == null or not is_instance_valid(parent):
		push_error("TitanLightning: no parent to spawn the strike into")
		return null
	var strike := TitanLightning.new()
	strike.name = "TitanLightning"
	strike.source = from
	strike.position = at
	strike._life = -maxf(delay, 0.0)
	parent.add_child(strike)
	return strike


func _ready() -> void:
	add_to_group(&"titan_lightning")
	_ring = MeshInstance3D.new()
	_ring.name = "Glyph"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.88
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	_ring.mesh = torus
	_material = StandardMaterial3D.new()
	_material.albedo_color = COLOUR
	_material.emission_enabled = true
	_material.emission = COLOUR
	_material.emission_energy_multiplier = 5.0
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = _material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	_column = MeshInstance3D.new()
	_column.name = "Column"
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.55
	cyl.bottom_radius = radius
	cyl.height = COLUMN_HEIGHT
	cyl.radial_segments = 10
	_column.mesh = cyl
	_column.position = Vector3.UP * COLUMN_HEIGHT * 0.5
	_column.material_override = _material
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.visible = false
	add_child(_column)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life < 0.0:
		visible = false
		return
	visible = true
	if not _struck:
		_tick_telegraph()
		return
	var k := (_life - telegraph) / maxf(BossTuning.LIGHTNING["active"], 0.01)
	_material.albedo_color.a = clampf(1.0 - k, 0.0, 1.0)
	if k >= 1.0:
		queue_free()


## The glyph shrinks from the full radius to a point over the windup: an unblockable whose shape
## tells you exactly how long you have (juice §11.1 "ground decal of the AoE").
func _tick_telegraph() -> void:
	var k: float = clampf(_life / maxf(telegraph, 0.01), 0.0, 1.0)
	var r: float = radius * lerpf(1.6, 1.0, k)
	_ring.scale = Vector3(r, maxf(r * 0.05, 1.0), r)
	_material.emission_energy_multiplier = lerpf(3.0, 12.0, k)
	if _life >= telegraph:
		_strike()


func _strike() -> void:
	_struck = true
	_column.visible = true
	_ring.visible = false
	Audio.play(&"shockcore", global_position)
	Feel.shake(0.3, global_position)
	Feel.flash(Color(0.85, 0.75, 1.0), 0.1)
	# CONTRACTS §7 environment hook: the storm answers with a sky flash. A missing environment is a
	# no-op by design (call_group, not a direct call).
	get_tree().call_group(&"time_of_day", &"lightning_at", global_position)
	_damage()


func _damage() -> void:
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 60.0
	params.shape = cyl
	params.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 30.0)
	params.collision_mask = Layers.MASK_ENEMY_ATTACK
	params.collide_with_areas = true
	params.collide_with_bodies = true
	for r: Dictionary in space.intersect_shape(params, 8):
		var col: Object = r.get("collider")
		if not (col is Hurtbox):
			continue
		var hurt := col as Hurtbox
		var victim := hurt.actor() as Node3D
		if victim == null:
			continue
		var hit := HitInfo.make(damage, HitInfo.CRUSH, source, &"titan_lightning")
		hit.stagger = impact
		hit.unblockable = true
		hit.position = hurt.global_position
		hit.knockback = Vector3.UP * BossTuning.LIGHTNING["knockback"]
		hurt.apply(hit)
