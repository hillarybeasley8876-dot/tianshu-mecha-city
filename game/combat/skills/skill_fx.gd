class_name SkillFx
extends RefCounted
## The one place the skills code touches the fx unit (CONTRACTS §1: we may not edit their files).
## Finds the FeelDirector's VfxLibrary by class through the tree, caches it, and re-tries on a timer
## while it is missing — main.tscn instances the director after the player, so the first skill may
## fire before it exists. Every helper is null-tolerant: with no library the skill still runs, it
## simply draws its own meshes (each skill owns its distinctive visual anyway).
##
## Feel rows (docs/FEEL.md) are fired through the `Feel` autoload, not here: SkillSystem calls
## `Feel.play(&"rift_step", pos)` and the director does hitstop/shake/sound together.

const RETRY := 0.5

static var _cached: Node = null
static var _next_try: float = 0.0


## The VfxLibrary node, or null when the fx unit is not in the tree (tests, the bare range scene).
static func library(from: Node) -> Node:
	if _cached != null and is_instance_valid(_cached) and _cached.is_inside_tree():
		return _cached
	_cached = null
	if from == null or not from.is_inside_tree():
		return null
	var tree := from.get_tree()
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_try:
		return null
	_next_try = now + RETRY
	var root: Node = tree.current_scene if tree.current_scene != null else tree.root
	if root == null:
		return null
	var found := root.find_children("*", "VfxLibrary", true, false)
	if not found.is_empty():
		_cached = found[0]
	return _cached


## Pooled particle one-shot. Returns false when there is no library or the kind is unknown.
static func spawn(from: Node, kind: StringName, at: Vector3, normal: Vector3 = Vector3.UP,
		scale: float = 1.0) -> bool:
	var lib := library(from)
	if lib == null or not lib.has_method(&"spawn"):
		return false
	return bool(lib.call(&"spawn", kind, at, normal, scale))


## Expanding shockwave ring (the library's ShockwaveFx handles the tween).
static func ring(from: Node, at: Vector3, normal: Vector3, radius: float, seconds: float,
		color: Color) -> bool:
	var lib := library(from)
	if lib == null or not lib.has_method(&"spawn_ring"):
		return false
	return bool(lib.call(&"spawn_ring", at, normal, radius, seconds, color))


## Short-lived OmniLight3D flash (the pool caps concurrent lights at 8).
static func flash(from: Node, at: Vector3, color: Color, energy: float, range_m: float,
		frames: float = 3.0) -> void:
	var lib := library(from)
	if lib != null and lib.has_method(&"flash_light"):
		lib.call(&"flash_light", at, color, energy, range_m, frames)


static func decal(from: Node, kind: StringName, at: Vector3, normal: Vector3, scale: float) -> bool:
	var lib := library(from)
	if lib == null:
		return false
	var pool: Variant = lib.get(&"decals")
	if pool == null or not (pool as Object).has_method(&"add"):
		return false
	return bool((pool as Object).call(&"add", kind, at, normal, scale))


## Ghost the mech's meshes at their current pose (overdrive afterimages, rift transit).
static func afterimage(from: Node, source: Node3D, life: float, color: Color) -> bool:
	var lib := library(from)
	if lib == null or not lib.has_method(&"afterimage") or source == null:
		return false
	return int(lib.call(&"afterimage", source, life, color)) > 0


static func spawn_debris(from: Node, at: Vector3, count: int, speed: float, size: float) -> void:
	var lib := library(from)
	if lib != null and lib.has_method(&"spawn_debris"):
		lib.call(&"spawn_debris", at, count, speed, size)


## Additive, unshaded, transparent material for the skills' own geometry (cable, ward, well, lance).
static func glow(color: Color, energy: float = 2.0, cull: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = Color(color.r, color.g, color.b)
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED if cull else BaseMaterial3D.CULL_BACK
	m.disable_receive_shadows = true
	return m


## Basis for a unit box stretched along `dir`: `Basis.scaled()` scales the ROWS (global axes), which
## shears any beam that is not axis-aligned — the local axes have to be scaled as columns instead.
static func stretched(dir: Vector3, up: Vector3, width: float, length: float) -> Basis:
	var b := Basis.looking_at(dir, up)
	return Basis(b.x * width, b.y * width, b.z * length)


## Basis for a unit CYLINDER (radius 0.5, height 1, built along its local +Y) laid along `dir`: the Y
## COLUMN carries the length, X and Z carry the width. `Basis.looking_at` aims -Z at `dir`, so the
## columns are re-ordered (x, -z, y) — a swap and a negation, which keeps the basis right-handed.
static func tube_basis(dir: Vector3, up: Vector3, width: float, length: float) -> Basis:
	var b := Basis.looking_at(dir, up)
	return Basis(b.x * width, -b.z * length, b.y * width)
