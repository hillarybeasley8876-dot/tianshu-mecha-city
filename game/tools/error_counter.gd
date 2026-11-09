extends Logger
## Counts engine errors/warnings (script errors, failed loads, push_error) so tool scripts can fail
## loudly. Usage: var counter := ErrorCounter.new(); OS.add_logger(counter) ... counter.errors
## `entries` keeps every error's raw text so a caller can filter (the test host's allow-list) or
## classify (script vs engine) instead of only counting.

var errors: int = 0
var warnings: int = 0
## One Dictionary per error: {code, message, file, line, function}. `code` is Godot's own label
## ("SCRIPT ERROR" for a GDScript error, "ERROR" for the engine's), `message` the rationale.
var entries: Array[Dictionary] = []
## Kept for tools that only want a printable list (autoplay.gd, capture.gd).
var first_errors: PackedStringArray = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		warnings += 1
		return
	errors += 1
	var what := rationale if rationale != "" else code
	entries.append({"code": code, "message": what, "file": file, "line": line, "function": function})
	if first_errors.size() < 20:
		first_errors.append("%s:%d %s(): %s" % [file, line, function, what])


func _log_message(_message: String, _error: bool) -> void:
	pass
