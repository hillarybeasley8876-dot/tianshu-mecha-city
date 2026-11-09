extends Node3D
## Camera diagnostic harness (camera-aim). Wraps `res://main.tscn` so a windowed drive run can log,
## every physics tick, where the rig is against the player it is supposed to be following, whether a
## cinematic still owns the view, and — in first person — how far the lens sits from the cockpit eye
## the rig is aiming at. With `--probe-luma=1` it also samples the rendered frame every frame and
## writes its mean luma, which is the "no black frame" gate for the cockpit view.
##
##   tools/godot.sh drive --scene=res://player/camera/demo/rig_probe.tscn \
##       --timeline=res://player/camera/demo/timeline_fp_run.json --out=camera-aim_fp \
##       --skip-menu --probe-log=/abs/path.csv --probe-luma=1 [game flags]
##
## Flags: --probe-log=<abs.csv>, --probe-luma=1, --probe-dump-at=<s> / --probe-dump-radius=<m>
## (one-shot dump of every visual instance near the lens), --fp-hide=<NodeName,…> (blank those nodes
## every tick, to bisect what covers the lens), --fp-nofx=1 (Feel.intensity 0: every screen effect off).

const MAIN := "res://main.tscn"
const CockpitFrame := preload("res://player/camera/cockpit_frame.gd")

## Luma is sampled on a grid rather than over every pixel: a full 1600x900 readback per frame costs
## more than the frame, and 48x27 samples are plenty to catch "the screen went black".
const LUMA_COLS := 48
const LUMA_ROWS := 27

var _log: FileAccess = null
var _luma: bool = false
var _t: float = 0.0
var _rows: int = 0
var _dumped: bool = false
var _last_luma: float = 1.0


func _ready() -> void:
	process_priority = 1000   # measure after the player, the hero model and the rig have all ticked
	add_child((load(MAIN) as PackedScene).instantiate())
	_luma = Game.flag("probe-luma", "") != ""
	if Game.flag("fp-nofx", "") != "":
		Feel.intensity = 0.0
	var path := Game.flag("probe-log", "")
	if path == "":
		return
	_log = FileAccess.open(path, FileAccess.WRITE)
	if _log == null:
		push_error("RigProbe: cannot write " + path)
		return
	_log.store_line("t,cine,fp,arm,fov,follow_err,on_screen,cam_dy,cam_res,luma,inside,rig_res,dip,hero_h,hero_cx,hero_cy,occ")


func _process(_delta: float) -> void:
	if _luma:
		_last_luma = _mean_luma()
	_hide()
	if Game.flag("fp-nofx", "") != "":
		Feel.intensity = 0.0


## Measured in `_physics_process` with `process_priority = 1000`, i.e. AFTER the player, the hero model
## and the rig have all run this tick. Anything else compares the rig against a socket it could not
## have seen yet: the hero's Skeleton3D updates its bone attachments on the idle frame, so a probe that
## read the socket from `_process` measures one frame of the model's own animation (up to 1 m on a hard
## landing crouch) and blames the camera for it.
func _physics_process(delta: float) -> void:
	if _log == null:
		return
	var rig := Game.camera_rig as Node3D
	var p := Game.player as Node3D
	if rig == null or p == null:
		return
	_t += delta
	_rows += 1
	var cam := rig.call(&"camera") as Camera3D
	var socket := _socket(p)
	var state := rig.call(&"hud_state") as Dictionary
	_log.store_line("%.3f,%s,%.3f,%.2f,%.1f,%.2f,%.3f,%.3f,%.3f,%.4f,%s,%.4f,%.3f,%.4f,%.4f,%.4f,%d" % [
		_t, state[&"cinematic"], float(rig.call(&"first_person_blend")),
		float(state[&"arm_length"]), float(state[&"fov"]),
		rig.global_position.distance_to(_follow(rig, p)),
		_on_screen(cam, p), cam.global_position.y - socket.y,
		cam.global_position.distance_to(_socket(p)), _last_luma, _inside(cam),
		float(rig.call(&"eye_residual")),
		cam.global_position.y - rig.global_position.y,
		_hero_box(cam, p)[0], _hero_box(cam, p)[1], _hero_box(cam, p)[2], _blocked(cam, p)])
	if not _dumped and _t > float(Game.flag("probe-dump-at", "1e9")):
		_dumped = true
		_dump(p, cam)
	_log.flush()


## The hero's screen box as [height, centre_x, centre_y] in frame fractions, computed analytically for
## a 16:9 frame so the numbers match the 1600x900 captures and do not depend on the window size. This
## is the lead's flight gate: >= 1/5 of the frame height, centre inside 0..1.
func _hero_box(cam: Camera3D, p: Node3D) -> Array:
	var box := AABB(p.global_position - Vector3(4.0, 8.0, 4.0), Vector3(8.0, 16.0, 8.0))
	var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for xi in 2:
		for yi in 2:
			for zi in 2:
				var v := box.position + Vector3(box.size.x * xi, box.size.y * yi,
						box.size.z * zi) - cam.global_position
				var d := v.dot(-cam.global_basis.z)
				if d < 0.1:
					return [0.0, -1.0, -1.0]
				var n := Vector2(v.dot(cam.global_basis.x) / (d * tan_v * (16.0 / 9.0)),
						v.dot(cam.global_basis.y) / (d * tan_v))
				lo = lo.min(n)
				hi = hi.max(n)
	return [(hi.y - lo.y) * 0.5, (lo.x + hi.x) * 0.25 + 0.5, 0.5 - (lo.y + hi.y) * 0.25]


## 1 when world geometry sits between the lens and the hero's chest.
func _blocked(cam: Camera3D, p: Node3D) -> int:
	var params := PhysicsRayQueryParameters3D.create(cam.global_position, _follow(Game.camera_rig, p))
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	return 0 if get_world_3d().direct_space_state.intersect_ray(params).is_empty() else 1


## The shake node's rotation in degrees (trauma noise + kick + landing dip live there).
func _shake_rot(rig: Node3D) -> Vector3:
	var node := rig.get_node_or_null(^"Yaw/Pitch/Shoulder/Arm/Shake") as Node3D
	return Vector3.ZERO if node == null else node.rotation * 57.29578


## The direction the lens actually faces, rounded: two frames that differ here are looking at
## different things even when the rig has not moved a metre.
func _fwd(cam: Camera3D) -> Vector3:
	return (-cam.global_basis.z).round() * 10.0 / 10.0


## Mean luma of the rendered frame on a LUMA_COLS x LUMA_ROWS grid, 0..1. Reads the viewport's own
## texture, so it sees exactly what a capture would: world, canopy and every CanvasLayer.
func _mean_luma() -> float:
	var tex := get_viewport().get_texture()
	if tex == null:
		return 1.0
	var img := tex.get_image()
	if img == null or img.is_empty():
		return 1.0
	var w := img.get_width()
	var h := img.get_height()
	var total := 0.0
	for y in LUMA_ROWS:
		for x in LUMA_COLS:
			var c := img.get_pixel(int((float(x) + 0.5) * w / LUMA_COLS),
					int((float(y) + 0.5) * h / LUMA_ROWS))
			total += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	return total / float(LUMA_COLS * LUMA_ROWS)


## Where the rig would sit if it were following properly: the chest pivot, or the cockpit eye.
func _follow(rig: Node3D, p: Node3D) -> Vector3:
	if float(rig.call(&"first_person_blend")) > 0.5:
		return _socket(p)
	return p.global_position + Vector3.UP * 12.5


## The exact point the rig's first-person blend is steering the camera at, bob filter included. In
## third person this is the raw socket, which the rig is not following, so the column is only read
## while `fp` > 0.5.
func _eye_target(rig: Node3D, p: Node3D) -> Vector3:
	var blend := rig.get_node_or_null(^"Blend")
	if blend == null:
		return CockpitFrame.eye_point(p)
	return blend.call(&"cockpit_point", p) as Vector3


func _on_screen(cam: Camera3D, p: Node3D) -> float:
	if cam.is_position_behind(p.global_position):
		return -1.0
	var uv := cam.unproject_position(p.global_position) / Vector2(cam.get_viewport().get_visible_rect().size)
	return uv.y


func _socket(p: Node3D) -> Vector3:
	return _named_socket(p, &"cockpit")


func _named_socket(p: Node3D, key: StringName) -> Vector3:
	if not p.has_method(&"model"):
		return p.global_position
	var model := p.call(&"model") as Node3D
	if model == null or not model.has_method(&"socket"):
		return p.global_position
	var s := model.call(&"socket", key) as Node3D
	return s.global_position if s != null else model.global_position


## What the camera volume overlaps right now on MASK_SIGHT (the hero's own meshes have no collider
## there, which is why the visual dump below exists).
func _inside(cam: Camera3D) -> String:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, cam.global_position)
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var names: Array[String] = []
	for hit in space.intersect_shape(params, 4):
		names.append(String((hit["collider"] as Node).name))
	return "/".join(names) if not names.is_empty() else "-"


## `--fp-hide=canopy_glass,CanopyHud` blanks the named nodes every tick, so a capture can bisect which
## piece of geometry is covering the lens.
func _hide() -> void:
	var keep := Game.flag("fp-keep", "")
	if keep != "":
		_keep_only(get_tree().root, get_tree().root, StringName(keep))
	var want := Game.flag("fp-hide", "")
	if want == "":
		return
	for key in want.split(",", false):
		_hide_named(get_tree().root, StringName(key))


## `--fp-keep=Player` blanks every visual instance in the tree that is NOT under the first node with
## that name, which splits "what is covering the lens" into world / hero / canopy in one run each.
func _keep_only(node: Node, root: Node, key: StringName) -> void:
	_tag_keep(root, key)
	for child in _visuals_all(node):
		if not bool(child.get_meta(&"fp_keep", false)):
			child.visible = false


func _tag_keep(node: Node, key: StringName) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).set_meta(&"fp_keep", _under(node, key))
	for c in node.get_children():
		_tag_keep(c, key)


func _under(node: Node, key: StringName) -> bool:
	var n: Node = node
	while n != null:
		if n.name == key:
			return true
		n = n.get_parent()
	return false


func _visuals_all(node: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		found.append(node as VisualInstance3D)
	for c in node.get_children():
		found.append_array(_visuals_all(c))
	return found


func _hide_named(node: Node, key: StringName) -> void:
	if node is Node3D and node.name == key:
		(node as Node3D).visible = false
	for c in node.get_children():
		_hide_named(c, key)


## One-shot dump of every visual instance whose world AABB reaches into the box around the camera,
## nearest first — the hero's own parts and the weapon VFX have no collider on MASK_SIGHT, so a shape
## query cannot see what covers the lens.
func _dump(p: Node3D, cam: Camera3D) -> void:
	var r := float(Game.flag("probe-dump-radius", "8"))
	var probe := AABB(cam.global_position - Vector3.ONE * r, Vector3.ONE * r * 2.0)
	var found: Array = []
	for node in _visuals(get_tree().root):
		var box: AABB = node.global_transform * node.get_aabb()
		if box.intersects(probe):
			found.append(["%s %s@%s" % [node.get_class(), node.name, node.get_parent().name],
					box.get_center().distance_to(cam.global_position)])
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	for f: Array in found.slice(0, 24):
		print("PROBEDUMP %s:%.1f" % [f[0], f[1]])
	print("PROBEDUMP model=%s socket=%s cam=%s muzzle=%s" % [
		(p.call(&"model") as Node3D).global_position, _socket(p), cam.global_position,
		_named_socket(p, &"muzzle_r")])


func _visuals(node: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if node is VisualInstance3D and (node as VisualInstance3D).visible:
		found.append(node as VisualInstance3D)
	for c in node.get_children():
		found.append_array(_visuals(c))
	return found
