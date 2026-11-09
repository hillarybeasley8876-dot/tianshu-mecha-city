class_name ScreenFx
extends CanvasLayer
## Full-screen post stack (feel unit). One CanvasLayer on layer 50 (under the HUD) with a single
## full-rect ColorRect running fx/screen_fx/post.gdshader over SCREEN_TEXTURE.
##
## Driven by core signals: Feel.flash_requested, Feel.post_requested, Feel.witch_time_changed. Gameplay
## code that needs an effect to *hold* (speed lines while boosting, radial blur during assault boost)
## calls sustain(effect, strength) every frame and sustain(effect, 0.0) to release.
##
## Everything runs on real time (process_mode ALWAYS + Feel.real_now()), so effects finish on
## schedule during hit-stop and slow-mo. Feel.intensity (Settings "screen shake") scales the result.

const POST := preload("res://fx/screen_fx/post.gdshader")
## WCAG 2.3.1 allows 3 flashes/s; full-screen flashes always exceed the area limit, so we cap at 2.
const FLASH_MIN_INTERVAL := 0.5
## A full-screen wash blows out the frame (juice-impact rule 12). Only the B/W impact frame may go
## further, and it is its own channel.
const FLASH_MAX_ALPHA := 0.25
## Settings "photosensitive": no B/W frames at all, flashes never above 0.1 alpha and never more
## than one per second (CONTRACTS §2 accessibility keys).
const PHOTO_FLASH_ALPHA := 0.1
const PHOTO_FLASH_INTERVAL := 1.0
const IMPACT_HARD := 0.55   ## impact_bw above this uses the hard threshold instead of a grey frame
## Radial blur is an edge effect: the shader masks it to 0 at the centre, and the edge value is capped.
const RADIAL_MAX := 0.04
## Speed lines: none below SPEED_MIN m/s, full at SPEED_FULL m/s (FEEL.md "speed lines on" at boost).
const SPEED_MIN := 40.0
const SPEED_FULL := 110.0
## Per-channel accessibility sliders (Settings keys, all 0..1).
const SLIDERS: Dictionary = {
	&"chromatic": &"fx_chromatic",
	&"radial_blur": &"fx_radial_blur",
	&"speedlines": &"fx_speed_lines",
	&"impact_bw": &"fx_flash",
}

@export var enabled: bool = true

var _rect: ColorRect
var _mat: ShaderMaterial
var _level: Dictionary = {}     ## effect -> Vector3(strength, seconds left, seconds total)
var _sustain: Dictionary = {}   ## effect -> strength held by gameplay code
var _flash_a: float = 0.0
var _flash_left: float = 0.0
var _flash_total: float = 0.001
var _flash_color: Color = Color.WHITE
var _last_flash_t: float = -1000.0
var _witch: float = 0.0
var _speed: float = 0.0
var _speed_held: bool = false   ## set_speed() was called this frame (no player to read from)
var _now: float = 0.0
var _last_real: float = 0.0
## Accepted full-screen flashes (rate limiter drops the rest) - tests and telemetry read this.
var flashes: int = 0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "Post"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = POST
	_rect.material = _mat
	add_child(_rect)
	visible = false
	_last_real = Feel.real_now()
	Feel.flash_requested.connect(_on_flash)
	Feel.post_requested.connect(_on_post)
	Feel.witch_time_changed.connect(_on_witch)
	Settings.changed.connect(_on_setting)


## Hold a screen effect at `strength` until sustain(effect, 0.0). Used for boost speed lines etc.
func sustain(effect: StringName, strength: float) -> void:
	if strength <= 0.0:
		_sustain.erase(_key(effect))
	else:
		_sustain[_key(effect)] = clampf(strength, 0.0, 1.0)


## Colour of the vignette channel for the next pulse (overdrive_ignite's rim is gold #F2C14E, a
## damage vignette is blood red). The director calls this just before Feel.post(&"vignette", ...).
func set_vignette_color(color: Color) -> void:
	_mat.set_shader_parameter(&"vignette_color", color)


## Player speed in m/s. Read from Game.player every frame, so speed lines follow the mech without
## the locomotion unit having to push anything (r2 review); set_speed() overrides it for one frame.
func _player_speed() -> float:
	var p := Game.player
	if p == null:
		return 0.0
	var v: Variant = p.get(&"velocity")
	return (v as Vector3).length() if v is Vector3 else 0.0


## Override the speed-line driver for this frame (tests and the gallery have no player node).
func set_speed(mps: float) -> void:
	_speed = clampf((mps - SPEED_MIN) / (SPEED_FULL - SPEED_MIN), 0.0, 1.0)
	_speed_held = true


## Accessibility slider (Settings "fx_chromatic" etc.) for a channel, 0..1.
func slider(key: StringName) -> float:
	if not SLIDERS.has(key):
		return 1.0
	var v: Variant = Settings.get_value(SLIDERS[key])
	return clampf(float(v) if v is float or v is int else 1.0, 0.0, 1.0)


## True when the photosensitive accessibility mode is on (Settings key of the same name).
func photosensitive() -> bool:
	return bool(Settings.get_value(&"photosensitive"))


func is_idle() -> bool:
	return _flash_left <= 0.0 and _level.is_empty() and _sustain.is_empty() and _witch <= 0.001 \
			and _speed <= 0.001


## Current strength of a post channel (after the sliders, Feel.intensity and the per-channel clamps).
## Tests and telemetry read this; gameplay code sets channels through Feel.post / sustain.
func channel(effect: StringName) -> float:
	var key := _key(effect)
	if key == &"radial_blur":
		return minf(_scaled(key) * Feel.intensity, RADIAL_MAX)
	if key == &"speedlines":
		return maxf(_scaled(key), _speed) * Feel.intensity
	if key == &"impact_bw":
		return 0.0 if photosensitive() else _scaled(key) * Feel.intensity
	return _scaled(key) * Feel.intensity


## Alpha the flash is blended at this frame (capped by FLASH_MAX_ALPHA, and by PHOTO_FLASH_ALPHA in
## photosensitive mode).
func flash_alpha() -> float:
	if _flash_left <= 0.0:
		return 0.0
	return minf(_flash_a * pow(_flash_left / _flash_total, 2.0), _flash_cap())


func _flash_cap() -> float:
	return minf(FLASH_MAX_ALPHA * slider(&"impact_bw"), PHOTO_FLASH_ALPHA) if photosensitive() \
			else FLASH_MAX_ALPHA * slider(&"impact_bw")


func _process(_delta: float) -> void:
	# Game clock, not the wall clock: a movie frame costs ~70 ms of wall time but 1/60 s of game time,
	# and a wall-clock dt would eat a 1-2 frame flash before it is ever drawn. Feel already clamps its
	# own step to 0.1 s; clamp ours too so a hitch cannot wipe a whole pulse.
	var now := Feel.real_now()
	var dt := minf(maxf(now - _last_real, 0.0), 0.1)
	_last_real = now
	_now += dt
	if not _speed_held:
		set_speed(_player_speed())
	_speed_held = false
	# Draw this frame's state first, then age it: a pulse requested during a physics tick gets its
	# full N frames on screen instead of N-1 (finding: 1-frame flashes were never drawn at all).
	_apply()
	visible = enabled and not is_idle()
	_advance(dt)


func _advance(dt: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - dt, 0.0)
	for key: StringName in _level.keys():
		var e: Vector3 = _level[key]
		e.y = maxf(e.y - dt, 0.0)
		if e.y <= 0.0:
			_level.erase(key)
		else:
			_level[key] = e
	var want := 1.0 if Feel.is_witch_time() else 0.0
	_witch = move_toward(_witch, want, dt / (0.12 if want > _witch else 0.25))


## One uniform write per frame; the shader only runs while something is on.
func _apply() -> void:
	var i := Feel.intensity
	if _flash_left > 0.0:
		var k := _flash_left / _flash_total
		var a := minf(_flash_a * k * k, _flash_cap())
		_mat.set_shader_parameter(&"flash_color", Color(_flash_color, a))
	else:
		_mat.set_shader_parameter(&"flash_color", Color(_flash_color, 0.0))
	_mat.set_shader_parameter(&"chromatic_px", channel(&"chromatic"))
	_mat.set_shader_parameter(&"radial", channel(&"radial_blur"))
	_mat.set_shader_parameter(&"vignette", channel(&"vignette"))
	_mat.set_shader_parameter(&"speed_lines", channel(&"speed_lines"))
	_mat.set_shader_parameter(&"desaturate", channel(&"desaturate"))
	var bw := channel(&"impact_bw")
	_mat.set_shader_parameter(&"impact_bw", maxf(bw, IMPACT_HARD) if bw > 0.5 else bw)
	_mat.set_shader_parameter(&"witch", _witch * i)
	_mat.set_shader_parameter(&"time_offset", _now)


## Channel strength after its accessibility slider (photosensitive mode kills the B/W frame).
func _scaled(key: StringName) -> float:
	return _value(key) * slider(key)


## Current strength of a channel: max of the timed envelope and the held value.
func _value(effect: StringName) -> float:
	var v := float(_sustain.get(effect, 0.0))
	if _level.has(effect):
		var e: Vector3 = _level[effect]
		v = maxf(v, e.x * clampf(e.y / maxf(e.z, 0.001), 0.0, 1.0))
	return v


func _on_flash(color: Color, duration: float) -> void:
	if not enabled or color.a <= 0.0 or duration <= 0.0:
		return
	var now := Feel.real_now()
	var photo := photosensitive()
	var interval := PHOTO_FLASH_INTERVAL if photo else FLASH_MIN_INTERVAL
	if now - _last_flash_t < interval:
		return
	_last_flash_t = now
	_flash_color = Color(color, 1.0)
	_flash_a = minf(color.a, PHOTO_FLASH_ALPHA / maxf(FLASH_MAX_ALPHA, 0.001)) if photo \
			else color.a
	_flash_total = maxf(duration, 0.001)
	_flash_left = _flash_total
	flashes += 1


func _on_post(effect: StringName, strength: float, duration: float) -> void:
	if not enabled or strength <= 0.0:
		return
	var key := _key(effect)
	if key == &"impact_bw" and photosensitive():
		return
	# A new pulse only replaces the running one when it is stronger, so a finisher's impact frame is
	# never cut short by a footstep.
	if _level.has(key) and (_level[key] as Vector3).y > 0.0 and (_level[key] as Vector3).x > strength:
		return
	_level[key] = Vector3(strength, maxf(duration, 0.001), maxf(duration, 0.001))


func _on_witch(active: bool) -> void:
	if active:
		_on_post(&"desaturate", 0.55, 0.4)


func _on_setting(key: StringName) -> void:
	if key == &"screen_shake" and Feel.intensity <= 0.0:
		_level.clear()
		_sustain.clear()
		_flash_left = 0.0


## Feel.post ids (core) -> shader channel names.
func _key(effect: StringName) -> StringName:
	match effect:
		&"speed_lines", &"speedlines":
			return &"speedlines"
		&"radial_blur", &"radial":
			return &"radial_blur"
		&"chroma", &"chromatic":
			return &"chromatic"
		&"impact_frame", &"impact_bw":
			return &"impact_bw"
	return effect
