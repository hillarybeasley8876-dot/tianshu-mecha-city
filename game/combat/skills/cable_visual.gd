class_name CableVisual
extends Node3D
## The Skyhook's cable and latch: a 0.5 m emissive core inside a 2.2 m glow tube stretched between the
## `hand_l` socket (CONTRACTS §5 — the left hand the Undertow Well throws from) and the hook tip, plus
## a glowing bead at the tip. Split out of skyhook_anchor.gd so that file stays about the grapple's
## behaviour rather than its geometry.
##
## r1 review: the old single 1.4 m ribbon went sub-pixel at the 120 m range, so the cable is now two
## pooled beam pieces (core + glow) drawn in world space, which stay readable at full range.

const CORE_WIDTH := 0.5
const GLOW_WIDTH := 2.2
const CORE_COLOR := Color(0.92, 1.0, 1.0)
const GLOW_COLOR := Color(0.42, 0.88, 1.0)
const LATCH_COLOR := Color(1.0, 0.85, 0.45)
const LATCH_RADIUS := 1.8

var _vfx: SkillVfx = null
var _core: SkillFxBeam = null
var _glow: SkillFxBeam = null
var _latch: MeshInstance3D = null


func _ready() -> void:
	_latch = MeshInstance3D.new()
	_latch.name = "Latch"
	var sphere := SphereMesh.new()
	sphere.radius = LATCH_RADIUS
	sphere.height = LATCH_RADIUS * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_latch.mesh = sphere
	_latch.material_override = SkillFx.glow(LATCH_COLOR, 5.0)
	_latch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_latch.extra_cull_margin = 32.0
	add_child(_latch)
	_latch.visible = false


## The pooled pieces come from the skills unit's own effect node (fx/** is the feel unit's).
func setup(vfx: SkillVfx) -> void:
	_vfx = vfx


func show_cable() -> void:
	if _vfx == null:
		return
	if _core == null or _core.free_to_use():
		_core = _vfx.beam()
		_core.open(CORE_COLOR, 0.95, 4.0)
	if _glow == null or _glow.free_to_use():
		_glow = _vfx.beam()
		_glow.open(GLOW_COLOR, 0.18, 1.8)
	_latch.visible = true


func hide_cable() -> void:
	if _core != null:
		_core.stop()
		_core = null
	if _glow != null:
		_glow.stop()
		_glow = null
	if _latch != null:
		_latch.visible = false


func is_shown() -> bool:
	return _core != null and not _core.free_to_use()


## Stretches the cable from `from` to `to`; a zero-length cable hides itself rather than drawing a
## degenerate box at the muzzle.
func draw(from: Vector3, to: Vector3) -> void:
	if not is_shown():
		return
	_core.line(from, to, CORE_WIDTH)
	_glow.line(from, to, GLOW_WIDTH)
	_latch.global_position = to
