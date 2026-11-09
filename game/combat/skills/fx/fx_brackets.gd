class_name SkillFxBrackets
extends SkillFxPiece
## The four converging brackets of the Zenith Lance charge (0.8 s): corner marks that close in on the
## muzzle and flash white on the last beat before the beam leaves. Drawn in the plane facing the fire
## direction so they read from the gameplay camera without a HUD element.

const OPEN_LIFE := 60.0
const ARM := 0.32   ## bracket arm length as a fraction of the spread

var _arms: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D = null
var _spread: float = 30.0
var _size: float = 26.0
var _duration: float = 0.8
var _driven: float = -1.0   ## >= 0 when the owner drives the convergence (see `set_progress`)


func _ready() -> void:
	super()
	_mat = SkillFx.glow(Color(1.0, 0.86, 0.45), 3.0, true)
	for i in 8:
		var mi := MeshInstance3D.new()
		mi.name = "Bracket%d" % i
		mi.mesh = BoxMesh.new()
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 64.0
		mi.visible = false
		add_child(mi)
		_arms.append(mi)


## `at` is the muzzle, `dir` the direction the lance will travel.
func open(at: Vector3, dir: Vector3, spread: float, size: float, seconds: float,
		color: Color) -> void:
	global_position = at
	var d := dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	global_basis = Basis.looking_at(d, up)
	_spread = spread
	_size = size
	_duration = maxf(seconds, 0.05)
	_driven = -1.0
	_mat.albedo_color = color
	_mat.emission = color
	_begin(OPEN_LIFE)
	_advance(0.0)


## Drives the convergence from the owner's own charge progress (0..1) instead of the world clock.
## The Lance charges on REAL time while the world runs at 0.3x, so a world-timed convergence would
## still be wide open when the beam leaves (audit #10).
func set_progress(u: float) -> void:
	_driven = clampf(u, 0.0, 1.0)
	_advance(0.0)


## Re-aim a running charge (the mech may turn while it charges) without restarting the convergence.
func aim(at: Vector3, dir: Vector3) -> void:
	global_position = at
	var d := dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	global_basis = Basis.looking_at(d, up)


func _advance(_delta: float) -> void:
	var u: float = _driven if _driven >= 0.0 else clampf(_t / _duration, 0.0, 1.0)
	# ease-in: the brackets hang wide, then snap shut on the last third of the charge
	var half: float = lerpf(_size * 0.5, _spread * 0.5, pow(u, 2.6))
	var arm: float = half * ARM
	var thick: float = maxf(half * 0.11, 0.6)
	var flash := 1.0 if u < 0.94 else 2.2
	_mat.emission_energy_multiplier = 3.0 * flash
	for corner in 4:
		var sx: float = 1.0 if (corner & 1) == 0 else -1.0
		var sy: float = 1.0 if (corner & 2) == 0 else -1.0
		var origin := Vector3(sx * half, sy * half, 0.0)
		_place(corner * 2, origin + Vector3(-sx * arm * 0.5, 0.0, 0.0),
				Vector3(arm, thick, thick))
		_place(corner * 2 + 1, origin + Vector3(0.0, -sy * arm * 0.5, 0.0),
				Vector3(thick, arm, thick))


func _place(index: int, local: Vector3, size: Vector3) -> void:
	var mi := _arms[index]
	mi.visible = true
	mi.transform = Transform3D(Basis.IDENTITY.scaled(size), local)


func stop() -> void:
	super()
	for mi in _arms:
		mi.visible = false
