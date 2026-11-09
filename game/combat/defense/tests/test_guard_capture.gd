extends Node
## Verifies the r7 CAPTURE TIMELINE, headless: `combat/melee/tests/timeline_guard_r7.json` is what the
## lead runs to photograph the Mirror Guard, and its shot times are only worth anything if the shield
## is really in the state each still claims to show. The pixels need a window; the timing does not.
##
## It boots the real `melee_range.tscn`, replays the timeline's own guard presses at 120 Hz, and
## records the shield's state at the three shot times the capture commands use:
##   * 1.82 s — the block panel ALONE (guard 0.22 s old, before the 0.3 s catch threshold);
##   * 6.35 s — the catch dome open with rounds orbiting inside it;
##   * 8.88 s — three frames after the perfect-parry press, mid-burst.
##
## `tools/godot.sh test res://combat/defense/tests/test_guard_capture.gd`

const RANGE := "res://combat/melee/tests/melee_range.tscn"
const TIMELINE := "res://combat/melee/tests/timeline_guard_r7.json"
const STEP := 1.0 / 120.0
## The three instants `--shots=` asks for, in the capture commands in status/melee-defense.md.
const SHOTS: Array[float] = [1.82, 6.35, 8.88]

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _range: Node3D = null
var _defense: DefenseSystem = null
var _events: Array[Dictionary] = []
var _pending: Array[float] = []
var _records: Array[Dictionary] = []
var _t: float = 0.0
var _next: int = 0
var _parry_t: float = -1.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _load_timeline():
		_finish()
		return
	var packed := load(RANGE) as PackedScene
	_check("range.scene_loads", packed != null, "cannot load " + RANGE)
	if packed == null:
		_finish()
		return
	_range = packed.instantiate() as Node3D
	add_child(_range)
	for _i in 240:
		await get_tree().physics_frame
		_defense = _find_defense()
		if _defense != null:
			break
	_check("range.defense_system_found", _defense != null)
	if _defense == null:
		_finish()
		return
	Events.parry_success.connect(func(_h: HitInfo, _s: Node) -> void: _parry_t = _t)
	_pending = SHOTS.duplicate()
	while not _pending.is_empty() and _t < 12.0:
		await get_tree().physics_frame
		_t += STEP
		_apply_due()
		_maybe_record()
	_assert_block(_records[0] if _records.size() > 0 else {})
	_assert_catch(_records[1] if _records.size() > 1 else {})
	_assert_parry(_records[2] if _records.size() > 2 else {})
	_check("shots.all_three_were_taken", _records.size() == SHOTS.size(),
			"took %d of %d" % [_records.size(), SHOTS.size()])
	_finish()


func _load_timeline() -> bool:
	var text := FileAccess.get_file_as_string(TIMELINE)
	var data: Variant = JSON.parse_string(text)
	_check("timeline.parses", data is Array, "%s is not a JSON array" % TIMELINE)
	if not data is Array:
		return false
	for ev: Dictionary in (data as Array):
		_check("timeline.every_event_has_a_time", ev.has("t"), "event without t: %s" % str(ev))
		if ev.has("t"):
			_events.append(ev)
	_check("timeline.ends", _events.size() > 0 and bool(_events[-1].get("end", false)))
	return _events.size() > 0


func _find_defense() -> DefenseSystem:
	if _range == null:
		return null
	var player := _range.get("player") as Node
	if player == null:
		return null
	for child in player.get_children():
		if child is DefenseSystem:
			return child as DefenseSystem
	return null


## The same verbs `tools/autoplay.gd` applies, in the same order.
func _apply_due() -> void:
	while _next < _events.size() and float(_events[_next]["t"]) <= _t:
		var ev := _events[_next]
		_next += 1
		if bool(ev.get("end", false)):
			continue
		for a: String in ev.get("press", []):
			Input.action_press(StringName(a))
		for a: String in ev.get("release", []):
			Input.action_release(StringName(a))
		for a: String in ev.get("tap", []):
			Input.action_press(StringName(a))
			Input.action_release(StringName(a))
		if ev.has("player"):
			_call_player(ev["player"] as Dictionary)


func _call_player(call: Dictionary) -> void:
	var player := _range.get("player") as Node
	if player == null or not player.has_method(StringName(call["method"])):
		_check("timeline.player_call_lands", false, "no %s on the rig player" % call["method"])
		return
	player.callv(StringName(call["method"]), call.get("args", []) as Array)


func _maybe_record() -> void:
	if _pending.is_empty() or _t < _pending[0]:
		return
	_pending.remove_at(0)
	_records.append({
		"t": _t,
		"guarding": _defense.is_guarding(),
		"fade": _defense.shield.fade(),
		"panel": _defense.shield.panel_visible(),
		"dome": _defense.dome.is_showing(),
		"dome_fade": _defense.dome.fade(),
		"caught": _defense.catch_count(),
		"parries": _defense.parries,
		"shards": _defense.shield.shards_active(),
		"flash": _defense.shield.flash(),
	})


## 1.82 s: the guard is 0.22 s old, so the panel is up and faded in and the catch field has NOT opened.
func _assert_block(r: Dictionary) -> void:
	if r.is_empty():
		_check("block.recorded", false, "no state captured at %.2f s" % SHOTS[0])
		return
	_check("block.guard_is_up", bool(r["guarding"]), str(r))
	_check("block.panel_is_faded_in", float(r["fade"]) > 0.99, "fade %.3f" % float(r["fade"]))
	_check("block.panel_is_visible", bool(r["panel"]))
	_check("block.catch_field_not_open_yet", not bool(r["dome"]),
			"the dome opened before %.2f s — the still would show the field, not the block" % SHOTS[0])


## 5.20 s: the guard has been held 1.0 s, so the dome is open and the battery's arcs are orbiting.
func _assert_catch(r: Dictionary) -> void:
	if r.is_empty():
		_check("catch.recorded", false, "no state captured at %.2f s" % SHOTS[1])
		return
	_check("catch.dome_is_open", bool(r["dome"]), str(r))
	_check("catch.dome_is_faded_in", float(r["dome_fade"]) > 0.99,
			"fade %.3f" % float(r["dome_fade"]))
	_check("catch.rounds_are_orbiting", int(r["caught"]) >= 1,
			"%d rounds held — the still has to show something inside the dome" % int(r["caught"]))


## 8.28 s: three frames after the press, so the parry has happened and the burst is still in the air.
func _assert_parry(r: Dictionary) -> void:
	if r.is_empty():
		_check("parry.recorded", false, "no state captured at %.2f s" % SHOTS[2])
		return
	_check("parry.landed_before_the_shot", int(r["parries"]) >= 1,
			"%d parries by %.2f s — the guard press at 8.23 s missed the 167 ms window"
			% [int(r["parries"]), SHOTS[2]])
	_check("parry.shards_are_still_in_the_air", int(r["shards"]) > 0,
			"the burst had already finished at %.2f s" % SHOTS[2])
	_check("parry.panel_is_still_flashing", float(r["flash"]) > 0.0,
			"flash %.3f" % float(r["flash"]))


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("PASS %s" % name)
		return
	_failures.append("%s%s" % [name, "" if detail == "" else " — " + detail])
	print("FAIL %s %s" % [name, detail])


func _finish() -> void:
	print("TEST %d checks, %d failed" % [_checks, _failures.size()])
	for line in _failures:
		print("TEST FAIL ", line)
	get_tree().quit(1 if _failures.size() > 0 else 0)
