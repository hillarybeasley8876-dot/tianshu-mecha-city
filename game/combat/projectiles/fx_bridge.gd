class_name FxBridge
extends RefCounted
## The one place the weapons/projectiles code touches the fx unit (CONTRACTS §6): it finds the
## FeelDirector's VfxLibrary in the running tree, caches it, and offers small helpers that fall back
## to a caller-supplied effect when the fx unit is not in the scene (tests, the bare range scene).
##
## The library is not in a group, so it is located by class through find_children once per tree and
## re-tried every `RETRY` seconds while it is missing (main.tscn instances the director after the
## player, so the first shots may arrive before it exists).

const RETRY := 0.5

static var _cached: Node = null
static var _next_try: float = 0.0
static var _disc: ImageTexture = null


## The VfxLibrary node, or null when the fx unit is not in the tree (fx unit's own class name).
static func library(from: Node) -> Node:
	if _cached != null and is_instance_valid(_cached) and _cached.is_inside_tree():
		return _cached
	_cached = null
	var tree := from.get_tree() if from != null and from.is_inside_tree() else null
	if tree == null:
		return null
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_try:
		return null
	_next_try = now + RETRY
	var root := tree.current_scene if tree.current_scene != null else tree.root
	if root == null:
		return null
	var found := root.find_children("*", "VfxLibrary", true, false)
	if not found.is_empty():
		_cached = found[0]
	return _cached


## Spawn a pooled fx kind. Returns false when there is no library or the kind is unknown, so the
## caller can draw its own fallback.
static func spawn(from: Node, kind: StringName, at: Vector3, normal: Vector3 = Vector3.UP,
		scale: float = 1.0) -> bool:
	var lib := library(from)
	if lib == null or not lib.has_method(&"spawn"):
		return false
	return bool(lib.call(&"spawn", kind, at, normal, scale))


## Short omni flash (the fx pool holds 8). No-op without the library.
static func flash(from: Node, at: Vector3, color: Color, energy: float, range_m: float,
		frames: float = 3.0) -> bool:
	var lib := library(from)
	if lib == null or not lib.has_method(&"flash_light"):
		return false
	lib.call(&"flash_light", at, color, energy, range_m, frames)
	return true


## Expanding ground/air ring. No-op without the library.
static func ring(from: Node, at: Vector3, normal: Vector3, radius: float, seconds: float,
		color: Color) -> bool:
	var lib := library(from)
	if lib == null or not lib.has_method(&"spawn_ring"):
		return false
	return bool(lib.call(&"spawn_ring", at, normal, radius, seconds, color))


## Drop the cache (scene changes, tests).
static func reset() -> void:
	_cached = null
	_next_try = 0.0


## 64x64 radial falloff disc, built once: the soft body of every smoke puff / flare sprite we draw
## ourselves (the fx unit has its own particle textures).
static func soft_disc_texture() -> ImageTexture:
	if _disc != null:
		return _disc
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (float(size) - 1.0) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / (c + 0.001)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a * (3.0 - 2.0 * a)))
	_disc = ImageTexture.create_from_image(img)
	return _disc
