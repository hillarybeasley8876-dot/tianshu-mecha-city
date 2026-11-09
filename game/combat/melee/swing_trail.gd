class_name SwingTrail
extends MeshInstance3D
## The saber's swing ribbon: a band of quads swept between the blade's root→tip line on every physics
## tick of a move's active window, fading over `MeleeTable.TRAIL_FADE` (FEEL.md melee_light /
## melee_heavy "arc sparks").
##
## TWO DEFECTS THIS FILE EXISTS TO PREVENT (review r5 item 1):
##  * A quad drawn between two poses the blade was never in at the same time. The string chains
##    L1→L2 through a cancel window shorter than TRAIL_FADE, so the finished swing's samples are
##    still alive when the next swing starts sampling; joining them drew the grey card that hung
##    beside the mech in the r4 filmstrips. Every swing therefore gets a LANE, and a quad never
##    bridges two of them.
##  * A dead arc held at full brightness. Each sample carries its own timestamp and fades on its own
##    clock — one shared timer was reset by every new sample and kept the previous swing lit.

const TRAIL_ENERGY := 1.6
const TRAIL_POINTS := 8
const RIBBON_MID := 0.5      ## where along the blade the ribbon's middle vertex sits
const ROOT_LANE := 0.3       ## the hilt half of the ribbon is held back this far (see `_lane_quad`)
const HEAD_ALPHA := 0.4      ## peak opacity PER QUAD: the fan's lanes overlap, and additive
                             ## blending sums them — at 0.85 a dozen quads clip to a white card
const TRAIL_INNER := 0.62    ## the ribbon starts this far up the blade, not at the hilt
## The furthest the blade may travel between two consecutive samples, and therefore the longest quad
## the ribbon can ever draw. This is deliberately TIGHT: a quad is `blade length x step`, so a 12 m
## step is a 12 x 5 m sheet of paper beside the mech — the "grey card" of review r5 item 1. Measured
## travel is 0.2–0.6 m per tick during an active window and ~2.2 m per tick for the fastest clip
## swing, so 3 m never cuts a real swing; anything faster restarts the ribbon instead.
const MAX_STEP := 3.0
const MIN_SAMPLE_STEP := 0.08  ## m below which a sample is the same pose (a hit-stop holds the arm)
## How far the blade tip may get from the newest sample before the ribbon is dropped as stale. This
## is the same order as MAX_STEP on purpose: the shipped hero's clips swing 12–22 frames
## AFTER the active window closes, so the finished arc sat 7–10 m from the blade for the rest of its
## fade — measured on screen in the r4 strips, and exactly the "grey card floating beside the mech"
## the lead flagged (review r5 item 1). Measured drift after the window closes is ~0.3 m per tick, so
## 3 m drops the stale arc ~0.05 s into its fade while a LIVE swing (0.2–0.6 m per tick) never
## reaches it.
const DETACH_STEP := 3.0

var sampling: bool = false

var _ribbon: ImmediateMesh = null
var _tips: Array[Vector3] = []
var _roots: Array[Vector3] = []
var _stamps: Array[float] = []   ## `_clock` when each sample was taken
var _lanes: Array[int] = []      ## which swing each sample belongs to
var _drawn: Array[float] = []    ## root→root span of every quad the last rebuild drew (tests read it)
var _lane_quads: int = 0         ## …of those, how many touch the CURRENT swing's samples
var _bridges: int = 0            ## …and how many straddle two swings (must stay 0)
var _clock: float = 0.0
var _lane: int = 0


func _ready() -> void:
	name = "Trail"
	## The ribbon's vertices are WORLD positions, so the mesh must not inherit its parent's
	## transform — without `top_level` every quad is transformed twice and lands tens of metres
	## away, which is what whited out the r2 captures.
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbon = ImmediateMesh.new()
	mesh = _ribbon
	material_override = CombatMesh.trail()


## Starts a new swing: nothing drawn from here on may join a sample taken before this call.
func open_lane() -> void:
	_lane += 1


func set_sampling(on: bool) -> void:
	sampling = on


func clear() -> void:
	_tips.clear()
	_roots.clear()
	_stamps.clear()
	_lanes.clear()
	_drawn.clear()
	_lane_quads = 0
	_bridges = 0
	_ribbon.clear_surfaces()


## The blade's TIP, every tick. A ribbon the blade has already run away from is not a trail — see
## DETACH_STEP. The TIP is the measure, not the root: the hand barely moves while the tip swings
## through 180°. Only applies between swings: while a swing is sampling, the newest sample IS the
## blade and the ribbon is attached by construction.
func track(tip: Vector3) -> void:
	if sampling or _tips.is_empty():
		return
	if _tips.back().distance_to(tip) > DETACH_STEP:
		clear()


## One sample of the blade's root→tip line. A gap wider than one plausible swing step (a lunge, a
## teleport, a respawn) restarts the ribbon instead of stretching one quad across the whole map; a
## step below MIN_SAMPLE_STEP is the same pose — a local hit-stop holds the arm dead still, and the
## frozen trail is exactly what that frame should show.
func sample(root: Vector3, tip: Vector3) -> void:
	if not _roots.is_empty():
		var step: float = _roots.back().distance_to(root)
		if step > MAX_STEP:
			clear()
		elif step < MIN_SAMPLE_STEP:
			return
	_roots.append(root)
	_tips.append(tip)
	_stamps.append(_clock)
	_lanes.append(_lane)
	while _tips.size() > TRAIL_POINTS:
		_tips.pop_front()
		_roots.pop_front()
		_stamps.pop_front()
		_lanes.pop_front()


## Rebuilt on the PHYSICS tick so the trail shows every sample at 120 Hz, in the same tick the blade
## and the hit volume read.
func _physics_process(delta: float) -> void:
	_clock += delta
	_prune()
	if not _stamps.is_empty() or _ribbon.get_surface_count() > 0:
		_rebuild()


## Drops samples older than TRAIL_FADE.
func _prune() -> void:
	while not _stamps.is_empty() and _clock - _stamps[0] > MeleeTable.TRAIL_FADE:
		_stamps.pop_front()
		_roots.pop_front()
		_tips.pop_front()
		_lanes.pop_front()
	if _stamps.is_empty() and _ribbon.get_surface_count() > 0:
		clear()


## A three-vertex-wide ribbon spanning the FULL blade length, built as triangles: a 3-wide
## TRIANGLE_STRIP folds back on itself every sample and renders as a bowtie. The leading lane (root →
## mid) is white-hot, the trailing lane (mid → tip) cools to cyan, and both fade toward the tail.
##
## Two quads are never drawn: one that BRIDGES two swings (see `open_lane`) and one longer than
## MAX_STEP. Both are the "grey card floating beside the mech" defect — a quad built from two poses
## the blade was never in at the same time.
func _rebuild() -> void:
	_ribbon.clear_surfaces()
	_drawn.clear()
	_lane_quads = 0
	_bridges = 0
	if _tips.size() < 2:
		return
	_ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := _tips.size()
	for i in n - 1:
		if not _joins(i):
			continue
		var a := _alpha(i, float(i) / float(n - 1))
		var b := _alpha(i + 1, float(i + 1) / float(n - 1))
		_lane_quad(_roots[i], _tips[i], a, _roots[i + 1], _tips[i + 1], b)
		_drawn.append(_roots[i].distance_to(_roots[i + 1]))
		if _lanes[i] != _lanes[i + 1]:
			_bridges += 1
		if _lanes[i + 1] == _lane:
			_lane_quads += 1
	_ribbon.surface_end()


## Whether samples `i` and `i + 1` may be joined by a quad.
func _joins(i: int) -> bool:
	if _lanes[i] != _lanes[i + 1]:
		return false
	return _roots[i].distance_to(_roots[i + 1]) <= MAX_STEP


## Newest sample (the blade right now) is brightest; the tail falls away to nothing, and each sample
## also fades by its own age. Even the head stays translucent: a 14 m quad at full alpha reads as a
## sheet of paper held beside the mech.
func _alpha(i: int, k: float) -> float:
	var age := clampf(1.0 - (_clock - _stamps[i]) / MeleeTable.TRAIL_FADE, 0.0, 1.0)
	return age * k * k * HEAD_ALPHA


## One segment of the ribbon between two samples: two quads, inner→mid and mid→tip. The ribbon
## starts TRAIL_INNER of the way up the blade — a sheet drawn from the hilt is a card held beside
## the mech, and the hilt end barely moves anyway.
##
## ADD blending IGNORES alpha, so the fade has to live in the colour: `a` scales the energy. The r4
## strips were a flat white card for exactly that reason — the ribbon's alpha ramp never reached the
## blend equation, and the whole sheet snapped off in one frame when the fade timer ran out.
func _lane_quad(r0: Vector3, t0: Vector3, a0: float, r1: Vector3, t1: Vector3, a1: float) -> void:
	var i0 := r0.lerp(t0, TRAIL_INNER)
	var i1 := r1.lerp(t1, TRAIL_INNER)
	var m0 := i0.lerp(t0, RIBBON_MID)
	var m1 := i1.lerp(t1, RIBBON_MID)
	var c0 := a0 * ROOT_LANE
	var c1 := a1 * ROOT_LANE
	_quad(i0, m0, m1, i1, _tint(c0, false), _tint(c0, true), _tint(c1, true), _tint(c1, false))
	_quad(m0, t0, t1, m1, _tint(a0, true), _tint(a0, false), _tint(a1, false), _tint(a1, true))


## One ribbon vertex colour: cyan-white at the blade's edge, cooler behind it, energy scaled by the
## fade so the tail really disappears.
func _tint(a: float, hot: bool) -> Color:
	var c := (SaberVisual.CORE_COLOR.lerp(SaberVisual.GLOW_COLOR, 0.3)) if hot \
			else SaberVisual.GLOW_COLOR
	return Color(c * (TRAIL_ENERGY * a), a)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color,
		cd: Color) -> void:
	_vertex(a, ca)
	_vertex(b, cb)
	_vertex(c, cc)
	_vertex(a, ca)
	_vertex(c, cc)
	_vertex(d, cd)


func _vertex(at: Vector3, color: Color) -> void:
	_ribbon.surface_set_color(color)
	_ribbon.surface_set_normal(Vector3.UP)
	_ribbon.surface_add_vertex(at)


## Root→root span of every quad the last rebuild actually drew.
func spans() -> Array[float]:
	return _drawn.duplicate()


## Quads the last rebuild drew that touch the CURRENT swing's samples. It is 0 on the first tick of a
## new swing by construction — a quad needs two samples, and the lane guard refuses to borrow one
## from the swing before.
func new_lane_quads() -> int:
	return _lane_quads


## Quads the last rebuild drew ACROSS two swings. Always 0; the tests read it so that removing the
## lane guard fails the suite instead of quietly passing.
func bridges() -> int:
	return _bridges
