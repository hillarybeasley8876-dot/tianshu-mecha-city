extends Node
## Core test: the README's control table matches the real bindings (tooling item 4).
##   tools/godot.sh test res://core/tests/test_readme_controls.gd
## Every binding in InputSetup's KEYS/MOUSE/AXES tables and PadInput's NORMAL/SHIFTED tables must
## appear, on ONE row of the README's table, together with the other half of its action — and the
## README must not list a binding the code does not have. Delete a row from README.md and this fails.
##
## The README lives at the repo root, one level above res://, so it is read by absolute path.

const InputSetup := preload("res://core/input_setup.gd")
const PadInput := preload("res://core/pad_input.gd")
const README := "../README.md"

## Godot's key/button constants -> the words the README uses.
const KEY_WORDS: Dictionary = {
	KEY_W: "W", KEY_S: "S", KEY_A: "A", KEY_D: "D", KEY_SPACE: "Space", KEY_CTRL: "Ctrl",
	KEY_SHIFT: "Shift", KEY_ALT: "Left Alt", KEY_F: "F", KEY_Q: "Q", KEY_1: "1", KEY_E: "E",
	KEY_C: "C", KEY_Z: "Z", KEY_X: "X", KEY_G: "G", KEY_R: "R", KEY_V: "V", KEY_B: "B",
	KEY_TAB: "Tab", KEY_ESCAPE: "Esc", KEY_F11: "F11", KEY_F3: "F3",
}
const MOUSE_WORDS: Dictionary = {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_WHEEL_DOWN: "Wheel ↓",
	MOUSE_BUTTON_WHEEL_UP: "Wheel ↑",
}
## Mouse motion has no InputMap entry: `look_*` are relative-motion actions and the lock switch is a
## flick, so the README writes one word for both.
const MOUSE_WORD := "Mouse"
const PAD_WORDS: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓",
	JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu",
}
const STICK_WORDS: Dictionary = {JOY_AXIS_LEFT_X: "LS", JOY_AXIS_LEFT_Y: "LS",
	JOY_AXIS_RIGHT_X: "RS", JOY_AXIS_RIGHT_Y: "RS",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	var rows := _read_rows()
	if rows.is_empty():
		print("README CONTROLS TEST 0 checks, 1 failures (no table in %s)" % README)
		print("FAIL")
		get_tree().quit(1)
		return
	_check_actions(rows)
	_check_no_extras(rows)
	print("README CONTROLS TEST %d checks, %d failures" % [_checks, _fails])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("PASS " if ok else "FAIL ") + what)


## The README's controls table: one Dictionary per row, {kb: [tokens], pad: [tokens], verb: String}.
func _read_rows() -> Array[Dictionary]:
	var path := ProjectSettings.globalize_path("res://").path_join(README)
	if not FileAccess.file_exists(path):
		push_error("readme test: no README at " + path)
		return []
	var out: Array[Dictionary] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var row := line.strip_edges()
		if not row.begins_with("|") or row.contains("---"):
			continue
		var cols := row.trim_prefix("|").trim_suffix("|").split("|")
		if cols.size() < 3 or cols[0].strip_edges() == "Verb":
			continue
		out.append({"verb": cols[0].strip_edges(),
				"kb": _tokens(cols[1]), "pad": _tokens(cols[2])})
	return out


func _tokens(cell: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var rest := cell
	while true:
		var a := rest.find("`")
		if a < 0:
			break
		var b := rest.find("`", a + 1)
		if b < 0:
			break
		out.append(rest.substr(a + 1, b - a - 1))
		rest = rest.substr(b + 1)
	return out


## Every action's keyboard half and gamepad half must sit on the SAME row.
func _check_actions(rows: Array[Dictionary]) -> void:
	for action: StringName in InputSetup.KEYS:
		for key: int in InputSetup.KEYS[action]:
			var word: String = KEY_WORDS.get(key, "")
			if word == "":
				push_error("readme test: no README word for key %d on %s" % [key, action])
				continue
			_check(_on_one_row(rows, word, _pad_words(action)), "%s: `%s` + %s on one row"
					% [action, word, _pad_words(action)])
	for action: StringName in InputSetup.MOUSE:
		for button: int in InputSetup.MOUSE[action]:
			var word: String = MOUSE_WORDS.get(button, "")
			if word == "":
				push_error("readme test: no README word for mouse button %d on %s" % [button, action])
				continue
			_check(_on_one_row(rows, word, _pad_words(action)), "%s: `%s` + %s on one row"
					% [action, word, _pad_words(action)])
	for action: StringName in InputSetup.AXES:
		var axis: int = InputSetup.AXES[action][0]
		var word: String = STICK_WORDS.get(axis, "")
		if word == "":
			continue
		# The look_* and move_* axes are driven by the mouse and the keyboard too, so their keyboard
		# half is the one word the README uses for mouse motion.
		var kb := MOUSE_WORD if String(action).begins_with("look_") else _kb_words(action)
		_check(_row_with(rows, word).size() > 0 and _on_one_row(rows, kb, [word]),
				"%s: %s + `%s` on one row" % [action, kb, word])
	# PadInput's own tables: normal, shifted (RB + face button) and the L3+R3 chord.
	for button: int in PadInput.NORMAL:
		var word: String = PAD_WORDS.get(button, "")
		if word == "":
			push_error("readme test: no README word for pad button %d" % button)
			continue
		_check(_row_with(rows, word).size() > 0, "pad %s: `%s` is in the table"
				% [PadInput.NORMAL[button], word])
	for button: int in PadInput.SHIFTED:
		var shifted := "RB+" + String(PAD_WORDS.get(button, "?"))
		_check(_row_with(rows, shifted).size() > 0, "pad %s: `%s` is in the table"
				% [PadInput.SHIFTED[button], shifted])
	_check(_row_with(rows, "L3+R3").size() > 0, "pad overdrive: `L3+R3` is in the table")
	_check(_row_with(rows, "RB+RT").size() > 0, "pad missiles: `RB+RT` is in the table")


## The README must not invent a binding.
func _check_no_extras(rows: Array[Dictionary]) -> void:
	var known_kb: Dictionary = {}
	for k: int in KEY_WORDS:
		known_kb[KEY_WORDS[k]] = true
	for b: int in MOUSE_WORDS:
		known_kb[MOUSE_WORDS[b]] = true
	known_kb[MOUSE_WORD] = true
	var known_pad: Dictionary = {}
	for b: int in PAD_WORDS:
		known_pad[PAD_WORDS[b]] = true
	for a: int in STICK_WORDS:
		known_pad[STICK_WORDS[a]] = true
	for b: int in PadInput.SHIFTED:
		known_pad["RB+" + String(PAD_WORDS.get(b, "?"))] = true
	known_pad["L3+R3"] = true
	known_pad["RB+RT"] = true
	for row: Dictionary in rows:
		for t in row["kb"]:
			_check(known_kb.has(t), "keyboard cell `%s` (%s) is a real binding" % [t, row["verb"]])
		for t in row["pad"]:
			_check(known_pad.has(t), "gamepad cell `%s` (%s) is a real binding" % [t, row["verb"]])


## The keyboard half of an action: its first key, else its first mouse button, else mouse motion.
func _kb_words(action: StringName) -> String:
	for key: int in InputSetup.KEYS.get(action, []):
		return KEY_WORDS.get(key, "")
	for button: int in InputSetup.MOUSE.get(action, []):
		return MOUSE_WORDS.get(button, MOUSE_WORD)
	return MOUSE_WORD


func _pad_words(action: StringName) -> Array:
	var out: Array = []
	for button: int in PadInput.NORMAL:
		if PadInput.NORMAL[button] == action:
			out.append(PAD_WORDS.get(button, ""))
	for button: int in PadInput.SHIFTED:
		if PadInput.SHIFTED[button] == action:
			out.append("RB+" + String(PAD_WORDS.get(button, "")))
	if action == &"missiles":
		out.append("RB+RT")
	if action == &"overdrive":
		out.append("L3+R3")
	if action == &"reload" or action == &"weapon_next":
		out.append("D-pad ↑")
	if action == &"fire":
		out.append("RT")
	return out


func _row_with(rows: Array[Dictionary], token: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in rows:
		if token in row["kb"] or token in row["pad"]:
			out.append(row)
	return out


## True when ONE row carries the keyboard token and every gamepad token the action has.
func _on_one_row(rows: Array[Dictionary], kb: String, pads: Array) -> bool:
	for row: Dictionary in rows:
		if not (kb in row["kb"]):
			continue
		var all := true
		for p: String in pads:
			if p != "" and not (p in row["pad"]):
				all = false
		if all:
			return true
	return false
