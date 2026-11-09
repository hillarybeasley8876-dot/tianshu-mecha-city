class_name HudLicencesPage
extends HudMenuScreen
## 开源许可 LICENCES (hud r6 item 3): the full third-party notice, on screen, reachable from the
## credits on the title, on pause and from the victory page.
##
## It is a `HudMenuScreen` with one row per laid-out line, so the cursor, the scrolling and the pad
## navigation are the ones every other page uses — a licence page thousands of lines tall is not the
## place for a second input scheme. The text itself is composed by `HudLicences`, which the headless
## writer in `ui/licenses/` also reads, so this page and `build/THIRD_PARTY_LICENSES.txt` can never
## say different things.

## A licence line is body text, not a menu row: tighter pitch and one size down from the action pages.
const LINE_H := 19.0
const PAGE_WIDTH := 1500.0
## Rows two consecutive pages share, so no line is ever scrolled past unseen.
const PAGE_OVERLAP := 3


func _ready() -> void:
	super()
	row_h = LINE_H
	list_width = PAGE_WIDTH
	heading_size = HudPalette.SIZE_HEAD
	page_scroll = true
	page_overlap = PAGE_OVERLAP


## Composes the notice and lays it out. Called by `HudMenuRoot` when the page is built, and by the
## suite; the text is not read per frame.
func build(title: String = "开源许可  LICENCES", sub: String = "") -> void:
	set_rows(_lines(), title, sub if sub != "" else HudLicences.HEADER)


## One row per line: `header` rows are the section captions, the rest are body text. Lines longer than
## the column are wrapped here, with the font the draw uses, so nothing is ever cut off the right edge.
func _lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := HudPalette.font_or(get_theme_default_font())
	var limit := list_width - PAD * 2.0
	for section: Dictionary in HudLicences.new().sections():
		out.append({"id": String(section["title"]), "label": String(section["title"]),
				"kind": Kind.INFO, "value": "", "header": true})
		for raw in section["lines"] as PackedStringArray:
			for line in _wrap(f, String(raw), limit):
				out.append({"id": line, "label": line, "kind": Kind.INFO, "value": ""})
	out.append({"id": "back", "label": "返回  BACK", "kind": Kind.ACTION})
	return out


## Greedy word wrap; a single word longer than the column (a URL, a path) is left whole rather than
## broken, because a broken licence URL is worse than a slightly wide line.
func _wrap(f: Font, text: String, limit: float) -> PackedStringArray:
	if text == "" or f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			HudPalette.SIZE_SMALL).x <= limit:
		return PackedStringArray([text])
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var next := word if line == "" else line + " " + word
		if line != "" and f.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				HudPalette.SIZE_SMALL).x > limit:
			out.append(line)
			line = word
		else:
			line = next
	if line != "":
		out.append(line)
	return out


## Body text, not a two-column row: the label IS the line, drawn at body size across the full width.
func draw_row(r: Dictionary, box: Rect2, selected: bool) -> void:
	if bool(r.get("header", false)):
		super(r, box, selected)
		return
	var f := HudPalette.font_or(get_theme_default_font())
	if selected:
		draw_rect(box, Color(HudPalette.CYAN.r, HudPalette.CYAN.g, HudPalette.CYAN.b, 0.08), true)
		draw_line(Vector2(box.position.x + 1.0, box.position.y + 2.0),
				Vector2(box.position.x + 1.0, box.end.y - 2.0), HudPalette.CYAN_DIM, 2.0)
	var label := String(r.get("label", ""))
	var action := int(r.get("kind", Kind.INFO)) == Kind.ACTION
	draw_string(f, Vector2(box.position.x + PAD, box.position.y + row_h * 0.72), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			HudPalette.SIZE_BODY if action else HudPalette.SIZE_SMALL,
			HudPalette.WHITE if action else HudPalette.TEXT_DIM)
