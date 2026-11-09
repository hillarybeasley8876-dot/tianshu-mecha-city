class_name FlowHiveVisual
extends Node3D
## The look of a Hive Spire (蚀巢): monster-assets' `HiveModel` (three damage states, weak-point
## sockets) when it has landed, a grey-box stand-in until then. Either way flow owns the four glowing
## pods and the core glow, because those are the weak points the fight is about (brief §3) and no
## model carries them as separate geometry.
##
## The model is duck-typed (`set_state` / `weak_points` / `socket` / `collision_mesh`) so flow keeps
## compiling and running while monster-assets finishes `hive_model.tscn`.
##
## look/flow.md item 1: the pods are clusters of translucent sacs solved onto the trunk's own visible
## surface, not spheres pushed out to a guessed radius — the guess (13.2 m) was wider than the trunk at
## the top and narrower than its roots, so four flat discs floated in the air beside the spire. The
## spire now collides with the model's hull, so a shot that visually hits the trunk is a shot that
## connects.

const MODEL_SCENE := "res://enemies/models/hive/hive_model.tscn"
const MODEL_SCRIPT := "res://enemies/models/hive_model.gd"
const POD_COLOR := Color(0.62, 0.95, 0.22)
const CORE_COLOR := Color(0.68, 0.32, 1.0)
## Pod ring as fractions of the spire height, used when the model carries no `pod_*` sockets.
const POD_HEIGHT := 0.30
const POD_RING := 0.16
const POD_MIN_HEIGHT := 0.18
## Weak-point footprint as a fraction of the height: the Hurtbox radius (`FlowHiveSpire`) and the sac
## radius both scale off this, so a 60 m spire has a ~4 m sac inside a ~6 m weak point.
const POD_RADIUS := 0.075
const SAC_RADIUS := 0.033
## Radius of the core's torn opening as a fraction of the height — a 10 m wound on a 60 m trunk,
## which is what it takes for the fight's last target to read from a fighting stand 70 m out without
## the collar wrapping past the silhouette of a trunk only ~7 m across at that height.
const CORE_OPENING := 0.085
## The core's sacs, as a fraction of that opening: small enough that four of them read as four bulbs
## inside the wound rather than one sphere covering it.
const CORE_SAC := 0.30
const CORE_HEIGHT := 0.52
## `--core-legacy` builds the core the way it was before flow-look-r1 polish 1 — one flat sac cluster
## laid on the chest face — so the A/B that proves the change comes out of a single run, from the
## same stand, with the same lighting.
const LEGACY_CORE_FLAG := "core-legacy"
## `--flow-verbose` prints where every weak point was solved on the shell.
const VERBOSE_FLAG := "flow-verbose"
## Radius of the grey-box stand-in's trunk, and the fallback the pods sit on when the GLB has no
## collision hull. The real trunk is far thinner than this at the top — see the header.
const TRUNK_RADIUS := 0.22
## Metres the pod anchor sits back inside the shell (`FlowHiveSurface.SINK`), so the sacs grow half
## out of it; the cluster itself steps back out onto the surface.
const POD_SINK := FlowHiveSurface.SINK
const SHAKE_DROP := 4.0            ## 1/s the shake decays at
const SHAKE_REACH := 0.5           ## m the trunk moves at the top of the shake

var height: float = 60.0
var state: StringName = &"intact"
## One MeshInstance3D per pod — every sac of a cluster merged into a single surface (`FlowHivePods`),
## so a burst is a `visible = false` and a spire costs five weak-point draw calls, not twenty.
var pods: Array[MeshInstance3D] = []
## Which pods are still on the trunk. `set_state` must not resurrect a pod that has burst — cracking
## the shell open used to put all four back for a frame.
var pod_alive: Array[bool] = [true, true, true, true]
## The ruptured boil the last 6,000 HP lives in (`FlowHiveCore`) — a torn collar, a dished cavity, the
## sac cluster and the violet lamp. It used to be one flat ellipse on the chest face.
var core: FlowHiveCore = null

var _model: Node3D = null
var _pod_points: Array[Vector3] = []
var _pod_normals: Array[Vector3] = []
var _core_normal: Vector3 = Vector3.FORWARD
var _core_at: Vector3 = Vector3.ZERO
## The shell's radius of curvature across the core's bearing, so the core's collar hugs the trunk
## instead of floating off it (see `FlowHiveCore.build`).
var _core_curve: float = INF
## The trunk's two shells and the solve that puts a weak point on them (`FlowHiveSurface`).
var _surface: FlowHiveSurface = FlowHiveSurface.new()
var _shake: float = 0.0


func build(at_height: float) -> void:
	height = maxf(at_height, 8.0)
	_model = _instance_model()
	if _model == null:
		_model = _procedural()
	_model.name = "Model"
	add_child(_model)
	_surface.load_from(_model, self)
	_resolve_weak_points()
	# 60,000 faces is 2 MB a spire and nothing outside the solve wants them.
	_surface.drop_skin()
	_build_weak_points()
	set_state(&"intact")


## Pod positions in the spire's local space — flow puts a Hurtbox + Targetable on each. The E2E bot
## scores candidate firing stands against them (flow_debug_view).
func pod_positions() -> Array[Vector3]:
	return _pod_points


## The trunk's surface normal at pod `index` — the acid burst and the scar decal fire along it.
func pod_normal(index: int) -> Vector3:
	return _pod_normals[index] if index >= 0 and index < _pod_normals.size() else Vector3.UP


## Where the core sits once every pod has burst: on the shell's chest face, not on the axis. A core
## at the axis is inside the hull, so no shot can reach it — the fight could not be finished.
func core_position() -> Vector3:
	return _core_at


## The trunk's surface normal at the core — the burst fires along it when the shell gives way.
func core_normal() -> Vector3:
	return _core_normal


## The trunk's own hull as a collision shape, or null when there is no model (the stand-in answers
## with `hull_radius` instead). `FlowHiveSpire` uses this instead of a guessed cylinder.
func hull_shape() -> ConcavePolygonShape3D:
	return _surface.hull_shape()


## The trunk's SHOT collision: a decimated trimesh of the mesh the player actually sees, so every pod
## and the exposed core is the first thing a one-hit shot meets from the open side (r5 brief item 7).
## Null when there is no model — the caller falls back to the hull, then to a cylinder.
func skin_shape() -> ConcavePolygonShape3D:
	return _surface.skin_shape()


func skin_face_count() -> int:
	return _surface.skin_face_count()


## The stand-in trunk's radius at height `y`, for the fallback collision cylinder.
func hull_radius(y: float) -> float:
	var trunk := height * 0.82
	return lerpf(height * TRUNK_RADIUS, height * 0.10, clampf(y / maxf(trunk, 1.0), 0.0, 1.0))


## The triangles of the mesh the player actually sees, in the visual's local space — the tests measure
## how far each pod sits from them. See `FlowHiveSurface` for why the solve does not keep them.
func skin_faces() -> PackedVector3Array:
	return _surface.skin_faces(_model, self)


## Every pod and the core, solved onto the shell: the model's own socket picks the height and the
## bearing, the trunk's visible surface (`FlowHiveSurface`) says where the shell is at that height.
func _resolve_weak_points() -> void:
	_pod_points.clear()
	_pod_normals.clear()
	var sockets := _model_pod_sockets()
	for i in 4:
		var at: Vector3 = sockets[i] if i < sockets.size() else _ring_fallback(float(i))
		var found := _on_shell(_bearing(at, float(i)), at.y)
		_pod_points.append(found[0])
		_pod_normals.append(found[1])
	var core_at := _model_socket(&"core")
	var chest := _model_socket(&"chest")
	var core_y: float = core_at.y if core_at != Vector3.INF else height * CORE_HEIGHT
	var core_bearing: float = atan2(chest.z, chest.x) if chest != Vector3.INF else PI * 0.5
	var core := _on_shell(core_bearing, core_y)
	_core_at = core[0]
	# The face normal is not usable here: the ray along the chest bearing at the core's height lands on
	# a rib of the shell, whose face can lean 40° off the bearing, and a boil stood up along THAT hangs
	# off the side of the trunk. The core gets the bearing itself, tilted by how fast the trunk tapers.
	var dir := Vector3(cos(core_bearing), 0.0, sin(core_bearing))
	_core_normal = Vector3(dir.x, -_surface.slope(core_bearing, core_y), dir.z).normalized()
	# A curvature measured across 0.26 rad lands inside a single rib and comes back as 0.1 m on a 60 m
	# hive; one measured across the collar's OWN angular width averages the trunk instead. The floor is
	# the opening itself, so the collar can wrap as hard as the trunk really does.
	var radial := maxf(Vector2(_core_at.x, _core_at.z).length(), 1.0)
	var opening := height * CORE_OPENING
	var span := clampf(opening / radial, 0.25, 1.1)
	_core_curve = maxf(_surface.curvature(core_bearing, core_y, span), opening)
	if Game.has_flag(VERBOSE_FLAG):
		print("FLOWVIS core %s bearing %.2f y %.1f at %.1f,%.1f,%.1f n %.2f,%.2f,%.2f curve %.1f"
				% [name, core_bearing, core_y, _core_at.x, _core_at.y, _core_at.z,
				_core_normal.x, _core_normal.y, _core_normal.z, _core_curve])


## `[point, normal]` on the shell, or on the stand-in cone when the ray finds no face along that
## bearing.
func _on_shell(bearing: float, y: float) -> Array:
	var found := _surface.solve(bearing, y)
	if not found.is_empty():
		return found
	var dir := Vector3(cos(bearing), 0.0, sin(bearing))
	return [dir * maxf(hull_radius(y) - FlowHiveSurface.SINK, 1.0) + Vector3.UP * y, dir]


## The model's own bearing for a socket, or an even spread when the marker sits on the axis — the four
## pods still end up on four sides of the trunk.
func _bearing(at: Vector3, index: float) -> float:
	var radial := Vector2(at.x, at.z)
	if radial.length() <= height * 0.06:
		return TAU * (index + 0.5) / 4.0
	return atan2(at.z, at.x)


func _ring_fallback(index: float) -> Vector3:
	var a := TAU * (index + 0.5) / 4.0
	return Vector3(cos(a), 0.0, sin(a)) * height * POD_RING + Vector3.UP * height * POD_HEIGHT


func set_state(next: StringName) -> void:
	state = next
	# A destroyed spire is a wreck: nothing left to ring or shake, and the trunk goes back on its base.
	set_physics_process(next != &"destroyed")
	if next == &"destroyed":
		_shake = 0.0
		if _model != null:
			_model.position = Vector3.ZERO
	if _model != null and _model.has_method(&"set_state"):
		_model.call(&"set_state", next)
	# The destroyed mesh replaces the trunk, so the pods and the core go with it.
	var standing := next != &"destroyed"
	for i in pods.size():
		pods[i].visible = standing and pod_alive[i]
	if core != null:
		core.set_open(standing and next == &"cracked")


## One pod is gone (brief §3): its glow goes out and stays out, whatever the shell does afterwards.
## The model's own per-pod glow goes with it when monster-assets' `pod_alive` uniform lands — until
## then the painted bulbs under the sacs stay lit and the cluster is the honest tell.
func burst_pod(index: int) -> void:
	if index < 0 or index >= pod_alive.size():
		return
	pod_alive[index] = false
	if index < pods.size():
		pods[index].visible = false
	if _model != null and _model.has_method(&"set_pod_alive"):
		_model.call(&"set_pod_alive", index, false)
	_shake = 1.0


## The trunk rings where the pod was: the whole 60 m reads the hit, not only the sac that popped.
func shake() -> void:
	_shake = 1.0


## A checkpoint restore puts a burst pod back on the shell, glow and all (SPEC §7.1).
func restore_pod(index: int) -> void:
	if index < 0 or index >= pod_alive.size():
		return
	pod_alive[index] = true
	if _model != null and _model.has_method(&"set_pod_alive"):
		_model.call(&"set_pod_alive", index, true)


## White hit flash on the shell (the model's `set_hit_flash`, a no-op on the stand-in).
func flash(v: float) -> void:
	if _model != null and _model.has_method(&"set_hit_flash"):
		_model.call(&"set_hit_flash", v)


## The pulse moved into `hive_pod.gdshader` (TIME), so nothing here writes a material per frame; what
## is left is the trunk shake, which only runs while a pod burst is ringing out.
func _physics_process(delta: float) -> void:
	if _shake <= 0.0:
		return
	_shake = maxf(_shake - delta * SHAKE_DROP, 0.0)
	if _model == null:
		return
	if _shake <= 0.0:
		_model.position = Vector3.ZERO
		return
	var reach := SHAKE_REACH * _shake * _shake * height / 60.0
	_model.position = Vector3(sin(_shake * 41.0), 0.0, cos(_shake * 33.0)) * reach


# --- the trunk's surface --------------------------------------------------------------------------

# --- model ----------------------------------------------------------------------------------------

func _instance_model() -> Node3D:
	if ResourceLoader.exists(MODEL_SCENE):
		var packed := load(MODEL_SCENE) as PackedScene
		if packed != null:
			return packed.instantiate() as Node3D
	var script := load(MODEL_SCRIPT) as GDScript
	if script != null:
		var node := Node3D.new()
		node.set_script(script)
		return node
	return null


## The model's own pod sockets as positions in the spire's local space: markers named `pod_0..3` as
## authored (monster-assets places them on the glowing bulbs), else any `weak_*` marker high enough on
## the trunk to read as a weak point from the ground. The names come from the model's `weak_points()`
## list, so a missing socket is never probed — `MonsterModel.socket()` warns and answers with its
## visual root. Positions go through `to_local`, so a model scaled to the spire's height is exact.
func _model_pod_sockets() -> Array[Vector3]:
	var named: Array[Vector3] = []
	var weak: Array[Vector3] = []
	for node in _model_weak_nodes():
		var at := to_local(node.global_position)
		if String(node.name).begins_with("pod_"):
			named.append(at)
		elif String(node.name).begins_with("weak_") and at.y >= height * POD_MIN_HEIGHT:
			weak.append(at)
	return named if named.size() == 4 else named + weak


## The rig's weak-point markers (empty when there is no model).
func _model_weak_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _model == null or not _model.has_method(&"weak_points"):
		return out
	for n: Variant in _model.call(&"weak_points"):
		var node := n as Node3D
		if node != null:
			out.append(node)
	return out


func _model_socket(socket_name: StringName) -> Vector3:
	if _model == null or not _model.has_method(&"socket"):
		return Vector3.INF
	var node := _model.call(&"socket", socket_name) as Node3D
	# MonsterModel answers a missing socket with its visual root and a warning, so the name is the
	# only honest test that the socket is really there.
	if node == null or node == _model or StringName(node.name) != socket_name:
		return Vector3.INF
	return to_local(node.global_position)


## Grey-box spire: a tapered trunk, a collar and a crown of spines, so the silhouette still reads as
## a 60 m objective from the far side of the district.
func _procedural() -> Node3D:
	var root := Node3D.new()
	root.name = "StandIn"
	var shell := _glow_material(Color(0.19, 0.16, 0.2), 0.0)
	var trunk := CylinderMesh.new()
	trunk.top_radius = height * 0.10
	trunk.bottom_radius = height * TRUNK_RADIUS
	trunk.height = height * 0.82
	_mesh_at(root, trunk, shell, Vector3.UP * height * 0.41)
	var collar := TorusMesh.new()
	collar.inner_radius = height * 0.16
	collar.outer_radius = height * TRUNK_RADIUS
	_mesh_at(root, collar, shell, Vector3.UP * height * 0.58)
	for i in 5:
		var spine := CylinderMesh.new()
		spine.top_radius = 0.4
		spine.bottom_radius = height * 0.035
		spine.height = height * 0.30
		var a := TAU * float(i) / 5.0
		var m := _mesh_at(root, spine, shell, Vector3(cos(a), 0.0, sin(a)) * height * 0.09
				+ Vector3.UP * height * 0.92)
		m.rotation = Vector3(cos(a) * 0.34, 0.0, -sin(a) * 0.34)
	return root


# --- weak points ----------------------------------------------------------------------------------

## Four pod clusters and the core, each a single merged surface (`FlowHivePods`) stood up on the
## trunk's normal so the sacs grow out of the shell instead of hanging in the air beside it.
func _build_weak_points() -> void:
	var sac := height * SAC_RADIUS
	var seed_base := int(absf(global_position.x * 7.0 + global_position.z * 13.0)) if is_inside_tree() \
			else 0
	for i in _pod_points.size():
		pods.append(FlowHivePods.on_trunk(POD_COLOR, _pod_points[i], _pod_normals[i], sac,
				seed_base + i * 31, POD_SINK))
	var opening := height * CORE_OPENING
	core = FlowHiveCore.build(CORE_COLOR, _core_at + _core_normal * POD_SINK, _core_normal,
			opening, opening * CORE_SAC, seed_base + 977, _core_curve,
			Game.has_flag(LEGACY_CORE_FLAG))
	for pod in pods:
		add_child(pod)
	add_child(core)


func _mesh_at(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.5
	return mat
