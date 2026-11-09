extends Node3D
## city-art vista scene (world/art/tests/vistas.tscn). Instances city-build's city — which now instances
## `environment.tscn` and dresses itself (CONTRACTS §7 "Art integration") — reads the dressing counters
## back, and writes `cameras.json` so `tools/godot.sh shot --cams=res://world/art/tests/cameras.json`
## captures the ART.md §8 vistas.
##   tools/godot.sh shot --scene=res://world/art/tests/vistas.tscn --out=art_V1 --env-only \
##     --cams=res://world/art/tests/cameras.json
##   ... --tod=0.5 / --tod=1.0 for the mid and boss passes, --quality=low for the low preset.

const CITY_SCENE := "res://world/city.tscn"
const CAMERAS := "res://world/art/tests/cameras.json"
# city-art r12 §3: the repo root is derived from the project directory, never written down.
const VISTAS_REL := "data/vistas.json"
## `data/vistas.json` is lead-owned and outside `res://`, so the path is derived from where the
## checkout actually is. Lazy, because a static initialiser runs before the autoloads exist.
static var _vistas: String = ""


static func vistas_path() -> String:
	if _vistas.is_empty():
		_vistas = ArtRepo.at(VISTAS_REL)
	return _vistas
const PERF_WARM := 60          ## frames to settle a new camera before sampling
const PERF_SAMPLE := 30        ## frames averaged for the frame-time number

var city: Node3D
var dressed: int = 0
var swapped: int = 0
var probes: int = 0


func _ready() -> void:
	city = _instance_city()
	_write_cameras()
	# The Spire lights raycast the built tower, so their counters only exist after a physics frame.
	for i in 3:
		await get_tree().physics_frame
	var art := _art()
	if art == null:
		push_error("VISTAS no ArtIntegration node — city.tscn did not instance environment.tscn")
	else:
		dressed = art.props
		swapped = art.surfaces
		probes = art.probes
	print("VISTAS city=%s props=%d surfaces=%d probes=%d spire=%d/%d mask=%d skyline=%d signs=%d"
		% [city != null, dressed, swapped, probes,
		   art.spire_strips if art != null else 0, art.spire_rings if art != null else 0,
		   art.mask_buildings if art != null else 0, art.skyline_surfaces if art != null else 0,
		   art.signs if art != null else 0])
	if Game.has_flag("art-perf"):
		_perf_run.call_deferred()


## The dressing and the material swap now happen inside the city (CONTRACTS §7 "Art integration"), so
## the harness only reads the counters back instead of doing the work itself.
func _art() -> CityArt:
	var env := city.get_node_or_null(^"ArtEnvironment") if city != null else null
	return env.get_node_or_null(^"ArtIntegration") as CityArt if env != null else null



## `--art-perf` walks the vista cameras and prints draw calls, primitives and frame time at each, which
## is the brief's "perf numbers at each vista". RenderingServer counters read 0 until two frames have
## rendered, so every camera gets a settle period first.
func _perf_run() -> void:
	var cams := _vista_cameras()
	if cams.is_empty():
		push_error("vistas: --art-perf needs the vista cameras; %s missing" % vistas_path())
		get_tree().quit(1)
		return
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 6000.0
	add_child(cam)
	print("PERF %-4s %10s %12s %10s %10s" % ["cam", "draw_calls", "primitives", "frame_ms", "fps"])
	for c in cams:
		cam.fov = float(c["fov"])
		cam.position = Vector3(c["pos"][0], c["pos"][1], c["pos"][2])
		cam.look_at(Vector3(c["look"][0], c["look"][1], c["look"][2]), Vector3.UP)
		cam.current = true
		await _frames(PERF_WARM)
		var t0 := Time.get_ticks_usec()
		await _frames(PERF_SAMPLE)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(PERF_SAMPLE)
		print("PERF %-4s %10d %12d %10.2f %10.1f" % [c["name"],
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			ms, 1000.0 / maxf(ms, 0.001)])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _vista_cameras() -> Array:
	if not FileAccess.file_exists(CAMERAS):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMERAS))
	return parsed if parsed is Array else []


## city.gd instances `environment.tscn` itself now; the placeholder removal stays only as a guard for a
## city build that still ships its own blockout sky.
func _instance_city() -> Node3D:
	if not ResourceLoader.exists(CITY_SCENE):
		push_error("vistas: %s does not exist yet — city-build has not exported the city" % CITY_SCENE)
		return null
	var packed := load(CITY_SCENE) as PackedScene
	var node := packed.instantiate() as Node3D
	add_child(node)
	for placeholder in [^"BlockoutEnvironment", ^"Sun"]:
		var n := node.get_node_or_null(NodePath(placeholder))
		if n != null:
			print("VISTAS removing city placeholder ", placeholder)
			node.remove_child(n)
			n.queue_free()
	return node


## Writes the ART.md §8 vista cameras in the format tools/godot.sh shot expects.
func _write_cameras() -> void:
	if not FileAccess.file_exists(vistas_path()):
		push_warning("vistas: %s missing — using the built-in defaults" % vistas_path())
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(vistas_path()))
	if not (parsed is Dictionary):
		push_error("vistas: %s is not a JSON object" % vistas_path())
		return
	var rows: Array = []
	for v in (parsed as Dictionary).get("vistas", []):
		rows.append({"name": String(v["id"]), "pos": v["pos_godot"], "look": v["look_godot"],
			"fov": float(v.get("fov", 55.0))})
	var f := FileAccess.open(CAMERAS, FileAccess.WRITE)
	if f == null:
		push_error("vistas: cannot write %s (error %d)" % [CAMERAS, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(rows, "  "))
	f.close()
	print("VISTAS wrote %d cameras to %s" % [rows.size(), CAMERAS])
