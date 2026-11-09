class_name FlowHiveCore
extends Node3D
## The exposed hive core (lead review `flow-look-r1`, polish 1). It used to be one violet ellipse laid
## flat on the trunk's chest face — the fight's last target read as a sticker. It is now a ruptured
## boil: a torn collar of chitin flaps curling off the lip, a dark dished cavity behind them, the sac
## cluster pushing out of it, and a violet light that breathes with the sacs so the torn edges catch it.
##
## Local frame: +Y is the trunk's surface normal at the anchor and y = 0 is the shell there. EVERY
## piece of this sits in FRONT of the shell (`_shell_y` is where the trunk actually is at a given
## radius) — the trunk's own mesh is opaque, so a cavity modelled behind the surface would simply be
## invisible. The depth read comes from the dish, the flaps that curl in over it and the light.
##
## Layout is seeded off the spire's position, so a hive looks the same every run and the E2E's A/B
## captures line up.

const SEGMENTS := 24             ## collar flaps round the lip
const SHARDS := 14               ## loose plates folded back outside the collar
const FLOOR_SEGMENTS := 22
## Fractions of the opening radius `R`.
const RIM := 0.70                ## where the cavity's lip sits
const DISH := 0.30               ## how deep the cavity dishes, measured from its centre
const COLLAR_H := 0.50           ## how far a flap stands off the lip
const SHARD_H := 0.24
## The loose plates stay just outside the collar. Further out and they leave the trunk's silhouette
## and hang in the air, which is the whole defect this file exists to fix.
const SHARD_RING := 1.02
const CLEAR := 0.15              ## m every piece keeps off the shell so nothing z-fights it
## The heartbeat (review polish 1): emission breathing 0.6 -> 1.4 at 1.2 Hz.
const PULSE_LO := 0.6
const PULSE_HI := 1.4
const PULSE_HZ := 1.2
const LIGHT_BASE := 1.3
const LIGHT_SPAN := 0.7

var radius: float = 5.0
## The shell's radius of curvature the collar was laid against (see `build`).
var curve: float = INF

var _light: OmniLight3D = null
var _phase: float = 0.0
var _t: float = 0.0


## How far a point of the wound sits in front of the trunk's own surface. The trunk is opaque, so a
## piece laid behind it is simply gone and the boil reads as a sticker again — the test measures this.
func clearance(at: Vector3) -> float:
	return at.y - _shell_y(Vector2(at.x, at.z).length(), curve)


## `curve` is the shell's local radius of curvature across the bearing (`FlowHiveSurface.curvature`,
## INF when the trunk is flat there) — without it the collar's outer edge floats metres off a trunk
## that has already curved away.
static func build(color: Color, at: Vector3, normal: Vector3, open_radius: float, sac_radius: float,
		seed_value: int, curve: float, legacy: bool = false) -> FlowHiveCore:
	var node := FlowHiveCore.new()
	node.name = "Core"
	node.radius = open_radius
	node.curve = curve
	node._phase = FlowHivePods.phase_of(seed_value)
	node.transform = _frame(at, normal)
	if legacy:
		# The pre-polish core: one sac cluster laid flat on the shell, no wound, no lamp. Kept only so
		# the A/B that proves the change is one run from one stand (see `LEGACY_CORE_FLAG`).
		var flat := FlowHivePods.cluster(color, sac_radius, seed_value + 5)
		flat.name = "Sacs"
		node.add_child(flat)
		node.set_open(false)
		return node
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	node.add_child(node._collar(rng, curve))
	node.add_child(node._cavity(color, curve))
	node.add_child(node._sacs(color, sac_radius, seed_value))
	node.add_child(node._lamp(color))
	node.set_open(false)
	return node


## Stand +Y along the trunk's normal, the same frame `FlowHivePods.on_trunk` uses.
static func _frame(at: Vector3, normal: Vector3) -> Transform3D:
	var up := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var axis := Vector3.UP.cross(up)
	var basis := Basis.IDENTITY
	if axis.length_squared() > 0.0001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))
	elif up.dot(Vector3.UP) < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	return Transform3D(basis, at)


## Open or shut: the whole boil, its light and its per-frame breathing go together, so a sealed core
## costs nothing and a destroyed spire leaves no violet lamp burning on the wreck.
func set_open(on: bool) -> void:
	visible = on
	set_process(on)
	if _light != null:
		_light.visible = on


func _process(delta: float) -> void:
	_t += delta
	if _light == null:
		return
	var beat := 0.5 + 0.5 * sin(TAU * PULSE_HZ * _t + _phase)
	_light.light_energy = LIGHT_BASE + LIGHT_SPAN * beat


# --- geometry -------------------------------------------------------------------------------------

## Where the trunk's own surface is, `r` metres out from the anchor in the tangent plane. Second
## order: the shell falls away from its tangent plane by r²/2ρ.
func _shell_y(r: float, curve: float) -> float:
	if is_inf(curve) or curve <= 0.0:
		return 0.0
	return -r * r / (2.0 * curve)


## The cavity floor: a dish rising from `CLEAR` at the centre to `CLEAR + DISH*R` at the lip, so it
## reads as a hole with the shell's own bulge as its back wall.
func _floor_y(r: float, curve: float) -> float:
	var t: float = clampf(r / maxf(radius * RIM, 0.01), 0.0, 1.0)
	return maxf(CLEAR + radius * DISH * t * t, _shell_y(r, curve) + CLEAR)


func _collar(rng: RandomNumberGenerator, curve: float) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		_flap(tool, rng, curve, float(i), float(SEGMENTS), RIM, COLLAR_H, 0.42)
	for i in SHARDS:
		# The loose plates barely lean: at 0.55 their tips reached 1.8R, which is off the trunk's
		# silhouette and hanging in the air — the exact defect this file exists to fix.
		_flap(tool, rng, curve, float(i) + 0.5, float(SHARDS), SHARD_RING, SHARD_H, 0.16)
	tool.generate_normals()
	var collar := _mesh(tool.commit(), _chitin())
	collar.name = "Collar"
	return collar


## One torn flap: a plate that is wide where it is still attached to the lip and narrows to a jagged
## tip, leaning `lean` of its own length — negative curls back over the cavity and throws it into
## shadow, positive folds away from it. Both are in the ring, which is what makes the lip read as torn
## rather than machined; a constant-width quad read as a paper card.
func _flap(tool: SurfaceTool, rng: RandomNumberGenerator, curve: float, index: float, count: float,
		base_f: float, height_f: float, lean: float) -> void:
	var mid := TAU * (index + 0.5) / count + rng.randf_range(-0.06, 0.06)
	var half_base := TAU / count * 0.5 * rng.randf_range(0.55, 0.9)
	var half_tip := half_base * rng.randf_range(0.14, 0.45)
	var rb := radius * base_f * rng.randf_range(0.92, 1.08)
	var rt := rb * (1.0 + rng.randf_range(-lean * 0.7, lean))
	var yb := _floor_y(rb, curve) if base_f < 1.0 else _shell_y(rb, curve) + CLEAR
	var yt := _shell_y(rt, curve) + CLEAR + radius * height_f * rng.randf_range(0.6, 1.35)
	var p0 := _ring(rb, mid - half_base, yb)
	var p1 := _ring(rb, mid + half_base, yb)
	var p2 := _ring(rt, mid + half_tip, yt)
	var p3 := _ring(rt, mid - half_tip, yt)
	var dark := Color(0.052, 0.045, 0.066)
	var edge := Color(0.20, 0.16, 0.24)
	_tri(tool, p0, p1, p2, dark, dark, edge)
	_tri(tool, p0, p2, p3, dark, edge, edge)


## The cavity: a dished fan in near-black chitin. It carries NO emission of its own — a uniform
## violet emission across the whole dish is exactly the flat lilac sticker the review flagged. What
## light it gets comes from the lamp in front of it, so the dish has a real falloff into its corners.
func _cavity(color: Color, curve: float) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := radius * RIM
	var heart := color * 0.06
	heart.a = 1.0
	var wall := Color(0.022, 0.019, 0.030)
	for i in FLOOR_SEGMENTS:
		var a0 := TAU * float(i) / FLOOR_SEGMENTS
		var a1 := TAU * float(i + 1) / FLOOR_SEGMENTS
		_tri(tool, Vector3(0.0, _floor_y(0.0, curve), 0.0), _ring(rim, a0, _floor_y(rim, curve)),
				_ring(rim, a1, _floor_y(rim, curve)), heart, wall, wall)
	tool.generate_normals()
	var cavity := _mesh(tool.commit(), _chitin())
	cavity.name = "Cavity"
	return cavity


## The heart itself: the pod sacs packed into the cavity. `core_energy` is 1.0 and the pulse band is
## 0.6 → 1.4, so the peak emission lands exactly on the review's 1.4 ceiling instead of the 2.0 a pod's
## 1.45 base would have given at the top of the beat.
func _sacs(color: Color, sac_radius: float, seed_value: int) -> MeshInstance3D:
	var mi := FlowHivePods.cluster(color, sac_radius, seed_value + 5, radius * 0.45, -0.10)
	mi.material_override = FlowHivePods.beating(color, _phase, PULSE_LO, PULSE_HI, PULSE_HZ, 0.9, 16.0)
	mi.position = Vector3.UP * (CLEAR + sac_radius * 0.25)
	mi.name = "Sacs"
	return mi


## A small unshadowed omni so the torn edges catch the heartbeat. It sits IN FRONT of the sacs, not
## inside them: a lamp buried in a translucent sac lights it from within and the whole cluster blows
## out to white. One per spire, and only while the shell is open (engine rules: no shadowed omni on
## anything that moves).
func _lamp(color: Color) -> OmniLight3D:
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = color
	_light.light_energy = LIGHT_BASE
	_light.omni_range = radius * 3.0
	_light.shadow_enabled = false
	_light.position = Vector3.UP * (radius * 1.05)
	return _light


# --- helpers --------------------------------------------------------------------------------------

func _ring(r: float, a: float, y: float) -> Vector3:
	return Vector3(cos(a) * r, y, sin(a) * r)


func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color,
		cc: Color) -> void:
	tool.set_color(ca)
	tool.add_vertex(a)
	tool.set_color(cb)
	tool.add_vertex(b)
	tool.set_color(cc)
	tool.add_vertex(c)


func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _chitin() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.72
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
