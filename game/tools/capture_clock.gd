extends RefCounted
## One clock for a capture run (tools/capture.gd): `--times`, `--pulse` and `--key` are all measured
## from the SAME instant — the moment the world is ready and the warm-up frames are done. Before this,
## `--pulse` was compared against the time since engine start while `--times` was compared against the
## time since world-ready, so a pulse fired about 1.1 s before the shot it was meant to line up with
## (camera-aim r8, Request 6).
##
## The unit is the frame delta Godot hands `_process`, i.e. GAME time: a run that slows time down
## stretches the clock with it, exactly as the shot times always have.

var _t: float = 0.0          ## accumulated since engine start
var _origin: float = -1.0    ## _t when the timed phase began; < 0 = not started yet


func advance(delta: float) -> void:
	_t += delta


## Called once, when the world is ready and the warm-up is done.
func start() -> void:
	_origin = _t


func started() -> bool:
	return _origin >= 0.0


## Seconds since the timed phase began; 0 before it starts.
func now() -> float:
	return _t - _origin if started() else 0.0


## True once `t` seconds of the timed phase have passed. Never true before `start()`.
func due(t: float) -> bool:
	return started() and now() >= t
