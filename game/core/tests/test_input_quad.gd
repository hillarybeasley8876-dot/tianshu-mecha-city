extends Node
## Core test: the F3 debug input quad — the press-to-photon instrument (SPEC/ACCEPTANCE §2).
##   tools/godot.sh test res://core/tests/test_input_quad.gd
## One flip per injected key, mouse-button and pad-button press, visible by the NEXT drawn frame; the
## quad is off by default, ignores releases, and never consumes input.

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await _quad_tests()
	print("INPUT QUAD TEST %d checks, %d failures" % [_checks, _fails])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("PASS " if ok else "FAIL ") + what)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _mouse(button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _pad(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## One frame: the flip must be on screen by the time this returns.
func _frame() -> void:
	await get_tree().process_frame


func _quad_tests() -> void:
	var quad := get_node_or_null(^"/root/InputQuad")
	_check(quad != null, "the InputQuad autoload exists (F3 has a consumer)")
	if quad == null:
		return
	_check(not quad.is_enabled(), "the quad is OFF by default")
	_check(not quad.get_child(0).visible, "... and not drawn")

	# Off: a press must not flip anything.
	var before: bool = quad.is_lit()
	_key(KEY_J, true)
	await _frame()
	_check(quad.is_lit() == before, "a press while the quad is off flips nothing")
	_key(KEY_J, false)
	await _frame()

	quad.set_enabled(true)
	_check(quad.is_enabled() and quad.get_child(0).visible, "set_enabled(true) shows the quad")

	var lit: bool = quad.is_lit()
	_key(KEY_J, true)
	await _frame()
	_check(quad.is_lit() != lit, "a key press flips the quad by the next frame")
	lit = quad.is_lit()
	_key(KEY_J, false)
	await _frame()
	_check(quad.is_lit() == lit, "the key RELEASE does not flip it")
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _frame()
	_check(quad.is_lit() != lit, "a mouse-button press flips the quad by the next frame")
	lit = quad.is_lit()
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _frame()
	_check(quad.is_lit() == lit, "the mouse RELEASE does not flip it")
	_pad(JOY_BUTTON_A, true)
	await _frame()
	_check(quad.is_lit() != lit, "a pad-button press flips the quad by the next frame")
	lit = quad.is_lit()
	_pad(JOY_BUTTON_A, false)
	await _frame()
	_check(quad.is_lit() == lit, "the pad RELEASE does not flip it")

	# Two presses in one frame still flip twice (parity), so a film never misses an edge.
	_key(KEY_K, true)
	_pad(JOY_BUTTON_B, true)
	await _frame()
	_check(quad.is_lit() == lit, "two presses in one frame flip twice (back to the same colour)")
	_key(KEY_K, false)
	_pad(JOY_BUTTON_B, false)
	await _frame()

	# F3 toggles it through the real action.
	Input.action_press(&"debug_toggle")
	await _frame()
	Input.action_release(&"debug_toggle")
	await _frame()
	_check(not quad.is_enabled(), "F3 (debug_toggle) turns the quad back off")

	# It must not eat input: a press still reaches the InputMap.
	quad.set_enabled(true)
	_key(KEY_SPACE, true)
	await _frame()
	_check(Input.is_action_pressed(&"jump"), "the quad does not consume input (jump still pressed)")
	_key(KEY_SPACE, false)
	await _frame()

	var rect := quad.get_child(0) as ColorRect
	_check(rect.size.x >= 96.0 and rect.size.y >= 96.0,
			"the quad is at least 96 px square (%.0fx%.0f)" % [rect.size.x, rect.size.y])
	_check(quad.layer > 8, "the quad draws above every HUD layer (layer %d)" % quad.layer)
	_check(quad.process_mode == Node.PROCESS_MODE_ALWAYS, "the quad runs while the tree is paused")
	quad.set_enabled(false)
