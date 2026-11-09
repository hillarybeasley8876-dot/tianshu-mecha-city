class_name SkillDummyEnemy
extends CharacterBody3D
## Enemy stand-in for the skills tests: a damageable team-1 actor carrying the REAL StatusComponent, so
## marks, primes, stagger and the pull / slow hooks are exercised against the enemies unit's own code
## rather than a mock of it.
##
## `body_height`, `mass_kg`, `hp_max` and `enemy_type` are the fields SkillContext reads to classify
## light / heavy / boss, so a test can make any archetype it needs.

signal died(enemy: SkillDummyEnemy)

var enemy_type: StringName = &"ripper"
var hp: float = 3000.0
var hp_max: float = 3000.0
var body_height: float = 6.0
var mass_kg: float = 1.0
var move_speed: float = 0.0
var alive: bool = true

var status: StatusComponent = StatusComponent.new()
var hits: Array[HitInfo] = []
var damage_taken: float = 0.0
## Test switch: records every hit but never dies, so a damage total can be asserted. Deliberately does
## NOT touch hp_max — SkillContext classifies bosses by hp_max, and inflating it would turn a Brute
## dummy into a boss.
var invincible: bool = false


func _ready() -> void:
	collision_layer = Layers.ENEMY
	collision_mask = 0
	add_to_group(&"enemy")
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = maxf(body_height * 0.3, 1.5)
	cap.height = maxf(body_height, cap.radius * 2.0)
	shape.shape = cap
	shape.position = Vector3(0.0, cap.height * 0.5, 0.0)
	add_child(shape)
	var marker := Targetable.new()
	marker.name = "Lock"
	marker.position = Vector3(0.0, body_height * 0.5, 0.0)
	add_child(marker)
	status.configure({"stability": 150.0})
	_build_visual()


## A readable silhouette for the capture range: a dark carapace block with an emissive core, sized
## from `body_height` so a Brute reads as a Brute next to a Swarmer.
func _build_visual() -> void:
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(body_height * 0.55, body_height, body_height * 0.8)
	body.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.11, 0.14)
	mat.roughness = 0.65
	mat.metallic = 0.25
	body.material_override = mat
	body.position = Vector3(0.0, body_height * 0.5, 0.0)
	add_child(body)
	var core := MeshInstance3D.new()
	core.name = "Core"
	var sphere := SphereMesh.new()
	sphere.radius = body_height * 0.16
	sphere.height = body_height * 0.32
	core.mesh = sphere
	core.material_override = SkillFx.glow(Color(0.55, 1.0, 0.35), 2.4)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.position = Vector3(0.0, body_height * 0.72, -body_height * 0.3)
	add_child(core)


func _physics_process(delta: float) -> void:
	# StatusComponent.tick() zeroes `pull_accel` every frame, so the pull the Undertow Well wrote has
	# to be read before the tick that clears it
	var pull := status.pull_accel if status != null else Vector3.ZERO
	if status != null:
		status.tick(delta)
	if pull != Vector3.ZERO:
		velocity += pull * delta
	else:
		velocity = Vector3.ZERO
	if velocity != Vector3.ZERO:
		move_and_slide()


func take_hit(hit: HitInfo) -> void:
	if not alive:
		return
	hits.append(hit)
	damage_taken += hit.amount
	if not invincible:
		hp = maxf(hp - hit.amount, 0.0)
	hit.final_amount = hit.amount
	if hit.stagger > 0.0:
		status.add_impact(hit.stagger)
	Events.hit_landed.emit(hit, self)
	if hp <= 0.0 and not invincible:
		alive = false
		died.emit(self)


func is_alive() -> bool:
	return alive


func get_team() -> int:
	return 1


func hit_pause(_seconds: float) -> void:
	pass


func set_hit_flash(_v: float) -> void:
	pass


## Makes this dummy a heavy (the Skyhook pulls the player in instead of yanking it).
func make_heavy() -> void:
	enemy_type = &"juggernaut"
	mass_kg = 9.0
	hp_max = 7000.0
	hp = hp_max
	body_height = 22.0


## Makes this dummy a boss (no knockback, no air-lock, no pull).
func make_boss() -> void:
	enemy_type = &"titan"
	mass_kg = 90.0
	hp_max = 60000.0
	hp = hp_max
	body_height = 90.0


func last_hit() -> HitInfo:
	return hits[-1] if not hits.is_empty() else null


func hit_count() -> int:
	return hits.size()
