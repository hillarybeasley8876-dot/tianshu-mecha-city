extends CanvasLayer
## InputQuad (autoload, tooling-owned): the on-screen instrument for the press-to-photon measurement.
## F3 (`debug_toggle`) shows or hides a square in the top-right corner that flips black <-> white on the
## FIRST FRAME DRAWN after a key, mouse-button or pad-button press. The lead films the 120 Hz panel at
## 240 fps and counts frames between the finger and the flip: 50 ms = 12 frames.
##
## It is a measuring instrument, not a game feature:
##   * it never consumes input — no `set_input_as_handled()`, and it reads RAW events in `_input()` so
##     it still sees a press the UI already swallowed (CONTRACTS §3 grants this one exception);
##   * `PROCESS_MODE_ALWAYS`, so it works on the title screen and while the tree is paused;
##   * a CanvasLayer above every HUD layer and above the post-process stack;
##   * off by default, so a shipped run looks like the game.
## It drives nothing in the game and no unit may read it.

## Corner square, in pixels. SPEC's panel is 1600x900; 128 px is well over the 96 px the brief asks for
## and stays legible in a 240 fps phone film.
const SIZE := Vector2(128.0, 128.0)
const MARGIN := 16.0
## CanvasLayer.layer above every HUD layer (hud uses 1..8) and above the post-process CanvasLayers.
const LAYER := 120

var _rect: ColorRect
var _lit: bool = false
var _pending: int = 0        ## presses seen since the last drawn frame
var _enabled: bool = false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "Quad"
	_rect.color = Color(0, 0, 0, 1)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_rect.size = SIZE
	_rect.position = Vector2(-SIZE.x - MARGIN, MARGIN)
	_rect.visible = false
	add_child(_rect)


## Raw events on purpose: an action-only reader would miss a press the menus already consumed, and the
## measurement is about the panel, not about the game.
func _input(event: InputEvent) -> void:
	if not _enabled:
		return
	if (event is InputEventKey and (event as InputEventKey).pressed) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed):
		_pending += 1


## Runs after the frame's input and before it is drawn, so a press lands on the next drawn frame.
func _process(_delta: float) -> void:
	# The InputMap is registered at runtime (InputSetup.register_actions, called by the tool hosts and
	# by camera_rig.gd), and this autoload ticks from frame 0 — polling an action that is not there yet
	# logs an engine ERROR every frame (`tools/godot.sh check` caught one). Ask the map first.
	if InputMap.has_action(&"debug_toggle") and Input.is_action_just_pressed(&"debug_toggle"):
		set_enabled(not _enabled)
	if _enabled and _pending > 0:
		# Count, not a flag: two presses inside one frame flip twice, so a 240 fps film never loses an
		# edge to a coincidence.
		_lit = (_pending % 2 == 1) != _lit
		_pending = 0
		_rect.color = Color(1, 1, 1, 1) if _lit else Color(0, 0, 0, 1)


func set_enabled(on: bool) -> void:
	_enabled = on
	_rect.visible = on
	_pending = 0


func is_enabled() -> bool:
	return _enabled


## Telemetry for the quad test and for a film: true = the square is white right now.
func is_lit() -> bool:
	return _lit
