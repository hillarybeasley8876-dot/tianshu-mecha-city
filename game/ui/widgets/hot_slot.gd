class_name HudHotSlot
extends Control
## One hex slot of the skill hotbar (brief §4, skills-catalog §4.9, look review items 8/12). The slot is
## dumb: `hotbar.gd` owns the layout and pushes numbers in, the slot draws a frame, a vector icon, the
## clockwise radial cooldown wipe, the charge pips and the key glyph for the current input device.
##
## A ready slot is a quiet outline, not a lit panel: eight full-strength hexes shouting "ready" gave the
## eye nowhere to land. It brightens for `FLASH_TIME` after it comes up, and stays bright while the
## skill is running.

const R := 18.0                    ## px circumradius of the hex frame (36 px across the corners)
const FLASH_TIME := 1.2            ## s the slot stays lit after it becomes ready (item 12.3)
const ICON_SCALE := 0.75           ## the icons are authored for a 24 px slot
const REST_OUTLINE := 0.55         ## alpha of a ready-but-idle frame

enum Mode { COOLDOWN, MISSILES, GUARD, MELEE }

var id: StringName = &""
var label: String = ""
var action: StringName = &""
var mode: int = Mode.COOLDOWN
var glyph: String = ""
var wipe: float = 0.0              ## 1 = just used, 0 = ready
var charges: int = 1
var charges_max: int = 1
var ready_now: bool = true
var active: bool = false           ## the skill is running right now (well up, fins out, guard held)
var outage: bool = false           ## EN outage: desaturate + red rim (skills-catalog §4.9)
var charge: float = 0.0            ## 0..1 progress for the charged melee slot
var lock_count: int = 0
var flash: float = 0.0             ## s left of the "just came up" highlight


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(R * 2.0, R * 2.0)
	size = custom_minimum_size


func tick(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(flash - delta, 0.0)


## Called by the hotbar on the frame a slot comes back up; starts the highlight.
func signal_ready() -> void:
	flash = FLASH_TIME
	queue_redraw()


func center() -> Vector2:
	return size * 0.5


## Frame colour: cyan when ready, dim while recharging, amber while the skill is running, red rim in
## an EN outage so the player can see the whole bar is unusable at a glance.
func frame_color() -> Color:
	if outage:
		return HudPalette.DANGER
	if active:
		return HudPalette.AMBER
	if not ready_now:
		return HudPalette.CYAN_DIM
	return HudPalette.CYAN


## How loudly a slot is allowed to speak: full while it is running, still bright for a beat after it
## comes up, an outline at `REST_OUTLINE` the rest of the time.
func frame_alpha() -> float:
	if outage or active or not ready_now:
		return 1.0
	if flash > 0.0:
		return lerpf(REST_OUTLINE, 1.0, flash / FLASH_TIME)
	return REST_OUTLINE


func _draw() -> void:
	var c := center()
	var col := frame_color()
	col.a *= frame_alpha()
	var lit := active or flash > 0.0
	if lit or not ready_now:
		HudPalette.draw_hex(self, c, R, HudPalette.panel_fill(0.45), 0.0, true)
	_draw_icon(c, Color(col.r, col.g, col.b, 0.35 if outage else 1.0))
	if wipe > 0.001:
		_draw_wipe(c)
	HudPalette.draw_hex(self, c, R, col, 1.5)
	if flash > 0.0 and HudPalette.motion > 0.0:
		HudPalette.draw_hex(self, c, R, Color(1, 1, 1, flash / FLASH_TIME * 0.45), 0.0, true)
	_draw_pips(c, col)
	if glyph != "":
		_draw_glyph(c)


## The remaining cooldown as a dark pie eaten clockwise from 12 o'clock (dossier §4.9).
func _draw_wipe(c: Vector2) -> void:
	var pts := PackedVector2Array([c])
	var steps := 26
	var sweep := TAU * clampf(wipe, 0.0, 1.0)
	for i in steps + 1:
		var a := -PI * 0.5 + sweep * float(i) / float(steps)
		pts.append(c + Vector2(cos(a), sin(a)) * (R - 1.5))
	draw_colored_polygon(pts, Color(0.043, 0.07, 0.125, 0.78))


## Charge pips along the bottom edge; the missile slot shows its lock count instead.
func _draw_pips(c: Vector2, col: Color) -> void:
	var base := c + Vector2(0.0, R - 5.0)
	if mode == Mode.MISSILES:
		var filled := mini(lock_count, 12)
		for i in 4:
			var on := i * 3 < filled
			draw_circle(base + Vector2(float(i - 1) * 5.0 - 2.0, 0.0), 1.8,
					col if on else HudPalette.TEXT_DIM)
		return
	if mode == Mode.MELEE:
		if charge > 0.01:
			HudPalette.draw_bar(self, Rect2(c + Vector2(-R + 5.0, R - 7.0), Vector2((R - 5.0) * 2.0, 3.0)),
					charge, HudPalette.AMBER)
		return
	for i in charges_max:
		var x := base.x + (float(i) - float(charges_max - 1) * 0.5) * 6.0
		draw_circle(Vector2(x, base.y), 2.0, col if i < charges else HudPalette.TEXT_DIM)


## The key letter sits INSIDE the bottom of the hex, outlined — under it, in dim grey at 14 px, it was
## unreadable over a sunlit street (look review items 8.5 and 12.4).
func _draw_glyph(c: Vector2) -> void:
	var theme_font := get_theme_default_font()
	var w := HudPalette.text_width(theme_font, glyph, HudPalette.SIZE_TINY)
	HudPalette.draw_text(self, theme_font, c + Vector2(-w * 0.5, R - 3.0), glyph,
			HudPalette.SIZE_TINY, HudPalette.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false, true)


## Abstract vector marks, one per kit verb — no bitmaps, so they stay crisp at any HUD scale and cost
## nothing to load. Authored for a 24 px slot and scaled about the centre to fit `R`.
func _draw_icon(c: Vector2, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(ICON_SCALE, ICON_SCALE))
	match id:
		&"guard":
			draw_colored_polygon(PackedVector2Array([Vector2(0, -10), Vector2(9, -5),
					Vector2(7, 8), Vector2(0, 12), Vector2(-7, 8), Vector2(-9, -5)]), col)
		&"rift_step":
			for s: float in [-1.0, 1.0]:
				var x := s * 5.0
				draw_polyline(PackedVector2Array([Vector2(x - s * 4.0, -9.0),
						Vector2(x + s * 4.0, 0.0), Vector2(x - s * 4.0, 9.0)]), col, 2.0)
		&"well":
			draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 24, col, 1.5, true)
			for i in 4:
				var d := Vector2(cos(TAU * float(i) / 4.0), sin(TAU * float(i) / 4.0))
				draw_line(d * 12.0, d * 5.0, col, 1.5)
		&"fins":
			for s: float in [-1.0, 0.0, 1.0]:
				var tip := Vector2(s * 9.0, -11.0)
				draw_colored_polygon(PackedVector2Array([tip, Vector2(s * 3.0 + 2.5, 9.0),
						Vector2(s * 3.0 - 2.5, 9.0)]), col)
		&"missiles":
			for i in 3:
				var x := (float(i) - 1.0) * 7.0
				draw_colored_polygon(PackedVector2Array([Vector2(x, -11.0),
						Vector2(x + 3.0, 4.0), Vector2(x - 3.0, 4.0)]), col)
				draw_line(Vector2(x, 5.0), Vector2(x, 10.0), col, 1.5)
		&"anchor":
			draw_arc(Vector2(0, 4.0), 8.0, deg_to_rad(20.0), deg_to_rad(160.0), 16, col, 2.0, true)
			draw_line(Vector2(0, -11.0), Vector2(0, 8.0), col, 2.0)
			draw_line(Vector2(-5.0, -7.0), Vector2(5.0, -7.0), col, 2.0)
		&"burst":
			for i in 6:
				var d := Vector2(cos(TAU * float(i) / 6.0), sin(TAU * float(i) / 6.0))
				draw_line(d * 4.0, d * 11.0, col, 2.0)
			draw_circle(Vector2.ZERO, 3.0, col)
		&"melee":
			draw_line(Vector2(-8.0, 9.0), Vector2(7.0, -10.0), col, 3.0)
			draw_line(Vector2(-9.0, 4.0), Vector2(-3.0, 10.0), col, 2.0)
		_:
			draw_circle(Vector2.ZERO, 6.0, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
