class_name BossCollapse
extends RefCounted
## The Brood Titan's death sequence (boss unit, brief §5). Three beats that have to happen in this
## order to read at all: a chain of `kill_large` blasts walks UP the standing body over
## COLLAPSE_BLAST_TIME while the camera can still see it, the corpse then topples outward and slides
## over the deck edge, and dust + a smoke column bloom out of the rim where it crossed.
##
## `BroodTitan` owns one and ticks it; every number is `BossTuning`'s. No generic dissolve: the brief
## and the lead's r2 are explicit that a 60 m boss does not fade out.

var finished: bool = false
## Blasts fired so far, and how far through the topple the body is — the titan's `collapse_state()`
## passes both on, so the death beat is inspectable from the HUD and from the suite.
var blasts: int = 0

var _body: Node3D
var _model: Node3D
var _tree: SceneTree
var _fall_dir: Vector3 = Vector3.FORWARD
var _t: float = 0.0
var _next_blast: int = 0
var _smoke: Node3D = null
var _smoke_done: bool = false


## `fall_dir` is the horizontal direction the body goes over the rim; the titan has already turned to
## face it, so the model's local −Z is outward and a tip about X reads as a fall in that direction.
func _init(body: Node3D, model: Node3D, fall_dir: Vector3) -> void:
	_body = body
	_model = model
	_tree = body.get_tree()
	_fall_dir = fall_dir


## Starts the beat: turns the corpse OUTWARD, away from the deck centre, so a 60 m trunk ends up over
## the rim instead of lying across the arena. Turning it first is what makes the topple read as a
## direction.
static func begin(body: Node3D, model: Node3D) -> BossCollapse:
	var out := body.global_position
	var arena := body.get_tree().get_first_node_in_group(&"boss_arena") as Node3D
	if arena != null:
		out = body.global_position - arena.global_position
	out.y = 0.0
	if out.length_squared() < 1.0:
		out = -body.global_basis.z
	out = out.normalized()
	body.look_at_from_position(body.global_position, body.global_position + out, Vector3.UP)
	return BossCollapse.new(body, model, out)


func tick(delta: float) -> void:
	if finished or _body == null or not is_instance_valid(_body):
		return
	_t += delta
	var k: float = clampf(_t / BossTuning.COLLAPSE_TIME, 0.0, 1.0)
	# Hinged at the feet: eased so almost all of the rotation happens after the blast chain, which is
	# the part the player is meant to be watching.
	if _model != null and is_instance_valid(_model):
		_model.rotation_degrees.x = -BossTuning.COLLAPSE_FALL_DEG * ease(k, 2.4)
	# The whole corpse slides outward and drops, so by the end of the beat the mass is past the rim
	# and the dust is the only thing left on the deck.
	_body.global_position += _fall_dir * (BossTuning.COLLAPSE_SLIDE * delta * k)
	_body.global_position.y -= BossTuning.COLLAPSE_DROP * delta * ease(k, 1.6)
	while _next_blast < BossTuning.COLLAPSE_BLASTS and _t >= BossTuning.COLLAPSE_BLAST_TIME \
			* float(_next_blast) / float(BossTuning.COLLAPSE_BLASTS):
		_blast(_next_blast)
		_next_blast += 1
	_edge_smoke(k)
	if _t >= BossTuning.COLLAPSE_TIME:
		finished = true


## One blast of the chain: feet first, head last, so the titan comes apart from the ground up.
func _blast(index: int) -> void:
	blasts += 1
	var step := float(index) / float(maxi(BossTuning.COLLAPSE_BLASTS - 1, 1))
	var at := _body.global_position + Vector3(randf_range(-14.0, 14.0),
			BossTuning.HEIGHT * (0.08 + 0.85 * step), randf_range(-14.0, 14.0))
	var vfx := _vfx()
	if vfx != null:
		vfx.call(&"spawn", &"kill_large", at, Vector3.UP, BossTuning.COLLAPSE_BLAST_SCALE)
		vfx.call(&"spawn_debris", at, 8, 22.0, 2.4, true)
	Feel.shake(0.3, at)
	Audio.play(&"kill_large_far", at)


## Dust off the rim as the body crosses it, then a borrowed smoke column that keeps burning through
## the victory beat and is given back when the beat is over.
func _edge_smoke(k: float) -> void:
	if k < 0.55 or _smoke_done:
		return
	_smoke_done = true
	var at := _edge_point()
	var vfx := _vfx()
	if vfx != null:
		vfx.call(&"spawn", &"dust_ring", at, Vector3.UP, BossTuning.COLLAPSE_DUST_SCALE)
		vfx.call(&"spawn", &"debris", at, Vector3.UP, BossTuning.COLLAPSE_DUST_SCALE)
		_smoke = vfx.call(&"emitter", &"smoke_column", at,
				BossTuning.COLLAPSE_DUST_SCALE) as Node3D
	Feel.shake(0.45, at)
	Audio.play(&"spire_destroyed", at)


## Where the corpse crossed the rim: outward along the fall line, at deck height.
func _edge_point() -> Vector3:
	var at := _body.global_position + _fall_dir * BossTuning.HEIGHT * 0.6
	var arena := _tree.get_first_node_in_group(&"boss_arena") as Node3D
	if arena != null:
		at.y = arena.global_position.y
	return at


func _vfx() -> Node:
	return _tree.get_first_node_in_group(&"vfx_library")


## The emitter is only borrowed; it outlives the corpse, so the owner must hand it back.
func release() -> void:
	if _smoke == null:
		return
	var vfx := _vfx()
	if vfx != null:
		vfx.call(&"release_emitter", _smoke)
	_smoke = null


## How long the edge keeps smoking (the victory beat plus the fall cut).
static func smoke_seconds() -> float:
	return BossTuning.COLLAPSE_SMOKE_TIME


## 0 → 1 across COLLAPSE_TIME, on the SLOWED clock: the killing blow's 0.2× slow-mo makes this take
## longer in real seconds than the topple's own length.
func progress() -> float:
	return clampf(_t / BossTuning.COLLAPSE_TIME, 0.0, 1.0)
