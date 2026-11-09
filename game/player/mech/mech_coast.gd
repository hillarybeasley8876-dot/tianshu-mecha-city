class_name MechCoast
extends RefCounted
## The step-up coast (mech-move r8 item 1, SPEC §4 "Stepping"). Owned by `MechLocomotion`.
##
## `MechStepping.try_step` used to move the capsule up onto a kerb in ONE tick. Measured tick by tick
## on the sandbox kerb (`probe_float.gd --case=walk_kerb --debug=1`), that is 2.01 m up and 4.24 m
## forward between two consecutive physics frames: the hip cleared the trailing foot's plant by
## 6.96 m before the gait released it — 10.4 m from a hip whose leg reaches 8.5 m — so the leg IK
## clamped and the sole floated 0.91 m above the kerb (`walk_kerb` 75 % near, worst +0.91 / -1.11).
##
## Two things fix it, and both live here:
##
## 1. **The coast.** `try_step` hands over the whole displacement instead of applying it, and the body
##    walks it out over `run-up / speed` seconds. That IS the speed the mech was already doing, so the
##    body neither stalls nor surges, and — the point — the hip advances no faster than the feet can
##    follow. `move_and_slide` is skipped for the duration (`try_step` already proved the straight
##    line clear with `test_move` up and then forward), so `is_on_floor()` keeps the value the last
##    real move left and the mech never enters S.AIR half way up a kerb.
## 2. **The model lag.** The model node hangs off the body, so the gait's ground plane
##    (`Hero3Frame.ground()`) and every hip in the rig ride the capsule's climb. Holding the node
##    `lag` metres low keeps that plane on the surface the trailing foot is really standing on;
##    `Hero3Ground` then plants each foot on the surface under IT, so the leading foot stands on the
##    kerb top while the trailing one is still on the road. The lag is given back per METRE travelled,
##    not per second, so the feet are back under the hips after the same stretch of road at a walk and
##    at a boost.

## Metres the model still lags the capsule. Read through `MechLocomotion.step_lag` (telemetry, tests).
var lag: float = 0.0
var _t: float = 0.0
var _dur: float = 0.0
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
## The model node's own rest offset, read once so a tool that parks the node somewhere else on purpose
## keeps its value (`probe_float.gd --nofix` puts it back on the body origin).
var _rest_y: float = INF


## True while the capsule is being walked up onto a kerb instead of teleported there.
func active() -> bool:
	return _t > 0.0


## `move` is the whole displacement the capsule used to take in one tick: the rise plus the run-up
## past the kerb face. `speed` is the mech's own horizontal speed, which is what sets the duration.
func begin(b: CharacterBody3D, move: Vector3, rise: float, speed: float, min_dur: float) -> void:
	var run := Vector3(move.x, 0.0, move.z).length()
	_from = b.global_position
	_to = _from + move
	_dur = maxf(run / maxf(speed, 0.1), min_dur)
	_t = _dur
	lag = maxf(lag, rise)


## The coast IS the move: place the body along the straight line to the kerb top. Called by
## `PlayerMech._physics_process` in place of `_move()` while `active()`.
func advance(b: CharacterBody3D) -> void:
	var p := 1.0 - _t / maxf(_dur, 0.0001)
	b.global_position = _to if p >= 1.0 else _from.lerp(_to, p)


## Runs the coast clock and gives the lag back. The lag is held for the whole coast — the trailing
## foot is on the lower surface until it ends — and then unwinds per metre travelled, with a time
## floor so a mech that stops dead on a kerb still puts its feet back under it.
func tick(rd: float, speed: float, ease_speed: float, ease_ratio: float) -> void:
	_t = maxf(_t - rd, 0.0)
	if _t > 0.0:
		return
	lag = maxf(lag - maxf(ease_speed * rd, ease_ratio * speed * rd), 0.0)


## Hold the model node `lag` metres low so the legs plan on the surface the feet are really on.
func apply_lag(model: Node3D) -> void:
	if model == null or not is_instance_valid(model):
		return
	if _rest_y == INF:
		_rest_y = model.position.y
	if is_zero_approx(lag) and is_equal_approx(model.position.y, _rest_y):
		return
	model.position.y = _rest_y - lag


## A state change drops the coast but NOT the lag: the mech left the ground on its own terms, and the
## model still has a kerb's rise to give back once it is down again.
func stop() -> void:
	_t = 0.0
	_dur = 0.0


## A death or a scripted reset drops both, so nothing is left half done.
func reset() -> void:
	stop()
	lag = 0.0
