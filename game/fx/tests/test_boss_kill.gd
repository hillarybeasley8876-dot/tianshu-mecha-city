extends Node
## feel r5b item 3 - the boss death plays `boss_kill`, exactly once, and never `kill_large`.
##     tools/godot.sh test res://fx/tests/test_boss_kill.gd
##
## `brood_titan.gd` is flow's file (it switched the death to `boss_kill` for its r5 decision 6); this
## is the feel unit's confirmation that the switch is live on the real boss, through the real death
## path, and that nothing else on that path re-plays the big kill row. It reads `Feel.event_requested`
## only - no director needed, because `Feel.play` emits the signal whatever is listening.

## How long to watch after the killing blow: the collapse runs BossTuning.DEATH_CINEMATIC.
const WATCH := 2.0

var _harness: BossTestHarness = null
var _fails: int = 0
var _seen: Array[StringName] = []
var _counting: bool = false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_harness = BossTestHarness.new(self)
	if not _harness.build():
		_check(false, "the boss harness builds")
		_finish()
		return
	Feel.event_requested.connect(_on_event)
	_kill()
	await _harness.step(WATCH)
	Feel.event_requested.disconnect(_on_event)
	_report()
	_finish()


## The killing blow through the titan's own pipeline, the way the other boss suites do it.
func _kill() -> void:
	_harness.reset_titan()
	_harness.titan.hp = 500.0
	_counting = true
	_harness.hit_titan(2000.0)
	_check(not _harness.titan.is_alive(), "the titan died from the killing blow")


func _on_event(id: StringName, _at: Vector3, _strength: float) -> void:
	if _counting:
		_seen.append(id)


func _report() -> void:
	var boss_kills := 0
	var kill_larges := 0
	for id in _seen:
		if id == &"boss_kill":
			boss_kills += 1
		elif id == &"kill_large":
			kill_larges += 1
	_check(boss_kills == 1,
			"the boss death played boss_kill once (%d, saw: %s)" % [boss_kills, _ids()])
	_check(kill_larges == 0,
			"and never kill_large, so the row is the only kill it takes (%d)" % kill_larges)


func _ids() -> String:
	var out := PackedStringArray()
	for id in _seen:
		out.append(String(id))
	return ", ".join(out)


func _check(ok: bool, msg: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		_fails += 1


func _finish() -> void:
	if _harness != null:
		_harness.release_all()
	print("TEST feel boss_kill: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
