class_name MonsterModel
extends Node3D
## A rigged HUSK monster model (monster-assets). Implements the CONTRACTS §6 model API so
## `enemies/<type>/<type>.tscn` swaps its placeholder for this scene and nothing else changes:
## `set_locomotion(state, speed)`, `play_action(id) -> float`, `socket(name)`, `hit_pause(s)`,
## `set_hit_flash(v)` — plus the placeholder's extras (`set_telegraph`, `set_stagger`,
## `break_plate`, `visual_root`) which the enemies unit calls when they exist.
##
## Everything the build knows about the model is data: `<type>/<type>_rig.json` (written by
## `blender/monsters/build_all.py`) carries the size, the bone names, the clip lengths and loop
## flags, and every socket in Godot model space. Nothing here is hard-coded per type.
##
## Per-instance state goes through `set_instance_shader_parameter`, so all 40 rippers on screen
## share one ShaderMaterial (see `monster_body.gdshader`).
##
## This file is the facade only (lead split r1): the body lives in `MonsterAssembly`, the material
## in `MonsterLook`, the clip/gait/action state in `MonsterPlayback`, the markers in `MonsterSockets`
## and the flash/tell/plate state in `MonsterTells`.

const LOCOMOTION_BLEND := MonsterPlayback.LOCOMOTION_BLEND
const ACTION_BLEND := MonsterPlayback.ACTION_BLEND
## Fallback clip length when a caller asks for an action this type does not have.
const MISSING_ACTION := MonsterPlayback.MISSING_ACTION
## Juggernaut armour plates (SPEC §7 "armour plates break"); only a visual budget here.
const PLATE_COUNT := MonsterTells.PLATE_COUNT
const MIN_SPEED_SCALE := MonsterPlayback.MIN_SPEED_SCALE
const MAX_SPEED_SCALE := MonsterPlayback.MAX_SPEED_SCALE
const MAX_SPEED_SCALE_LIMIT := MonsterPlayback.MAX_SPEED_SCALE_LIMIT
const MIN_SPEED_SCALE_LIMIT := MonsterPlayback.MIN_SPEED_SCALE_LIMIT

@export var body_type: StringName = &"ripper"

var rig: Dictionary = {}
var visual: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var meshes: Array[MeshInstance3D] = []

var _playback: MonsterPlayback
var _sockets: MonsterSockets
var _tells: MonsterTells


func _ready() -> void:
	rig = _load_rig()
	var assembly := MonsterAssembly.new()
	assembly.build(self, body_type, rig)
	visual = assembly.visual
	skeleton = assembly.skeleton
	animation = assembly.animation
	meshes = assembly.meshes
	_playback = MonsterPlayback.new()
	_playback.setup(animation, rig, body_type)
	_sockets = MonsterSockets.new()
	_sockets.setup(visual, skeleton, rig, body_type)
	_tells = MonsterTells.new()
	_tells.setup(visual, meshes)
	_playback.apply_state()


func _load_rig() -> Dictionary:
	var path := "res://enemies/models/%s/%s_rig.json" % [body_type, body_type]
	if not FileAccess.file_exists(path):
		push_error("MonsterModel(%s): no rig data at %s — run blender/monsters/build_all.py"
				% [body_type, path])
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	push_error("MonsterModel(%s): %s is not valid JSON" % [body_type, path])
	return {}


## The per-type look numbers from `<type>_rig.json` (see `MonsterLook`). Static because `HiveModel`
## shares the shader and the table.
static func apply_look(material: ShaderMaterial, look: Dictionary,
		pod_mask_path: String = "") -> void:
	MonsterLook.apply(material, look, pod_mask_path)


# --- model API (CONTRACTS §6) ---------------------------------------------------------------------

## Drive the locomotion loop. `state` is EnemyBase's move state (idle / walk / run / stagger / ...);
## the rig data maps it onto this type's clip, and the gait ladder picks the rung whose authored
## stride is nearest the speed the body is really moving (lead r3).
func set_locomotion(state: StringName, speed: float) -> void:
	_playback.set_locomotion(state, speed)


## Play a one-shot action and return its length in seconds, so callers can time gameplay against it.
func play_action(id: StringName, blend: float = ACTION_BLEND) -> float:
	return _playback.play_action(id, blend)


func socket(name: StringName) -> Node3D:
	var found := _sockets.marker(name)
	if found == null:
		push_warning("MonsterModel(%s): no socket '%s'" % [body_type, name])
		return visual
	return found


## Every weak-point marker this model carries, strongest violet core first.
func weak_points() -> Array[Node3D]:
	return _sockets.weak_points()


## Local hit-stop: freeze this monster's own animation (Feel owns the global time scale, and
## EnemyVisuals owns the vibration offset, so this only stops playback).
func hit_pause(seconds: float) -> void:
	_playback.pause(seconds)


func set_hit_flash(v: float) -> void:
	_tells.set_flash(v)


func _process(delta: float) -> void:
	_playback.advance(delta)


# --- extras the placeholder also provides (the enemies unit calls them when they exist) ------------

## Attack tell: white glint = parryable, red = unblockable (SPEC §7 counters). v ramps 0 -> 1 over
## the windup so the tell builds instead of snapping on (juice §11.1).
func set_telegraph(kind: StringName, v: float) -> void:
	_tells.set_telegraph(kind, v)


## A staggered monster keeps an amber tell for the whole window so the finisher opening reads at any
## distance (juice §7 ladder), and leans off balance.
func set_stagger(on: bool) -> void:
	_tells.set_stagger(on)


## Juggernaut armour plates (SPEC §7 "armour plates break"): true while a plate is left to break.
func break_plate() -> bool:
	return _tells.break_plate()


func plates_left() -> int:
	return _tells.plates_left()


func visual_root() -> Node3D:
	return visual


# --- read-only helpers for tests and the capture scenes -------------------------------------------

## Measured size of the finished model along the axis the brief pins (height, length or span).
func measured_size() -> float:
	var size := world_size()
	match String((rig.get("size", {}) as Dictionary).get("axis", "height")):
		"length":
			return size.z
		"span":
			return size.x
		_:
			return size.y


## World-space bounding size of the body meshes (rest pose).
func world_size() -> Vector3:
	var box := AABB()
	var first := true
	for mesh in meshes:
		if mesh.mesh == null:
			continue
		var local := mesh.mesh.get_aabb()
		var basis := mesh.global_transform.basis
		var scaled := Vector3(absf(basis.x.dot(local.size)), absf(basis.y.dot(local.size)),
				absf(basis.z.dot(local.size)))
		var centre := mesh.global_transform * local.get_center()
		var grown := AABB(centre - scaled * 0.5, scaled)
		box = grown if first else box.merge(grown)
		first = false
	return box.size


func target_size() -> float:
	return float((rig.get("size", {}) as Dictionary).get("target", 0.0))


func clip_ids() -> PackedStringArray:
	return _playback.clip_ids()
