extends Node
## Look input (camera-aim): mouse relative motion (unsmoothed, SPEC §5) and the gamepad right stick with
## the SPEC response curve. The rig consumes `take_delta()` (degrees this physics tick) and clamps pitch.
## Aim input runs on REAL time during slow motion (juice-impact §3.4) with a floor on the compensation
## so a 50 ms hit-stop does not fling the view.

const MOUSE_DEG_PER_PX := 0.06      ## at Settings.mouse_sensitivity 1.0 (360° ≈ 6000 px)
const STICK_YAW_DEG_PER_SEC := 300.0 ## SPEC §5: gamepad yaw cap
const STICK_PITCH_DEG_PER_SEC := 180.0
const STICK_CURVE := 2.0            ## SPEC §5: response exponent
const ADS_SCALE := 0.6              ## finer aim while zoomed in
const FLICK_DEG := 15.0             ## mouse flick that switches hard-lock target (brief)
const FLICK_DECAY := 60.0           ## degrees per second the flick accumulator bleeds off

signal flicked(direction: float)    ## hard-lock target switch: flick (+1 right / -1 left)

var enabled: bool = true

var _mouse: Vector2 = Vector2.ZERO
var _using_pad: bool = false        ## last look input came from the stick (soft-lock cone width)
var _stick_flick: float = 0.0       ## seconds the stick has been past the flick threshold
var _flick_accum: float = 0.0       ## signed mouse yaw degrees accumulated towards a flick


func _ready() -> void:
	# The rig may be instanced without a window (headless tests); capturing there is pointless.
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var rel := (event as InputEventMouseMotion).relative
		_mouse += rel
		_using_pad = false
		_accumulate_flick(rel.x)


func _physics_process(delta: float) -> void:
	_flick_accum = move_toward(_flick_accum, 0.0, FLICK_DECAY * Feel.real_delta(delta))


## Degrees to rotate this tick: x = yaw (right positive), y = pitch (down positive).
## `ads` scales the rate down; `speed_scale` is the aim-assist slowdown (0..1, gamepad only).
func take_delta(delta: float, ads: bool, speed_scale: float) -> Vector2:
	if not enabled:
		_mouse = Vector2.ZERO
		return Vector2.ZERO
	var sens := float(Settings.get_value(&"mouse_sensitivity"))
	var out := Vector2.ZERO
	if _mouse != Vector2.ZERO:
		var scale_px := MOUSE_DEG_PER_PX * sens * (ADS_SCALE if ads else 1.0)
		out += _mouse * scale_px
		_mouse = Vector2.ZERO
	var stick := _stick_vector(delta)
	if stick != Vector2.ZERO:
		var stick_sens := float(Settings.get_value(&"stick_sensitivity")) * (ADS_SCALE if ads else 1.0)
		var rate := Vector2(STICK_YAW_DEG_PER_SEC, STICK_PITCH_DEG_PER_SEC) * stick_sens * speed_scale
		# `delta` is already real time: the rig converts with Feel.real_delta before calling in. Converting
		# again divided the stick rate by Engine.time_scale twice (audit #1) — 20x too fast in a hit-stop.
		out += Vector2(stick.x * rate.x, stick.y * rate.y) * delta
	return out


## Consumes accumulated mouse motion without moving the view (cinematics, HUD screens).
func flush() -> void:
	_mouse = Vector2.ZERO


## A deliberate sideways mouse flick (> FLICK_DEG before the accumulator bleeds off) switches target.
func _accumulate_flick(relative_x: float) -> void:
	var sens := float(Settings.get_value(&"mouse_sensitivity"))
	_flick_accum += relative_x * MOUSE_DEG_PER_PX * sens
	if absf(_flick_accum) >= FLICK_DEG:
		flicked.emit(signf(_flick_accum))
		_flick_accum = 0.0


## Curved stick vector (-1..1 per axis). SPEC §5 caps the rates, so there is no extra acceleration.
func _stick_vector(delta: float) -> Vector2:
	var raw := Vector2(
			Input.get_action_strength(&"look_right") - Input.get_action_strength(&"look_left"),
			Input.get_action_strength(&"look_down") - Input.get_action_strength(&"look_up"))
	raw = raw.limit_length(1.0)
	_watch_flick(raw, delta)
	if raw.length() < 0.001:
		return Vector2.ZERO
	_using_pad = true
	return Vector2(_curve(raw.x), _curve(raw.y)) * raw.length()


## The soft-lock cone is wider on a pad (SPEC §5: 7° mouse / 10° pad).
func using_pad() -> bool:
	return _using_pad


## Right-stick flick (target switch): a hard push past 0.8 held under 0.25 s.
func _watch_flick(raw: Vector2, delta: float) -> void:
	if absf(raw.x) < 0.8:
		_stick_flick = 0.0
		return
	_stick_flick += delta
	if _stick_flick <= 0.25:
		flicked.emit(signf(raw.x))
		_stick_flick = 1.0


func _curve(v: float) -> float:
	return signf(v) * pow(absf(v), STICK_CURVE)
