class_name FxSkateTrail
extends Node3D
## Feet-contact sparks and a dust trail under the boost skate and the ground slide (hero-v3 r9
## item 3: the run-to-skate change has to be sold with lean, sparks and dust; the lean and the
## backpack plumes are the hero unit's, this is the ground half).
##
## Four GPUParticles3D, built once in _ready: one spark shower and one dust plume per foot, parked
## on that foot's ground contact every physics tick and switched off the instant the mech leaves the
## floor. Nothing is instantiated per shot and nothing goes through the VfxLibrary pools, so a skate
## can never steal a kill's blast - the whole trail costs `particle_budget()` particles, flat,
## whatever the mech does.
##
## The feet are read off the model's own `R_Foot` / `L_Foot` bones. NOT `Hero3Sole.contacts()`: that
## solver owns a per-foot smoothed floor height and asking it again from here would advance the
## smoothing twice per tick with a different delta and move the hero's feet. One downward ray per
## foot per tick puts the effect on the surface actually under the boot.

## Which foot is which bone, in `Hero3Stepper.LEGS` order (index 0 = right).
const FEET: Array[String] = ["R_Foot", "L_Foot"]
## Move states that skate: the free 42 m/s ground boost and the 84 m/s assault boost (SPEC §4).
const SKATE: Array[StringName] = [&"slide", &"assault"]
## Move states that slide along the ground: the four dodge dashes and the lunge.
const SLIDE: Array[StringName] = [&"dash_f", &"dash_b", &"dash_l", &"dash_r", &"lunge"]
## Below this the mech is walking or running (16 m/s) and the boots are not scraping anything.
const MIN_SPEED := 18.0
## Speed at which the emitters run at full rate: the boost skate.
const FULL_SPEED := 42.0
const SPARK_AMOUNT := 40
const SPARK_LIFE := 0.32
const DUST_AMOUNT := 24
const DUST_LIFE := 0.9
## How far below the ankle bone the floor is looked for.
const PROBE := 8.0
## Half the stance width, used only when the model has no skeleton to read the feet off.
const STANCE := 1.6
## A global hit-stop freezes the mech, so a frozen skate must not sit there pumping sparks.
const STOP_SCALE := 0.5

var _sparks: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _bones: PackedInt32Array = PackedInt32Array([-1, -1])
var _contacts: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _active: bool = false
var _override: Node3D = null
var _query: PhysicsRayQueryParameters3D = null


func _ready() -> void:
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN)
	_query.collision_mask = Layers.WORLD
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	for i in FEET.size():
		_sparks.append(_spark())
		_dust.append(_plume())
		add_child(_sparks[i])
		add_child(_dust[i])


## Tests (and any scene with more than one mech) point the trail at a player explicitly; null hands
## it back to `Game.player`.
func set_player(p: Node3D) -> void:
	_override = p


func active() -> bool:
	return _active


## Where each foot's effect is parked this tick, in world space.
func contacts() -> Array[Vector3]:
	return _contacts.duplicate()


## The four emitters, fixed for the life of the scene.
func emitter_count() -> int:
	return _sparks.size() + _dust.size()


## The most particles this trail can ever have alive at once - the budget the test gates on.
func particle_budget() -> int:
	return FEET.size() * (SPARK_AMOUNT + DUST_AMOUNT)


## Is this a state the boots scrape in? Pure, so a test can ask without a mech.
static func wants(state: StringName, grounded: bool, speed: float) -> bool:
	return grounded and speed >= MIN_SPEED and (state in SKATE or state in SLIDE)


func _physics_process(_delta: float) -> void:
	var p := _player()
	if p == null or not wants(_state(p), _grounded(p), _speed(p)) \
			or Engine.time_scale < STOP_SCALE:
		_stop()
		return
	var model := _model(p)
	if model == null:
		_stop()
		return
	_track(p, model)


## Moves the four emitters onto the feet and switches them on.
func _track(p: Node3D, model: Node3D) -> void:
	var travel := _velocity(p)
	travel.y = 0.0
	var dir := travel.normalized() if travel.length_squared() > 1.0 else -model.global_basis.z
	# The emitters aim along their own -Z (VfxPresets.facing), so the yaw that points -Z backwards
	# along the travel is atan2(dir.x, dir.z): sparks and dust leave behind the boot, not under it.
	var basis := Basis(Vector3.UP, atan2(dir.x, dir.z))
	var t := clampf((travel.length() - MIN_SPEED) / (FULL_SPEED - MIN_SPEED), 0.0, 1.0)
	var feet := _feet(model)
	for i in FEET.size():
		_contacts[i] = feet[i]
		_aim(_sparks[i], feet[i], basis, lerpf(0.45, 1.0, t))
		_aim(_dust[i], feet[i], basis, lerpf(0.3, 1.0, t))
	_active = true


func _aim(node: GPUParticles3D, at: Vector3, basis: Basis, ratio: float) -> void:
	node.global_position = at
	node.global_basis = basis
	node.amount_ratio = ratio
	node.emitting = true


func _stop() -> void:
	if not _active:
		return
	_active = false
	for node: GPUParticles3D in _sparks + _dust:
		node.emitting = false


# --- the mech --------------------------------------------------------------------------------------

func _player() -> Node3D:
	var p := _override if _override != null else Game.player
	if p == null or not is_instance_valid(p):
		return null
	if not p.has_method(&"move_state") or not p.has_method(&"is_grounded"):
		return null
	return p if p.has_method(&"model") else null


func _state(p: Node3D) -> StringName:
	return p.call(&"move_state")


func _grounded(p: Node3D) -> bool:
	return bool(p.call(&"is_grounded"))


func _velocity(p: Node3D) -> Vector3:
	var v: Variant = p.get(&"velocity")
	return v if v is Vector3 else Vector3.ZERO


func _speed(p: Node3D) -> float:
	var v := _velocity(p)
	return Vector2(v.x, v.z).length()


## The skinned mech, or whatever stand-in answers `model()`.
func _model(p: Node3D) -> Node3D:
	var m: Variant = p.call(&"model")
	return m if m is Node3D and is_instance_valid(m) else null


# --- the feet --------------------------------------------------------------------------------------

## Each foot's ground contact: the ankle bone dropped onto the floor under it, or the model's own
## ground plane when there is no world under the mech. A model with no skeleton (the placeholder box)
## has no feet to read, so the two emitters sit one stance-width either side of it.
func _feet(model: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var skel := _skeleton(model)
	for i in FEET.size():
		var at := model.global_position + model.global_basis.x * (STANCE * _side(i))
		if skel != null and _bones[i] >= 0:
			at = skel.global_transform * skel.get_bone_global_pose(_bones[i]).origin
		out.append(Vector3(at.x, _floor(at, model.global_position.y), at.z))
	return out


## Index 0 is the right foot (`Hero3Stepper.LEGS` order), which is the model's +X side.
func _side(i: int) -> float:
	return 1.0 if i == 0 else -1.0


## Caches the two foot bone indices the first time a skeleton shows up (the model is built after
## this node, so they cannot be looked up in _ready).
func _skeleton(model: Node3D) -> Skeleton3D:
	if _bones[0] >= 0:
		return model.get(&"skeleton") as Skeleton3D
	var skel: Variant = model.get(&"skeleton")
	if not (skel is Skeleton3D):
		return null
	for i in FEET.size():
		_bones[i] = (skel as Skeleton3D).find_bone(FEET[i])
	return skel as Skeleton3D if _bones[0] >= 0 else null


func _floor(at: Vector3, plane: float) -> float:
	if _query == null:
		return plane
	_query.from = Vector3(at.x, at.y + 1.0, at.z)
	_query.to = Vector3(at.x, at.y - PROBE, at.z)
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else plane


# --- the emitters ------------------------------------------------------------------------------------

## A continuous spark shower: hot white at the contact, cooling to the blast orange, thrown BACK
## along the travel and slightly up (the cone axis is the emitter's own -Z, tilted by `dir`).
func _spark() -> GPUParticles3D:
	var p := VfxPresets.build_sparks(SPARK_AMOUNT, VfxPresets.HOT, VfxPresets.ORANGE,
			6.0, 16.0, SPARK_LIFE, 0.16, 26.0, 14.0, Vector3(0.0, 0.35, -1.0))
	p.name = "SkateSparks"
	return _continuous(p)


## A low rooster tail of ground dust behind the boot: the same puff shader the dust ring uses, aimed
## backwards instead of straight up.
func _plume() -> GPUParticles3D:
	var p := VfxPresets.build_dust(DUST_AMOUNT, DUST_LIFE, 9.0, 0.55)
	p.name = "SkateDust"
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0.0, 0.55, -1.0)
	pm.spread = 34.0
	pm.flatness = 0.4
	pm.gravity = Vector3(0.0, -2.0, 0.0)
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 9.0
	return _continuous(p)


## `VfxPresets` builds one-shots for the pools; a trail emits for as long as the boot scrapes.
func _continuous(p: GPUParticles3D) -> GPUParticles3D:
	p.one_shot = false
	p.explosiveness = 0.0
	p.emitting = false
	p.amount_ratio = 1.0
	return p
