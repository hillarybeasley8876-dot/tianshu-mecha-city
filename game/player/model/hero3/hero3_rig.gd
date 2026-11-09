class_name Hero3Rig
extends Node3D
## Everything on the Tianshu model that is not the animation itself: the CONTRACTS §5 sockets
## (Marker3D under a BoneAttachment3D, offsets from the generated `Hero3Sockets.TABLE`), the weapon
## nodes, the seven blade drones and the backpack thrusters.
##
## The model is ONE rigid-skinned mesh (`Hero3Body`) plus three weapon nodes; the drones are bones
## inside the body mesh, so `set_wings` fans them by rotating their bones.

## bone -> drone index. The 7 blades split 4/3 between `wing_l` and `wing_r` so corona_fins.gd, which
## asks for those two sockets, keeps working.
const DRONE_BONES: Array[String] = ["Drone_1", "Drone_2", "Drone_3", "Drone_4",
		"Drone_5", "Drone_6", "Drone_7"]
## The three nodes `set_saber_drawn` and the rifle swap show and hide. Matched by EXACT name: the body
## mesh is called Hero3Body, and a prefix match swept it in and painted the whole mech cyan.
const WEAPON_NODES: Array[String] = ["Hero3Saber", "Hero3Rifle", "Hero3Shield"]
## The fan: each drone swings out of the folded rest pose by this much at set_wings(1). Owned by
## `Hero3Drones`, re-exported here because the filmstrips and the tests read it off the rig.
const FAN_DEG: Array[float] = Hero3Drones.FAN_DEG
## Thruster nozzles: MEASURED off the mesh by `Hero3Nozzle` at load, not typed here (lead r9 item 2).
## The r8 table guessed a bone, a fraction along it and a hand-typed offset, and added that offset to a
## point that was already in skeleton space while the flame's position is in BONE space -- which is
## how the plumes ended up over the hero's head. There is no calf nozzle on this mesh (measured), so
## there are exactly two plumes, both on the back frame.
## The plume cone's own length, in metres at scale 1. The mouth is at its BASE, so a flame of length L
## has its centre L/2 along the exhaust axis from the nozzle. `Hero3Plume` owns the number now (lead
## r10): it is also the shader's `height` uniform and the axis of every look gate.
const PLUME_LENGTH := Hero3Plume.LENGTH
## The cone's tip radius, in metres — the flame necks down to a point rather than to nothing, so the
## tip still has a fragment to fade out on.
const TIP_RADIUS := 0.04
## cyan -> amber: the seams and the blade edge carry the Tripo atlas's emission, so overdrive is a
## material-level tint rather than a light. `Hero3Shade` owns it now (lead r7): it reaches the body,
## the weapons, the modelled visor and the drone tips, not just the surfaces that already glowed.
## How far the `saber_r` socket sits from the hand bone along the blade, in metres.
const HILT := 1.5

var model: Node3D
var skeleton: Skeleton3D
## Every material decision on the mech, and the modelled light sources (hero-v3 r7).
var shade: Hero3Shade
var glow: Hero3Glow
## The measured rifle barrel: `{"dir": <R_Hand rest basis>, "len": metres}` (lead r4 item 6).
var rifle: Dictionary = {}
## Where the SABER points when `R_Hand`'s euler is zero, in skeleton space. Every blade write in the
## unit is `bone_basis = X * rest`, so the blade direction is `X * blade_rest` and aiming the blade at
## a direction is one quaternion (lead r4 item 7).
var blade_rest: Vector3 = Vector3(0.0, -1.0, 0.0)

var _sockets: Dictionary = {}
## socket -> `[bone index, local transform]`, so `update()` can place them from the bone pose itself.
## `BoneAttachment3D` only refreshes on a process frame, which is not good enough for a gate that
## steps the model by hand and not fast enough for a beam that leaves the muzzle the same tick.
var _socket_local: Dictionary = {}
var _weapons: Dictionary = {}
var _thrusters: Array[MeshInstance3D] = []
## The backpack pair, `{flame, attach, scale}`, re-aimed along the flight path (lead r8 item 3).
var _backpack: Array[Dictionary] = []
## The measured nozzles, `{bone, at, axis, radius}` in bone space (`Hero3Nozzle`).
var _nozzles: Array[Dictionary] = []
## World direction the plumes should run, or ZERO to leave them on their bones.
var _thrust_dir: Vector3 = Vector3.ZERO
var _thruster_mat: ShaderMaterial
var _level: float = 0.0
var _charging: bool = false
var _saber_drawn: bool = true
## The seven blade drones: the fan and the per-drone hide API (lead r8 item 4).
var drones: Hero3Drones
## Leaf bones have no child to measure against; their length is cached on setup.
var rest_length_cache: Dictionary = {}


func setup(model_: Node3D, skeleton_: Skeleton3D) -> void:
	model = model_
	skeleton = skeleton_
	_build_sockets()
	_find_weapons()
	if not plain_shaded():
		shade = Hero3Shade.new()
		shade.name = "Hero3Shade"
		add_child(shade)
		shade.setup(model)
		shade.debug_mask(_flag("hero3-debug"))
		glow = Hero3Glow.new()
		glow.name = "Hero3Glow"
		add_child(glow)
		glow.setup(skeleton, body_mesh(), shade.armour_surface)
	rifle = measure_rifle()
	_place_muzzle(rifle)
	blade_rest = _measure_blade()
	_place_saber(_blade_extent())
	_build_thrusters()
	drones = Hero3Drones.new()
	drones.setup(skeleton, DRONE_BONES, glow)


## Every socket in CONTRACTS §5, built from the table the Blender build emitted.
func _build_sockets() -> void:
	for row: Dictionary in Hero3Sockets.TABLE:
		for socket_name: String in row:
			var info: Dictionary = row[socket_name]
			var bone := skeleton.find_bone(String(info["bone"]))
			if bone < 0:
				push_error("Hero3Rig: socket %s wants missing bone %s" % [socket_name, info["bone"]])
				continue
			var attach := BoneAttachment3D.new()
			attach.name = "Attach_%s" % socket_name
			attach.bone_idx = bone
			skeleton.add_child(attach)
			var marker := Marker3D.new()
			marker.name = "Socket_%s" % socket_name
			marker.position = info["pos"]
			marker.rotation_degrees = info["rot"]
			attach.add_child(marker)
			_sockets[StringName(socket_name)] = marker
			_socket_local[StringName(socket_name)] = [bone, marker.transform]


## Place every socket from the bone pose it hangs on. Called from `update()`.
func _place_sockets() -> void:
	var xf := skeleton.global_transform
	for socket_name: StringName in _socket_local:
		var row: Array = _socket_local[socket_name]
		var marker := _sockets[socket_name] as Node3D
		marker.global_transform = xf * skeleton.get_bone_global_pose(int(row[0])) \
				* (row[1] as Transform3D)


func socket(socket_name: StringName) -> Node3D:
	if not _sockets.has(socket_name):
		push_warning("Hero3Rig: no socket named %s" % socket_name)
		return null
	return _sockets[socket_name]


## Where the saber points with `R_Hand` at euler zero, MEASURED OFF THE MESH: the direction from the
## hand to the furthest vertex it carries, in skeleton space.
##
## The `saber_r` socket in the generated table does NOT agree with the mesh -- its own -Z is 50 deg off
## the blade the modeller actually built -- so aiming the socket axis sent the steel through the floor
## while the socket tip reached happily out to 20 m (lead r4 item 7). The socket is re-placed on the
## measured axis below, so the two agree from here on.
func _measure_blade() -> Vector3:
	var blade := _blade_extent()
	return blade["dir"] if not blade.is_empty() else Vector3(0.0, -1.0, 0.0)


## `{dir, len}` for the saber: the axis in SKELETON space at the rest pose, and how far the steel runs
## along it from the hand.
func _blade_extent() -> Dictionary:
	var hand := skeleton.find_bone("R_Hand")
	var saber := weapon(&"Hero3Saber") as MeshInstance3D
	if hand < 0 or saber == null or saber.skin == null or saber.mesh == null:
		push_warning("Hero3Rig: no saber mesh to measure")
		return {}
	var rest := skeleton.get_bone_global_rest(hand)
	var bind := PackedInt32Array()
	for b in saber.skin.get_bind_count():
		var bone := saber.skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(String(saber.skin.get_bind_name(b)))
		bind.append(bone)
	var far := Vector3.ZERO
	var best := -1.0
	for s in saber.mesh.get_surface_count():
		var arrays := saber.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or verts.is_empty():
			continue
		var per := int(bones.size() / verts.size())
		for i in verts.size():
			var top := -1
			var w := -1.0
			for j in per:
				if weights[i * per + j] > w:
					w = weights[i * per + j]
					top = int(bones[i * per + j])
			if top < 0 or bind[top] != hand:
				continue
			var offset := verts[i] - rest.origin
			if offset.length_squared() > best:
				best = offset.length_squared()
				far = offset
	if best <= 0.0:
		push_warning("Hero3Rig: the saber mesh has no vertices on R_Hand")
		return {}
	return {"dir": far.normalized(), "len": far.length()}


## Put `saber_r` at the steel tip with its -Z along the blade, using the measured mesh.
func _place_saber(blade: Dictionary) -> void:
	var marker := _sockets.get(&"saber_r") as Node3D
	var hand := skeleton.find_bone("R_Hand")
	if marker == null or hand < 0 or blade.is_empty():
		return
	var rest := skeleton.get_bone_global_rest(hand)
	var dir: Vector3 = rest.basis.inverse() * (blade["dir"] as Vector3)
	var back := -dir
	var up := Vector3.UP if absf(back.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(back).normalized()
	# at the HILT, not the tip: the socket is where the blade hangs from and `SaberVisual` runs the
	# energy extension from `blade_length()` metres out along its -Z
	marker.transform = Transform3D(Basis(x, back.cross(x).normalized(), back), dir * HILT)
	if _socket_local.has(&"saber_r"):
		_socket_local[&"saber_r"] = [_socket_local[&"saber_r"][0], marker.transform]


## The rifle's barrel, MEASURED off the mesh rather than assumed: the direction from the hand to the
## furthest vertex the R_Hand carries, and how far out that vertex is. Returns
## `{"dir": <in the R_Hand rest basis>, "len": metres}`.
##
## `muzzle_r` in the generated socket table sits 0.16 m from the hand bone, which is nowhere near the
## barrel tip, and `WeaponContext.aim_dir_from` fires beams out of it (lead r4 item 6).
func measure_rifle() -> Dictionary:
	var fallback := {"dir": Vector3(0.0, 0.0, -1.0), "len": 4.6}
	var hand := skeleton.find_bone("R_Hand")
	var rifle := weapon(&"Hero3Rifle") as MeshInstance3D
	if hand < 0 or rifle == null or rifle.skin == null or rifle.mesh == null:
		push_warning("Hero3Rig: no rifle mesh to measure, the muzzle falls back to 4.6 m")
		return fallback
	var rest := skeleton.get_bone_global_rest(hand)
	var bind := PackedInt32Array()
	for b in rifle.skin.get_bind_count():
		var bone := rifle.skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(String(rifle.skin.get_bind_name(b)))
		bind.append(bone)
	var far := Vector3.ZERO
	var best := -1.0
	for s in rifle.mesh.get_surface_count():
		var arrays := rifle.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or verts.is_empty():
			continue
		var per := int(bones.size() / verts.size())
		for i in verts.size():
			var top := -1
			var w := -1.0
			for j in per:
				if weights[i * per + j] > w:
					w = weights[i * per + j]
					top = int(bones[i * per + j])
			if top < 0 or bind[top] != hand:
				continue
			var offset := verts[i] - rest.origin
			if offset.length_squared() > best:
				best = offset.length_squared()
				far = offset
	if best <= 0.0:
		push_warning("Hero3Rig: the rifle mesh has no vertices on R_Hand")
		return fallback
	return {"dir": (rest.basis.inverse() * far).normalized(), "len": far.length()}


## Put `muzzle_r` at the barrel tip with its -Z along the barrel, using the measured rifle.
func _place_muzzle(rifle: Dictionary) -> void:
	var marker := _sockets.get(&"muzzle_r") as Node3D
	if marker == null:
		return
	var dir: Vector3 = rifle["dir"]
	# the marker's -Z has to run along the barrel, so its +Z runs back down it
	var back := -dir
	var up := Vector3.UP if absf(back.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(back).normalized()
	marker.transform = Transform3D(Basis(x, back.cross(x).normalized(), back),
			dir * float(rifle["len"]))
	# `_place_sockets` rewrites every marker from the local transform captured at build time, so the
	# measured one has to go back into that table or the next frame undoes this
	if _socket_local.has(&"muzzle_r"):
		_socket_local[&"muzzle_r"] = [_socket_local[&"muzzle_r"][0], marker.transform]


## The weapon meshes are skinned, so the glTF importer hangs them under the Skeleton3D rather than
## beside it: the search has to be recursive.
func _find_weapons() -> void:
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and WEAPON_NODES.has(String(node.name)):
			_weapons[StringName(node.name)] = node
		stack.append_array(node.get_children())


func weapon(which: StringName) -> Node3D:
	return _weapons.get(which) as Node3D


## The armour mesh: `Hero3Glow` measures the visor and the vent patches off it.
func body_mesh() -> MeshInstance3D:
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and String(node.name).begins_with("Hero3Body"):
			return node as MeshInstance3D
		stack.append_array(node.get_children())
	push_error("Hero3Rig: no Hero3Body mesh in the model")
	return null


# --- drones -----------------------------------------------------------------------------------------

## The seven blades fold along the back frame at 0 and fan out like the concept sheet at 1.
func set_wings(open: float) -> void:
	drones.set_open(open)


## Hide or show individual blades (skills r4, the Corona Fins): bit `i` set means drone `i` is OUT
## as a fin, so its copy on the back is not drawn. `Drone_1..4` ride `wing_l`, `Drone_5..7` ride
## `wing_r`; `fins_max` is 6, so the lead's mapping keeps `Drone_1` (bit 0) docked for good.
func set_drones_docked(mask: int) -> void:
	drones.set_docked(mask)


## Read-back of the mask `set_drones_docked` was given.
func drones_docked() -> int:
	return drones.docked()


## One drone at a time, 0-based; `deployed` true hides its blade.
func set_drone_deployed(index: int, deployed: bool) -> void:
	drones.set_deployed(index, deployed)


func drone_deployed(index: int) -> bool:
	return drones.is_deployed(index)


## Where drone `index` is mounted, in WORLD space, so a fin leaves its own blade.
func drone_tip(index: int) -> Vector3:
	return drones.tip(index)


# --- thrusters --------------------------------------------------------------------------------------

## Cone flame meshes with an animated additive shader: the old hero's white box quads were what TAA
## smeared into mosaic ghosts (brief root cause #4).
##
## Each flame's BASE sits exactly on its measured nozzle mouth and runs along the measured exhaust
## axis, both in the bone's own frame, so a `BoneAttachment3D` places them with no arithmetic left to
## get wrong (lead r9 item 2).
func _build_thrusters() -> void:
	_nozzles = Hero3Nozzle.measure(skeleton)
	_thruster_mat = Hero3Plume.material()
	if _thruster_mat == null:
		push_error("Hero3Rig: no plume material, so the backpack has no flame")
		return
	# The cone's own radii are GEOMETRY, so they come from the measured mouth, not from the look
	# profile: `rim` in the shader is a fraction of the radius at that height, and a typed radius
	# would put the cap's soft edge somewhere the mesh is not.
	if not _nozzles.is_empty():
		var mouth_radius := _plume_radius(float(_nozzles[0]["radius"]))
		_thruster_mat.set_shader_parameter(&"radius_base", mouth_radius)
		_thruster_mat.set_shader_parameter(&"radius_tip", TIP_RADIUS)
	for spec: Dictionary in _nozzles:
		var bone := skeleton.find_bone(String(spec["bone"]))
		if bone < 0:
			push_error("Hero3Rig: nozzle wants missing bone %s" % spec["bone"])
			continue
		var axis := (spec["axis"] as Vector3).normalized()
		var mouth := spec["at"] as Vector3
		var radius := float(spec["radius"])
		var flame := MeshInstance3D.new()
		flame.name = "Thruster%d" % _thrusters.size()
		flame.mesh = _plume_mesh(radius)
		flame.material_override = _thruster_mat
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# NOT a BoneAttachment3D: those only refresh on a PROCESS frame, so the plume trailed the pack
		# by a frame at 60 fps and by 1.7 m in any gate that steps the model by hand. `_aim_thrusters`
		# places them from the bone pose itself every tick, the same reason `_place_sockets` exists.
		add_child(flame)
		_thrusters.append(flame)
		_backpack.append({"flame": flame, "bone": bone, "mouth": mouth, "axis": axis})
	_aim_thrusters()


## One plume cone: the measured mouth radius at the base, tapering to a point `PLUME_LENGTH` out.
##
## The ring count is not decoration — the shader's radial falloff reads `NORMAL` per fragment, and a
## 14-gon interpolates that badly enough to band. The bottom CAP is load-bearing too: its normal runs
## along the exhaust axis, so it is the only part of the shell that is bright when the plume is seen
## from directly behind (lead r10's close-up camera), where every side fragment is edge-on.
func _plume_mesh(radius: float) -> CylinderMesh:
	var cone := CylinderMesh.new()
	cone.bottom_radius = _plume_radius(radius)
	cone.top_radius = TIP_RADIUS
	cone.height = PLUME_LENGTH
	cone.radial_segments = 20
	cone.rings = 6
	cone.cap_bottom = true
	cone.cap_top = true
	return cone


## The flame's mouth radius, in metres. The measured plate is broad armour and a floor keeps a
## degenerate measurement from producing a plume with no mouth at all.
func _plume_radius(measured: float) -> float:
	return maxf(measured, 0.25)


func bone_length(idx: int) -> float:
	var children := skeleton.get_bone_children(idx)
	if children.is_empty():
		return float(rest_length_cache.get(idx, 1.0))
	return skeleton.get_bone_global_rest(idx).origin.distance_to(
			skeleton.get_bone_global_rest(children[0]).origin)


## The measured nozzles (`Hero3Nozzle`), in each bone's own rest frame. The thruster gate reads them
## so it can measure the flame against the mouth the MESH gave, not against a number typed twice.
func nozzles() -> Array[Dictionary]:
	return _nozzles


## The plume meshes, in nozzle order.
func thruster_nodes() -> Array[MeshInstance3D]:
	return _thrusters


func set_thrusters(level: float) -> void:
	_level = clampf(level, 0.0, 1.0)


## Point the backpack plumes along a world direction (lead r8 item 3). In flight the mech leans into
## its path, which would swing the nozzles -- mounted on the back frame -- up behind it and push the
## thrust downwards; aiming them backwards along the velocity instead is what "the thrusters point
## along the thrust" means. ZERO leaves every nozzle on the bone it is mounted on.
func set_thrust_dir(world_dir: Vector3) -> void:
	_thrust_dir = world_dir if world_dir.length_squared() > 1e-6 else Vector3.ZERO


## Re-aim the backpack pair. Called from `update()` because the attachments' global transforms are
## only current once the skeleton has been posed this tick.
func _aim_thrusters() -> void:
	# The flame's own length and width, straight off the throttle (lead r10 item 2): a grounded mech
	# has a small ember in the middle of the plate, a hover a medium plume, an assault the whole cone.
	# Scaling the NODE rather than fading the shader means the mesh's tip IS the tip of the flame, so
	# the gate measures the plume's real world length instead of a mirrored number.
	var reach := Hero3Plume.reach(_level)
	var wide := Hero3Plume.width(_level)
	for row: Dictionary in _backpack:
		var flame := row["flame"] as MeshInstance3D
		if flame == null:
			continue
		var pose := skeleton.global_transform * skeleton.get_bone_global_pose(int(row["bone"]))
		# the MOUTH stays where the mesh put it; only the direction the flame runs changes
		var dir := (pose.basis * (row["axis"] as Vector3)).normalized()
		if _thrust_dir != Vector3.ZERO:
			dir = _thrust_dir
		# The cone runs -Y (base, on the mouth) to +Y (tip), so a scale of `reach` along Y moves the
		# base to -PLUME_LENGTH * reach / 2; pushing the origin that far along `dir` puts it back on
		# the mouth. The scale is built from the basis's own COLUMNS, i.e. the mesh's own axes (X/Z
		# across the plume, Y along it) -- `Basis.scaled()` scales the GLOBAL axes, which shears a
		# plume whose axis is not a global one and is the same trap r8's `Basis.scaled(float)` hit.
		var axis_basis := _plume_basis(dir)
		flame.global_transform = Transform3D(
				Basis(axis_basis.x * wide, axis_basis.y * reach, axis_basis.z * wide),
				pose * (row["mouth"] as Vector3) + dir * (PLUME_LENGTH * reach * 0.5))


## A rotation that carries the plume mesh's own +Y axis onto `dir`. The cone runs from its wide BASE
## at -Y to its point at +Y, so +Y is the direction the flame travels and the mouth is at -Y.
func _plume_basis(dir: Vector3) -> Basis:
	return Basis(Quaternion(Vector3.UP, dir))


# --- state ------------------------------------------------------------------------------------------

## `--hero3-plain` runs the model with the Blender materials exactly as exported: the A/B baseline the
## r7 readability numbers are measured against, in the same binary as the fix.
func plain_shaded() -> bool:
	return not _flag("hero3-plain").is_empty()


## `--hero3-nopower` keeps every emissive lit through a death: the A/B baseline the r8 power-down gate
## is measured against, in the same binary as the fix (the same discipline as `--hero3-plain`).
func power_down_enabled() -> bool:
	return _flag("hero3-nopower").is_empty()


func _flag(name: String) -> String:
	var loop := Engine.get_main_loop() as SceneTree
	var game: Node = loop.root.get_node_or_null("Game") if loop != null else null
	return String(game.call(&"flag", name, "")) if game != null else ""


func set_overdrive(on: bool) -> void:
	if shade != null:
		shade.set_overdrive(on)


## Power the mech down or back up (lead r8, from the mech-move acceptance). A wreck's emissives go
## out over `Hero3Shade.POWER_TIME`; the revive brings them back.
func set_powered(on: bool) -> void:
	if shade != null:
		shade.set_powered(on)


## A held weapon or melee charge lights the vents with the boost (lead r7 item 1).
func set_charging(on: bool) -> void:
	_charging = on


func set_saber_drawn(on: bool) -> void:
	_saber_drawn = on
	var saber := weapon(&"Hero3Saber")
	if saber != null:
		saber.visible = on


func saber_drawn() -> bool:
	return _saber_drawn


func update(delta: float) -> void:
	_place_sockets()
	drones.update(delta)
	if shade != null:
		shade.set_pulse(_level, _charging)
		shade.update(delta)
		glow.set_state(maxf(_level, shade.tint), shade.tint, shade.power)
		glow.update(delta)
	_aim_thrusters()
	if _thruster_mat != null:
		_thruster_mat.set_shader_parameter(&"level", _level)
		_thruster_mat.set_shader_parameter(&"time_s", float(Time.get_ticks_msec()) * 0.001)
		# A wreck's nozzles go out with the rest of its emissives (lead r8 3b): the ember rides
		# `Hero3Shade.power`, which is 0 on a dead mech and 1 on a live one.
		_thruster_mat.set_shader_parameter(&"idle_glow", Hero3Plume.IDLE_GLOW
				* (shade.power if shade != null else 1.0))


func report() -> Dictionary:
	return {"sockets": _sockets.size(), "weapons": _weapons.size(),
			"thrusters": _thrusters.size(),
			"drones": drones.report(),
			"thruster_level": snappedf(_level, 0.01),
			"shade": shade.report() if shade != null else {"shell": false},
			"glow": glow.report() if glow != null else {"tips": 0}}
