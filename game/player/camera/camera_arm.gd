extends Node3D
## Camera arm (camera-aim): the SpringArm3D of SPEC §5. A 1.5 m sphere probe with a 0.5 m margin is cast
## from the shoulder pivot along the view's +Z (behind the player) against Layers.MASK_SIGHT. The arm
## pulls IN instantly so the camera can never end up inside a building, and pushes back out at 10 m/s
## after a 0.25 s hold, so a pillar the player runs past does not pump the view in and out.
## The node's local position.z IS the current arm length; the Camera3D is its child.

const PROBE_RADIUS := 1.5
const MARGIN := 0.5                 ## clearance kept in front of the surface
const RECOVER_SPEED := 10.0         ## m/s the arm pushes back out
const RECOVER_DELAY := 0.25         ## s of clear sight before it starts pushing out
const CAMERA_RADIUS := 0.5          ## volume kept clear around the camera while pushing out
const MIN_LENGTH := 0.0
const DITHER_GROUP := &"camera_dither"   ## city-art joins its buildings to this group (SPEC §5)
const FADE_CLEARED := 1.0           ## nothing in the way: fully solid
const FADE_OCCLUDING := 0.3         ## SPEC §5: occluding buildings dither to 30 %
const FADE_RATE := 4.0              ## per second, so a pillar the player runs past does not pop

@export var length: float = 42.0    ## desired (unobstructed) arm length, set by the rig each tick

var _probe: SphereShape3D
var _camera_probe: SphereShape3D
var _volume: BoxShape3D
var _current: float = 42.0
var _clear_time: float = 0.0
var _push_bonus: float = 0.0        ## extra m/s the rig asks for on top of RECOVER_SPEED
var _fade: float = FADE_CLEARED     ## manual override from the rig (0 = invisible, 1 = solid)
var _faded: Dictionary = {}         ## Node -> fade currently applied, so it can be released


func _ready() -> void:
	_probe = SphereShape3D.new()
	_probe.radius = PROBE_RADIUS
	_camera_probe = SphereShape3D.new()
	_camera_probe.radius = CAMERA_RADIUS
	_volume = BoxShape3D.new()
	_current = length
	position.z = _current


## Casts the probe and writes position.z. Returns the length in use.
func update(delta: float) -> float:
	var free_length := _free_length()
	if free_length < _current:
		_current = free_length            # instant: never let the view clip for a frame
		_clear_time = 0.0
	else:
		_clear_time += delta
		if _clear_time >= RECOVER_DELAY:
			# The axis can be clear while the camera body would land inside something beside it (a deck
			# overhead, a pillar), so the push-out is verified against a sphere at the new position.
			var want := minf(_current + (RECOVER_SPEED + _push_bonus) * delta, free_length)
			if _camera_clear(want):
				_current = want
			else:
				_clear_time = 0.0
	_current = clampf(_current, MIN_LENGTH, length)
	position.z = _current
	_update_occluders(delta)
	return _current


## Extra push-out speed on top of RECOVER_SPEED. The rig raises it while a framing change (CONTRACTS §5
## large-target framing) wants the arm tens of metres further out: 22 m at the SPEC §5 collision rate
## would take 2.2 s, which is a whole boss-intro beat. Occluder recovery keeps the plain 10 m/s.
func set_push_bonus(mps: float) -> void:
	_push_bonus = maxf(mps, 0.0)


## Manual fade override from the rig (0 = invisible, 1 = solid). Anything in the `camera_dither` group
## between the hero and the camera is driven to `min(override, FADE_OCCLUDING)` while it is in the way.
func set_fade(amount: float) -> void:
	_fade = clampf(amount, 0.0, 1.0)


## SPEC §5 "occluding buildings dither to 30 %": the box swept from the shoulder pivot back to the
## camera is queried each tick and every collider in the group is faded, then released when it is clear.
func _update_occluders(delta: float) -> void:
	var occluding := {}
	# The DESIRED arm length, not the retracted one: a pillar that pushes the camera in is exactly the
	# thing the player needs to see through, and by then it is no longer "between" hero and camera.
	var span := maxf(length, 0.01)
	if is_inside_tree() and span > 1.0:
		var space := get_world_3d().direct_space_state
		_volume.size = Vector3(PROBE_RADIUS * 2.0, PROBE_RADIUS * 2.0, span)
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = _volume
		var origin := _origin()
		params.transform = Transform3D(global_basis, origin + global_basis.z * span * 0.5)
		params.collision_mask = Layers.MASK_SIGHT
		params.collide_with_areas = false
		params.collide_with_bodies = true
		for hit in space.intersect_shape(params, 8):
			var node := hit["collider"] as Node
			if node != null and node.is_in_group(DITHER_GROUP):
				occluding[node] = true
	var want := minf(_fade, FADE_OCCLUDING) if not occluding.is_empty() else _fade
	for node: Node in occluding:
		_apply_fade(node, move_toward(float(_faded.get(node, FADE_CLEARED)), want, FADE_RATE * delta))
	for node: Node in _faded.keys():
		if occluding.has(node):
			continue
		var left := move_toward(float(_faded[node]), FADE_CLEARED, FADE_RATE * delta)
		_apply_fade(node, left)
		if is_equal_approx(left, FADE_CLEARED):
			_faded.erase(node)


## city-art's contract: a node in the group either implements `set_fade(amount)` or carries a
## MeshInstance3D whose material reads the `fade` instance parameter.
func _apply_fade(node: Node, amount: float) -> void:
	_faded[node] = amount
	if node.has_method(&"set_fade"):
		node.call(&"set_fade", amount)
		return
	var mesh := node as MeshInstance3D
	if mesh == null:
		for child in node.get_children():
			if child is MeshInstance3D:
				mesh = child as MeshInstance3D
				break
	if mesh != null:
		mesh.set_instance_shader_parameter(&"fade", amount)


func current_length() -> float:
	return _current


## How many occluders are currently faded (HUD/telemetry).
func faded_count() -> int:
	return _faded.size()


## Snap the arm (mode switch, teleport, cinematic) instead of easing into place.
func snap() -> void:
	_current = clampf(_free_length(), MIN_LENGTH, length)
	_clear_time = RECOVER_DELAY
	position.z = _current


## Distance the camera may travel backwards before the probe touches scenery.
func _free_length() -> float:
	if length <= 0.0:
		return 0.0
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _probe
	# From the SHOULDER PIVOT, not from the camera: this node sits `position.z` behind it already.
	params.transform = (get_parent() as Node3D).global_transform   # the shoulder pivot, not the camera
	params.motion = global_basis.z * length
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit := space.cast_motion(params)
	if hit.is_empty():
		# No motion result means the probe cannot move at all: the pivot itself is inside geometry.
		return MIN_LENGTH if _blocked_at_pivot(space, params) else length
	var safe := float(hit[0])
	if safe >= 1.0:
		return length                      # nothing behind the player: no margin to take off
	return clampf(length * maxf(safe, 0.0) - MARGIN, MIN_LENGTH, length)


## Is the camera volume itself free at arm length `l`?
func _camera_clear(l: float) -> bool:
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _camera_probe
	params.transform = Transform3D(Basis.IDENTITY, _origin() + global_basis.z * l)
	params.collision_mask = Layers.MASK_SIGHT
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return space.intersect_shape(params, 1).is_empty()


## The shoulder pivot this arm hangs from (the parent), which is where every probe starts.
func _origin() -> Vector3:
	return (get_parent() as Node3D).global_position


func _blocked_at_pivot(space: PhysicsDirectSpaceState3D, params: PhysicsShapeQueryParameters3D) -> bool:
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = params.shape
	probe.transform = params.transform
	probe.collision_mask = params.collision_mask
	probe.collide_with_areas = false
	probe.collide_with_bodies = true
	return not space.intersect_shape(probe, 1).is_empty()
