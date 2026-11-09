class_name SkillFxPiece
extends Node3D
## Base of every effect the skills unit draws itself (CONTRACTS §1: the fx unit owns `fx/**`, so each
## skill's signature geometry lives here). A piece is pooled by `SkillVfx`, times itself on the WORLD
## clock (CONTRACTS §3: VFX use plain delta, so witch time drags them with the world they belong to)
## and goes invisible — never `queue_free` — when its life runs out.

var _t: float = 0.0
var _life: float = 0.0


func _ready() -> void:
	visible = false


## Pool bookkeeping: an invisible piece may be handed to the next caller.
func free_to_use() -> bool:
	return not visible


func _begin(life: float) -> void:
	_t = 0.0
	_life = maxf(life, 0.016)
	visible = true


func stop() -> void:
	visible = false
	_t = 0.0


func life_left() -> float:
	return maxf(_life - _t, 0.0)


## 0 at the moment of firing, 1 at the end of life.
func progress() -> float:
	return clampf(_t / maxf(_life, 0.0001), 0.0, 1.0)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_advance(delta)
	if _t >= _life:
		stop()


## Per-frame animation; the base only counts time.
func _advance(_delta: float) -> void:
	pass
