extends Node
## city-art r10: the settle bake is only safe if it cannot go stale silently
## (world/art/tests/test_settle_cache.gd).
## Run: tools/godot.sh test res://world/art/tests/test_settle_cache.gd
##
## The settle pass is computed once by a tool and replayed at load, because turning 1 275 render meshes
## into something a ray can be cast against costs ~2.2 s and the budget is 1.5 s. That trade is only
## sound while the baked numbers still describe the city in front of us, so this test re-derives the
## fingerprint of every input the pass reads and fails when the file no longer matches it. Re-bake with
##   SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600

const MIN_BATCHES := 100      ## r10b: the pass settles ~134 DRESSING batches; structure is never settled
## Where the content-stamp check keeps its scratch copies. Emptied at the start and the end of every
## run, so nothing lands in git even if the suite is interrupted.
const PROBE_DIR := "res://world/art/tests/stamp_probe"

var _failures: int = 0


func _ready() -> void:
	var stamp := SettleCache.fingerprint()
	_expect(FileAccess.file_exists(SettleCache.PATH),
			"%s exists — bake it with SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600"
			% SettleCache.PATH)
	if _failures > 0:
		_done()
		return
	var raw := FileAccess.get_file_as_string(SettleCache.PATH)
	var parsed: Variant = JSON.parse_string(raw)
	_expect(parsed is Dictionary, "%s is a JSON object" % SettleCache.PATH)
	if not (parsed is Dictionary):
		_done()
		return
	var data := parsed as Dictionary
	_expect(int(data.get("version", -1)) == SettleCache.VERSION,
			"the cache format is version %d, the code wants %d — re-bake"
			% [int(data.get("version", -1)), SettleCache.VERSION])
	_expect(String(data.get("stamp", "")) == stamp,
			"the cache is STALE: it was baked against %s and the inputs now fingerprint %s — re-bake "
			% [String(data.get("stamp", "?")).substr(0, 8), stamp.substr(0, 8)]
			+ "with SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600")
	var batches: Dictionary = data.get("batches", {})
	_expect(batches.size() >= MIN_BATCHES,
			"the cache holds %d batches, expected at least %d" % [batches.size(), MIN_BATCHES])
	var kept := 0
	var dropped := 0
	for key: String in batches:
		var row: Dictionary = batches[key]
		var n := int(row.get("n", 0))
		var list: Array = row.get("kept", [])
		kept += list.size()
		dropped += n - list.size()
		for i in list:
			if int(i) < 0 or int(i) >= n:
				_failures += 1
				print("SETTLE CACHE FAIL: batch '%s' keeps index %d of %d" % [key, int(i), n])
				break
	_expect(kept > 2000, "the cache keeps %d instances, expected more than 2 000" % kept)
	# r10b: no kit batch other than the roof machinery may appear. Settling a deck slab, a pylon or an
	# arena cover piece leaves city-build's collider behind, so a cache that contains one is a bug the
	# bake would otherwise hide.
	for key: String in batches:
		if not key.begins_with("kit_"):
			continue
		var model := key.get_slice("_", 1)
		_expect(CityArt.kit_role(model) == "dressing",
				"batch '%s' is STRUCTURE (kit model %s) — the settle pass must never move or drop it"
				% [key, model])
	print("SETTLE CACHE %d batches, %d kept, %d dropped, stamp %s (fingerprint %.1f ms)"
			% [batches.size(), kept, dropped, stamp.substr(0, 8), SettleCache.last_cost_ms])
	# A cache the runtime can actually read back, through the same code path the city uses.
	_expect(SettleCache.load() != null, "SettleCache.load() accepts the file on disk")
	_check_content_stamp()
	_done()


## city-art r16 §5: the per-file half of the fingerprint must follow CONTENT. It used to be
## `path:size:mtime`, and git keeps no mtimes — so a fresh checkout of a byte-identical tree
## fingerprinted differently from the tree that baked it, every clean clone recomputed the pass at boot
## and `tools/godot.sh export` refused to pack. Proven here on SCRATCH COPIES (a tile glb and a kit glb,
## never a tracked file): the same bytes rewritten with a new mtime keep the stamp, and one flipped byte
## in the glb's BIN chunk changes it.
func _check_content_stamp() -> void:
	var dir := PROBE_DIR
	_wipe(dir)
	_expect(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) == OK,
			"the scratch directory %s is writable" % dir)
	var tile := _first_glb(SettleCache.TILE_DIR)
	var kit := _first_kit_glb()
	var prop := _first_glb(SettleCache.PROP_DIR)
	if tile == "" or kit == "" or prop == "":
		_expect(false, "a tile glb (%s), a kit glb (%s) and a prop glb (%s) exist to copy"
				% [tile, kit, prop])
		return
	# A fresh name every run: `content_md5` reads Godot's import cache when the path has a record, and a
	# record only describes the file as it was at the last IMPORT — which is exactly right in the game
	# (every tools/godot.sh subcommand imports first) and exactly wrong for a file this test rewrites
	# mid-run. A name that has never been imported always hashes its bytes.
	# r16a: the prop meshes are in the stamp too (lead r16 decision) and get the same proof.
	var tag := str(Time.get_ticks_usec())
	for pair: Array in [[tile, "%s/tile_%s.glb" % [dir, tag]], [kit, "%s/kit_%s.glb" % [dir, tag]],
			[prop, "%s/prop_%s.glb" % [dir, tag]]]:
		var src: String = pair[0]
		var dst: String = pair[1]
		if not _copy(src, dst):
			_expect(false, "copied %s to %s" % [src, dst])
			continue
		var before := _dir_stamp(dir)
		var before_md5 := SettleCache.content_md5(dst)
		# The import-cache fast path must agree with hashing the bytes, or the whole stamp is a fiction.
		_expect(before_md5 == FileAccess.get_md5(dst),
				"content_md5(%s) matches the file's own md5" % dst.get_file())
		# 1. the SAME bytes, written again: a new mtime, an identical stamp. The sleep is what makes the
		# mtime really move — without it both writes land in the same second and the old rule passes by
		# luck, which is the other half of why this went unnoticed for three rounds.
		OS.delay_msec(1100)
		_copy(src, dst)
		var touched := _dir_stamp(dir)
		_expect(touched == before,
				"rewriting %s with the same bytes keeps its stamp (%s -> %s)"
				% [dst.get_file(), before.substr(0, 8), touched.substr(0, 8)])
		# 2. one flipped byte inside the BIN chunk: same size, same everything else, a different stamp.
		var at := _bin_chunk_offset(dst)
		if at < 0:
			_expect(false, "%s has a BIN chunk to flip a byte in" % dst.get_file())
			continue
		OS.delay_msec(1100)
		_flip_byte(dst, at)
		var flipped := _dir_stamp(dir)
		_expect(flipped != before,
				"one flipped byte at offset %d of %s changes its stamp" % [at, dst.get_file()])
	_wipe(dir)


## The scratch copies live in their own directory under the tests folder, emptied at the start and the
## end of every run, because the stamp has to walk the same listing on both versions of the stamper for
## the baseline to be a fair one.
func _wipe(dir: String) -> void:
	var abs := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(abs.path_join(f))


## The stamp of one directory, through the production stamper. `_stamp_dir` rather than `stamp_dir` so
## this test also compiles against the pre-r16 cache and can be run against it as the failing baseline.
func _dir_stamp(dir: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	SettleCache._stamp_dir(ctx, dir, 1)
	return ctx.finish().hex_encode()


## The first .glb in a `res://` directory, sorted, so the probe is the same file on every run.
func _first_glb(dir: String) -> String:
	var names := ResourceLoader.list_directory(dir)
	names.sort()
	for f in names:
		if f.ends_with(".glb"):
			return dir.path_join(f)
	return ""


func _first_kit_glb() -> String:
	for model in ResourceLoader.list_directory(SettleCache.KIT_DIR):
		var sub := SettleCache.KIT_DIR.path_join(model)
		if model.contains("."):
			continue
		var found := _first_glb(sub)
		if found != "":
			return found
	return ""


func _copy(src: String, dst: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(src)
	if bytes.is_empty():
		return false
	var out := FileAccess.open(dst, FileAccess.WRITE)
	if out == null:
		return false
	out.store_buffer(bytes)
	out.close()
	return true


## A glb is a 12-byte header then chunks of `length:u32, type:4cc, data`. This is the first byte of the
## BIN chunk's data, i.e. a byte that changes the model's contents and not the file's structure.
func _bin_chunk_offset(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var at := 12
	while at + 8 <= f.get_length():
		f.seek(at)
		var length := f.get_32()
		var kind := f.get_buffer(4)
		if kind == PackedByteArray([0x42, 0x49, 0x4E, 0x00]):
			f.close()
			return at + 8
		at += 8 + length
	f.close()
	return -1


func _flip_byte(path: String, at: int) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek(at)
	var b := f.get_8()
	f.seek(at)
	f.store_8(b ^ 0x01)
	f.close()


func _done() -> void:
	print("SETTLE CACHE TEST %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if ok:
		return
	_failures += 1
	print("SETTLE CACHE FAIL: %s" % what)
