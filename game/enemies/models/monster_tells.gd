class_name MonsterTells
extends RefCounted
## The per-instance shader state of a HUSK monster (monster-assets): hit flash, the attack tell,
## the stagger lean and the juggernaut's armour plates. All of it goes through
## `set_instance_shader_parameter`, so every copy of a type shares one ShaderMaterial.
##
## Split out of `monster_model.gd` (lead split r1).

const GLINT := Color(1, 1, 1)
const DANGER := Color(1.0, 0.16, 0.12)
const AMBER := Color(1.0, 0.69, 0.13)
## Juggernaut armour plates (SPEC §7 "armour plates break"); only a visual budget here.
const PLATE_COUNT := 4

var flash: float = 0.0

var _meshes: Array[MeshInstance3D] = []
var _visual: Node3D
var _tell: float = 0.0
var _tell_kind: StringName = &"parryable"
var _staggered: bool = false
var _plates: int = PLATE_COUNT


func setup(visual: Node3D, meshes: Array[MeshInstance3D]) -> void:
	_visual = visual
	_meshes = meshes


func set_flash(v: float) -> void:
	flash = clampf(v, 0.0, 1.0)
	set_param(&"hit_flash", flash)


## Attack tell: white glint = parryable, red = unblockable (SPEC §7 counters). v ramps 0 -> 1 over
## the windup so the tell builds instead of snapping on (juice §11.1).
func set_telegraph(kind: StringName, v: float) -> void:
	_tell_kind = kind
	_tell = clampf(v, 0.0, 1.0)
	var colour := GLINT if kind != EnemyAttack.UNBLOCKABLE else DANGER
	if _staggered and _tell <= 0.01:
		colour = AMBER
	set_param(&"tell", _tell)
	set_param(&"tell_color", Vector3(colour.r, colour.g, colour.b))


## A staggered monster keeps an amber tell for the whole window so the finisher opening reads at any
## distance (juice §7 ladder), and leans off balance.
func set_stagger(on: bool) -> void:
	_staggered = on
	if _visual != null:
		_visual.rotation_degrees.z = 7.0 if on else 0.0
	set_telegraph(_tell_kind, _tell)


## Juggernaut armour plates (SPEC §7 "armour plates break"). The model is one skinned mesh, so a
## broken plate is a state on the shared shader — the carapace darkens and loses its metal as plates
## go, and the exposed violet core gains emission, which is the readable "hit the back" cue.
func break_plate() -> bool:
	if _plates <= 0:
		return false
	_plates -= 1
	set_param(&"armor_damage", 1.0 - float(_plates) / float(PLATE_COUNT))
	set_param(&"emission_scale", 1.0 + 0.35 * (1.0 - float(_plates) / float(PLATE_COUNT)))
	return true


func plates_left() -> int:
	return _plates


func set_param(parameter: StringName, value: Variant) -> void:
	for mesh in _meshes:
		mesh.set_instance_shader_parameter(parameter, value)
