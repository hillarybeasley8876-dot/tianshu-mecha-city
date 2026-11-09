class_name HudCreditsSuite
extends RefCounted
## The credits and the licences (brief §9, ACCEPTANCE §5, hud r6 items 2/3/4). Every check here is
## about the page being HONEST: naming what the build really ships, labelling every AI family, never
## cutting a string, and shipping the licence texts the .app needs.

const PRESET := "res://export_presets.cfg"
## The shipping canvas (project.godot viewport_width/height) every layout check measures against.
const CANVAS := Vector2(1920.0, 1080.0)


static func run(h: HudTestHarness) -> void:
	var m := h.menus()
	await _credits(m, h)
	await _ai_labels(m, h)
	await _music(m, h)
	await _layout(m, h)
	await _licences(m, h)
	await _export_filter(h)


## ACCEPTANCE §5: the credits page names every audio pack and music track the build ships. It is read
## from the audio unit's own manifest, so a new pack shows up there without anyone editing the HUD.
static func _credits(m: HudMenuRoot, h: HudTestHarness) -> void:
	m.show_page(HudMenuRoot.Page.TITLE)
	var at := HudTestHarness.row_index(m.screen(), "credits")
	h.check(at >= 0, "the title offers a credits entry")
	m.screen().index = at
	h.press(&"ui_accept")
	h.check(m.page == HudMenuRoot.Page.CREDITS, "credits opens from the title")
	for want: String in ["Kenney — Sci-Fi Sounds", "OGA — 100 CC0 SFX",
			"OGA — The Free Firearm Sound Library"]:
		h.check(_label_contains(m.screen(), want), "credits names '%s'" % want)
	for want: String in ["Covert Operations", "Technological Menace", "Epic Combat", "Forgotten Victory"]:
		h.check(_value_contains(m.screen(), want), "credits names the track '%s'" % want)
	h.check(_label_contains(m.screen(), "Poly Haven"), "the CC0 textures are credited")
	h.check(_value_contains(m.screen(), "polyhaven.com"), "the texture row carries its source")
	h.check(_label_contains(m.screen(), "Godot Engine 4.7"), "the engine is credited")
	h.check(_label_contains(m.screen(), "Noto Sans CJK SC"), "the CJK font is credited")
	h.check(_label_contains(m.screen(), "Rajdhani SemiBold"), "the display font is credited")
	h.check(_value_contains(m.screen(), "© 2014-2021 Adobe"), "the Noto copyright line is on the page")
	h.check(_value_contains(m.screen(), "Indian Type Foundry"), "the Rajdhani copyright line is on the page")
	h.check(_value_contains(m.screen(), "SIL OFL 1.1"), "the font licence is named")
	h.check(HudTestHarness.row_index(m.screen(), "licences") >= 0, "credits links to the LICENCES page")
	h.press(&"ui_cancel")
	h.check(m.page == HudMenuRoot.Page.TITLE, "cancel returns to the page that opened credits")


## hud r6 item 2: every family that ships AI content has an AI row, and nothing generated is called
## in-house. The old page credited the Tripo-built city as "Procedural — built in-house".
static func _ai_labels(m: HudMenuRoot, h: HudTestHarness) -> void:
	m.show_page(HudMenuRoot.Page.CREDITS)
	var s := m.screen()
	h.check(_label_contains(s, "AI-GENERATED CONTENT"), "credits carries an AI-generated content section")
	# Read through the script's own constant map: a table that is missing or malformed must produce a
	# readable FAIL, not a crash that hides the rest of the gate.
	var consts: Dictionary = HudCredits.new().get_script().get_script_constant_map()
	var ai_rows: Array = consts.get("AI_ROWS", [])
	var inhouse: Array = consts.get("INHOUSE_ROWS", [])
	for r: Array in ai_rows:
		h.check(r.size() >= 3, "the AI row %s carries a family, a label and a disclosure" % str(r))
		if r.size() < 3:
			continue
		h.check(_label_contains(s, String(r[1])), "AI family '%s' has a row on the page" % String(r[0]))
		h.check(String(r[2]).begins_with("AI-generated"), "AI family '%s' says what made it" % String(r[0]))
	h.check(ai_rows.size() >= 7, "every AI family the build ships has a row (%d)" % ai_rows.size())
	h.check(not inhouse.is_empty(), "the in-house section is declared")
	for r: Array in inhouse:
		h.check(not String(r[1]).contains("Tripo") and not String(r[1]).contains("AI"),
				"the in-house row '%s' claims nothing that was generated" % String(r[0]))
	h.check(_label_contains(s, "CITY BUILDINGS"), "the AI-built city has its own AI row")
	h.check(_label_contains(s, "STREET PROPS"), "the AI-built street props have an AI row")
	h.check(_label_contains(s, "HUSK RIGS & CLIPS"), "the Tripo rigs and clips have an AI row")
	h.check(_label_contains(s, "HERO MECH"), "the AI-generated hero has its own AI row")
	h.check(_label_contains(s, "CONCEPT ART"), "the AI concept images are disclosed")
	h.check(not _value_contains(s, "rigged + textured in-house"),
			"no row calls Tripo content in-house")
	h.check(not _value_contains(s, "Procedural — Blender / Godot, built in-house"),
			"no row calls the AI-generated city in-house")
	h.check(_label_contains(s, "BUILT IN-HOUSE"), "the work that really was ours has its own section")
	h.check(_value_contains(s, "collision, navigation, the Spire"),
			"the in-house section names the procedural city work")
	h.check(_label_contains(s, "VOICE LINES"), "the cockpit AI voice line count is on the page")
	m.show_page(HudMenuRoot.Page.TITLE)


## hud r6 item 4b: the MUSIC header is derived from the licence column. 7 of the 13 music files are
## our own synthesis, so "all CC0 1.0" was false.
static func _music(m: HudMenuRoot, h: HudTestHarness) -> void:
	m.show_page(HudMenuRoot.Page.CREDITS)
	var s := m.screen()
	var data := HudCredits.new()
	var header := ""
	for r in data.rows():
		if String(r.get("label", "")).begins_with("音乐  MUSIC"):
			header = String(r.get("label", ""))
	h.check(header != "", "the page carries a MUSIC header")
	var clips: Array = data.get("music") if "music" in data else []
	var cc0 := 0
	var ours := 0
	for clip: Dictionary in clips:
		if String(clip["licence"]) == "ours":
			ours += 1
		else:
			cc0 += 1
	h.check(header.contains("%d files" % clips.size()),
			"the MUSIC header counts every music file (%d)" % clips.size())
	h.check(header.contains("%d %s" % [cc0, HudCredits.LICENCE]),
			"the MUSIC header counts the CC0 tracks from the licence column (%d)" % cc0)
	h.check(header.contains("%d our own synthesis" % ours),
			"the MUSIC header counts our own synthesis (%d)" % ours)
	h.check(not header.contains("all CC0"), "the header no longer claims every music file is CC0")
	h.check(clips.size() == 13, "the manifest ships 13 music files")
	h.check(_label_contains(s, "metronome"), "the own-synthesis music clips are listed too")
	m.show_page(HudMenuRoot.Page.TITLE)


## hud r6 item 4a: nothing on any page is cut. A value either fits its column or wraps under its label,
## and every wrapped line fits the list width. The long audio author list is the case that failed.
static func _layout(m: HudMenuRoot, h: HudTestHarness) -> void:
	# The headless host hands the pages a square viewport; the gate is about the SHIPPING canvas.
	for id: int in [HudMenuRoot.Page.CREDITS, HudMenuRoot.Page.CONTROLS]:
		m.show_page(id)
		var s := m.screen()
		s.canvas_override = CANVAS
		var label: String = HudMenuRoot.Page.keys()[id]
		h.check(s.list_width <= 1920.0, "%s: the list fits a 1920 px canvas" % label)
		var cut := 0
		var wide := 0
		for r in s.rows:
			if String(r.get("value", "")) == "":
				continue
			if s.value_px(r) > s.value_width():
				wide += 1
				if s._wrapped(r).is_empty():
					cut += 1
		h.check(cut == 0, "%s: no value is cut by its column (%d cut)" % [label, cut])
		h.check(s.wrap_values or wide == 0,
				"%s: every wide value wraps under its label instead" % label)
	h.check(HudTestHarness.row_index(m.screen(), "back") >= 0, "the controls page keeps a BACK row")
	m.show_page(HudMenuRoot.Page.CREDITS)
	var s := m.screen()
	s.index = 0
	s.scroll = 0.0
	h.check(s.scrollable(), "the credits page scrolls instead of running off the canvas")
	h.check(s._total > s._window_h(), "the credits really are taller than the canvas (%.0f px)"
			% s._total)
	# Every row must be reachable by the keys: walk the cursor to the last row and back.
	var seen := 0
	var last := -1
	while s.index != last and seen <= s.rows.size():
		last = s.index
		h.press(&"ui_down")
		seen += 1
	h.check(s.index == s.rows.size() - 1, "every credits row is reachable with ui_down")
	h.check(s.scroll > 0.0, "the list has scrolled to bring the last row into the window")
	seen = 0
	while s.index > 0 and seen <= s.rows.size():
		h.press(&"ui_up")
		seen += 1
	h.check(s.index == 0 and s.scroll == 0.0, "ui_up walks back to the first row")
	for id: int in [HudMenuRoot.Page.CREDITS, HudMenuRoot.Page.CONTROLS]:
		m.show_page(id)
		m.screen().canvas_override = Vector2.ZERO
	m.show_page(HudMenuRoot.Page.TITLE)


## hud r6 item 3: the LICENCES page, reached from the credits, holds the engine and font licences.
static func _licences(m: HudMenuRoot, h: HudTestHarness) -> void:
	m.show_page(HudMenuRoot.Page.CREDITS)
	m.screen().index = HudTestHarness.row_index(m.screen(), "licences")
	h.press(&"ui_accept")
	h.check(m.page == HudMenuRoot.Page.LICENCES, "the LICENCES page opens from the credits")
	var page := m.screen()
	page.canvas_override = CANVAS
	h.check(page is HudLicencesPage, "the LICENCES page is its own file")
	h.check(page.scrollable(), "the licence text scrolls")
	h.check(page.list_width <= 1920.0, "the licence page fits a 1920 px canvas")
	var text: String = HudLicences.new().notice_text()
	for want: String in ["Juan Linietsky", "FreeType", "Indian Type Foundry", "Adobe"]:
		h.check(text.contains(want), "the LICENCES text holds '%s'" % want)
	h.check(text.contains("SIL OPEN FONT LICENSE"), "the LICENCES text holds the OFL body")
	h.check(page.rows.size() > 200, "the licence page lays out the whole notice (%d lines)"
			% page.rows.size())
	# Scroll to the end and back with the keys and the pad.
	var last := -1
	var guard := 0
	while page.index != last and guard <= page.rows.size():
		last = page.index
		h.press(&"ui_down")
		guard += 1
	h.check(page.index == page.rows.size() - 1, "every licence line is reachable with ui_down")
	h.check(page.scroll > 0.0, "the licence list scrolls")
	h.pad_button(JOY_BUTTON_DPAD_LEFT)
	h.check(page.index == page.rows.size() - 2, "pad / arrow left is the line-by-line scroll")
	var bottom := page.index
	h.press(&"ui_up")
	h.check(page.index < bottom, "ui_up pages back up the licence text")
	guard = 0
	while page.index > 0 and guard <= page.rows.size():
		h.press(&"ui_up")
		guard += 1
	h.check(page.index == 0, "ui_up reaches the first licence line")
	h.check(HudTestHarness.row_index(page, "back") == page.rows.size() - 1, "the licence page ends on BACK")
	page.index = page.rows.size() - 1
	h.press(&"ui_accept")
	h.check(m.page == HudMenuRoot.Page.CREDITS, "BACK returns to the credits")
	page.canvas_override = Vector2.ZERO
	m.show_page(HudMenuRoot.Page.TITLE)


## The export trap (hud r6 item 3): `include_filter` in the preset ships `.json` and `ui/licenses/*`
## only, so a `.txt` anywhere else is in no build at all — yet every dev run reads it from disk and
## passes. Every file the LICENCES page reads must match one of the globs.
static func _export_filter(h: HudTestHarness) -> void:
	var globs := _include_globs()
	h.check(not globs.is_empty(), "the export preset declares an include_filter")
	for path in HudLicences.files():
		h.check(_matches(globs, path), "%s is shipped by the export's include_filter" % path)
		h.check(FileAccess.get_file_as_string(path) != "", "%s is readable" % path)
	# The trap itself: the same file left in `ui/fonts/` ships nowhere, and this check must say so.
	h.check(not _matches(globs, "res://ui/fonts/OFL.txt"),
			"a licence left in ui/fonts/ is NOT shipped — the check rejects it")


static func _include_globs() -> PackedStringArray:
	var cfg := ConfigFile.new()
	if cfg.load(PRESET) != OK:
		push_error("HudCreditsSuite: cannot read " + PRESET)
		return PackedStringArray()
	var out := PackedStringArray()
	for section in cfg.get_sections():
		var v: Variant = cfg.get_value(section, "include_filter", "")
		for glob in String(v).split(",", false):
			var g := String(glob).strip_edges()
			if g != "":
				out.append(g)
	return out


## `String.match` is the glob the exporter uses, so the check is the same test it makes.
static func _matches(globs: PackedStringArray, path: String) -> bool:
	var rel := path.trim_prefix("res://")
	for g in globs:
		if rel.match(g) or path.match(g) or ("res://" + rel).match(g):
			return true
	return false


static func _label_contains(s: HudMenuScreen, needle: String) -> bool:
	for r in s.rows:
		if String(r.get("label", "")).contains(needle):
			return true
	return false


static func _value_contains(s: HudMenuScreen, needle: String) -> bool:
	for r in s.rows:
		if String(r.get("value", "")).contains(needle):
			return true
	return false
