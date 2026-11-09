class_name HudWidget
extends Control
## Base for every HUD element: a full-rect Control that pulls its numbers from `HudData` once per
## frame and redraws itself. Widgets never talk to gameplay directly, and they never draw when the
## state they need is absent — that is how the HUD survives units landing at different times
## (brief §1).

var data: HudData = null
var suppressed: bool = false      ## set by hud.gd when the canopy HUD takes over (brief §7)
## Attention (look review item 9): with every widget at 100 % all the time the eye had nowhere to land,
## and the one urgent thing — an unblockable windup — was just another element in the noise. A widget
## sits at full strength while anything in `watch_keys` is changing or while `urgent()` is true, and
## `AWAKE_HOLD` seconds after the last change it settles back to `rest_alpha`, which `hud.gd` sets.
var rest_alpha: float = 1.0
var watch_keys: PackedStringArray = PackedStringArray()

const AWAKE_HOLD := 3.0           ## s of quiet before a widget is allowed to settle
const FADE := 0.25                ## s the settle takes

var _theme_font: Font = null
var _clock_prev: float = -1.0     ## last frame's Feel.real_now(), see _process
var _awake: float = AWAKE_HOLD
var _watch_hash: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_theme_font = get_theme_default_font()


## UI timing runs on Feel's unscaled clock (CONTRACTS §3): the frame delta this node sees carries the
## time scale, so in a hit-stop every HUD pop, flash and lifetime would freeze and in slow-mo it would
## crawl while the real-time camera kept moving (audit #3). `Feel.real_now()` is read, not
## `Feel.real_delta(delta)`, which inside _process can return the wrong frame's scale.
func _process(delta: float) -> void:
	if data == null:
		return
	var now := Feel.real_now()
	if _clock_prev < 0.0:
		_clock_prev = now
	var dt := delta if world_clock() else clampf(now - _clock_prev, 0.0, 0.1)
	_clock_prev = now
	update_hud(dt)
	if suppressed:
		visible = false
	_tick_attention(dt)
	if visible:
		queue_redraw()


## Drives `modulate.a` between 1.0 and `rest_alpha` (look review item 9). A widget that watches nothing
## is one the player is looking at by definition (reticle, markers), so it never fades.
func _tick_attention(dt: float) -> void:
	if suppressed or not visible or watch_keys.is_empty():
		modulate.a = move_toward(modulate.a, 1.0, dt / FADE)
		return
	var h := _state_hash()
	if h != _watch_hash:
		_watch_hash = h
		_awake = AWAKE_HOLD
	else:
		_awake = maxf(_awake - dt, 0.0)
	var target := 1.0 if (_awake > 0.0 or urgent()) else rest_alpha
	modulate.a = move_toward(modulate.a, target, dt / FADE)


## The widget's watched values, hashed, so any change pops the widget back to full strength.
func _state_hash() -> int:
	var parts := PackedStringArray()
	for k in watch_keys:
		parts.append("%s=%s" % [k, data.state.get(k)])
	return hash("|".join(parts))


## Override to keep a widget bright whatever its numbers are doing (low armour, empty magazine).
func urgent() -> bool:
	return false


## The screen area this widget's chrome owns, so world-anchored readouts can be kept off it
## (look review item 10.4). Empty means the widget lays no claim on the frame.
func chrome_rect() -> Rect2:
	return Rect2()


## Widgets whose progress belongs to the game world rather than to the UI (windups, lock timers)
## override this: their timings must slow down with everything else.
func world_clock() -> bool:
	return false


## Read `data.state` and set `visible` / cached values. Overridden by every widget.
func update_hud(_delta: float) -> void:
	pass


## Hide unless the snapshot carries every one of `keys` (brief §1: missing key = hide the widget).
func require(keys: PackedStringArray) -> bool:
	if data == null:
		return false
	for k in keys:
		if not data.state.has(k):
			visible = false
			return false
	return true


func font() -> Font:
	if _theme_font == null:
		_theme_font = get_theme_default_font()
	return HudPalette.font_or(_theme_font)


## Text helpers. `outline` defaults ON (look review item 8.1): everything the HUD prints is drawn
## straight over a city that runs from white sky to black shadow. Turn it off only inside a panel.
func text(pos: Vector2, s: String, size: int, col: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0,
		shadow: bool = false, outline: bool = true) -> void:
	HudPalette.draw_text(self, _theme_font, pos, s, size, col, align, width, shadow, outline)


func text_w(s: String, size: int) -> float:
	return HudPalette.text_width(_theme_font, s, size)


## `shadow` is for labels that float over the world with no panel behind them.
func centered(pos: Vector2, s: String, size: int, col: Color, shadow: bool = false,
		outline: bool = true) -> void:
	var at := pos - Vector2(text_w(s, size) * 0.5, 0.0)
	HudPalette.draw_text(self, _theme_font, at, s, size, col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, shadow, outline)


## The rect this widget draws into, in VIRTUAL layout pixels: the viewport's, divided by the HUD scale
## `hud.gd` puts on the root Control. Every geometry constant in the HUD is authored for 1600×900 and
## comes out correct at any window size or `hud_scale` — including inside the canopy SubViewport,
## whose buffer is always 1600×900.
func screen_size() -> Vector2:
	var r := get_viewport_rect().size / maxf(HudPalette.ui_scale, 0.05)
	return r if r.x > 1.0 and r.y > 1.0 else Vector2(1600.0, 900.0)


func screen_center() -> Vector2:
	return screen_size() * 0.5
