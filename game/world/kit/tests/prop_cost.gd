extends Node3D
## Measures what the props cost at a spawn (city-kit r10). The shipped `perf_probe.gd` only descends
## one level under World, and the props live at `World/ArtEnvironment/Dressing`, so it never reported
## them. This boots main.tscn, waits for the world, then hides the Dressing node and reports the
## draws / objects / primitives it was costing, plus the frame time with and without it.
##   tools/godot.sh shot --scene=res://world/kit/tests/prop_cost.tscn --out=propcost --times=99999 \
##       --warm=2 --skip-menu --spawn=-566,26,524,180
## Prints "PROPCOST ..." lines and quits.

const WARM := 150
const SAMPLE := 40

var _main: Node
var _dressing: Node3D
var _phase: int = -1
var _frames: int = 0
var _last_us: int = 0
var _base: Dictionary = {}
var _after: Dictionary = {}
var _fps: PackedFloat64Array = []
var _fps_hidden: PackedFloat64Array = []


func _ready() -> void:
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_run.call_deferred()


func _info() -> Dictionary:
	return {
		"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"objs": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
	}


func _run() -> void:
	var waited := 0.0
	while waited < 240.0 and not bool(Game.call("world_built")):
		await get_tree().process_frame
		waited += get_process_delta_time()
	_dressing = _find(_main, "Dressing")
	if _dressing == null:
		push_error("prop_cost: no Dressing node under the city")
		get_tree().quit(2)
		return
	while _phase < 3:
		await get_tree().process_frame
		_tick()
	_report()


## Phases: -1 warm up, 0 sample with the props shown, 1 sample with them hidden, 2 put them back.
func _tick() -> void:
	var now := Time.get_ticks_usec()
	var dt := float(maxi(now - _last_us, 1))
	_last_us = now
	_frames += 1
	match _phase:
		-1:
			if _frames >= WARM:
				_base = _info()
				_phase = 0
				_frames = 0
		0:
			_fps.append(1e6 / dt)
			if _frames >= SAMPLE:
				_dressing.visible = false
				_phase = 1
				_frames = 0
		1:
			if _frames > 8:
				_fps_hidden.append(1e6 / dt)
			if _frames >= SAMPLE + 8:
				_dressing.visible = true
				_after = _info()
				_phase = 3


func _mean(values: PackedFloat64Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxf(float(values.size()), 1.0)


func _find(node: Node, wanted: String) -> Node3D:
	if node is Node3D and node.name == wanted:
		return node as Node3D
	for child in node.get_children():
		var found := _find(child, wanted)
		if found != null:
			return found
	return null


func _report() -> void:
	var after := _after
	var shown := _mean(_fps)
	var hidden := _mean(_fps_hidden)
	print("PROPCOST draws %d -> %d without props (props %d)"
			% [_base["draws"], after["draws"], int(_base["draws"]) - int(after["draws"])])
	print("PROPCOST prims %d -> %d without props (prop triangles %d)"
			% [_base["prims"], after["prims"], int(_base["prims"]) - int(after["prims"])])
	print("PROPCOST frame %.2f ms with props, %.2f ms without (delta %.2f ms)"
			% [1000.0 / maxf(shown, 0.001), 1000.0 / maxf(hidden, 0.001),
			1000.0 / maxf(shown, 0.001) - 1000.0 / maxf(hidden, 0.001)])
	get_tree().quit(0)
