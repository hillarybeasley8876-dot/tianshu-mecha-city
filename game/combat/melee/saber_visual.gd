class_name SaberVisual
extends Node3D
## Dawn Edge (曦刃) visuals: a tapered blade (white core #EFFFFF inside an additive cyan #4FE6FF glow,
## both HDR so they bloom). The swing trail lives in its own node — see `SwingTrail`.
##
## THE BLADE IS THE HAND (review r4): `_blade.global_transform` is the `saber_r` socket's pose,
## nothing else. Nothing in this file may place the blade on a computed arc — the swing comes from
## the model's clip, so the energy blade and the arm can never disagree.

const CORE_COLOR := Color("efffff")
const GLOW_COLOR := Color("4fe6ff")
const CORE_ENERGY := 2.6
const GLOW_ENERGY := 1.1
const HILT_LENGTH := 2.6
const HUM_HZ := 7.3          ## idle flicker, so the blade is never a dead plastic stick
const HUM_DEPTH := 0.16
## hero-v3 (review r5 item 2) models its own blade on `R_Hand` and answers `has_own_blade()`. We then
## draw NO second blade over it — only the additive sheath, which starts at the model's steel tip and
## runs out to `MeleeTable.BLADE_LENGTH` (the energy extension), plus the trail. Used when the model
## answers `has_own_blade()` but offers no `blade_length()`.
const OWN_BLADE_FALLBACK := MeleeTable.MODEL_BLADE_LENGTH
## The blade's pose inside the `saber_r` socket, in the socket's own space: the mesh runs along −Z
## from the hilt, so this is the rotation that puts the energy blade out along the grip.
const SOCKET_POS := Vector3(0.0, 0.0, 0.0)
const SOCKET_ROT_DEG := Vector3(0.0, 0.0, 0.0)

var lit: bool = false
var swinging: bool = false   ## true through a move's active window: the ribbon samples
var own_blade: bool = false  ## the model draws the steel itself (hero-v3); we only sheath it

var _blade: Node3D = null
var _core: MeshInstance3D = null
var _glow: MeshInstance3D = null
var _hilt: MeshInstance3D = null
var _trail: SwingTrail = null
var _model_blade: float = 0.0    ## the model's own steel length (0 = we draw the whole blade)
var _socket: Node3D = null
var _hum: float = 0.0
var _extend: float = 0.0        ## 0 = stowed, 1 = full blade; runs the ignite/retract animation
var _core_mat: StandardMaterial3D = null
var _glow_mat: StandardMaterial3D = null


func _ready() -> void:
	top_level = true
	_build_blade()
	_build_trail()
	_stow()
	set_physics_process(true)


## Attaches the blade to the model's `saber_r` socket when the model offers one (HeroModel API,
## CONTRACTS §5); without a model the blade rides the melee system node itself, which the melee
## system parks at the chest pivot facing the aim.
func attach(model: Node) -> void:
	if model == null or not is_instance_valid(model):
		return
	if model.has_method(&"socket"):
		var s := model.call(&"socket", &"saber_r") as Node3D
		if s != null:
			_socket = s
	_adopt_model_blade(model)


## hero-v3 carries its own modelled saber. Drawing our 14 m energy blade on top of it would put a
## second blade through the mech's hand, so the core, the glow's white heart and the hilt all step
## aside: what is left is the additive sheath over the model's steel, which also runs out to
## `MeleeTable.BLADE_LENGTH` — the energy extension that keeps the visible reach equal to the reach
## the hit volume uses.
func _adopt_model_blade(model: Node) -> void:
	if own_blade or not model.has_method(&"has_own_blade"):
		return
	if not bool(model.call(&"has_own_blade")):
		return
	own_blade = true
	if model.has_method(&"blade_length"):
		_model_blade = clampf(float(model.call(&"blade_length")), 0.5, MeleeTable.BLADE_LENGTH)
	else:
		_model_blade = OWN_BLADE_FALLBACK
	if _core != null:
		_core.visible = false
	if _hilt != null:
		_hilt.visible = false
	## The sheath is rebuilt as the EXTENSION only: it starts at the steel tip and grows out to the
	## agreed length as the blade ignites, so the ignition reads as energy running up the model's
	## blade rather than a second blade appearing in the hand.
	if _glow != null:
		_glow.mesh = CombatMesh.blade(maxf(MeleeTable.BLADE_LENGTH - _model_blade, 0.5),
				MeleeTable.BLADE_HALF)
		_glow.position = Vector3(0.0, 0.0, -_model_blade)


## The length of the model's own steel, 0 when we draw the whole blade. The HUD and the tests read it
## to see that a hero-v3 model took the blade over.
func model_blade_length() -> float:
	return _model_blade


## Whether we still draw a white core / hilt of our own. A model that carries its own blade must
## leave both false, or there are two blades in the hand (review r5 item 2).
func draws_own_steel() -> bool:
	return _core != null and _core.visible and _hilt != null and _hilt.visible


## The swing ribbon node — the tests read its lane bookkeeping (review r5 item 1).
func trail() -> SwingTrail:
	return _trail


## The socket's node — the tests read it to check the drawn blade against the hand.
func socket() -> Node3D:
	return _socket


## Core, glow and hilt: two nested tapered prisms plus a short emissive collar at the grip. The glow
## is the same mesh scaled up, so the taper reads on both and the silhouette stays a blade.
func _build_blade() -> void:
	_blade = Node3D.new()
	_blade.name = "Blade"
	add_child(_blade)
	var mesh := CombatMesh.blade(MeleeTable.BLADE_LENGTH, MeleeTable.BLADE_HALF)
	_core_mat = CombatMesh.hdr(CORE_COLOR, CORE_ENERGY)
	_core = _instance("Core", mesh, _core_mat)
	_blade.add_child(_core)
	_glow_mat = CombatMesh.hdr(GLOW_COLOR, GLOW_ENERGY, 0.5)
	_glow = _instance("Glow", mesh, _glow_mat)
	_glow.scale = Vector3(MeleeTable.BLADE_GLOW_SCALE, MeleeTable.BLADE_GLOW_SCALE, 1.005)
	_blade.add_child(_glow)
	var collar := CylinderMesh.new()
	collar.top_radius = 0.5
	collar.bottom_radius = 0.72
	collar.height = HILT_LENGTH
	collar.radial_segments = 8
	_hilt = _instance("Hilt", collar, CombatMesh.hdr(GLOW_COLOR, 1.5, 0.8))
	_hilt.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_hilt.position = Vector3(0.0, 0.0, HILT_LENGTH * 0.5)
	_blade.add_child(_hilt)


static func _instance(name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build_trail() -> void:
	_trail = SwingTrail.new()
	add_child(_trail)


## Ignites or stows the blade. The blade only exists while melee is active (lead note): ignition
## grows it out of the hilt over 0.12 s behind a flash, and stowing pulls it back in. The hilt itself
## is the hero model's own part, which rides the hip until the melee system draws it.
func set_lit(on: bool) -> void:
	if on == lit:
		return
	lit = on
	if on:
		_extend = maxf(_extend, 0.001)
		_ignite_flash()
	else:
		swinging = false
		clear_swing()


## Opens or closes the trail's sampling window (the melee system calls it at the active window's
## edges). The blade itself keeps following the hand either way.
##
## Opening a window starts a NEW LANE in the trail: the string chains L1→L2 through a cancel window
## shorter than TRAIL_FADE, so L1's samples are still alive when L2's active frames begin. Without
## the lane the first quad of L2 is drawn from L1's last sample — the grey card hanging beside the
## mech in the r4 strips (review r5 item 1).
func set_swinging(on: bool) -> void:
	if on and not swinging:
		_trail.open_lane()
	swinging = on
	_trail.set_sampling(on and lit)


## 0..1 — how much of the blade is out. The HUD and the tests read it to see the ignition run.
func extend_ratio() -> float:
	return _extend


func _ignite_flash() -> void:
	var at := global_position
	if _socket != null and is_instance_valid(_socket):
		at = _socket.global_position
	CombatVfx.flash(self, at, Color(0.75, 0.97, 1.0), 4.0, 16.0)
	CombatVfx.spawn(self, &"spark_burst", at, Vector3.UP, 0.5)


## The blade grows along its own −Z, so it reads as extending from the hilt rather than scaling up.
func _run_extend(delta: float) -> void:
	var want := 1.0 if lit else 0.0
	if is_equal_approx(_extend, want):
		return
	_extend = move_toward(_extend, want, delta / MeleeTable.BLADE_EXTEND)
	if _core == null or _glow == null:
		return
	var k := maxf(_extend, 0.0001)
	_core.scale.z = k
	_glow.scale.z = k * 1.005
	_blade.visible = _extend > 0.001


func clear_swing() -> void:
	if _trail != null:
		_trail.clear()


## Nothing but the model's own hilt until the first melee input.
func _stow() -> void:
	lit = false
	swinging = false
	_extend = 0.0
	clear_swing()
	if _core == null or _glow == null:
		return
	_core.scale.z = 0.0001
	_glow.scale.z = 0.0001
	_blade.visible = false


## The blade is glued to the hand on the PHYSICS tick, so the ribbon's samples and the hit volumes
## read the same pose in the same tick. The trail rebuilds itself in its own `_physics_process`,
## which runs right after this one.
func _physics_process(_delta: float) -> void:
	_follow_socket()
	var pts := blade_points()
	_trail.track(pts[1])
	if swinging and lit:
		_trail.sample(pts[0], pts[1])


func _process(delta: float) -> void:
	_run_extend(delta)
	_idle_hum(delta)


## The blade is alive even at rest: the core and glow breathe a few percent at HUM_HZ, with a second
## detuned sine so it never looks like a loop.
func _idle_hum(delta: float) -> void:
	if not lit or _core_mat == null:
		return
	_hum += delta
	var k := 1.0 + HUM_DEPTH * (sin(_hum * HUM_HZ) * 0.6 + sin(_hum * HUM_HZ * 2.7) * 0.4)
	_core_mat.albedo_color = Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 1.0) * (CORE_ENERGY * k)
	_glow_mat.albedo_color = Color(GLOW_COLOR * (GLOW_ENERGY * k), 0.5)
	_hilt.scale = Vector3.ONE * (1.0 + HUM_DEPTH * 0.5 * sin(_hum * HUM_HZ * 1.6))


## The blade sits in the hand: the socket's world pose (plus the socket-space blade offset), or the
## owner node's own pose when the model has no socket to offer. This runs whether or not the blade
## is drawn — a stowed blade that keeps a stale pose reads as an 11 m detach the tick it ignites.
func _follow_socket() -> void:
	if _blade == null:
		return
	if _socket != null and is_instance_valid(_socket):
		_blade.global_transform = _socket.global_transform * _socket_pose()
		return
	_blade.global_transform = global_transform


func _socket_pose() -> Transform3D:
	return Transform3D(Basis.from_euler(SOCKET_ROT_DEG * (PI / 180.0)), SOCKET_POS)


## Blade root and tip in world space, for the trail and for the tests. The tip follows the ignition
## scale, so a half-drawn blade has a half-length trail; a model that carries its own steel starts at
## the steel tip instead, because that part of the blade is there before we ignite anything.
func blade_points() -> Array[Vector3]:
	if _blade == null:
		return [global_position, global_position]
	var xf := _blade.global_transform
	return [xf.origin, xf.origin - xf.basis.z * drawn_length()]


## How far the drawn tip is from the socket origin right now.
func drawn_length() -> float:
	var k := clampf(_extend, 0.0, 1.0)
	if own_blade:
		return lerpf(_model_blade, MeleeTable.BLADE_LENGTH, k)
	return MeleeTable.BLADE_LENGTH * k
