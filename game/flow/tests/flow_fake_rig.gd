class_name FlowFakeRig
extends Node3D
## Stands in for the camera rig in the flow tests (CONTRACTS §5): records the cinematic shot lists and
## their duration, so a scripted beat can be checked headless — the real rig needs a window.

var shots: Array = []
var durations: Array[float] = []
var look_enabled: bool = true
var ended: int = 0
var snaps: int = 0
## The FOV the beat held (`CameraRig.hold_fov`) and the arm length it collapsed to.
var fov_held: float = 0.0
var arm_length: float = -1.0


func request_cinematic(list: Array, seconds: float) -> void:
	shots.append(list)
	durations.append(seconds)


## `FlowHiveCollapse` takes the lens with an EMPTY shot list and places the camera itself (r5b item 2),
## so the rig's own transform is what a collapse check reads.
func hold_fov(degrees: float) -> void:
	fov_held = degrees


func set_arm_length(length: float) -> void:
	arm_length = length


## The real rig re-seats itself behind the hero without easing; flow calls it on every respawn so the
## view never crosses the city to catch up (r5 brief item 1).
func snap_to_player() -> void:
	snaps += 1


func set_look_enabled(on: bool) -> void:
	look_enabled = on


func end_cinematic() -> void:
	ended += 1
