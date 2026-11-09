extends Node3D
## Cockpit interior (camera-aim): the canopy the player sees in first person. Geometry comes from
## cockpit_build.gd; this script only decides WHERE it sits and how it moves.
## It places itself at the model's `cockpit` socket (SPEC §5 eye band 11.5–13.5 m), follows the view
## yaw with an 80 ms lag so a turn feels like a mass moving, and takes a ≤1.5° knock when the player is
## hit — the view itself is never rotated by damage (SPEC §5).

const Build := preload("res://player/camera/cockpit_build.gd")

const LAG := 0.08                   ## s the canopy trails a turn (SPEC §5)
const REST_PITCH_DEG := -6.0        ## the rig's default pitch: the canopy is raked with it
const DAMAGE_DEG := 1.5             ## max damage knock on the mesh, never on the view
const DAMAGE_DECAY := 6.0           ## deg/s it settles back
const EYE_HEIGHT := 13.5            ## fallback when the model has no cockpit socket
const EYE_MIN := 11.5               ## SPEC §5 band floor: below this the view sits inside the head
const EYE_FORWARD := 1.2            ## m the eye sits in front of the socket, at the canopy glass

var _yaw: float = 0.0
var _damage: float = 0.0


func _ready() -> void:
	visible = false
	Events.player_damaged.connect(_on_damaged)
	Build.build(self, REST_PITCH_DEG)


func _physics_process(delta: float) -> void:
	var rig := Game.camera_rig
	var player := Game.player as Node3D
	var shown := rig != null and player != null and float(rig.call(&"first_person_blend")) > 0.5
	if shown and not visible:
		# Audit #7: the lag state is only integrated while visible, so without a reseed the canopy came
		# back at the heading of the last first-person session (0 rad the first time) and swept into
		# place over the whole blend. Seed it to the live view instead — no sweep on entry.
		_yaw = deg_to_rad((rig.call(&"look_angles") as Vector2).x)
		_damage = 0.0
	visible = shown
	if not visible:
		return
	# Audit #8: the canopy trails a view that turns on real time (CONTRACTS §3), so its lag and knock
	# decay must too — on scaled delta the struts froze through a hit-stop and lagged 3-5x in slow-mo.
	var dt := Feel.real_delta(delta)
	_damage = move_toward(_damage, 0.0, DAMAGE_DECAY * dt)
	var want := deg_to_rad((rig.call(&"look_angles") as Vector2).x)
	_yaw += wrapf(want - _yaw, -PI, PI) * clampf(dt / LAG, 0.0, 1.0)
	var basis := Basis(Vector3.UP, _yaw) * Basis(Vector3.FORWARD, deg_to_rad(_damage))
	global_transform = Transform3D(basis, eye_point(player))


## The eye position: the hero model's `cockpit` socket, else 13.5 m above the model root (SPEC §2/§5).
## Heights are from the feet, so the fallback uses the model root, not the body node (whose origin is the
## capsule centre).
static func eye_point(player: Node3D) -> Vector3:
	var forward := -player.global_basis.z.normalized() * EYE_FORWARD
	if not player.has_method(&"model"):
		return player.global_position + Vector3.UP * EYE_HEIGHT
	var model := player.call(&"model") as Node3D
	if model == null:
		return player.global_position + Vector3.UP * EYE_HEIGHT
	var eye := model.global_position + Vector3.UP * EYE_HEIGHT
	if model.has_method(&"socket"):
		var s := model.call(&"socket", &"cockpit") as Node3D
		if s != null:
			eye = s.global_position
	# The socket is meant to sit in the SPEC's 11.5–13.5 m band; the placeholder model puts it at 9.9 m,
	# which buries the view in the mech's own head, so the eye is lifted to the band floor (see Requests).
	eye.y = maxf(eye.y, model.global_position.y + EYE_MIN)
	return eye + forward


func _on_damaged(_hit: HitInfo) -> void:
	_damage = clampf(_damage + DAMAGE_DEG, -DAMAGE_DEG, DAMAGE_DEG)
