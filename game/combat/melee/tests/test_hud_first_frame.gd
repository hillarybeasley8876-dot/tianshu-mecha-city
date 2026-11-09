extends Node
## Regression: `MeleeSystem.hud_state()` must answer in the SAME FRAME the component enters the tree,
## before its first physics tick. CONTRACTS §5 has the HUD polling every component's `hud_state()`
## from `_process`; a test-host boot of `res://main.tscn` adds main in a deferred flush AFTER that
## frame's physics step, so the HUD's first poll beats MeleeSystem's first tick. `MeleeSystem` builds
## `charge` / `lunge` / `strike` in `_refresh()`, which only runs from `_physics_process`.
##
## `tools/godot.sh test res://combat/melee/tests/test_hud_first_frame.gd`

const ErrorCounter := preload("res://tools/error_counter.gd")

## The 12 keys documented at melee_system.gd:11-12.
const KEYS: Array[String] = [
	"combo_step", "charging", "lunge_ready", "execution_available", "jackpot", "move",
	"phase", "buffered", "executing", "return_window", "last_hit_usec", "last_hit_kind",
]

var _harness: MeleeTestHarness = null
var _errors: int = 0               ## script errors logged during the last `hud_state()` call
var _first: String = ""            ## the first of them, for the FAIL detail


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_harness = MeleeTestHarness.new(self)
	if not _harness.build():
		_finish()
		return
	var h := _harness
	## Precondition: the system entered the tree in this very physics frame, so no `_refresh()` ran.
	h.check("boot.same_physics_frame_as_add_child",
			h.built_frame == Engine.get_physics_frames(),
			"added on frame %d, polled on frame %d" % [h.built_frame, Engine.get_physics_frames()])
	var state: Variant = _poll(h)
	_check_keys(h, "boot", state)
	h.check("boot.no_errors_logged", _errors == 0, "%d error(s): %s" % [_errors, _first])
	if state is Dictionary:
		var d: Dictionary = state
		h.check("boot.charging_is_float_0", d["charging"] is float and is_zero_approx(d["charging"]),
				"got %s (%s)" % [str(d["charging"]), type_string(typeof(d["charging"]))])
		h.check("boot.lunge_ready_is_bool_false",
				d["lunge_ready"] is bool and not bool(d["lunge_ready"]),
				"got %s (%s)" % [str(d["lunge_ready"]), type_string(typeof(d["lunge_ready"]))])
		h.check("boot.execution_available_is_bool_false",
				d["execution_available"] is bool and not bool(d["execution_available"]),
				"got %s" % str(d["execution_available"]))
	## One physics tick later `_refresh()` has run: the same keys come back with the same types.
	## `h.ticks()` awaits `physics_frame`, which fires at the START of a frame — before the nodes'
	## `_physics_process` — so two awaits are one system tick.
	await h.ticks(2)
	h.check("tick1.parts_built", h.system.charge != null and h.system.lunge != null,
			"charge=%s lunge=%s" % [str(h.system.charge), str(h.system.lunge)])
	var after: Variant = _poll(h)
	_check_keys(h, "tick1", after)
	if state is Dictionary and after is Dictionary:
		_check_types(h, state as Dictionary, after as Dictionary)
	_finish()


## Calls `hud_state()` with the host's error counter attached, so script errors the exit code
## ignores are counted here. Returns Variant: on the unguarded code the call aborts and yields null.
func _poll(h: MeleeTestHarness) -> Variant:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var out: Variant = h.system.hud_state()
	OS.remove_logger(counter)
	_errors = counter.errors
	_first = counter.first_errors[0] if counter.first_errors.size() > 0 else ""
	return out


func _check_keys(h: MeleeTestHarness, tag: String, state: Variant) -> void:
	if state is Dictionary:
		for key in KEYS:
			h.check("%s.key_present.%s" % [tag, key], (state as Dictionary).has(key))
		return
	for key in KEYS:
		h.check("%s.key_present.%s" % [tag, key], false,
				"hud_state() returned %s" % type_string(typeof(state)))


func _check_types(h: MeleeTestHarness, before: Dictionary, after: Dictionary) -> void:
	for key in KEYS:
		if not before.has(key) or not after.has(key):
			h.check("tick1.same_type.%s" % key, false, "key missing")
			continue
		h.check("tick1.same_type.%s" % key, typeof(before[key]) == typeof(after[key]),
				"%s -> %s" % [type_string(typeof(before[key])), type_string(typeof(after[key]))])


func _finish() -> void:
	var h := _harness
	var failed: int = h.failures.size() if h != null else 1
	print("TEST %d checks, %d failed" % [h.checks if h != null else 0, failed])
	for line in (h.failures if h != null else PackedStringArray(["harness did not build"])):
		print("TEST FAIL ", line)
	get_tree().quit(1 if failed > 0 else 0)
