extends Node
## Weapons FEEL-row audit (lead r5 item 2). Runs on its own, NOT inside `test_weapons.gd`, because
## the three rows it needs (`gatling_overheat`, `gatling_vent_good`, `gatling_jam`) are the lead's
## (docs/FEEL.md), the `.tres` are feel's and the sound mapping is audio's — until they land this
## file fails on purpose, and the main suite stays green.
##
##   tools/godot.sh test res://combat/weapons/tests/test_feel_rows.gd -- --audio-trace
##
## It instances the REAL `res://fx/feel_director.tscn` (so the perf suite still measures what it did)
## and drives the real WeaponSystem through an overheat and the perfect / good / miss vent results.

const DIRS: Array[String] = ["res://combat/weapons/", "res://combat/projectiles/"]
const CALL := "Feel\\.play\\(&\"([a-z0-9_]+)\""
const TRES := "res://fx/events/%s.tres"
const ROWS: Array[StringName] = [&"gatling_overheat", &"gatling_vent_perfect", &"gatling_vent_good",
		&"gatling_jam"]

var _fails: int = 0
var _checks: int = 0
var _harness: WeaponTestHarness = null
var _director: Node = null
var _played: Array[StringName] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://fx/feel_director.tscn") as PackedScene
	if packed == null:
		_check("feel.director_scene_loads", false, "cannot load res://fx/feel_director.tscn")
		_finish()
		return
	_director = packed.instantiate()
	add_child(_director)
	_director.connect(&"event_played", func(id: StringName, _at: Vector3, _s: float) -> void:
			_played.append(id))
	_harness = WeaponTestHarness.new(self)
	if not _harness.build():
		_finish()
		return
	_harness.system.switch_weapon(1)
	await _harness.step(0.4)
	await _vents()
	_call_sites()
	_finish()


## One overheat, then the three press windows. Each result must play its own row and the good vent
## must ask for a sound.
func _vents() -> void:
	var g := _harness.system.gatling
	_harness.clear_targets()
	_harness.add_target(Vector3(0.0, 11.5, -100.0), 24.0)
	_harness.aim_at(Vector3(0.0, 11.5, -100.0))
	await _trip()
	_check("vent.overheat_fires_its_row", _saw(&"gatling_overheat"),
			"rows played: %s" % [_played])
	await _press_at(g, 0.1)                     # far from the marker -> jam
	_check("vent.miss_fires_its_row", _saw(&"gatling_jam"), "rows played: %s" % [_played])
	await _trip()
	await _press_at(g, g.tuning.vent_mark * g.tuning.vent_sweep + 0.08)
	_check("vent.good_fires_its_row", _saw(&"gatling_vent_good"), "rows played: %s" % [_played])
	var counts := Audio.request_counts()
	_check("vent.good_requests_a_sound", int(counts.get(&"gatling_vent", 0)) > 0
			or int(counts.get(&"gatling_vent_good", 0)) > 0,
			"no gatling_vent request in %s (run with -- --audio-trace)" % [counts.keys()])
	await _trip()
	await _press_at(g, g.tuning.vent_mark * g.tuning.vent_sweep + 0.02)
	_check("vent.perfect_fires_its_row", _saw(&"gatling_vent_perfect"),
			"rows played: %s" % [_played])
	# One perfect vent = exactly two `gatling_vent_perfect` requests: the row's `ui_vent_chime` layer
	# and the audio router's id mapping. A third means gameplay code plays the sound itself too.
	var perfect := int(Audio.request_counts().get(&"gatling_vent_perfect", 0))
	_check("vent.perfect_sound_has_one_source", perfect == 2,
			"%d gatling_vent_perfect requests for 1 perfect vent" % perfect)
	_check("vent.no_unknown_rows", int(_director.call(&"warned_unknown")) == 0,
			"%d unknown ids warned" % int(_director.call(&"warned_unknown")))
	for id in ROWS:
		_check("vent.row_loaded_%s" % id, bool(_director.call(&"has_event", id)),
				"no %s" % TRES % id)


## Wind the gauge to one round short of the vent and trip it, so the needle starts from a known spot.
func _trip() -> void:
	var g := _harness.system.gatling
	g.reset_state()
	g.heat = 99.2
	_harness.press(&"fire")
	var guard := 0
	while not g.overheated() and guard < 120:
		await _harness.step(1.0 / 120.0)
		guard += 1
	_harness.release(&"fire")


## Wait until the needle reaches `target` seconds into its sweep, then tap.
func _press_at(g: ThunderSpindleGatling, target: float) -> void:
	var current := g.needle() * g.tuning.vent_sweep
	if target > current:
		await _harness.step(target - current)
	await _harness.tap(&"fire", 0.02)


func _saw(id: StringName) -> bool:
	return id in _played


## Every literal `Feel.play(&"…")` id under the two owned directories must be a FEEL.md row and have
## its `fx/events/<id>.tres` (the pattern of audio/tests/test_audio_call_sites.gd).
func _call_sites() -> void:
	var found: Dictionary = {}
	for dir_path in DIRS:
		_scan(dir_path, found)
	var ids: Array[StringName] = []
	for id: StringName in found:
		ids.append(id)
	ids.sort()
	var rows := FeelTable.ids()
	var missing: Array[String] = []
	for id in ids:
		if id not in rows:
			missing.append("%s: not a FEEL.md row" % id)
		elif not ResourceLoader.exists(TRES % id):
			missing.append("%s: no %s" % [id, TRES % id])
	_check("call_sites.scanned", ids.size() >= 10, "%d ids found" % ids.size())
	_check("call_sites.every_id_has_a_row", missing.is_empty(),
			"%d unresolved: %s" % [missing.size(), ", ".join(missing)])
	for id in ids:
		print("  FEEL id %s" % id)


func _scan(dir_path: String, found: Dictionary) -> void:
	# DirAccess is fine in a test: this never runs from an exported build.
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("FeelRows: cannot open " + dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if entry != "tests":
				_scan(full, found)
		elif entry.ends_with(".gd"):
			_scan_file(full, found)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_file(path: String, found: Dictionary) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	var regex := RegEx.new()
	regex.compile(CALL)
	for result in regex.search_all(text):
		found[StringName(result.get_string(1))] = path


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("PASS %s" % name)
		return
	_fails += 1
	print("FAIL %s %s" % [name, detail])


func _finish() -> void:
	print("TEST %d checks, %d failed" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
