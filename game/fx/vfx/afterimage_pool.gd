class_name AfterimagePool
extends Node3D
## Afterimage helper (feel unit): a fading unlit copy of a mesh pose, used by quick boost (3 ghosts),
## perfect dodge (witch time) and overdrive. Callers hand over the MeshInstance3D they want ghosted;
## the pool never duplicates meshes, it only re-points a pooled MeshInstance3D at the same resource,
## so a mech with 12 parts costs 12 slots of the pool and zero allocations per boost.

const MAX_GHOSTS := 48
const DEFAULT_LIFE := 0.18
const CYAN := Color(0.31, 0.9, 1.0)

var _ghosts: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
## Age in unscaled game seconds per slot, stepped in _process. Not a wall-clock birth stamp: the
## skills that spawn ghosts (Rift Step 0.14 s, Overdrive 0.25 s) count player time, and a movie frame
## costs ~70 ms of wall time but 1/60 s of game time.
var _age: PackedFloat64Array = PackedFloat64Array()
var _life: PackedFloat64Array = PackedFloat64Array()
var _next: int = 0


func _ready() -> void:
	for i in MAX_GHOSTS:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(CYAN, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		var mi := MeshInstance3D.new()
		mi.name = "Ghost%d" % i
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_ghosts.append(mi)
		_mats.append(mat)
		_age.append(-1.0)
		_life.append(DEFAULT_LIFE)


## Ghost one mesh at its current world pose.
func spawn_mesh(source: MeshInstance3D, life: float = DEFAULT_LIFE, color: Color = CYAN) -> void:
	if source == null or source.mesh == null or not source.is_visible_in_tree():
		return
	var slot := _take()
	var g := _ghosts[slot]
	g.mesh = source.mesh
	# Godot 4 property name is `skeleton` (the Godot 3 `skeleton_path` does not exist and errored
	# ~1500 times per drive run, which broke the Overdrive afterimages and the Rift Step streak).
	# A skinned mech part has to be pointed at the source's Skeleton3D or the ghost renders in bind
	# pose; the path is re-based because the ghost lives under the VfxLibrary, not under the mech.
	g.skeleton = _rebase_skeleton(g, source)
	g.global_transform = source.global_transform
	# The ghost is culled exactly like the mesh it copies: first person hides the hero's body by
	# layer (camera_hero_cull.gd), and a default-layer ghost would draw it over the cockpit view.
	g.layers = source.layers
	g.visible = true
	_mats[slot].albedo_color = Color(color, 0.5)
	_age[slot] = 0.0
	_life[slot] = maxf(life, 0.02)


## Ghost every MeshInstance3D under `root` (a mech model), capped at MAX_GHOSTS per call.
func spawn(root: Node3D, life: float = DEFAULT_LIFE, color: Color = CYAN) -> int:
	var n := 0
	for mi in _meshes(root):
		if n >= MAX_GHOSTS:
			break
		spawn_mesh(mi, life, color)
		n += 1
	return n


func live_count() -> int:
	var n := 0
	for i in _ghosts.size():
		if _ghosts[i].visible and _age[i] < _life[i]:
			n += 1
	return n


func _process(delta: float) -> void:
	var dt := minf(Feel.real_delta(delta), 0.1)
	for i in _ghosts.size():
		if not _ghosts[i].visible:
			continue
		_age[i] += dt
		var k := 1.0 - _age[i] / _life[i]
		if k <= 0.0:
			_ghosts[i].visible = false
			_ghosts[i].mesh = null
			continue
		_mats[i].albedo_color.a = k * k * 0.5


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _take() -> int:
	for i in _ghosts.size():
		var slot := (_next + i) % _ghosts.size()
		if not _ghosts[slot].visible or _age[slot] >= _life[slot]:
			_next = (slot + 1) % _ghosts.size()
			return slot
	var slot := _next
	_next = (_next + 1) % _ghosts.size()
	return slot


func _rebase_skeleton(ghost: MeshInstance3D, source: MeshInstance3D) -> NodePath:
	if source.skeleton.is_empty():
		return NodePath()
	var skel := source.get_node_or_null(source.skeleton)
	return ghost.get_path_to(skel) if skel != null else NodePath()
