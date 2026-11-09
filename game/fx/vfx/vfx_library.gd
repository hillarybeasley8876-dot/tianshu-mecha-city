class_name VfxLibrary
extends Node3D
## The shared, pooled VFX library (feel unit). Every unit spawns effects through here:
##     get_tree().get_first_node_in_group(&"vfx_library").spawn(&"missile_blast", pos, normal, 1.0)
## Nothing is instantiated at shot time - the pools for all kinds in VfxPresets.POOL are built in
## _ready and recycled (the oldest slot is stolen when a pool runs dry), so 40 blasts in one frame
## cost restarts, not allocations.
##
## Owned pools: particle one-shots (sparks, blasts, dust, steam, thrusters), shockwave rings, flash
## OmniLight3D (max 8), debris RigidBody3D and afterimages. Decal kinds are routed to DecalPool.

const MAX_PENDING := 96   ## chained spawns waiting on a timer (kill_large's 3 blasts)

## Kinds handled by the decal ring buffer instead of the particle pools.
const DECAL_KINDS: Array[StringName] = [&"scorch", &"scorch_ring", &"land_crater", &"bullet_hole",
		&"impact_glow"]
## Spark bursts also leave a brief hot glow on the surface they hit (r2 MUST-FIX 3), so a wall 150 m
## away flashes at the contact point instead of only throwing sub-pixel streaks.
const GLOW_KINDS: Array[StringName] = [&"spark_bullet", &"spark_beam", &"spark_burst"]
## Ring defaults; a caller can override with spawn_ring().
const RING_SECONDS := 0.18
const RING_RADIUS := 8.0
## FEEL.md header: first-person VFX opacity -40 % (the camera rig sets the `fx_opacity` global).
## `fx_opacity` and `fx_pixel_scale` are declared in project.godot [shader_globals], so every fx shader
## compiles in any load order, exports included; this library only sets them.
const FP_OPACITY := 0.6

var lights: FlashLightPool
var debris: DebrisPool
var afterimages: AfterimagePool
var decals: DecalPool
## Feet-contact sparks + dust under the boost skate (hero-v3 r9 item 3). Its own four emitters, so a
## 42 m/s skate never touches the pools above.
var skate: FxSkateTrail

var _nodes: Dictionary = {}    ## kind -> Array[Node3D]
var _free: Dictionary = {}     ## kind -> PackedFloat64Array (real-time seconds the slot frees at)
var _cursor: Dictionary = {}   ## kind -> int (round-robin start)
var _persistent: Dictionary = {}  ## kind -> Array[Node3D] (fire_loop, smoke_column)
var _persistent_used: Dictionary = {}
var _pending: Array[Dictionary] = []
var _warned: Dictionary = {}
var _now: float = 0.0


func _ready() -> void:
	# World VFX freeze with the world: the director runs ALWAYS so Feel keeps ticking, but blasts,
	# particles, debris and glows must not keep simulating (and expiring) behind the pause menu.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# Other units find the library through this group instead of scanning for the class.
	add_to_group(&"vfx_library")
	_now = _clock()
	lights = FlashLightPool.new()
	lights.name = "FlashLights"
	debris = DebrisPool.new()
	debris.name = "Debris"
	afterimages = AfterimagePool.new()
	afterimages.name = "Afterimages"
	decals = DecalPool.new()
	decals.name = "Decals"
	skate = FxSkateTrail.new()
	skate.name = "SkateTrail"
	for child: Node3D in [lights, debris, afterimages, decals, skate]:
		add_child(child)
	for kind: StringName in VfxPresets.POOL:
		_prewarm(kind)
	for kind: StringName in VfxPresets.PERSISTENT:
		_prewarm_persistent(kind)


## First-person VFX opacity (the camera rig calls this; 1.0 = third person, 0.6 = first person).
func set_first_person(first_person: bool) -> void:
	RenderingServer.global_shader_parameter_set(&"fx_opacity", FP_OPACITY if first_person else 1.0)


## Fire one pooled effect. `normal` orients streaks and rings (Vector3.UP = ground); `scale` is a
## size multiplier. Unknown kinds warn once and return false.
func spawn(kind: StringName, at: Vector3, normal: Vector3 = Vector3.UP, scale: float = 1.0) -> bool:
	if kind in DECAL_KINDS:
		return decals.add(kind, at, normal, scale)
	if kind == &"debris":
		debris.burst(at, maxi(int(8.0 * scale), 1), 9.0 * scale, 0.8 * scale)
		return true
	if not _nodes.has(kind):
		if not _warned.has(kind):
			_warned[kind] = true
			push_warning("VfxLibrary: unknown vfx kind '%s' (add it to VfxPresets)" % kind)
		return false
	var slot := _take(kind)
	var node: Node3D = (_nodes[kind] as Array)[slot]
	node.global_position = at
	if node is FxFlashPop:
		# A bare contact flash (impact_star) sizes itself from the configured resting pop.
		node.global_basis = Basis.IDENTITY
		node.call(&"fire", clampf(scale, 0.05, 40.0))
	elif node.has_method(&"fire") and not (node is ShockwaveFx):
		# Composites (FxBlast, FxImpact) size and orient their own children.
		node.global_basis = Basis.IDENTITY
		node.scale = Vector3.ONE
		node.call(&"fire", at, normal, VfxPresets.radius_of(kind), clampf(scale, 0.05, 40.0))
	else:
		var k := clampf(scale, 0.05, 40.0)
		node.global_basis = VfxPresets.facing(normal)
		# A spark emitter is sized through its shader's size_mul (see VfxPresets.set_size_mul), so its
		# culling box keeps matching the real throw; everything else scales the node.
		var sized := node is GPUParticles3D and VfxPresets.set_size_mul(node as GPUParticles3D, k)
		node.scale = Vector3.ONE if sized else Vector3.ONE * k
		if node is ShockwaveFx:
			(node as ShockwaveFx).fire(at, normal, RING_RADIUS * k, RING_SECONDS, VfxPresets.ORANGE)
		else:
			VfxPresets.restart(node)
	_hold(kind, slot, VfxPresets.life_of(kind))
	if kind in GLOW_KINDS:
		decals.add(&"impact_glow", at, normal, clampf(scale, 0.05, 4.0))
	return true


## Capture aid only: slows every real-time VFX node so the feel gallery can photograph the peak
## frame of a 0.18 s ring or a 3-frame flash (`--fx-slow=`). Never called in game.
func set_time_scale(factor: float) -> void:
	var f := maxf(factor, 0.001)
	for kind: StringName in _nodes:
		for node: Node3D in _nodes[kind]:
			_apply_time_scale(node, f)


func _apply_time_scale(node: Node, f: float) -> void:
	if node is ShockwaveFx or node is FxFireball or node is FxFlashPop:
		node.set(&"time_scale", f)
	for child in node.get_children():
		_apply_time_scale(child, f)


## Borrow a continuous emitter (fire_loop, smoke_column) for as long as the caller needs it: a burning
## wreck, a reactor stack. Returns null when the pool is exhausted. Call release_emitter() to give
## it back; the node keeps running until then.
func emitter(kind: StringName, at: Vector3, scale: float = 1.0) -> Node3D:
	if not _persistent.has(kind):
		push_warning("VfxLibrary: '%s' is not a persistent emitter kind" % kind)
		return null
	var nodes: Array = _persistent[kind]
	var used: Array = _persistent_used[kind]
	for i in nodes.size():
		if used[i] != null:
			continue
		var node: Node3D = nodes[i]
		node.global_position = at
		node.global_basis = Basis.IDENTITY
		node.scale = Vector3.ONE * clampf(scale, 0.05, 60.0)
		node.visible = true
		used[i] = kind
		_persistent_used[kind] = used
		return node
	return null


func release_emitter(node: Node3D) -> void:
	for kind: StringName in _persistent:
		var nodes: Array = _persistent[kind]
		var used: Array = _persistent_used[kind]
		for i in nodes.size():
			if nodes[i] != node:
				continue
			node.visible = false
			used[i] = null
			_persistent_used[kind] = used
			return


## Spawn after `delay` seconds of game time - chained effects (kill_large fires at 0 / 0.15 / 0.35 s).
func queue(kind: StringName, at: Vector3, normal: Vector3, scale: float, delay: float) -> void:
	if _pending.size() >= MAX_PENDING:
		_pending.pop_front()
	_pending.append({"kind": kind, "at": at, "normal": normal, "scale": scale, "t": delay})


func spawn_ring(at: Vector3, normal: Vector3, radius: float, seconds: float, color: Color) -> bool:
	if not _nodes.has(&"shockwave_ring"):
		return false
	var slot := _take(&"shockwave_ring")
	var ring := ((_nodes[&"shockwave_ring"] as Array)[slot]) as ShockwaveFx
	ring.fire(at, normal, radius, seconds, color)
	_hold(&"shockwave_ring", slot, seconds + 0.05)
	return true


func flash_light(at: Vector3, color: Color, energy: float, range_m: float, frames: float = 3.0) -> void:
	lights.flash(at, color, energy, range_m, frames)


func spawn_debris(at: Vector3, count: int, speed: float = 9.0, size: float = 0.8,
		metal: bool = false) -> void:
	debris.burst(at, count, speed, size, metal)


## Ghost a mech's meshes at their current pose (quick boost, perfect dodge, overdrive).
func afterimage(source: Node3D, life: float = 0.18, color: Color = VfxPresets.CYAN) -> int:
	return afterimages.spawn(source, life, color) if source != null else 0


func active_count() -> int:
	var n := 0
	for kind: StringName in _free:
		var times: PackedFloat64Array = _free[kind]
		for t in times:
			if t > _now:
				n += 1
	return n


func pool_size(kind: StringName) -> int:
	return (_nodes[kind] as Array).size() if _nodes.has(kind) else 0


func _process(delta: float) -> void:
	_now = _clock()
	_update_pixel_scale()
	var i := 0
	while i < _pending.size():
		var p := _pending[i]
		p["t"] = float(p["t"]) - delta
		if float(p["t"]) <= 0.0:
			spawn(p["kind"], p["at"], p["normal"], float(p["scale"]))
			_pending.remove_at(i)
		else:
			i += 1


func _prewarm(kind: StringName) -> void:
	var n := VfxPresets.pool_size(kind)
	var nodes: Array = []
	var times := PackedFloat64Array()
	for i in n:
		var node := VfxPresets.build(kind)
		node.name = "%s%d" % [String(kind), i]
		add_child(node)
		nodes.append(node)
		times.append(-1.0)
	_nodes[kind] = nodes
	_free[kind] = times
	_cursor[kind] = 0


func _prewarm_persistent(kind: StringName) -> void:
	var nodes: Array = []
	var used: Array = []
	for i in int(VfxPresets.PERSISTENT[kind]):
		var node := VfxPresets.build(kind)
		node.name = "%s%d" % [String(kind), i]
		node.visible = false
		add_child(node)
		nodes.append(node)
		used.append(null)
	_persistent[kind] = nodes
	_persistent_used[kind] = used


## Marks a slot busy for `life` seconds. Packed arrays are value types, so the array must be written
## back into the dictionary - assigning through a temporary would silently do nothing.
func _hold(kind: StringName, slot: int, life: float) -> void:
	var times: PackedFloat64Array = _free[kind]
	times[slot] = _now + life
	_free[kind] = times


## Round-robin over the slots; a busy pool steals the one closest to finishing.
func _take(kind: StringName) -> int:
	var times: PackedFloat64Array = _free[kind]
	var size := times.size()
	var start := int(_cursor[kind])
	for i in size:
		var slot := (start + i) % size
		if times[slot] <= _now:
			_cursor[kind] = (slot + 1) % size
			return slot
	_cursor[kind] = (start + 1) % size
	return start


## World metres per screen pixel, per metre of depth: the streak and flash shaders use it to hold a
## minimum *screen* size, so a hit 150 m away still draws a visible tracer. It has to come from the
## camera rather than from VIEWPORT_SIZE in the shader - that built-in reads 0 in an offscreen
## capture, which silently turned every spark into a kilometres-long additive streak.
func _update_pixel_scale() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var size := vp.get_visible_rect().size
	var cam := vp.get_camera_3d()
	var fov := 55.0
	var height := maxf(size.y, 1.0)
	if cam != null:
		if cam.keep_aspect == Camera3D.KEEP_WIDTH:
			fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(cam.fov) * 0.5) / maxf(size.x / height, 0.01)))
		else:
			fov = cam.fov
	RenderingServer.global_shader_parameter_set(&"fx_pixel_scale",
			tan(deg_to_rad(fov) * 0.5) * 2.0 / height)


## Game clock, not the wall clock: _hold/_take free ring and emitter slots, and must age them on the
## same clock ShockwaveFx runs on or a live ring's slot is reused while it is still expanding.
func _clock() -> float:
	return Feel.real_now()
