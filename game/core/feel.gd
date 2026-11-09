extends Node
## Feel (autoload, core-owned): the ONLY owner of Engine.time_scale, plus a request bus for screen
## effects. Gameplay code calls these functions; the feel unit (fx/feel_director.gd) and the camera
## rig implement the visuals by listening to the signals. Nothing else may write Engine.time_scale.
##
## Preferred entry point: `Feel.play(&"event_id", world_pos, strength, actors)` — the FeelDirector
## looks the id up in its data table (docs/FEEL.md rows, one FeelEvent resource each) and fires
## hitstop, shake, flash, FOV, slow-mo, particles, sound and rumble together. `actors` are the nodes
## a LOCAL hit-stop belongs to (the victim of a gunfire kill, attacker + victim of a melee hit); pass
## them and the director runs `local_hit_stop` for you. The primitives below are for code that
## needs one effect directly (weapon recoil kick, a scripted cinematic).
## Local hit-stop (only the actors involved freeze) is per actor: actors implement
## `hit_pause(seconds: float)`; `Feel.local_hit_stop(actors, seconds)` calls it on each.
## Global hit-stop is rate-limited here: at most one start per 150 ms and 3 per second.
##
## Time model: hit-stop (short freeze) and slow-mo (longer, eased) combine as min(); both run on real
## time, so they end on schedule however slow the game is. Slow-mo requests combine with each other
## the same way — see slow_mo().
## THREE CLOCKS (CONTRACTS §3) — physics still ticks 120×/s of real time, each tick's `delta` is scaled:
##   real_delta(delta)       input timing (tap/hold, double-tap, chords, buffers), UI, camera springs.
##   locomotion_delta(delta) player movement: never slowed by witch time or global hit-stops.
##   player_delta(delta)     player timers/fire rates/cooldowns/anims: full speed in witch time, frozen by
##                           global hit-stops (that freeze IS the impact).
##   plain delta             world: enemies, projectiles, VFX, props.

signal shake_requested(trauma: float, origin: Vector3)     ## trauma 0..1 added; origin INF = global
signal flash_requested(color: Color, duration: float)
signal fov_kick_requested(degrees: float, duration: float)
signal post_requested(effect: StringName, strength: float, duration: float)  ## chromatic, radial_blur, vignette, speedlines, desaturate
signal rumble_requested(weak: float, strong: float, duration: float)   ## fx RumbleMixer drives the pads
signal kick_requested(degrees: float, world_dir: Vector3, duration: float)  ## camera recoil/impact kick
signal shake_floor_requested(trauma: float, seconds: float)  ## hold camera trauma >= this for `seconds` (real time)
signal witch_time_changed(active: bool)
## Both are emitted by play(); the 3-argument one is the audio router's and the HUD's, the
## 4-argument one carries the actors a LOCAL hit-stop belongs to (the feel director).
signal event_requested(event: StringName, at: Vector3, strength: float)
signal event_with_actors_requested(event: StringName, at: Vector3, strength: float, actors: Array)

const MIN_SCALE := 0.02

## One live slow_mo() request, with its own clock (see slow_mo).
class SlowMo:
	var scale: float = 1.0
	var left: float = 0.0
	var ease_in: float = 0.05
	var ease_out: float = 0.25
	var t: float = 0.0
	var witch: bool = false

var intensity: float = 1.0   ## global screen-effect multiplier (Settings: 0 = off, accessibility)
var _stop_left: float = 0.0
var _stop_scale: float = 1.0
var _slows: Array[SlowMo] = []
var _witch: bool = false
var _real_time: float = 0.0          ## unscaled game seconds (see real_now)
var _stop_starts: Array[float] = []  ## real_now() of recent global hit-stop starts (rate limit)
var _stop_part: float = 1.0          ## hit-stop factor inside the scale written for the next frame
var _frame_scale: float = 1.0        ## scale THIS frame's _process deltas were scaled by (pre-write)
var _frame_stop: float = 1.0         ## hit-stop factor inside _frame_scale


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000  ## run before every other node so real_now() is current for the frame


## Data-driven feel event (see header). Unknown ids are reported once by the FeelDirector.
## `actors` are the nodes a LOCAL row's hit-stop belongs to (the victim of a gunfire kill, the
## attacker and the victim of a melee hit); pass them and the director runs the stop for you.
func play(event: StringName, at: Vector3 = Vector3.INF, strength: float = 1.0,
		actors: Array = []) -> void:
	event_requested.emit(event, at, strength)
	event_with_actors_requested.emit(event, at, strength, actors)


## Freeze (or nearly freeze) the whole game for `seconds` of real time. Longer requests extend the
## current stop (never add). Rate-limited: returns false when the request was dropped.
func hit_stop(seconds: float, scale: float = 0.05) -> bool:
	if seconds <= 0.0:
		return false  # a stop attenuated to nothing must not use up the rate-limit budget
	var now := _real_time
	while not _stop_starts.is_empty() and now - _stop_starts[0] > 1.0:
		_stop_starts.pop_front()
	if _stop_left <= 0.0:
		if _stop_starts.size() >= 3 or (not _stop_starts.is_empty() and now - _stop_starts[-1] < 0.15):
			return false
		_stop_starts.append(now)
	if seconds > _stop_left:
		_stop_left = seconds
		_stop_scale = maxf(scale, MIN_SCALE)
	return true


## Freeze only the given actors (each implements hit_pause(seconds)); the rest of the world runs on.
func local_hit_stop(actors: Array, seconds: float) -> void:
	for a: Variant in actors:
		if a is Node and is_instance_valid(a) and (a as Node).has_method(&"hit_pause"):
			(a as Node).call(&"hit_pause", seconds)


## Slow motion to `scale` for `seconds` real time, easing in/out (seconds). witch=true marks a perfect
## dodge slow-mo (HUD tint, player keeps speed via player_time_comp()).
##
## Requests COMBINE: every one keeps its own clock and the running scale is the minimum of the live
## requests, so a kill's 0.35 s slow-mo no longer cuts the boss death's 1.2 s one short, and a
## non-witch request never ends witch time (witch stays on until its own clock runs out).
## `scale >= 1.0` means "full speed now": it cancels every running request. That is the idiom the
## combat suites already use to clear a slow-mo.
func slow_mo(scale: float, seconds: float, ease_in: float = 0.05, ease_out: float = 0.25,
		witch: bool = false) -> void:
	if scale >= 1.0 or seconds <= 0.0:
		_slows.clear()
		_refresh_witch()
		return
	var req := SlowMo.new()
	req.scale = clampf(scale, MIN_SCALE, 1.0)
	req.left = seconds
	req.ease_in = ease_in
	req.ease_out = ease_out
	req.witch = witch
	_slows.append(req)
	_refresh_witch()


func shake(trauma: float, origin: Vector3 = Vector3.INF) -> void:
	shake_requested.emit(trauma * intensity, origin)


## Continuous shake: the camera keeps its trauma at least `trauma` for `seconds` of real time (a beam, a
## rumble under the boss) — unlike shake(), which adds a decaying impulse.
func shake_floor(trauma: float, seconds: float) -> void:
	shake_floor_requested.emit(clampf(trauma * intensity, 0.0, 1.0), maxf(seconds, 0.0))


func flash(color: Color, duration: float = 0.08) -> void:
	flash_requested.emit(Color(color, color.a * intensity), duration)


func fov_kick(degrees: float, duration: float = 0.25) -> void:
	fov_kick_requested.emit(degrees * intensity, duration)


func post(effect: StringName, strength: float, duration: float) -> void:
	post_requested.emit(effect, strength * intensity, duration)


## The fx unit's RumbleMixer owns the motors (max of envelopes); core only requests.
func rumble(weak: float, strong: float, duration: float) -> void:
	rumble_requested.emit(weak, strong, duration)


## Camera kick (recoil, directional hit) — the camera rig's spring channel implements it.
func kick(degrees: float, world_dir: Vector3 = Vector3.ZERO, duration: float = 0.2) -> void:
	kick_requested.emit(degrees * intensity, world_dir, duration)


func is_witch_time() -> bool:
	return _witch


## Real seconds until the world is back to full speed: the longest live slow-mo request, 0 when none
## is running. Replaces the old single-clock `_slow_left` field, which combining requests cannot keep.
func slow_seconds_left() -> float:
	var longest := 0.0
	for req in _slows:
		longest = maxf(longest, req.left)
	return longest


## Multiplier that brings scaled time back to real time for the player during witch time (Bayonetta:
## the player moves at full speed while the world crawls) — but never through a global hit-stop, which
## freezes the player too (the freeze IS the impact).
func player_time_comp() -> float:
	if not _witch:
		return 1.0
	if Engine.is_in_physics_frame():
		return _stop_part / maxf(Engine.time_scale, MIN_SCALE)
	return _frame_stop / maxf(_frame_scale, MIN_SCALE)


## Real seconds that elapsed during a tick or frame whose (scaled) delta is `delta`. Physics deltas carry
## the live scale; _process deltas carry the scale of the frame's start, which this node rewrites first
## thing every frame — so a _process caller must divide by that one, not the new one.
func real_delta(delta: float) -> float:
	var scale := Engine.time_scale if Engine.is_in_physics_frame() else _frame_scale
	return delta / maxf(scale, MIN_SCALE)


func locomotion_delta(delta: float) -> float:
	return real_delta(delta)


func player_delta(delta: float) -> float:
	return delta * player_time_comp()


## Unscaled game clock in seconds: the sum of every frame's delta with the time scale removed. Equals wall
## time in live play, and stays correct under --fixed-fps tests and Movie Maker captures (which a wall
## clock would not), so hit-stops/slow-mos last the same number of frames everywhere.
func real_now() -> float:
	return _real_time


func _process(delta: float) -> void:
	# `delta` was scaled by the time scale this node set last frame: remove it to get real seconds.
	_frame_scale = Engine.time_scale
	_frame_stop = _stop_part
	var real_dt := minf(real_delta(delta), 0.1)
	_real_time += real_dt
	var scale := 1.0
	var stop := 1.0
	if _stop_left > 0.0:
		_stop_left -= real_dt
		stop = _stop_scale
		scale = stop
	if not _slows.is_empty():
		var slow := _advance_slows(real_dt)
		scale = minf(scale, slow)
	var paused := get_tree().paused
	Engine.time_scale = scale if not paused else 1.0
	_stop_part = stop if not paused else 1.0


## Ages every live request, drops the finished ones and returns the slowest scale still running.
func _advance_slows(real_dt: float) -> float:
	var slow := 1.0
	var i := _slows.size() - 1
	while i >= 0:
		var req := _slows[i]
		req.t += real_dt
		req.left -= real_dt
		if req.left <= 0.0:
			_slows.remove_at(i)
		else:
			slow = minf(slow, _slow_curve(req))
		i -= 1
	_refresh_witch()
	return slow


## Witch time is on while ANY live request asks for it: a kill's plain slow-mo must not end the
## player's perfect-dodge window early.
func _refresh_witch() -> void:
	var on := false
	for req in _slows:
		if req.witch:
			on = true
			break
	if on != _witch:
		_witch = on
		witch_time_changed.emit(on)


func _slow_curve(req: SlowMo) -> float:
	var k := 1.0
	if req.ease_in > 0.0 and req.t < req.ease_in:
		k = req.t / req.ease_in
	elif req.ease_out > 0.0 and req.left < req.ease_out:
		k = maxf(req.left, 0.0) / req.ease_out
	return lerpf(1.0, req.scale, clampf(k, 0.0, 1.0))
