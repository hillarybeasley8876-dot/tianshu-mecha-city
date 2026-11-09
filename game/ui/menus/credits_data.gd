class_name HudCredits
extends RefCounted
## Credits rows for the credits page (brief §9, ACCEPTANCE §5). The audio unit owns the audio facts and
## the texture unit owns the texture facts; this READS `audio/audio_manifest.csv` and
## `assets/textures/manifest.json` so every pack the build actually ships is named, and pairs them with
## the author/licence table from `audio/CREDITS_AUDIO.md`. A source in a manifest that the table does
## not know is still listed, with a warning — the credits can never be quietly incomplete.
##
## The AI section is the one that must never be wrong in the other direction (hud r6 item 2): a false
## "built in-house" on generated content is worse than a missing row. Every family that ships AI
## content has a row in `AI_ROWS`, every row names what made it, and `INHOUSE_ROWS` is only the work
## that really was done here. The facts behind them are recorded in `status/hud.md` r6.

const MANIFEST := "res://audio/audio_manifest.csv"
const TEXTURES := "res://assets/textures/manifest.json"
const LICENCE := "CC0 1.0"

## Sound packs, in the order CREDITS_AUDIO.md lists them: pack name -> author. Strings are audio r6's
## final ones (`status/audio.md` Request 8) and `tools/sfx/run.sh credits_check.py` fails if this page
## and the manifest ever disagree again.
const PACKS: Array[Array] = [
	["Kenney — Sci-Fi Sounds", "Kenney"],
	["Kenney — Digital Audio", "Kenney"],
	["OGA — 50 CC0 Sci-Fi SFX", "rubberduck"],
	["OGA — 100 CC0 SFX", "rubberduck"],
	["OGA — 100 CC0 SFX #2", "rubberduck"],
	["OGA — 80 CC0 Creature SFX", "rubberduck"],
	["OGA — 202 More Sound Effects", "OwlishMedia"],
	["OGA — Swishes Sound Pack", "artisticdude"],
	["OGA — The Free Firearm Sound Library",
		"Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney (submitted to OGA by bart)"],
]

## Sources in the manifest that are not third-party CC0 packs, so they are credited for what they
## are instead of inheriting a licence they do not have.
const OTHER: Dictionary = {
	"own synthesis (tools/sfx)": "mecha-city audio unit · ours",
	"minimax speech-2.8-hd (AI-generated voice)": "AI-generated · labelled below",
}

## AI-generated content that must carry a label (ACCEPTANCE §5). One row per family that ships AI
## content; `family` is what the suite checks the list against. The generator is named only where a
## record names it (`art/tripo/jobs.json`, `art/tripo/*/rig.log`, `audio/audio_manifest.csv`).
const AI_ROWS: Array[Array] = [
	["concept", "概念图  CONCEPT ART",
		"AI-generated images — the inputs to every model below (art/concept, not shipped)"],
	["city", "城市建筑  CITY BUILDINGS",
		"AI-generated 3D — Tripo AI image→model (67 kit parts), placed in-house"],
	["props", "街道道具  STREET PROPS",
		"AI-generated 3D — Tripo AI image→model (30 props), placed in-house"],
	["husk", "蚀骸模型  HUSK MODELS",
		"AI-generated 3D — Tripo AI image→model (7 monsters)"],
	["husk_rig", "蚀骸骨骼与动作  HUSK RIGS & CLIPS",
		"AI-generated rigs (5) + motion clips (3 sets) — Tripo AI, re-cut and extended in-house"],
	["hero", "天枢机体  HERO MECH",
		"AI-generated 3D — Tripo AI image→model, rigged + animated in-house"],
	["voice", "座舱 AI 语音  COCKPIT AI VOICE",
		"AI-generated speech — minimax speech-2.8-hd, processed in-house"],
]

## Built here. Nothing in this list was generated, so nothing in it may claim a generator either.
const INHOUSE_ROWS: Array[Array] = [
	["程序化城市  PROCEDURAL CITY",
		"Built in-house — collision, navigation, the Spire, the blockout"],
	["着色器与特效  SHADERS & VFX",
		"Built in-house — Godot shaders, materials and VFX"],
]

## Engine and font licences (hud r6 item 3). The full texts are on the 开源许可 LICENCES page, read
## from the engine at runtime and from `ui/licenses/` for the two fonts.
const ENGINE_ROWS: Array[Array] = [
	["Godot Engine 4.7", "MIT · godotengine.org/license"],
	["Noto Sans CJK SC", "© 2014-2021 Adobe · SIL OFL 1.1"],
	["Rajdhani SemiBold", "© 2014 Indian Type Foundry · SIL OFL 1.1"],
]

## Everything the manifests counted, for the section subtitles.
var sfx_count: int = 0
var voice_count: int = 0
var texture_count: int = 0
## Empty when `assets/textures/manifest.json` read cleanly; otherwise the reason, shown as a row.
var texture_error: String = ""
## Packs named in the manifest (a row can layer several).
var used_packs: Dictionary = {}
## Music clips in manifest order: `id` -> `source` / `author` / `licence`.
var music: Array[Dictionary] = []


## Reads the manifests and returns the credits rows: `label` / `value` / `header`.
func rows() -> Array[Dictionary]:
	_scan_audio()
	_scan_textures()
	var out: Array[Dictionary] = []
	out.append(_header("音频  AUDIO — %d sounds · every third-party layer is %s" % [sfx_count, LICENCE]))
	for p in PACKS:
		if used_packs.has(p[0]):
			out.append(_row(String(p[0]), "%s · %s" % [String(p[1]), LICENCE]))
	# Our own synthesis and the AI voice are sources too, and they are not CC0 — credit them as what
	# they are rather than letting them fall through with a licence that is not theirs.
	for name: String in OTHER:
		if used_packs.has(name):
			out.append(_row(name, String(OTHER[name])))
	for name: String in used_packs:
		if _known(name):
			continue
		push_warning("HUD credits: source '%s' is in the manifest but not in HudCredits" % name)
		out.append(_row(name, "see audio/CREDITS_AUDIO.md"))
	out.append(_header(_music_header()))
	for clip in music:
		out.append(_row(String(clip["id"]), _music_value(clip)))
	out.append(_header("贴图  TEXTURES — %d tiling materials" % texture_count))
	out.append(_row("Poly Haven", texture_error if texture_error != "" else "%s · polyhaven.com" % LICENCE))
	out.append(_header("AI 生成内容  AI-GENERATED CONTENT — labelled per licence terms"))
	for r in AI_ROWS:
		out.append(_row(String(r[1]), String(r[2])))
	out.append(_row("座舱语音条数  VOICE LINES", "%d" % voice_count))
	out.append(_header("自建内容  BUILT IN-HOUSE"))
	for r in INHOUSE_ROWS:
		out.append(_row(String(r[0]), String(r[1])))
	out.append(_header("引擎与字体  ENGINE & FONTS"))
	for r in ENGINE_ROWS:
		out.append(_row(String(r[0]), String(r[1])))
	return out


## The AI families the credits must cover. The suite reads this, so a new family cannot be added to
## `AI_ROWS` without the check following it.
static func ai_families() -> PackedStringArray:
	var out := PackedStringArray()
	for r in AI_ROWS:
		out.append(String(r[0]))
	return out


## The header is derived from the licence column, never asserted: 7 of the 13 music files are our own
## synthesis, so "all CC0" was false (hud r6 item 4b).
func _music_header() -> String:
	var cc0 := 0
	var ours := 0
	for clip in music:
		if String(clip["licence"]) == "ours":
			ours += 1
		else:
			cc0 += 1
	return "音乐  MUSIC — %d files · %d %s · %d our own synthesis" % [music.size(), cc0, LICENCE, ours]


func _music_value(clip: Dictionary) -> String:
	var licence := String(clip["licence"])
	var name := "our own synthesis" if licence == "ours" else String(clip["source"])
	return "%s — %s · %s" % [name, String(clip["author"]),
			"built in-house" if licence == "ours" else LICENCE]


func _known(name: String) -> bool:
	if OTHER.has(name):
		return true
	for p in PACKS:
		if String(p[0]) == name:
			return true
	return false


## One pass over the audio manifest: how many sounds of each kind ship, and which packs they layer.
func _scan_audio() -> void:
	sfx_count = 0
	voice_count = 0
	used_packs.clear()
	music.clear()
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		push_error("HUD credits: cannot read %s (error %d)" % [MANIFEST, FileAccess.get_open_error()])
		return
	var cols := f.get_csv_line()                        # header
	var at := _columns(cols)
	if at.is_empty():
		f.close()
		return
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < cols.size():
			continue
		var path := String(row[int(at["file"])])
		if path.begins_with("audio/music/"):
			music.append({"id": String(row[int(at["id"])]), "source": String(row[int(at["source"])]),
					"licence": String(row[int(at["licence"])]), "author": String(row[int(at["author"])])})
			continue                                       # music has a section of its own
		if path.begins_with("audio/voice/"):
			voice_count += 1
		else:
			sfx_count += 1
		for pack in String(row[int(at["source"])]).split(" + ", false):
			used_packs[pack.strip_edges()] = true
	f.close()


## Column name -> index, or an empty dictionary (with an error) when the header is not the manifest
## this reads. Better a loud failure than credits built off the wrong columns.
func _columns(cols: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for name: String in ["id", "file", "source", "licence", "author"]:
		var at := cols.find(name)
		if at < 0:
			push_error("HUD credits: %s has no '%s' column" % [MANIFEST, name])
			return {}
		out[name] = at
	return out


## Poly Haven CC0 tiling materials (city-art's manifest). A missing file is an error AND a visible row
## — never a silently shorter credits page.
func _scan_textures() -> void:
	texture_count = 0
	texture_error = ""
	var text := FileAccess.get_file_as_string(TEXTURES)
	if text == "":
		texture_error = "manifest unreadable (error %d)" % FileAccess.get_open_error()
		push_error("HUD credits: cannot read %s (error %d)" % [TEXTURES, FileAccess.get_open_error()])
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		texture_count = (parsed as Dictionary).size()
	else:
		texture_error = "manifest is not a JSON object"
		push_error("HUD credits: %s is not a JSON object" % TEXTURES)


func _header(label: String) -> Dictionary:
	return {"id": label, "label": label, "kind": HudMenuScreen.Kind.INFO, "value": "", "header": true}


func _row(label: String, value: String) -> Dictionary:
	return {"id": label, "label": label, "kind": HudMenuScreen.Kind.INFO, "value": value}
