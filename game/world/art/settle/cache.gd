class_name SettleCache
extends RefCounted
## The settle pass's RESULT on disk (city-art r10). The pass is a pure function of the city, so it is
## computed once by a tool and replayed at load: turning 1 275 render meshes into something a ray can
## be cast against costs ~2.2 s, and the brief's budget for the whole settle is 1.5 s.
##
##   SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600      # writes the cache
##   tools/godot.sh test res://world/art/tests/test_settle_cache.gd         # fails when it is stale
##
## The stamp is a fingerprint of every input the pass reads — the two layouts, the kit assignment and
## index, the tile, kit and prop glbs (their CONTENT, see `_content_md5`) and the cache format version.
## If any of them moves, the cache is stale, `load()` returns null, and the pass computes at load and
## says so. A stale cache can never be applied by accident.
##
## city-art r16 §5: the glb half of that stamp used to be `path:size:mtime`. Git keeps no mtimes, so a
## fresh checkout of a byte-identical tree fingerprinted differently from the tree that baked it: every
## clean clone recomputed the pass at boot (+1.5 s) and `tools/godot.sh export` refused to pack. The
## stamp is content-only now, and the per-file hash comes from Godot's own import cache where it can
## (`.godot/imported/<base>-<md5 of the res:// path>.md5` holds exactly `FileAccess.get_md5` of the
## source), so 450 MB of glbs costs a stat instead of a read.

const PATH := "res://world/art/settle_cache.json"
## Bump when the pass's RULES change — the cached numbers are only valid for the rules that made them.
## r12: the ROOF rule reads city-kit's roof map instead of only the render, so the placement it baked
## is a different placement.
## r16a: `CitySettle.VERIFY_M` went 1.0 m -> 0.5 m (the last two floaters were map answers the metre let
## through), so every roof unit the render overrules is at a different height than the one baked here.
const VERSION := 6

## The files whose CONTENT is hashed. Every one is a `res://` path: the fingerprint has to be
## computable on any machine that has the project; an absolute home path among them made the stamp
## depend on whose checkout made it (city-art r12 §3).
const INPUTS: Array[String] = [
	"res://world/city/layout.json",
	"res://world/city/design_layout.json",
	"res://world/kit/kit_assign.json",
	"res://world/kit/kit.json",
]
const TILE_DIR := "res://world/city/tiles"
## city-kit's own meshes. The settle pass reads them (the roof map is measured off them and the render
## it verifies against IS them), so a re-baked glb has to stale the bake — r12: it did not, and a
## re-bake after any kit change was a discipline rather than something the stamp enforced.
const KIT_DIR := "res://world/kit"
## city-art's prop meshes (lead r16 decision): the settle pass moves and drops prop instances, so a
## re-processed prop changes the bake exactly as a re-baked kit model does.
const PROP_DIR := "res://world/props/meshes"

## How long the last `fingerprint()` took, in milliseconds. Read by `test_settle_cache` so the cost of
## the content stamp is a number in the status file rather than an assumption.
static var last_cost_ms: float = 0.0
## The inputs do not change inside one run, and the walk costs ~240 ms, so the second and third callers
## in a process (`load()` then `save()` in the bake tool) reuse the first answer.
static var _stamp_memo: String = ""

var stamp: String = ""
## batch key -> {"n": int, "kept": PackedInt32Array, "d": PackedVector3Array}
var batches: Dictionary = {}
var dirty: bool = false


## A fingerprint of every input the settle pass reads — CONTENT only, for all of them.
static func fingerprint() -> String:
	if _stamp_memo != "":
		return _stamp_memo
	var t0 := Time.get_ticks_usec()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(str(VERSION).to_utf8_buffer())
	for path in INPUTS:
		if FileAccess.file_exists(path):
			ctx.update(FileAccess.get_md5(path).to_utf8_buffer())
		else:
			ctx.update(("missing:" + path).to_utf8_buffer())
	_stamp_dir(ctx, TILE_DIR, 1)
	_stamp_dir(ctx, KIT_DIR, 2)
	_stamp_dir(ctx, PROP_DIR, 1)
	last_cost_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_stamp_memo = ctx.finish().hex_encode()
	return _stamp_memo


## The content hash of every .glb under `dir`, `depth` levels deep.
static func _stamp_dir(ctx: HashingContext, dir: String, depth: int) -> void:
	var names := _list(dir)
	names.sort()
	for file in names:
		var full := dir.path_join(file)
		if file.ends_with(".glb"):
			ctx.update(("%s:%s" % [full, content_md5(full)]).to_utf8_buffer())
		elif depth > 1 and not file.contains("."):
			_stamp_dir(ctx, full, depth - 1)


## The directory listing the stamp walks. `DirAccess` and not `ResourceLoader.list_directory`: the
## latter is a snapshot taken when the process starts, so it cannot see a file written during the run —
## which is exactly what `test_settle_cache` needs in order to prove the content rule on scratch copies.
## Safe in a shipped build because `load()` only calls `fingerprint()` when NOT
## `OS.has_feature("template")`, and an exported pack has no real directories to walk anyway.
static func _list(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		out.append(f)
	for sub in d.get_directories():
		out.append(sub)
	return out


## The md5 of a file's BYTES. Godot's import cache already holds that number for every imported asset
## (`.godot/imported/<base>-<md5 of the res:// path>.md5`, `source_md5=`) and rewrites it whenever the
## source is re-imported, so the 259 glbs the stamp covers (450 MB) cost a stat and a 91-byte read
## instead of 376 ms of hashing. It is the same number `FileAccess.get_md5` returns — measured on all
## 259 files, 0 mismatches, including the 100 whose source is newer than the record.
##
## Trusting the record is sound rather than lazy: it is the number Godot itself used to decide the
## IMPORTED resource is up to date, and the settle pass reads the imported scene, not the raw bytes. A
## glb edited without an import is a tree whose game still renders the old model — every
## `tools/godot.sh` subcommand imports before it runs. A file with no record (a fresh checkout, a
## `user://` scratch copy) falls back to hashing the bytes, which is where `test_settle_cache` proves
## the rule.
static func content_md5(path: String) -> String:
	var imported := _import_md5(path)
	if imported != "":
		return imported
	return FileAccess.get_md5(path)


static func _import_md5(path: String) -> String:
	if not path.begins_with("res://") or FileAccess.get_modified_time(path) == 0:
		return ""
	var md5_path := "res://.godot/imported/%s-%s.md5" % [path.get_file(), path.md5_text()]
	var text := FileAccess.get_file_as_string(md5_path)
	var open := text.find("source_md5=\"")
	if open < 0:
		return ""
	return text.substr(open + "source_md5=\"".length(), 32)


## The cache on disk, or null when it is missing, unreadable or stale against `fingerprint()`.
static func load(path: String = PATH) -> SettleCache:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("SettleCache: %s is not a JSON object; the settle pass will recompute" % path)
		return null
	var data := parsed as Dictionary
	var cache := SettleCache.new()
	cache.stamp = String(data.get("stamp", ""))
	# An exported build ships the bake and every input it was made from in one immutable pack, but not
	# the tile glbs the stamp measures (only their imports), so the check fails there by construction:
	# the shipped app logged 77 "Failed to get size" errors and recomputed the pass at every load
	# (+4 s). `tools/godot.sh export` refuses to pack a stale bake instead.
	if not OS.has_feature("template") and cache.stamp != fingerprint():
		return null
	for key: String in (data.get("batches", {}) as Dictionary):
		var row: Dictionary = (data["batches"] as Dictionary)[key]
		cache.batches[key] = {
			"n": int(row.get("n", 0)),
			"nowhere": int(row.get("nowhere", 0)),
			"kept": PackedInt32Array(row.get("kept", [])),
			"d": _vectors(row.get("d", [])),
		}
	return cache


## A flat [x, y, z, x, y, z, ...] array in the file, a PackedVector3Array in memory. r12: a roof unit can
## move sideways onto the nearest flat cell, so a bare `dy` is no longer the whole move.
static func _vectors(flat: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var i := 0
	while i + 2 < flat.size():
		out.append(Vector3(float(flat[i]), float(flat[i + 1]), float(flat[i + 2])))
		i += 3
	return out


func has(key: String) -> bool:
	return batches.has(key)


func row(key: String) -> Dictionary:
	return batches.get(key, {})


func put(key: String, n: int, kept: PackedInt32Array, d: PackedVector3Array,
		nowhere: int) -> void:
	batches[key] = {"n": n, "nowhere": nowhere, "kept": kept, "d": d}
	dirty = true


## Packed arrays have no `to_array()` in 4.7; JSON wants a plain Array.
static func _ints(v: PackedInt32Array) -> Array:
	var out: Array = []
	out.resize(v.size())
	for i in v.size():
		out[i] = v[i]
	return out


## PackedVector3Array -> the flat float array the file stores.
static func _flat(v: PackedVector3Array) -> Array:
	var out: Array = []
	for d in v:
		out.append(d.x)
		out.append(d.y)
		out.append(d.z)
	return out


func save(path: String = PATH) -> bool:
	var out: Dictionary = {}
	for key: String in batches:
		var row: Dictionary = batches[key]
		out[key] = {"n": int(row["n"]), "nowhere": int(row["nowhere"]),
				"kept": _ints(row["kept"] as PackedInt32Array),
				"d": _flat(row["d"] as PackedVector3Array)}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SettleCache: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify({"version": VERSION, "stamp": fingerprint(), "batches": out}))
	file.close()
	dirty = false
	print("SETTLE CACHE wrote %s: %d batches" % [path, batches.size()])
	return true
