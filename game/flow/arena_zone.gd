class_name FlowArenaZone
extends Node3D
## The trigger that starts an arena's waves (brief §2, dossier §4.5). The footprint comes from the
## world's own `&"arena"` Area3D (CONTRACTS §7), so a concave arena triggers where the level designer
## drew it instead of on a bounding box; flow keeps each convex part of that decomposition and tests
## the hero's position against it.
##
## It is a polled point-in-polygon test, NOT an Area3D: seven monitoring convex hulls — the Crown deck
## alone is a 46-gon extruded 30 m — cost ~40 ms per frame in the real city (lead r3: flow must stay
## under 1 ms), and a trigger that only has to notice the hero crossing an arena edge does not need
## the physics engine at all. The poll runs at POLL_HZ on the world clock.

signal entered(arena_id: StringName)
signal exited(arena_id: StringName)

const POLL_HZ := 10.0
## The hero is a 16 m capsule: its centre sits ~8 m above its feet, so the vertical test reaches a
## little below `lo` and above `hi` and a mech standing on the arena floor counts as inside.
const FOOT_MARGIN := 10.0
const HEAD_MARGIN := 24.0

var arena_id: StringName = &""

var _parts: Array[PackedVector2Array] = []
var _lo: float = -INF
var _hi: float = INF
var _inside: bool = false
var _poll_t: float = 0.0


## `parts` are convex world-space footprints, `lo`/`hi` the vertical span of the world's own volume.
func build(id: StringName, parts: Array[PackedVector3Array], lo: float, hi: float) -> void:
	_prepare(id)
	for part in parts:
		if part.size() >= 3:
			_parts.append(_flat(part))
	_lo = lo
	_hi = maxf(hi, lo + 1.0)
	if _parts.is_empty():
		push_error("FlowArenaZone: arena '%s' has no usable footprint" % id)


## Sandbox: a square around the spawn, so the tutorial waves can be exercised before the city exists.
func build_box(id: StringName, centre: Vector3, radius: float, span: float) -> void:
	var poly := PackedVector3Array()
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		poly.append(centre + Vector3(cos(a), 0.0, sin(a)) * radius)
	build(id, [poly] as Array[PackedVector3Array], centre.y - span, centre.y + span)


func _prepare(id: StringName) -> void:
	arena_id = id
	name = "Arena_" + String(id)


func _flat(part: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in part:
		out.append(Vector2(p.x, p.z))
	return out


func is_inside() -> bool:
	return _inside


func _physics_process(delta: float) -> void:
	_poll_t += delta
	if _poll_t < 1.0 / POLL_HZ:
		return
	_poll_t = 0.0
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	poll(player.global_position)


## Test a world position and emit `entered`/`exited` on the edges. Public so the tests (and the tools)
## can drive it without waiting for the poll.
func poll(at: Vector3) -> bool:
	var now := contains(at)
	if now == _inside:
		return now
	_inside = now
	if now:
		entered.emit(arena_id)
	else:
		exited.emit(arena_id)
	return now


## Inside the vertical span and inside any of the convex parts.
func contains(at: Vector3) -> bool:
	if at.y < _lo - FOOT_MARGIN or at.y > _hi + HEAD_MARGIN:
		return false
	var p := Vector2(at.x, at.z)
	for part in _parts:
		if _crossing_test(p, part):
			return true
	return false


## Even-odd crossing test (no `Geometry2D.is_point_in_polygon`: it triangulates first and answers
## false for a footprint it cannot triangulate, which is a silent "the arena never triggers").
static func _crossing_test(p: Vector2, part: PackedVector2Array) -> bool:
	var inside := false
	var n := part.size()
	var j := n - 1
	for i in n:
		var a := part[i]
		var b := part[j]
		if (a.y > p.y) != (b.y > p.y) \
				and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside
