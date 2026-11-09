extends Camera3D
## Follow camera used only while `Game.camera_rig` is null, so mech-move captures and the tour movie
## work before camera-aim lands. It offers the two calls MechLocomotion needs (`yaw_basis`,
## `look_dir`) plus a spring follow; the real rig (CONTRACTS §5) replaces it without any other change.

const PIVOT_HEIGHT := 4.0    ## SPEC §5 chest pivot (11.5 m) above the body origin (7.5 m above the feet)
const DISTANCE := 28.0        ## SPEC §5 spring arm
const SIDE := 3.5            ## SPEC §5: over the right shoulder
const SENSITIVITY := 0.0030
const FOLLOW := 9.0
const PITCH_MIN := -1.2
const PITCH_MAX := 0.9

var yaw: float = 0.0
var pitch: float = -0.1396   ## SPEC §5: default pitch -8 deg


func _ready() -> void:
	current = true
	fov = 55.0  # SPEC §5: Godot FOV is vertical
	var p := _player()
	if p != null:
		global_position = p.global_position + Vector3(0.0, PIVOT_HEIGHT, DISTANCE)


func _unhandled_input(event: InputEvent) -> void:
	# No capture check: this is the stand-in rig, and the tour timeline steers it with injected
	# mouse motion (tools/autoplay.gd "look"/"look_rate") before camera-aim exists.
	if event is InputEventMouseMotion:
		_look((event as InputEventMouseMotion).relative)


## Shared with tests and tools: turn the camera by a relative mouse delta in pixels.
func _look(rel: Vector2) -> void:
	yaw = wrapf(yaw - rel.x * SENSITIVITY, -PI, PI)
	pitch = clampf(pitch - rel.y * SENSITIVITY, PITCH_MIN, PITCH_MAX)


## Horizontal camera orientation: player movement and dash directions are relative to it.
func yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func look_dir() -> Vector3:
	return -global_basis.z


func _process(delta: float) -> void:
	var p := _player()
	if p == null:
		return
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var pivot := p.global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)
	var offset := b * Vector3(SIDE, 0.0, DISTANCE)  # +Z is behind: the camera trails the mech
	global_position = global_position.lerp(pivot + offset, 1.0 - exp(-FOLLOW * delta))
	var up := Vector3.UP if absf((-global_basis.z).dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	look_at(pivot + b * Vector3(SIDE, 0.0, 0.0), up)


func _player() -> Node3D:
	return Game.player as Node3D
