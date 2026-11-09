class_name HudMenuRow
extends RefCounted
## Drawing one menu row (brief §9), out of `HudMenuScreen` so that file stays the page — its layout,
## its scrolling and its navigation — and this one stays the pixels.
##
## Two rules the r6 round added:
##   * a value that does not fit its column WRAPS onto its own lines under the label. Nothing on any
##     page is ever cut (`credits-text-clipped-and-header`);
##   * a section caption is cyan small caps over a hairline rule, so a long table (controls, credits)
##     reads as blocks instead of one flat wall of rows.

const PAD := 10.0
const VALUE_LINE := 22.0        ## px per wrapped value line


## `box` is the row's whole rect; `row_h` is the pitch the first baseline sits on, so a wrapped row's
## extra lines land under the label rather than under the middle of the box.
static func draw(ci: CanvasItem, f: Font, r: Dictionary, box: Rect2, selected: bool, row_h: float,
		value_w: float, wrapped: PackedStringArray) -> void:
	var kind := int(r.get("kind", HudMenuScreen.Kind.INFO))
	if bool(r.get("header", false)):
		_section(ci, f, r, box, row_h)
		return
	var col := HudPalette.WHITE if kind != HudMenuScreen.Kind.INFO else HudPalette.TEXT_DIM
	if selected:
		ci.draw_rect(box, Color(HudPalette.CYAN.r, HudPalette.CYAN.g, HudPalette.CYAN.b, 0.10), true)
		HudPalette.draw_brackets(ci, box, HudPalette.CYAN, 10.0, 1.5)
	var baseline := box.position.y + row_h * 0.68
	ci.draw_string(f, Vector2(box.position.x + PAD, baseline), String(r.get("label", "")),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, HudPalette.SIZE_BODY, col)
	_value(ci, f, r, box, baseline, col, value_w, wrapped)


static func _section(ci: CanvasItem, f: Font, r: Dictionary, box: Rect2, row_h: float) -> void:
	var label := String(r.get("label", ""))
	var baseline := box.position.y + row_h * 0.72
	ci.draw_string(f, Vector2(box.position.x + PAD, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			HudPalette.SIZE_SMALL, HudPalette.CYAN)
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, HudPalette.SIZE_SMALL).x
	ci.draw_line(Vector2(box.position.x + PAD + w + 10.0, baseline - 5.0),
			Vector2(box.end.x - PAD, baseline - 5.0), HudPalette.CYAN_DIM, 1.0)


static func _value(ci: CanvasItem, f: Font, r: Dictionary, box: Rect2, baseline: float, col: Color,
		value_w: float, wrapped: PackedStringArray) -> void:
	if not wrapped.is_empty():
		for i in wrapped.size():
			ci.draw_string(f, Vector2(box.position.x + PAD, baseline + float(i + 1) * VALUE_LINE),
					wrapped[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, HudPalette.SIZE_BODY, HudPalette.CYAN)
		return
	var kind := int(r.get("kind", HudMenuScreen.Kind.INFO))
	var right := box.end.x - PAD
	match kind:
		HudMenuScreen.Kind.TOGGLE:
			var on := bool(r["value"])
			ci.draw_string(f, Vector2(right - 34.0, baseline), "ON" if on else "OFF",
					HORIZONTAL_ALIGNMENT_RIGHT, 34.0, HudPalette.SIZE_SMALL,
					HudPalette.CYAN if on else HudPalette.TEXT_DIM)
			var t := Rect2(Vector2(right - 34.0 - 12.0 - 54.0, baseline - 12.0), Vector2(54.0, 14.0))
			HudPalette.draw_bar(ci, t, 1.0 if on else 0.0, HudPalette.CYAN if on else HudPalette.TRACK)
		HudMenuScreen.Kind.SLIDER:
			var lo := float(r.get("min", 0.0))
			var hi := float(r.get("max", 1.0))
			var bar := Rect2(Vector2(right - 220.0, baseline - 9.0), Vector2(180.0, 6.0))
			HudPalette.draw_bar(ci, bar, inverse_lerp(lo, hi, float(r["value"])), HudPalette.CYAN)
			ci.draw_string(f, Vector2(right - 36.0, baseline), format_value(r),
					HORIZONTAL_ALIGNMENT_RIGHT, 36.0, HudPalette.SIZE_SMALL, col)
		_:
			var txt := String(r.get("value", "")) if kind != HudMenuScreen.Kind.ACTION else ""
			if txt != "":
				ci.draw_string(f, Vector2(right - value_w, baseline), txt, HORIZONTAL_ALIGNMENT_RIGHT,
						value_w, HudPalette.SIZE_BODY, HudPalette.CYAN)


static func format_value(r: Dictionary) -> String:
	var v := float(r["value"])
	match String(r.get("unit", "")):
		"%": return "%d%%" % int(round(v * 100.0))
		"db": return "%+.0f" % v
		"deg": return "%d°" % int(round(v))
	return "%.2f" % v
