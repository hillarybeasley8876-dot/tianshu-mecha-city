class_name FlowAscensionCatapult
extends Area3D
## The Ascension Catapult (飞升弹射器, SPEC §8 / MAP §2): the only way onto the Crown. It stands at
## S4 — the Corona Fins ring at +160 on the Spire's north side — and stays dark until the third Hive
## Spire falls, when `GameFlow` opens it with the boss gate. Stepping onto the lit pad throws the mech
## up the last 110 m on a scripted 4.5 s arc and drops it on the Crown deck at B1.
##
## The flight is a kinematic arc rather than an impulse: the launch is a scripted traversal beat, the
## player has no control over it anyway (movement is locked), and a real impulse would have to thread
## the tuning's gravity, terminal velocity and the 260 m ceiling to land on one deck. Control comes
## back with the arc's own exit velocity, so the hero falls the last few metres and lands properly.

signal launched()
signal landed(at: Vector3)

## Launch pad and landing spot (Godot axes). The world's `S4` / `B1` spawn zones win; these are the
## layout's own numbers (MAP §2: Blender (0, 210, 160) → Godot (0, 160, −210)).
const PAD_FALLBACK := Vector3(0.0, 160.0, -210.0)
const LANDING_FALLBACK := Vector3(0.0, 224.0, -120.0)
const PAD_ZONE := &"S4"
const LANDING_ZONE := &"B1"
const PAD_RADIUS := 16.0
const FLIGHT_TIME := 4.5          ## s from the pad to the top of the arc
const ARC_HEIGHT := 60.0          ## m the apex stands above the landing point
## The apex's radius from the Spire axis. The Crown deck is Ø300 (r 150) and the pad sits UNDER it,
## 90 m out, so a straight pad → landing line goes through the deck: the arc swings out past the rim,
## rises there and comes back in over the fighting floor (lead r16 decision 2).
const ARC_OUT := 175.0
## m below the Crown deck's origin the gate point sits: the deck's underside is `CENTRE.y - 8`, the
## mech's half height is 7.5 and this leaves 8 m of daylight under the slab.
const UNDER_CLEARANCE := 24.0
const DROP := 27.5                ## m above the landing the arc ends, handed back as a real fall
const EXIT_SPEED := 18.0          ## m/s downward handed back with the controls
const PAD_COLOR := Color(0.55, 0.95, 1.0)   ## ART.md: cyan-white is the city's "up" connector colour
const BEAM_HEIGHT := 120.0
const HINT := "飞升弹射器已就绪  ASCENSION CATAPULT READY — STEP ON THE PAD"

var armed: bool = false
var flying: bool = false

var _pad: Vector3 = PAD_FALLBACK
var _landing: Vector3 = LANDING_FALLBACK
var _from: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _ring: MeshInstance3D = null
var _beam: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _pulse: float = 0.0


func _ready() -> void:
	collision_layer = Layers.TRIGGER
	collision_mask = Layers.PLAYER
	monitoring = false
	add_to_group(&"flow_catapult")
	_build()
	body_entered.connect(_on_body_entered)


## Build it where the world says S4 is; `open()` is what makes it live.
func place(pad: Vector3, landing: Vector3) -> void:
	_pad = pad
	_landing = landing
	global_position = pad


func _build() -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = PAD_RADIUS
	cylinder.height = 24.0
	shape.shape = cylinder
	shape.position = Vector3.UP * 8.0
	add_child(shape)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = PAD_COLOR
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_mat.emission = PAD_COLOR
	_mat.emission_energy_multiplier = 0.4
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring = _mesh("PadRing", _pad_mesh(), _mat)
	_beam = _mesh("Beam", _beam_mesh(), _mat)
	_ring.visible = false
	_beam.visible = false
	set_physics_process(false)


func _mesh(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = mat
	add_child(node)
	return node


func _pad_mesh() -> Mesh:
	var torus := TorusMesh.new()
	torus.inner_radius = PAD_RADIUS * 0.55
	torus.outer_radius = PAD_RADIUS
	torus.rings = 24
	return torus


func _beam_mesh() -> Mesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.5
	cylinder.bottom_radius = PAD_RADIUS * 0.5
	cylinder.height = BEAM_HEIGHT
	cylinder.radial_segments = 16
	return cylinder


## The third spire is down: the pad lights, the beam goes up and stepping on it launches (brief §1).
func open() -> void:
	if armed:
		return
	armed = true
	monitoring = true
	_ring.visible = true
	_beam.visible = true
	_beam.position = Vector3.UP * BEAM_HEIGHT * 0.5
	Feel.play(&"overdrive_ignite", _pad, 0.6)
	FxBridge.ring(self, _pad, Vector3.UP, PAD_RADIUS * 3.0, 1.2, PAD_COLOR)


func _process(delta: float) -> void:
	if not armed or _mat == null:
		return
	_pulse += delta
	var glow := 2.4 + sin(_pulse * 2.6) * 0.9
	_mat.emission_energy_multiplier = glow
	_mat.albedo_color = Color(PAD_COLOR.r, PAD_COLOR.g, PAD_COLOR.b, 0.35 + sin(_pulse * 2.6) * 0.15)


# --- the flight -----------------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if not armed or flying or not body.is_in_group(&"player"):
		return
	_launch(body)


func _launch(player: Node3D) -> void:
	flying = true
	# Inside `body_entered` the physics server refuses a direct change (and says so).
	set_deferred(&"monitoring", false)
	_from = player.global_position
	_t = 0.0
	# Duck-typed like every other flow hook: a stubbed hero (tests, --stub=player) has only some of
	# the PlayerMech API.
	if player.has_method(&"invulnerable_for"):
		player.call(&"invulnerable_for", FLIGHT_TIME + 3.0)
	if player.has_method(&"lock_movement"):
		player.call(&"lock_movement", FLIGHT_TIME, true)
	player.set(&"velocity", Vector3.ZERO)
	_thrusters(player, 1.0)
	Feel.play(&"boost_start", _from, 1.0)
	FxBridge.spawn(self, &"thruster_burst", _from, Vector3.DOWN, 4.0)
	FxBridge.ring(self, _from, Vector3.UP, PAD_RADIUS * 2.0, 0.8, PAD_COLOR)
	Audio.stinger(&"stinger_spire_cleared")
	_shoot()
	launched.emit()
	set_physics_process(true)


## The whole ascent in the duel frame: with no hard target the frame's −Z is the hero's facing, so the
## offsets sit behind and above the mech and the Crown stays in shot.
func _shoot() -> void:
	var rig := Game.camera_rig
	if rig == null or not rig.has_method(&"request_cinematic"):
		return
	rig.call(&"request_cinematic", [
		{"offset": Vector3(34.0, -6.0, 46.0), "fov": 62.0, "t": 0.0},
		{"offset": Vector3(-26.0, 16.0, 40.0), "fov": 55.0, "t": 1.8},
		{"offset": Vector3(20.0, 26.0, 58.0), "fov": 50.0, "t": 3.2},
	], FLIGHT_TIME + 0.6)


func _physics_process(delta: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		_end_flight(Vector3.ZERO)
		return
	_t += Feel.real_delta(delta)
	var u := clampf(_t / FLIGHT_TIME, 0.0, 1.0)
	player.global_position = arc(_from, _landing, u)
	player.set(&"velocity", Vector3.ZERO)
	if u >= 1.0:
		_end_flight(arc(_from, _landing, 1.0))


## The ascent as one Catmull-Rom curve through four points: the pad, a gate out past the deck's rim
## and just under its underside, the apex above everything, and the landing. The pad sits UNDER the
## Crown deck (90 m out, 80 m below the fighting floor), so a straight pad → landing line goes through
## it; the gate point is what makes the curve swing out before it rises (lead r16 decision 2).
static func arc(from: Vector3, landing: Vector3, u: float) -> Vector3:
	return _spline([from, gate(from), apex(from, landing), landing + Vector3.UP * DROP], u * 3.0)


## The gate: `ARC_OUT` from the Spire axis on the launch bearing, at a height that is still under the
## deck's underside (`CENTRE.y - 8`) with the mech's own 7.5 m half height and 8 m to spare.
static func gate(from: Vector3) -> Vector3:
	var axis := Vector3(FlowCrownDeck.CENTRE.x, 0.0, FlowCrownDeck.CENTRE.z)
	var out := _outward(from, axis)
	return axis + out * ARC_OUT + Vector3.UP * (FlowCrownDeck.CENTRE.y - UNDER_CLEARANCE)


## The apex: straight above the gate, `ARC_HEIGHT` over the landing, so the leg in over the rim and
## the fins is clear by tens of metres.
static func apex(from: Vector3, landing: Vector3) -> Vector3:
	var g := gate(from)
	return Vector3(g.x, landing.y + ARC_HEIGHT, g.z)


static func _outward(from: Vector3, axis: Vector3) -> Vector3:
	var out := Vector3(from.x - axis.x, 0.0, from.z - axis.z)
	return out.normalized() if out.length() > 1.0 else Vector3(0.0, 0.0, -1.0)


## Uniform Catmull-Rom over 4 control points, `t` in [0, 3]. It passes through every point, so the
## gate and the apex are really on the path and not just handles.
static func _spline(p: Array[Vector3], t: float) -> Vector3:
	var i := clampi(int(t), 0, p.size() - 2)
	var f := t - float(i)
	var a := p[maxi(i - 1, 0)]
	var b := p[i]
	var c := p[i + 1]
	var d := p[mini(i + 2, p.size() - 1)]
	return (b * 2.0 + (c - a) * f + (a * 2.0 - b * 5.0 + c * 4.0 - d) * f * f
			+ (b * 3.0 - a - c * 3.0 + d) * f * f * f) * 0.5


## Control comes back at the top of the arc with the exit velocity, so the hero drops the last metres
## onto the deck and the landing is a real `Events.landed` the whole game can hear. The pad re-arms
## here: `monitoring` is turned off at launch and nothing used to put it back, so a hero who fell off
## the Crown and landed back on S4 could never relaunch (r5 brief item 2).
func _end_flight(at: Vector3) -> void:
	set_physics_process(false)
	flying = false
	var player := Game.player
	if player != null and is_instance_valid(player):
		player.set(&"velocity", Vector3(0.0, -EXIT_SPEED, 0.0))
		_thrusters(player, 0.0)
		at = player.global_position
	var rig := Game.camera_rig
	if rig != null and rig.has_method(&"end_cinematic"):
		rig.call(&"end_cinematic")
	landed.emit(at)
	if armed:
		set_deferred(&"monitoring", true)


func _thrusters(player: Node3D, level: float) -> void:
	if not player.has_method(&"model"):
		return
	var model := player.call(&"model") as Node3D
	if model != null and model.has_method(&"set_thrusters"):
		model.call(&"set_thrusters", level)
