extends SceneTree
## Test host (core-owned): `tools/godot.sh test res://unit/tests/test_x.gd` runs this with
## --test=<path>. The test script is loaded at RUNTIME (after autoloads exist) and must
## `extends Node`: it is added under root, runs its checks (in _ready / _physics_process),
## prints PASS/FAIL lines and calls `get_tree().quit(<0 ok | 1 fail>)`. A SceneTree script cannot
## reference autoloads (Events, Game, ...) or class_name types that use them at compile time,
## which is why tests are Nodes. Timeout: --timeout=<s> (default 300) → exit 2.
##
## A suite that logs a SCRIPT ERROR or an engine ERROR (push_error included) FAILS, whatever it
## printed: "PASS" over two Nil errors is how melee's pair hid for four rounds. Warnings never fail a
## run, and neither do the lines Godot prints while tearing the process down (leaked objects and
## resources). Deliberate negatives and this round's routed reds are listed one by one, with the exact
## message and no wildcards, in res://tools/known_issues.txt; the host prints
## `TEST KNOWN-ERROR <tag> <suite>` for each and does not fail on it.
##
## The suite's own exit code is left alone: `_finalize()` only ever RAISES it to 1, so a suite that
## quit 1 stays 1 and a clean suite that quit 0 stays 0. (GDScript cannot intercept
## `get_tree().quit()` — the native method wins — so the verdict is applied after the loop ends.)

const ErrorCounter := preload("res://tools/error_counter.gd")
const InputSetup := preload("res://core/input_setup.gd")
const KNOWN_ISSUES := "res://tools/known_issues.txt"
## Godot prints these while tearing the process down; they say nothing about the suite.
const EXIT_TIME := ["ObjectDB instances leaked at exit", "were leaked at exit",
		"resources still in use at exit", "RID allocations of type", "still in use at exit"]

var _deadline: float = 300.0
var _t: float = 0.0
var _counter: ErrorCounter
var _suite: String = ""
var _allowed: Dictionary = {}      ## exact message -> tag
var _timed_out: bool = false
var _reported: bool = false


func _initialize() -> void:
	_counter = ErrorCounter.new()
	OS.add_logger(_counter)
	InputSetup.register_actions()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			_suite = arg.trim_prefix("--test=")
		elif arg.begins_with("--timeout="):
			_deadline = float(arg.trim_prefix("--timeout="))
	_allowed = _load_known(_suite)
	var script := load(_suite) as Script
	if script == null:
		push_error("test_host: cannot load test script " + _suite)
		quit(1)
		return
	var node := Node.new()
	node.set_script(script)
	if node.get_script() == null:
		push_error("test_host: %s must `extends Node` (got another base)" % _suite)
		quit(1)
		return
	node.name = "Test"
	root.add_child.call_deferred(node)


func _process(delta: float) -> bool:
	_t += delta
	if _t > _deadline:
		_timed_out = true
		print("TEST TIMEOUT after %.0f s (engine errors so far: %d)" % [_t, _counter.errors])
		for line in _counter.first_errors:
			print("TEST ERROR ", line)
		quit(2)
		return true
	return false


## Runs after the main loop ends, while the process exit code can still be raised.
func _finalize() -> void:
	if _reported:
		return
	_reported = true
	var split := _classify()
	var real: Array = split["real"]
	var known: Array = split["known"]
	for e: Dictionary in known:
		print("TEST KNOWN-ERROR %s %s :: %s" % [_allowed[e["message"]], _suite, e["message"]])
	print("TEST ERRORS %d (known %d, warnings %d)" % [real.size(), known.size(), _counter.warnings])
	for e: Dictionary in real.slice(0, 10):
		print("TEST ERROR %s:%d %s(): [%s] %s" % [e["file"], e["line"], e["function"], e["code"], e["message"]])
	# Only ever raise the code: a suite that already quit 1 keeps its 1, a clean one keeps its 0, and
	# a timeout keeps its 2.
	if not real.is_empty() and not _timed_out:
		quit(1)


## Every error the run logged, minus the exit-time teardown lines, split into the ones this suite is
## allowed to log and the ones that fail it.
func _classify() -> Dictionary:
	var real: Array[Dictionary] = []
	var known: Array[Dictionary] = []
	for e in _counter.entries:
		var msg: String = e["message"]
		if EXIT_TIME.any(func(p: String) -> bool: return msg.contains(p)):
			continue
		if _allowed.has(msg):
			known.append(e)
		else:
			real.append(e)
	return {"real": real, "known": known}


## The allow-list rows for this suite only: {exact message -> tag}.
func _load_known(suite: String) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(KNOWN_ISSUES):
		push_error("test_host: no allow-list at " + KNOWN_ISSUES)
		return out
	for line in FileAccess.get_file_as_string(KNOWN_ISSUES).split("\n"):
		var row := line.strip_edges()
		if row.is_empty() or row.begins_with("#"):
			continue
		var cols := row.split("|")
		if cols.size() < 5:
			push_error("test_host: malformed allow-list row (need 5 fields): " + row)
			continue
		if cols[0] == "error" and cols[1] == suite:
			out[cols[2]] = cols[3]
	return out
