class_name HudMenuScreen
extends Control
## One menu page (brief §9). Every page in the game — title, pause, settings, controls, game over,
## victory, credits, licences — is this control with a different row list, so keyboard and pad
## navigation, the selection brackets and the value editing are written once and tested once.
##
## Row kinds: ACTION (press), TOGGLE, SLIDER, CHOICE, INFO (not selectable).
##
## Long pages scroll (hud r6 item 4): the credits and the licences run past a 1920×1080 canvas, so a
## page whose rows do not fit becomes a scrolling list where the cursor walks EVERY row and the window
## follows it. A value too wide for its column wraps onto its own lines under the label instead of
## being cut — nothing on any page is ever clipped.

enum Kind { ACTION, TOGGLE, SLIDER, CHOICE, INFO }

const ROW_H := 34.0            ## default row pitch; long tables (the controls page) override it
const LIST_WIDTH := 560.0
const PAD := HudMenuRow.PAD
const HEAD_TOP := 68.0         ## px from the top to the heading baseline on a scrolling page
const HEAD_GAP := 54.0         ## px between the heading rule and the first row on a scrolling page
const FOOTER_H := 62.0         ## px the footer hint keeps at the bottom

signal chosen(id: StringName)
signal value_changed(id: StringName, value: Variant)

var page_title: String = ""
var subtitle: String = ""
var rows: Array[Dictionary] = []
var index: int = 0
var glyphs: HudGlyphs = null
## False on the title until the player presses anything. A Control caches its draw commands, so the
## setter has to invalidate or the "PRESS ANY KEY" frame would stay on screen.
var revealed: bool = true:
	set(v):
		if revealed != v:
			revealed = v
			queue_redraw()
var row_h: float = ROW_H        ## px per row; a long table needs a tighter pitch than an action list
var heading_size: int = HudPalette.SIZE_HUGE   ## the title screen wants a logo, not a caption
## Wide tables (controls, credits) widen the list; every value column is laid out from it, so a page
## never has to know the default width.
var list_width: float = LIST_WIDTH
## Share of the list the value column gets. Credits values (author lists) need more than the default.
var value_ratio: float = 0.45
## Let a value that does not fit its column wrap under the label instead of being cut (item 4a).
var wrap_values: bool = false
## A licence page is thousands of lines tall, so up/down PAGES it by one window (minus
## `page_overlap` rows, so no line is ever scrolled past unseen) instead of stepping one row. Left and
## right stay the line-by-line scroll either way.
var page_scroll: bool = false
var page_overlap: int = 3
## Rows the list is scrolled down by, in px. Owned by `move` / `adjust`; read by the draw.
var scroll: float = 0.0
## Test seam (hud r6 item 4): the suite measures a page on the shipping 1920x1080 canvas whatever
## window the headless host hands it. ZERO means "use the real viewport".
var canvas_override: Vector2 = Vector2.ZERO

var _heights: PackedFloat32Array = PackedFloat32Array()
var _tops: PackedFloat32Array = PackedFloat32Array()
var _total: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyphs = HudGlyphs.new()
	visible = false


## The only animated thing on a menu page is the title's "PRESS ANY KEY" pulse; static pages cost
## nothing because a hidden or revealed page skips the redraw.
func _process(_delta: float) -> void:
	if visible and not revealed:
		queue_redraw()


## Replaces the row list and puts the cursor on the first selectable row.
func set_rows(list: Array[Dictionary], title: String = "", sub: String = "") -> void:
	rows = list
	page_title = title
	subtitle = sub
	index = 0
	scroll = 0.0
	_layout()
	if not scrollable() and not _selectable(index):
		move(1)
	queue_redraw()


func row() -> Dictionary:
	return rows[index] if index >= 0 and index < rows.size() else {}


func _selectable(i: int) -> bool:
	return i >= 0 and i < rows.size() and int(rows[i].get("kind", Kind.INFO)) != Kind.INFO


# --- layout ---------------------------------------------------------------------------------------

## Row heights and tops. Recomputed on demand: a page redraws only when something changed, and the
## measurement is a few dozen `get_string_size` calls.
func _layout() -> void:
	_heights = PackedFloat32Array()
	_tops = PackedFloat32Array()
	_total = 0.0
	for r in rows:
		_tops.append(_total)
		var h := row_h
		if wrap_values:
			h += float(_wrapped(r).size()) * HudMenuRow.VALUE_LINE
		_heights.append(h)
		_total += h


## Does the list run past the window? Then the page scrolls and the cursor walks every row.
func scrollable() -> bool:
	_layout()
	return _overflows()


## The plain comparison, with no layout call, so `_list_top` and `_window_h` can both use it without
## recursing into each other. It measures against the SCROLLING top, which is where the list starts
## once it scrolls — measuring against the centred top would call a list that runs off the canvas
## "fits".
func _overflows() -> bool:
	return _total > screen_size().y - _scroll_top() - FOOTER_H


func _scroll_top() -> float:
	return HEAD_TOP + float(heading_size) + HEAD_GAP


func _window_h() -> float:
	return maxf(screen_size().y - _list_top() - FOOTER_H, row_h)


func _list_top() -> float:
	return _scroll_top() if _overflows() else screen_size().y * 0.5 - _total * 0.5 + 40.0


## The list's top-left, in canvas pixels. `scroll` is already applied by the caller that draws rows.
func list_origin() -> Vector2:
	return Vector2((screen_size().x - list_width) * 0.5, _list_top())


func row_height(i: int) -> float:
	_layout()
	return _heights[i] if i >= 0 and i < _heights.size() else row_h


## Keeps the cursor row inside the window, and the scroll inside the list.
func _ensure_visible() -> void:
	_layout()
	if not scrollable():
		scroll = 0.0
		return
	var win := _window_h()
	var top := _tops[index]
	scroll = clampf(scroll, top - win + _heights[index], top)
	scroll = clampf(scroll, 0.0, maxf(_total - win, 0.0))


## Right-aligned width of the value column: the rest of the list belongs to the label.
func value_width() -> float:
	return (list_width - PAD * 2.0) * value_ratio


## The value's own width, measured with the font and size the draw uses (item 4's gate measures this).
func value_px(r: Dictionary) -> float:
	var txt := String(r.get("value", "")) if int(r.get("kind", Kind.INFO)) != Kind.ACTION else ""
	if txt == "":
		return 0.0
	return HudPalette.font_or(get_theme_default_font()).get_string_size(
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, HudPalette.SIZE_BODY).x


## The value split to the full list width, or empty when it fits its column as it is.
func _wrapped(r: Dictionary) -> PackedStringArray:
	if not wrap_values or value_px(r) <= value_width():
		return PackedStringArray()
	var f := HudPalette.font_or(get_theme_default_font())
	var limit := list_width - PAD * 2.0
	var out := PackedStringArray()
	var line := ""
	for word in String(r.get("value", "")).split(" ", false):
		var next := word if line == "" else line + " " + word
		if line != "" and f.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				HudPalette.SIZE_BODY).x > limit:
			out.append(line)
			line = word
		else:
			line = next
	if line != "":
		out.append(line)
	return out

# --- navigation -----------------------------------------------------------------------------------

## Moves the cursor by `step`, wrapping and skipping INFO rows. On a scrolling page the cursor walks
## every row instead (so no row is unreachable) and the window follows it.
func move(step: int) -> void:
	if rows.is_empty():
		return
	if scrollable():
		var jump := maxi(int(_window_h() / row_h) - page_overlap, 1) if page_scroll else 1
		index = clampi(index + step * jump, 0, rows.size() - 1)
		_ensure_visible()
		queue_redraw()
		return
	var i := index
	for _n in rows.size():
		i = wrapi(i + step, 0, rows.size())
		if _selectable(i):
			index = i
			queue_redraw()
			return


## Left / right on the selected row: steps a slider, flips a toggle, cycles a choice. On a scrolling
## page it is the fine scroll — one row, whatever the row is.
func adjust(dir: int) -> void:
	if scrollable():
		index = clampi(index + dir, 0, rows.size() - 1)
		_ensure_visible()
		queue_redraw()
		return
	var r := row()
	if r.is_empty():
		return
	var kind := int(r.get("kind", Kind.INFO))
	if kind == Kind.TOGGLE:
		r["value"] = not bool(r["value"])
		value_changed.emit(StringName(r["id"]), r["value"])
		queue_redraw()
	elif kind == Kind.SLIDER:
		var step := float(r.get("step", 0.1))
		var v := clampf(float(r["value"]) + step * float(dir), float(r.get("min", 0.0)), float(r.get("max", 1.0)))
		r["value"] = snappedf(v, step)
		value_changed.emit(StringName(r["id"]), r["value"])
		queue_redraw()
	elif kind == Kind.CHOICE:
		var opts: Array = r.get("options", [])
		if opts.is_empty():
			return
		var i := wrapi(opts.find(r["value"]) + dir, 0, opts.size())
		r["value"] = opts[i]
		value_changed.emit(StringName(r["id"]), r["value"])
		queue_redraw()


## Confirm on the selected row. Sliders and choices also accept, so a pad player can nudge them.
func activate() -> void:
	var r := row()
	if r.is_empty():
		return
	var kind := int(r.get("kind", Kind.INFO))
	if kind == Kind.ACTION:
		chosen.emit(StringName(r["id"]))
	elif kind == Kind.TOGGLE:
		adjust(1)


## Applies an external value (Settings.changed, a live reload) without emitting back.
func sync(id: StringName, value: Variant) -> void:
	for r in rows:
		if StringName(r.get("id", &"")) == id:
			r["value"] = value
			queue_redraw()
			return


func screen_size() -> Vector2:
	if canvas_override.x > 1.0 and canvas_override.y > 1.0:
		return canvas_override
	var r := get_viewport_rect().size
	return r if r.x > 1.0 and r.y > 1.0 else Vector2(1600.0, 900.0)

# --- draw -----------------------------------------------------------------------------------------

func _draw() -> void:
	var s := screen_size()
	draw_rect(Rect2(Vector2.ZERO, s), Color(HudPalette.INK.r, HudPalette.INK.g, HudPalette.INK.b, 0.82), true)
	if not revealed:
		_draw_press_any_key(s)
		return
	_layout()
	var origin := list_origin()
	var scrolling := scrollable()
	var top := origin.y - (scroll if scrolling else 0.0)
	for i in rows.size():
		var y := top + _tops[i]
		if scrolling and (y + _heights[i] < origin.y or y > origin.y + _window_h()):
			continue
		draw_row(rows[i], Rect2(Vector2(origin.x, y), Vector2(list_width, _heights[i])), i == index)
	if scrolling:
		_mask(s, origin.y, origin.y + _window_h())
	_draw_heading(s)
	_draw_footer(s)


## The one row draw, so a page that is body text rather than a two-column table (the licences) can
## override it. `HudMenuRow` owns the pixels.
func draw_row(r: Dictionary, box: Rect2, selected: bool) -> void:
	HudMenuRow.draw(self, HudPalette.font_or(get_theme_default_font()), r, box, selected, row_h,
			value_width(), _wrapped(r))


## A scrolling list draws its rows first and then paints the page's own ink back over everything
## outside the window, so a half-scrolled row can never sit on the heading or the footer hint.
func _mask(s: Vector2, top: float, bottom: float) -> void:
	var ink := Color(HudPalette.INK.r, HudPalette.INK.g, HudPalette.INK.b, 0.82)
	draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, maxf(top, 0.0))), ink, true)
	draw_rect(Rect2(Vector2(0.0, bottom), Vector2(s.x, maxf(s.y - bottom, 0.0))), ink, true)


## Title state before the player has touched anything (brief §9 "Press any key").
func _draw_press_any_key(s: Vector2) -> void:
	var f := HudPalette.font_or(get_theme_default_font())
	var txt := "按任意键  PRESS ANY KEY"
	var pulse := 0.45 + 0.55 * (0.5 + 0.5 * sin(Feel.real_now() * 3.0))
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, HudPalette.SIZE_HEAD).x
	draw_string(f, Vector2((s.x - w) * 0.5, s.y * 0.5 + 30.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			HudPalette.SIZE_HEAD, Color(HudPalette.WHITE.r, HudPalette.WHITE.g, HudPalette.WHITE.b, pulse))


func _draw_heading(s: Vector2) -> void:
	var f := HudPalette.font_or(get_theme_default_font())
	var y := HEAD_TOP if _overflows() else _list_top() - 30.0 - float(heading_size)
	var w := f.get_string_size(page_title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, heading_size).x
	var at := Vector2((s.x - w) * 0.5, y)
	draw_string(f, at, page_title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, heading_size, HudPalette.CYAN)
	draw_line(Vector2(at.x, y + 12.0), Vector2(at.x + w, y + 12.0), HudPalette.CYAN_DIM, 1.0)
	if subtitle != "":
		var sw := f.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1.0, HudPalette.SIZE_BODY).x
		draw_string(f, Vector2((s.x - sw) * 0.5, y + 36.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				HudPalette.SIZE_BODY, HudPalette.TEXT_DIM)


## The hint names the keys that really navigate (mech-move r7): W / S are `move_forward` / `move_back`,
## not `ui_up` / `ui_down`, so on a page that pauses the tree they would move the mech instead.
func footer_hint() -> String:
	if scrollable():
		return "↑ ↓ 或 LS 滚动      ← → 微调      ENTER / A 确认      ESC / B 返回"
	return "↑ ↓ 或 LS 选择      ENTER / A 确认      ESC / B 返回      ← → 调整"


func _draw_footer(s: Vector2) -> void:
	var f := HudPalette.font_or(get_theme_default_font())
	var hint := footer_hint()
	var w := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, HudPalette.SIZE_SMALL).x
	draw_string(f, Vector2((s.x - w) * 0.5, s.y - 48.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			HudPalette.SIZE_SMALL, HudPalette.TEXT_DIM)
