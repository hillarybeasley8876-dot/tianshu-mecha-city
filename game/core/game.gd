extends Node
## Game (autoload, core-owned): references to the live scene parts + parsed launch flags.
## Units register themselves here (player in _ready, world when built, camera rig, hud) and read the
## others through it. Launch flags (tools and humans): --skip-menu --sandbox --spawn=x,y,z[,yaw_deg]
## --god --no-enemies --enemies=type:count,... --seed=N --quality=low|medium|high --stub=a,b
## (stub = do not instance that subsystem, e.g. hud, audio, enemies, world).

var player: Node3D = null
var world: Node3D = null          ## set by main when a world scene is instanced (null = no world)
var camera_rig: Node3D = null
var hud: CanvasLayer = null
var flags: Dictionary = {}        ## "--name=value" -> {"name": "value"}, bare "--name" -> "true"
var _world_built: bool = false


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var eq := arg.find("=")
			flags[arg.substr(2, eq - 2) if eq > 0 else arg.substr(2)] = arg.substr(eq + 1) if eq > 0 else "true"


func flag(name: String, default: String = "") -> String:
	return String(flags.get(name, default))


func has_flag(name: String) -> bool:
	return flags.has(name)


func stubbed(subsystem: String) -> bool:
	return subsystem in flag("stub").split(",", false)


## Tool runs (tools/godot.sh shot/run/drive/movie/perf export MC_TOOL_WINDOW=1) share the user's desktop:
## windowed in the bottom-right corner of the usable screen, never fullscreen (a fullscreen window takes a
## whole macOS Space), never on top, and it does not take keyboard focus. The window size is untouched, so
## captures and Movie Maker keep their resolution.
func _ready() -> void:
	if OS.get_environment("MC_TOOL_WINDOW") == "1" and DisplayServer.get_name() != "headless":
		_tool_window.call_deferred()


func _tool_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := DisplayServer.window_get_size()
	DisplayServer.window_set_position(screen.position + (screen.size - size).max(Vector2i.ZERO))


## F11 (`toggle_fullscreen`, core/input_setup.gd) flips the window between fullscreen and windowed.
## The game starts fullscreen (project.godot window/size/mode); tool runs are windowed by _tool_window.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full
				else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()


func register_player(p: Node3D) -> void:
	player = p
	Events.player_spawned.emit(p)


## The world calls this once its geometry/navigation is ready (tools wait for it before scripting).
func mark_world_built() -> void:
	_world_built = true
	Events.world_ready.emit()


func world_built() -> bool:
	return _world_built


## Spawn transform from --spawn=x,y,z[,yaw_deg]; `fallback` otherwise.
func spawn_transform(fallback: Transform3D) -> Transform3D:
	var spec := flag("spawn")
	if spec == "":
		return fallback
	var v := spec.split(",")
	if v.size() < 3:
		push_error("Game: --spawn needs x,y,z[,yaw]: " + spec)
		return fallback
	var basis := Basis(Vector3.UP, deg_to_rad(float(v[3]))) if v.size() > 3 else Basis.IDENTITY
	return Transform3D(basis, Vector3(float(v[0]), float(v[1]), float(v[2])))
