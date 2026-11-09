class_name AudioVoiceQueue
extends Node
## Cockpit AI line scheduler (ref/research/audio-music.md §1.5): one line at a time from a priority
## queue, the same line never repeated within 8 s, three words or fewer.
##
## Playing is delegated to a Callable so the queue stays independent of the voice pool.
##
## Clocks: the repeat guard and the busy window run on AudioClock (game seconds), and the busy window
## also waits for the pool to report the line stopped — a wall clock ended a 1.2 s line after 1.32 s of
## wall time, which is ~0.3 s of footage in a movie capture, so the next line talked over it.

const REPEAT_GUARD_S := 8.0
const MAX_QUEUE := 4
const LINE_TAIL_S := 0.12   ## breath between two lines

## Callable(event_id: StringName) -> bool; returns false when the line could not start.
var emit_line: Callable = Callable()
## Callable(event_id: StringName) -> bool; true while that line is still sounding in the pool.
var line_sounding: Callable = Callable()

var _queue: Array[Dictionary] = []
var _busy_until_s: float = 0.0
var _last_line_at: Dictionary = {}
var _current: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func request(line_id: StringName, priority: float, length_s: float) -> bool:
	if line_id == &"" or not emit_line.is_valid():
		return false
	if _current == line_id or _queue.any(func(entry): return entry["id"] == line_id):
		return false
	if AudioClock.since(float(_last_line_at.get(line_id, -1000.0))) < REPEAT_GUARD_S:
		return false
	if _queue.size() >= MAX_QUEUE:
		var worst := _lowest_priority_index()
		if priority <= _queue[worst]["priority"]:
			return false
		_queue.remove_at(worst)
	_queue.append({"id": line_id, "priority": priority, "length": length_s})
	_queue.sort_custom(func(a, b): return a["priority"] > b["priority"])
	_pump()
	return true


func _pump() -> void:
	if _busy() or _queue.is_empty():
		return
	var entry: Dictionary = _queue.pop_front()
	if not emit_line.call(entry["id"]):
		return
	_current = entry["id"]
	_last_line_at[_current] = AudioClock.now()
	_busy_until_s = AudioClock.now() + float(entry["length"]) + LINE_TAIL_S


## True while a line owns the speaker: the caller's length estimate is the lower bound (so a dropped
## or stolen line still leaves the slot), the pool's own report is the upper one.
func _busy() -> bool:
	if AudioClock.now() < _busy_until_s:
		return true
	return _current != &"" and line_sounding.is_valid() and bool(line_sounding.call(_current))


func _process(_delta: float) -> void:
	if _busy():
		return
	_current = &""
	_pump()


func clear() -> void:
	_queue.clear()
	_current = &""
	_busy_until_s = 0.0


func state() -> Dictionary:
	return {"queued": _queue.size(), "current": _current,
		"busy_for_ms": int(maxf(_busy_until_s - AudioClock.now(), 0.0) * 1000.0),
		"busy": _busy()}


func _lowest_priority_index() -> int:
	var worst := 0
	for i in _queue.size():
		if _queue[i]["priority"] < _queue[worst]["priority"]:
			worst = i
	return worst
