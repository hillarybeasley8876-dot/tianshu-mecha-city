class_name FlowBounds
extends RefCounted
## "You have fallen out of the world" (r5 brief item 5). The city's tunnel ends at U4, U5 and U6 are
## open, so the mech can walk or boost off one and fall to −3,000 with nothing noticing; the Crown has
## its own catch during the boss fight (`boss_arena.gd`) and this file leaves that alone.
##
## Two ways out of the world, both read from the city's own numbers:
## * the feet drop below `FALL_Y` — the lowest floor in the city is the −40 m tunnel deck, so −120 m is
##   80 m of "there is no floor under you";
## * the mech leaves the playable square in `world/city/layout.json` (`bounds.half`).
##
## Pure statics: `FlowGameFlow` asks every physics tick and the answer is a readable reason or "".

const LAYOUT := "res://world/city/layout.json"
## m below which there is no floor anywhere: the −40 tunnel deck is the lowest, so −120 is 80 m clear.
const FALL_Y := -120.0
## Fallback when the city layout is not in the build (a stubbed world, a headless fixture): the
## playable square MAP §5 documents.
const HALF_FALLBACK := 700.0
## No capsule to read (a stubbed hero): PlayerMech's own `MechTuning.capsule_height * 0.5`.
const HALF_HEIGHT := 7.5

static var _half: float = HALF_FALLBACK
static var _loaded: bool = false
## The capsule does not change size mid-run, and this is asked 120 times a second: the last answer is
## kept against the hero it was measured on.
static var _half_for: int = 0
static var _half_value: float = HALF_HEIGHT


## Reads `bounds.half` once. A missing or malformed layout is a warning and the documented fallback,
## never a crash: the flow still has to catch a fall in a stubbed world.
static func load_bounds() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(LAYOUT):
		push_warning("FlowBounds: no %s — out-of-bounds uses the ±%.0f m fallback" % [LAYOUT, HALF_FALLBACK])
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not (parsed is Dictionary):
		push_warning("FlowBounds: %s is not a JSON object — using the ±%.0f m fallback"
				% [LAYOUT, HALF_FALLBACK])
		return
	var half: Variant = ((parsed as Dictionary).get("bounds", {}) as Dictionary).get("half")
	if half == null:
		push_warning("FlowBounds: %s has no bounds.half — using ±%.0f m" % [LAYOUT, HALF_FALLBACK])
		return
	_half = float(half)


## The playable half-extent, for a test or a tool that wants to check the number it read.
static func half() -> float:
	load_bounds()
	return _half


## Why this hero is outside the world, or "" when it is inside it. The string names the margin, so a
## log line says how far out the mech went rather than only that it did.
static func reason(player: Node3D) -> String:
	if player == null or not is_instance_valid(player):
		return ""
	load_bounds()
	var at := player.global_position
	var feet := at.y - half_height(player)
	if feet < FALL_Y:
		return "feet at %.0f m, %.0f m below the %.0f m floor" % [feet, FALL_Y - feet, FALL_Y]
	var out := maxf(absf(at.x), absf(at.z))
	if out > _half:
		return "%.0f m out, %.0f m past the ±%.0f m bounds" % [out, out - _half, _half]
	return ""


## The capsule's bottom, measured the way the traversal probes measure it (`mech_stepping.gd`).
static func half_height(player: Node3D) -> float:
	var id := player.get_instance_id()
	if id == _half_for:
		return _half_value
	_half_for = id
	_half_value = HALF_HEIGHT
	for child in player.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is CapsuleShape3D:
			_half_value = (shape.shape as CapsuleShape3D).height * 0.5
			break
	return _half_value
