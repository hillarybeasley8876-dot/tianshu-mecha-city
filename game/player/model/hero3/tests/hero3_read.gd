extends Hero3Probe
## hero-v3 r7 — the in-game readability probe (lead brief r7 gate 2).
##
## The lead's finding was that the Tianshu reads as a black silhouette at the trailer's own cameras,
## and "it looks dark" is not a number. For every camera in `cams_read.json` this renders THREE frames
## at the shipping default:
##   <stem>_A.png   the shipping frame (post, glow, temporal upscaler) — what the trailer cuts
##   <stem>_B.png   the same camera with everything hidden except the hero's own meshes
##   <stem>_C.png   the same camera with the hero hidden too: the bare background
##   <stem>_D.png   the same camera with ONLY the modelled light sources (visor, vent, drone tips)
## so `B - C` is an EXACT screen mask of the hero, `D - C` is an exact mask of the accent cores the
## blow-out gate exempts, and `tmp/hero-v3/read.py` can measure, inside them, the share of pixels
## under luma 0.03, the hero's mean luma against a 24 px ring around the mask, and the share that
## clips. No heuristic, no threshold tuning.
##
##   tools/godot.sh shot --scene=res://player/model/hero3/tests/hero3_read.tscn --out=read \
##       --read-cams=res://player/model/hero3/tests/cams_read.json --tod=0.6

const FRAMES_REL := "tmp/hero-v3/read"
## Frames the third-person rig needs to travel to a fresh spawn before its camera is worth copying.
## 240 at 60 fps is 4 s, which covers the 400 m hop between the pier and the s04 arena.
const RIG_SETTLE := 240

var _cam: Camera3D
var _cams: Array = []
var _hidden: Array[GeometryInstance3D] = []
var _hero: Array[GeometryInstance3D] = []
## The modelled light sources, which the blow-out gate exempts ("except the accent cores").
var _cores: Array[GeometryInstance3D] = []


func _ready() -> void:
	boot()
	_cam = Camera3D.new()
	_cam.name = "ReadCamera"
	_cam.near = 0.05
	_cam.far = 6000.0
	add_child(_cam)
	if not _parse():
		get_tree().quit(1)
		return
	_run.call_deferred()


func _parse() -> bool:
	probe_dir(FRAMES_REL)
	warm = int(Game.flag("read-warm", "40"))
	tag = Game.flag("read-tag", "r7")
	var spec := Game.flag("read-cams", "res://player/model/hero3/tests/cams_read.json")
	if not FileAccess.file_exists(spec):
		push_error("hero3_read: camera list %s does not exist" % spec)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(spec))
	if not (parsed is Array) or (parsed as Array).is_empty():
		push_error("hero3_read: %s is not a non-empty JSON array" % spec)
		return false
	_cams = parsed as Array
	print("READ tag=%s cams=%d warm=%d out=%s" % [tag, _cams.size(), warm, out_dir])
	return true


func _run() -> void:
	await wait_world()
	await frames(warm)
	hide_canvas(get_tree().root)
	_collect_hero()
	print("READ hero meshes: %d, accent cores: %d" % [_hero.size(), _cores.size()])
	for c in _cams:
		await _one(c as Dictionary)
	print("READ done")
	get_tree().quit(0)


func _one(c: Dictionary) -> void:
	_teleport(c)
	# the aim happens AFTER the settle: in "game" mode it copies the third-person rig, and the rig
	# lerps toward the player rather than snapping, so a 400 m teleport needs seconds of frames before
	# its arm is where the take would have it. 0.5 s of warm-up left it 95 m out and framed a vista.
	var settle: int = RIG_SETTLE if String(c.get("mode", "fixed")) == "game" else warm
	await frames(settle)
	_aim(c)
	await frames(8)
	var stem := "%s_%s" % [tag, String(c["name"])]
	save_png(await grab(), stem + "_A")
	_hide_world()
	await frames(HIDE_SETTLE)
	save_png(await grab(), stem + "_B")
	_hide(_hero)
	await frames(HIDE_SETTLE)
	save_png(await grab(), stem + "_C")
	_show_all()
	_hide_world()
	_hide(_hero, _cores)
	await frames(HIDE_SETTLE)
	save_png(await grab(), stem + "_D")
	_show_all()
	await frames(4)
	print("READ %-12s done" % String(c["name"]))


## The hero's own geometry: everything under the model node, which includes the weapon nodes the rig
## parents onto the skeleton's bone attachments, the thruster cones and the modelled glow parts.
func _collect_hero() -> void:
	var player := Game.player as Node3D
	if player == null or not player.has_method(&"model"):
		push_error("hero3_read: the player exposes no model()")
		return
	var model := player.call(&"model") as Node3D
	if model == null:
		push_error("hero3_read: model() returned null")
		return
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GeometryInstance3D:
			_hero.append(node as GeometryInstance3D)
			if String(node.name).begins_with("Glow") or String(node.get_parent().name).begins_with("Glow"):
				_cores.append(node as GeometryInstance3D)
		stack.append_array(node.get_children())


func _teleport(c: Dictionary) -> void:
	if not c.has("spawn"):
		return
	var s: Array = c["spawn"]
	(Game.player as Node3D).call(&"debug_teleport", [float(s[0]), float(s[1]), float(s[2])],
			float(s[3]))


## `mode: "game"` COPIES the game's own third-person rig, which is what the s04 combat takes are cut
## from; `mode: "fixed"` places this probe's camera, which is what the s01 / s03 takes are cut from.
func _aim(c: Dictionary) -> void:
	if String(c.get("mode", "fixed")) == "game":
		var game_cam := _game_camera()
		if game_cam == null:
			push_warning("hero3_read: no game camera to copy for %s" % c["name"])
			return
		_cam.global_transform = game_cam.global_transform
		_cam.fov = game_cam.fov
		_cam.current = true
		return
	var pos: Array = c["pos"]
	var look: Array = c.get("look_hero", [0.0, 8.0, 0.0])
	var at := (Game.player as Node3D).global_position \
			+ Vector3(float(look[0]), float(look[1]), float(look[2]))
	_cam.fov = float(c.get("fov", 60.0))
	_cam.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	_cam.look_at(at, Vector3.UP)
	_cam.current = true


## The rig's own third-person camera, searched under `Game.camera_rig`. `get_viewport().get_camera_3d()`
## cannot answer this at all: by the time this runs, THIS probe's camera is the current one from the
## previous shot. The rig's arm is 42 m back and the cockpit camera sits at the eye, so the camera
## FURTHEST from the player is the one the s04 takes are cut from.
func _game_camera() -> Camera3D:
	var player := Game.player as Node3D
	var rig := Game.camera_rig as Node3D
	var best: Camera3D = null
	var best_d := -1.0
	# the rig is a SIBLING of the player (main.gd adds it at the top level and it follows
	# Game.player), so searching the player's own subtree finds nothing
	var stack: Array[Node] = [rig if rig != null else player]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Camera3D and node != _cam:
			var d := (node as Camera3D).global_position.distance_to(player.global_position)
			if d > best_d:
				best_d = d
				best = node as Camera3D
		stack.append_array(node.get_children())
	if best != null:
		print("READ game camera %s at %.1f m from the player" % [best.get_path(), best_d])
	return best


func _hide_world() -> void:
	_hidden.clear()
	_walk(get_tree().root, func(node: GeometryInstance3D) -> void:
		if not _hero.has(node) and node.visible:
			node.visible = false
			_hidden.append(node))


## Hide everything in `nodes` except what is in `keep`.
func _hide(nodes: Array[GeometryInstance3D], keep: Array[GeometryInstance3D] = []) -> void:
	for node in nodes:
		if not keep.has(node) and node.visible:
			node.visible = false
			_hidden.append(node)


func _show_all() -> void:
	for node in _hidden:
		node.visible = true
	_hidden.clear()


func _walk(node: Node, fn: Callable) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			fn.call(child as GeometryInstance3D)
		_walk(child, fn)
