class_name HudLicences
extends RefCounted
## The one composer for every third-party notice the build ships (hud r6 item 3). The LICENCES page and
## the headless writer that `tools/godot.sh export` calls both read THIS, so the text on screen and
## `build/THIRD_PARTY_LICENSES.txt` beside the .app can never drift apart.
##
## Engine text is read from the engine at runtime (`Engine.get_license_text`,
## `Engine.get_copyright_info`, `Engine.get_license_info`) and never pasted in; the two font licences
## are read from `res://ui/licenses/`, which is the only directory the export's include_filter ships
## `.txt` from (`game/export_presets.cfg`).

const DIR := "res://ui/licenses/"
## The font licences, in page order: file -> the heading it is printed under.
const FONT_FILES: Array[Array] = [
	["OFL-NotoSansSC.txt", "Noto Sans CJK SC — © 2014-2021 Adobe"],
	["OFL-Rajdhani.txt", "Rajdhani SemiBold — © 2014 Indian Type Foundry"],
]
const HEADER := "天枢 TIANSHU · MECHA CITY — THIRD-PARTY LICENCES / 开源许可"


## Every file the page reads, so the suite can prove each one matches an include_filter glob in
## `res://export_presets.cfg` — a `.txt` left anywhere else ships in no build at all.
static func files() -> PackedStringArray:
	var out := PackedStringArray()
	for f in FONT_FILES:
		out.append(DIR + String(f[0]))
	return out


## `title` / `lines`, in page order. The page wraps and scrolls them; the writer joins them.
func sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"title": "GODOT ENGINE 4.7 — MIT", "lines": _wrap_block(Engine.get_license_text())})
	out.append({"title": "ENGINE COMPONENTS", "lines": _components()})
	out.append({"title": "LICENCE TEXTS", "lines": _licence_texts()})
	for f in FONT_FILES:
		out.append({"title": String(f[1]) + " — SIL OFL 1.1", "lines": _read(String(f[0]))})
	return out


## The whole notice as one string — what `write_third_party.gd` puts in THIRD_PARTY_LICENSES.txt.
func notice_text() -> String:
	var parts := PackedStringArray([HEADER, ""])
	for s in sections():
		parts.append("=".repeat(72))
		parts.append(String(s["title"]))
		parts.append("=".repeat(72))
		parts.append_array(s["lines"] as PackedStringArray)
		parts.append("")
	return "\n".join(parts)


## One block per component: its name, then every part's copyright lines, the files it covers and the
## licence id. The licence BODIES are printed once each further down, the way a NOTICE file does it.
func _components() -> PackedStringArray:
	var out := PackedStringArray()
	for c: Dictionary in Engine.get_copyright_info():
		out.append(String(c.get("name", "?")))
		for part: Dictionary in c.get("parts", []):
			for line: String in part.get("copyright", []):
				out.append("    Copyright (c) " + line)
			out.append("    Files: " + ", ".join(part.get("files", [])))
			out.append("    Licence: " + String(part.get("license", "?")))
		out.append("")
	if out.is_empty():
		out.append("(the engine reported no third-party components)")
	return out


## The licence bodies, once each, for the ids the components above actually use.
func _licence_texts() -> PackedStringArray:
	var info := Engine.get_license_info()
	var used: Dictionary = {}
	for c: Dictionary in Engine.get_copyright_info():
		for part: Dictionary in c.get("parts", []):
			used[String(part.get("license", ""))] = true
	var out := PackedStringArray()
	for id: String in used:
		if not info.has(id):
			out.append("%s — (the engine shipped no text for this licence)" % id)
			out.append("")
			continue
		out.append("--- %s ---" % id)
		out.append_array(_wrap_block(String(info[id])))
		out.append("")
	return out


## Reads one licence file. A file that will not open is a `push_error` AND a visible line: the page
## must never come up blank because a path moved.
func _read(file: String) -> PackedStringArray:
	var path := DIR + file
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("HUD licences: cannot read %s (error %d)" % [path, FileAccess.get_open_error()])
		return PackedStringArray(["!! %s could not be opened (error %d) — see the build log"
				% [path, FileAccess.get_open_error()]])
	return _wrap_block(text)


func _wrap_block(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in text.replace("\r\n", "\n").split("\n"):
		out.append(line)
	return out
