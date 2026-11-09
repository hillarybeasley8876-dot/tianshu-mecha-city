extends Node
## Feel and Events routing for the rig (camera-aim). The rig is about placement; this is the switchboard
## that turns `Feel.shake/fov_kick/kick` and the locomotion events into calls on the rig's shake, FOV and
## arm channels, so the rig itself stays one file about where the camera is.
## FEEL header rules live in the channels: trauma² and the 1st-person scalings are applied there, this
## module only decides WHICH channel a request belongs to.

var _rig: Node3D = null
var _fov: Node = null
var _shake: Node = null


func setup(rig: Node3D, fov: Node, shake: Node) -> void:
	_rig = rig
	_fov = fov
	_shake = shake
	Feel.shake_requested.connect(_on_shake)
	Feel.shake_floor_requested.connect(_on_shake_floor)
	Feel.fov_kick_requested.connect(_on_fov_kick)
	Feel.kick_requested.connect(_on_kick)
	Events.landed.connect(_on_landed)
	Events.footstep.connect(_on_footstep)
	Events.boost_started.connect(_on_boost_started)
	Events.boost_ended.connect(_on_boost_ended)
	Events.paused_changed.connect(_on_paused)
	Events.player_spawned.connect(_on_player_spawned)


## Trauma for the shake channel, with the rig's distance falloff for a positioned source.
func _on_shake(trauma: float, origin: Vector3) -> void:
	_rig.call(&"add_trauma", trauma, origin)


## Held minimum trauma for continuous effects (a beam, a rumble): the shake channel keeps it up.
func _on_shake_floor(trauma: float, seconds: float) -> void:
	_shake.call(&"hold_floor", trauma, seconds)


## Transient FOV punch: snap to the requested degrees, then bleed off (juice-impact §3.3).
func _on_fov_kick(degrees: float, duration: float) -> void:
	_fov.call(&"kick", degrees, duration)


## Feel.kick: the view is shoved AWAY from `world_dir` in the spring channel (rifle recoil pitches up,
## a hit taken kicks back). Vector3.ZERO means "no direction": up plus a quarter turn of roll.
func _on_kick(degrees: float, world_dir: Vector3, duration: float) -> void:
	if world_dir.length_squared() < 0.001:
		_rig.call(&"apply_kick", degrees, 0.0, degrees * 0.25, duration)
		return
	var local := (_rig.call(&"view_basis") as Basis).inverse() * world_dir.normalized()
	_rig.call(&"apply_kick", -local.z * degrees, -local.x * degrees, -local.x * degrees * 0.3, duration)


func _on_landed(impact_speed: float) -> void:
	_shake.call(&"land", impact_speed)


## SPEC §5 "mass cues": a translate only, never a rotation, so the cockpit view stays level.
func _on_footstep(_position: Vector3, heavy: bool) -> void:
	_shake.call(&"footstep", heavy)


func _on_boost_started(kind: StringName) -> void:
	_fov.call(&"set_boost", kind, true)
	_rig.call(&"set_boost_arm", kind, true)


func _on_boost_ended(kind: StringName) -> void:
	_fov.call(&"set_boost", kind, false)
	_rig.call(&"set_boost_arm", kind, false)


func _on_paused(paused: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


## The rig follows whoever registers as the player; snap on (re)spawn so the first frame is in place.
func _on_player_spawned(_player: Node3D) -> void:
	_rig.call(&"snap_to_player")
