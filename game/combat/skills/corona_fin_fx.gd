class_name CoronaFinFx
extends RefCounted
## The Corona Fins' look, split out of corona_fins.gd: the blade mesh with its station marker, the
## cyan trail the thrown blades drag behind them and the two-layer beam each fin fires (r2 review:
## the r1 0.6 m core was sub-pixel past ~100 m, so the beams are now a 1.2 m core inside a 4 m glow,
## telegraphed by a 4 f pre-flash ring at the fin itself and answered by hit sparks on the target).
##
## Every entry point is static and null-tolerant on `ctx.vfx`, so the skill still runs (and still
## deals its damage) when the effects node is missing.

const FIN_LENGTH := 7.0
const BEAM_CORE_WIDTH := 1.2
const BEAM_GLOW_WIDTH := 4.0
const MARKER_RADIUS := 1.5       ## the bright bead that keeps a fin readable on its 18 m station
const PRE_FLASH_RING := 5.0
const HIT_SPARK_RADIUS := 3.6
const BEAM_SECONDS := 0.22      ## one beam lives exactly as long as the gap: a continuous barrage
const PRE_FLASH := 4.0 / 60.0   ## the fin charges for 4 frames before it fires
const TRAIL_GAP := 0.045
const FIN_COLOR := Color(0.35, 0.92, 1.0)
const BEAM_COLOR := Color(0.75, 1.0, 1.0)


## The blade plus the marker bead that says "a drone is holding this station": at 100-240 m the 7 m
## sliver of a blade is a few pixels, the 1.5 m emissive bead is what the eye actually catches.
static func blade_mesh() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = "Fin"
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 0.4, FIN_LENGTH)
	m.mesh = box
	m.material_override = SkillFx.glow(FIN_COLOR, 3.2)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bead := MeshInstance3D.new()
	bead.name = "Marker"
	var sphere := SphereMesh.new()
	sphere.radius = MARKER_RADIUS
	sphere.height = MARKER_RADIUS * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	bead.mesh = sphere
	bead.material_override = SkillFx.glow(BEAM_COLOR, 3.6)
	bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(bead)
	return m


## Points a blade's long axis down `dir` (the blade mesh runs along its local -Z).
static func look_along(mesh: MeshInstance3D, dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	mesh.global_basis = Basis.looking_at(dir, up)


## The 4 f charge tell at the muzzle: a shell on the fin and a flat ring standing across the shot,
## so the volley is telegraphed from the drone and not only from the target.
static func pre_flash(vfx: SkillVfx, at: Vector3, dir: Vector3) -> void:
	if vfx == null:
		return
	vfx.shell().fire(at, 0.3, 3.6, PRE_FLASH + 0.04, FIN_COLOR, BEAM_COLOR, 2.8, 1.6)
	var n := dir if dir.length_squared() > 0.0001 else Vector3.UP
	vfx.ring().fire(at, n.normalized(), 0.6, PRE_FLASH_RING, PRE_FLASH + 0.05, BEAM_COLOR, 0.12, 2.4)


## The shot itself: a hot core inside a wider glow tube, both living one beam gap.
static func fire_beam(vfx: SkillVfx, from: Vector3, to: Vector3) -> void:
	if vfx == null:
		return
	vfx.beam().flash(from, to, BEAM_GLOW_WIDTH, FIN_COLOR, BEAM_SECONDS, 1.8, 0.2)
	vfx.beam().flash(from, to, BEAM_CORE_WIDTH, BEAM_COLOR, BEAM_SECONDS, 3.2, 0.95)


## Where the beam lands: a short pop plus a light flash, so a hit is visible on the target's body
## even when the target itself is small in frame.
static func hit_spark(vfx: SkillVfx, at: Vector3) -> void:
	if vfx == null:
		return
	vfx.shell().fire(at, 0.4, HIT_SPARK_RADIUS, 0.18, FIN_COLOR, BEAM_COLOR, 2.4, 2.2)


## One short ribbon between where the blade was and where it is now. Ribbons come from their own pool:
## six fins in flight produce ~30 of them at once, which used to evict the Skyhook cable and the Lance
## layers from the shared beam pool (audit #6).
static func trail(vfx: SkillVfx, from: Vector3, to: Vector3) -> void:
	if vfx == null or from.distance_to(to) <= 0.4:
		return
	vfx.trail().flash(from, to, 1.2, FIN_COLOR, 0.24, 1.8, 0.6)
