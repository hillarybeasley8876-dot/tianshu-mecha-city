class_name CombatVfx
extends RefCounted
## Where the combat components find the shipped VFX library (melee + defence share this).
##
## In the game the FeelDirector is always present and owns the library. Demo ranges and headless
## tests run without a director, so a library that registered itself in group `vfx_library` is the
## fallback. Returns null — never a fake — when neither exists, so callers skip the effect honestly.

const GROUP := &"vfx_library"


## The library reachable from `from`, or null.
static func library(from: Node) -> Node:
	if from == null or not is_instance_valid(from) or not from.is_inside_tree():
		return null
	var tree := from.get_tree()
	if tree == null:
		return null
	var director := tree.root.find_child("FeelDirector", true, false)
	if director != null:
		var owned: Variant = director.get(&"vfx")
		if owned != null:
			return owned as Node
	return tree.get_first_node_in_group(GROUP)


## One pooled effect, when a library exists. Returns false when there is nothing to spawn into.
static func spawn(from: Node, kind: StringName, at: Vector3, normal: Vector3 = Vector3.UP,
		scale: float = 1.0) -> bool:
	var lib := library(from)
	if lib == null or not lib.has_method(&"spawn"):
		return false
	return bool(lib.call(&"spawn", kind, at, normal, scale))


## Debris burst (chunks with gravity) — used where the crescent scours the ground.
static func debris(from: Node, at: Vector3, count: int, speed: float, size: float,
		metal: bool = false) -> bool:
	var lib := library(from)
	if lib == null or not lib.has_method(&"spawn_debris"):
		return false
	lib.call(&"spawn_debris", at, count, speed, size, metal)
	return true


## A short-lived point light, so a heavy impact lights the arena for a few frames.
static func flash(from: Node, at: Vector3, color: Color, energy: float, range_m: float) -> bool:
	var lib := library(from)
	if lib == null or not lib.has_method(&"flash_light"):
		return false
	lib.call(&"flash_light", at, color, energy, range_m)
	return true
