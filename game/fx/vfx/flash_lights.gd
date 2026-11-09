class_name FlashLightPool
extends Node3D
## Pooled flash lights (feel unit): the 2-3 frame OmniLight3D pops that sell a muzzle, a blast or a
## finisher. Capped at 8 live lights so a salvo never eats the 16 shadow-caster budget
## (CONTRACTS §2); the pool steals the oldest slot instead of growing.

const MAX_LIGHTS := 8

var _lights: Array[OmniLight3D] = []
## Rendered-frame index each slot goes dark at. Frames, not seconds: a movie frame costs ~70 ms of
## wall time, so a seconds deadline would make every 2-4 frame pop last exactly one frame.
var _free_frame: PackedInt64Array = PackedInt64Array()
var _next: int = 0


func _ready() -> void:
	for i in MAX_LIGHTS:
		var l := OmniLight3D.new()
		l.name = "Flash%d" % i
		l.visible = false
		l.shadow_enabled = false
		l.light_specular = 0.2
		l.distance_fade_enabled = true
		l.distance_fade_begin = 220.0
		l.distance_fade_length = 60.0
		add_child(l)
		_lights.append(l)
		_free_frame.append(-1)


## Pop a light at `at` for `frames` (default 3 f). Energy/range follow the FEEL row (blast 8 / 12 m).
func flash(at: Vector3, color: Color, energy: float, range_m: float, frames: float = 3.0) -> void:
	if _lights.is_empty():
		return
	var slot := _oldest()
	var l := _lights[slot]
	l.global_position = at
	l.light_color = color
	l.light_energy = energy
	l.omni_range = maxf(range_m, 0.5)
	l.visible = true
	_free_frame[slot] = _frame() + int(maxf(frames, 1.0))


func active_count() -> int:
	var n := 0
	var now := _frame()
	for t in _free_frame:
		if t > now:
			n += 1
	return n


func _process(_delta: float) -> void:
	var now := _frame()
	for i in _lights.size():
		if _lights[i].visible and _free_frame[i] <= now:
			_lights[i].visible = false


## Round-robin from the last used slot, skipping lights that are still lit when one is free.
func _oldest() -> int:
	var now := _frame()
	for i in _lights.size():
		var slot := (_next + i) % _lights.size()
		if _free_frame[slot] <= now:
			_next = (slot + 1) % _lights.size()
			return slot
	var slot := _next
	_next = (_next + 1) % _lights.size()
	return slot


## Rendered-frame counter: Godot bumps it once per iteration, after physics and _process, so a pop
## requested from a physics tick still gets its full `frames` on screen whichever phase asked.
func _frame() -> int:
	return int(Engine.get_process_frames())
