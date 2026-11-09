class_name CrescentMesh
extends RefCounted
## The charged slash's crescent (review r1 MUST-FIX 2): a curved sheet of light, not a flat slab.
##
## Geometry, in the wave's own frame (−Z = travel, +X = across, +Y = up):
##   · `chord` metres across, drawn as an arc that bows FORWARD in the middle (sagitta `BOW`);
##   · `thickness` metres deep at the centre, tapering to points at the two tips;
##   · standing `height` metres tall and leaning back as it rises, so the crest trails the base;
##   · a slight vertical distortion on the crest, so it never reads as extruded cardboard.
##
## The whole gradient lives in the vertex colours: the base — the leading edge that scours the
## ground — is hot white at HDR energy, cooling to cyan by mid-height and fading to nothing at the
## crest and at the tips. `CombatMesh.hdr_vertex()` renders those straight into the glow pass.

const SEGMENTS := 28       ## spans across the chord
const ROWS := 7            ## rows from the leading edge up to the crest
const BOW := 0.22          ## sagitta as a fraction of the chord
const LEAN := 0.55         ## how far the crest trails the base, in thickness units
const HOT := Color("efffff")
const COOL := Color("4fe6ff")
const HOT_ENERGY := 1.7
const COOL_ENERGY := 0.55
const BODY_ALPHA := 0.16   ## the sheet is translucent; only the leading edge is solid light


## Builds the sheet. `phase` shifts the crest distortion so successive waves are not identical.
static func build(chord: float, thickness: float, height: float, phase: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		for j in ROWS:
			var u0 := float(i) / float(SEGMENTS)
			var u1 := float(i + 1) / float(SEGMENTS)
			var w0 := float(j) / float(ROWS)
			var w1 := float(j + 1) / float(ROWS)
			_quad(st, [u0, u1, u1, u0], [w0, w0, w1, w1], chord, thickness, height, phase)
	var mesh := st.commit()
	mesh.surface_set_material(0, CombatMesh.hdr_vertex())
	return mesh


## One grid cell as two triangles, wound consistently so the additive sheet has no dark seams.
static func _quad(st: SurfaceTool, us: Array, ws: Array, chord: float, thickness: float,
		height: float, phase: float) -> void:
	var pts: Array[Vector3] = []
	for i in 4:
		pts.append(_point(chord, thickness, height, phase, float(us[i]), float(ws[i])))
	_tri(st, pts[0], pts[1], pts[2], _color(float(us[0]), float(ws[0])),
			_color(float(us[1]), float(ws[1])), _color(float(us[2]), float(ws[2])))
	_tri(st, pts[0], pts[2], pts[3], _color(float(us[0]), float(ws[0])),
			_color(float(us[2]), float(ws[2])), _color(float(us[3]), float(ws[3])))


## One vertex of the sheet at `u` across the chord and `w` up its height.
static func _point(chord: float, thickness: float, height: float, phase: float, u: float,
		w: float) -> Vector3:
	var s := u * 2.0 - 1.0                     ## −1 .. 1 across the chord
	var taper := _taper(s)
	var bow := -BOW * chord * taper            ## the middle leads, the tips lag
	var crest := height * (0.55 + 0.45 * taper)
	crest *= 1.0 + 0.09 * sin(s * 4.1 + phase)  ## vertical distortion on the crest line
	var lean := LEAN * thickness * taper * w * w
	var wobble := thickness * 0.12 * sin(s * 5.3 + phase * 1.7) * taper
	return Vector3(s * chord * 0.5, crest * w, bow + lean + wobble)


## Points at the tips, thickest at the centre.
static func _taper(s: float) -> float:
	return pow(maxf(1.0 - s * s, 0.0), 0.62)


## White-hot at the base — the leading edge that scours the ground — cooling to cyan within the
## first third of the height and thinning to a translucent veil at the crest, so the sheet reads as
## a crescent of light rather than a lit slab.
static func _color(u: float, w: float) -> Color:
	var s := u * 2.0 - 1.0
	var edge := pow(maxf(1.0 - s * s, 0.0), 0.5)      ## the tips fade to points
	var solid := pow(maxf(1.0 - w, 0.0), 2.4)          ## only the base is solid
	var mix := clampf(w * 3.0, 0.0, 1.0)
	var energy := lerpf(HOT_ENERGY, COOL_ENERGY, mix)
	var alpha := edge * lerpf(BODY_ALPHA, 1.0, solid)
	return Color(HOT.lerp(COOL, mix) * energy, clampf(alpha, 0.0, 1.0))


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color,
		cc: Color) -> void:
	var n := (b - a).cross(c - a)
	st.set_normal(n.normalized() if n.length_squared() > 1e-8 else Vector3.UP)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
