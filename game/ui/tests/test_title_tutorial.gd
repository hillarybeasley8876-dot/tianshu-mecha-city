extends Node
## The real title path (hud r6 item 1, `hud-first-tutorial-prompt-dropped-from-title`).
##
## Every other HUD run uses `--skip-menu`, so nothing ever proved what a REAL player sees: the title
## can sit there for as long as they like, the drop-in takes 5.4 s after START, and the flow's first
## `prompt(&"move")` used to meet a queue that had already aged past its lifetime — popped AND retired
## on its first frame, so `W 移动 MOVE` never appeared at all and `MOUSE 环视 LOOK` got 5 s.
##
## This boots `res://main.tscn` with the REAL flow — no `--skip-menu`, no `--sandbox`, no stubs — waits
## `PRESS_AT` seconds after the world is built, presses ENTER through `Input.parse_input_event`
## (`Input.action_press` never reaches `menu_root.gd:_input`, which is why the stock autoplay cannot
## do this), and then logs the tutorial queue's front / age / queued / retired on every change and
## every 0.5 s. The `TITLEPROBE` lines are the table the status file quotes.
##
##   tools/godot.sh test res://ui/tests/test_title_tutorial.gd --timeout=900

const PRESS_AT := 10.0          ## s after the world is built before the player presses START
const PRESS_GAP := 0.4          ## s between the reveal press and the START press
const BUILD_TIMEOUT := 420.0    ## s the city build may take before the probe gives up
const MOVE_HOLD := 6.5          ## s of `move` the flow's own 7 s window must deliver
const LOOK_HOLD := 6.5          ## s of `look` the same window must deliver
const LOG_EVERY := 0.5

var _t: float = 0.0
var _built_at: float = -1.0
var _presses: int = 0
var _next_press: float = -1.0
var _hud: Node = null
var _tut: HudWidget = null
var _front: StringName = &""
var _log_t: float = 0.0
var _checks: int = 0
var _fails: PackedStringArray = PackedStringArray()
## id -> [first seen at, last seen at]
var _seen: Dictionary = {}
var _retired_at_queue: Dictionary = {}   ## id -> the retired set on the frame it reached the front


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("cannot load res://main.tscn")
		_finish()
		return
	add_child(packed.instantiate())
	print("TITLEPROBE boot: main.tscn instanced, waiting for the world")


func _process(delta: float) -> void:
	_t += delta
	if _built_at < 0.0:
		if Game.world != null:
			_built_at = _t
			_next_press = _t + PRESS_AT
			print("TITLEPROBE world built at t=%.2f, START at t=%.2f" % [_built_at, _next_press])
		elif _t > BUILD_TIMEOUT:
			_fail("the world was not built within %.0f s" % BUILD_TIMEOUT)
			_finish()
		return
	if _presses < 2 and _t >= _next_press:
		_press_enter()
		_presses += 1
		_next_press = _t + PRESS_GAP
		print("TITLEPROBE pressed ENTER (%d) at t=%.2f" % [_presses, _t])
	_sample(delta)
	if _presses >= 2 and _t > _built_at + PRESS_AT + 60.0:
		_finish()


## ENTER through the real input pipeline. `Input.action_press` would move the InputMap state and
## nothing else — `menu_root.gd:_input` never sees it.
func _press_enter() -> void:
	var down := InputEventKey.new()
	down.physical_keycode = KEY_ENTER
	down.keycode = KEY_ENTER
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_ENTER
	up.keycode = KEY_ENTER
	up.pressed = false
	Input.parse_input_event(up)


func _sample(delta: float) -> void:
	if _hud == null:
		_hud = Game.hud
		if _hud == null:
			return
		_tut = _hud.call(&"widget", &"tutorial") as HudWidget
		if _tut == null:
			return
		print("TITLEPROBE hud found at t=%.2f" % _t)
	var front := StringName(_tut.call(&"current_id"))
	var age := float(_tut.get(&"age"))
	var queued := int(_tut.call(&"queued"))
	var retired: Dictionary = _tut.get(&"_retired")
	if front != _front:
		_front = front
		if front != &"":
			_seen[front] = [_t, _t]
			_retired_at_queue[front] = retired.keys()
			print("TITLEPROBE front=%s at t=%.2f age=%.2f queued=%d retired=%s visible=%s"
					% [front, _t, age, queued, str(retired.keys()), str(_tut.visible)])
	elif front != &"":
		_seen[front][1] = _t
	_log_t += delta
	if _log_t >= LOG_EVERY:
		_log_t = 0.0
		print("TITLEPROBE t=%.2f front=%s age=%.2f queued=%d retired=%s visible=%s"
				% [_t, front, age, queued, str(retired.keys()), str(_tut.visible)])


func _finish() -> void:
	if _tut != null:
		for id: StringName in [&"move", &"look"]:
			var row: Array = _seen.get(id, [])
			_check(not row.is_empty(), "the title path shows the '%s' prompt at all" % id)
			if row.is_empty():
				continue
			var held := float(row[1]) - float(row[0])
			var want := MOVE_HOLD if id == &"move" else LOOK_HOLD
			_check(held >= want, "the '%s' prompt holds the front for %.1f s (got %.2f)"
					% [id, want, held])
		for id: StringName in [&"move", &"look"]:
			var at: Array = _retired_at_queue.get(id, [])
			_check(not at.has(String(id)),
					"'%s' is not already retired on the frame it reaches the front" % id)
	print("TEST %d checks, %d failed" % [_checks, _fails.size()])
	for line in _fails:
		print("TEST FAIL ", line)
	get_tree().quit(1 if _fails.size() > 0 else 0)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_fails.append(label)


func _fail(label: String) -> void:
	_checks += 1
	_fails.append(label)
	print("FAIL " + label)
