extends Node
## Tooling test: the capture clock (tools/capture_clock.gd) that `--times`, `--pulse` and `--key` share.
##   tools/godot.sh test res://tools/tests/test_capture_clock.gd
## The defect it guards (camera-aim r8, Request 6): `--pulse` counted from engine start while
## `--times` counted from world-ready, so a pulse fired about 1.1 s before the shot it was meant to
## line up with. One origin for all three, and nothing fires before it.

const Clock := preload("res://tools/capture_clock.gd")

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	_clock_tests()
	print("CAPTURE CLOCK TEST %d checks, %d failures" % [_checks, _fails])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("PASS " if ok else "FAIL ") + what)


func _clock_tests() -> void:
	var c := Clock.new()
	_check(not c.started(), "a fresh clock has not started")
	_check(c.now() == 0.0, "now() is 0 before start()")
	c.advance(5.0)
	_check(not c.due(0.1), "nothing is due before start(), however much time passed")
	_check(c.now() == 0.0, "... and now() still reads 0")

	c.start()
	_check(c.started(), "start() begins the timed phase")
	_check(is_equal_approx(c.now(), 0.0), "now() is 0 at the origin, not the accumulated time")
	_check(c.due(0.0), "t=0 is due at the origin")

	# The 1.1 s the old code was out by: after the world build, the timed phase starts from 0 again.
	c.advance(1.1)
	_check(is_equal_approx(c.now(), 1.1), "now() counts from the origin, not from engine start")
	_check(c.due(1.0), "a pulse at t=1.0 is due at 1.1 s of the timed phase")
	_check(not c.due(1.2), "a shot at t=1.2 is not due yet")

	c.advance(0.2)
	_check(is_equal_approx(c.now(), 1.3), "the clock keeps counting")
	_check(c.due(1.2), "... and the shot at t=1.2 is now due")
	_check(c.due(1.2), "due() stays true once passed (it is a level, not an edge)")

	# A second clock must not inherit the first one's origin.
	var d := Clock.new()
	d.advance(100.0)
	d.start()
	d.advance(0.5)
	_check(is_equal_approx(d.now(), 0.5), "two runs have independent origins")

	# start() twice (a re-run of the timed phase) restarts the clock.
	c.start()
	_check(is_equal_approx(c.now(), 0.0), "start() again resets the origin to now")
	_check(not c.due(0.5), "... so an already-passed time is no longer due")
