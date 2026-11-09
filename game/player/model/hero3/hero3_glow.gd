class_name Hero3Glow
extends Node3D
## The parts of the Tianshu that are LIGHT SOURCES rather than lit surfaces (hero-v3 r7): the amber
## visor slit, the chest grille's lit gaps, and a cyan tip on each of the seven blade drones.
##
## The atlas mask (`hero3_emissive.py`) recovers the seam piping, but the visor and the grille are
## small, curved and partly occluded, so they are modelled instead of painted. Nothing here is
## hand-placed: every patch comes from the same vertex walk `Hero3Rig._measure_blade` uses, measured
## on the ARMOUR surface only.
##
## They are PANELS, not boxes. The first pass used one unshaded box per opening and the lead was right
## to call it out -- a solid emissive box reads as an orange rectangle stuck on the armour. The
## concept's sternum is a PORTICULLIS: vertical gold bars with a warm amber cavity glowing between
## them, brightest in the middle. `hero3_glow.gdshader` draws exactly that in one feathered sheet per
## opening, MIXED rather than added (r8) so the atlas behind the cavity can never show through, and
## CONFORMED to the armour surface (r8) so the sheet cannot leave the plate's silhouette.

const SHADER := "res://player/model/hero3/hero3_glow.gdshader"
## bone -> how the grille is cut out of that bone's front face.
## `depth` is how far back from the frontmost point still counts as "the front face" (metres), `drop`
## where the panel starts as a fraction of that patch's height, `span` how much of the height it
## covers, `width` the fraction of the patch's width, `stripes` how many vertical lit gaps it is cut
## into (0 = a solid panel, which is what the visor is) and `duty` the fraction of each stripe period
## the lit part occupies -- the rest is a bar.
## `gain` is a multiplier on `IDLE_GAIN`: the visor is the focal point of the concept's head and has to
## hold its own against the atlas's own bright cyan seam on the helm, where the vent is a cavity.
## `core` is the thin hot line down the middle (the lead's r8 "a thin hot core and a soft glow").
const PATCHES: Array = [
	# the visor: one slit across the face, no bars, a hot core inside a soft glow
	{"bone": "Head", "depth": 0.30, "drop": 0.35, "span": 0.16, "width": 0.70,
		"stripes": 0.0, "duty": 1.0, "centre": 0.5, "gain": 2.0, "core": 1.10,
		"feather": Vector2(0.10, 0.40)},
	# the sternum: the concept's portcullis, seven vertical lit gaps between gold bars
	{"bone": "Spine02", "depth": 0.70, "drop": 0.28, "span": 0.36, "width": 0.36,
		"stripes": 7.0, "duty": 0.36, "centre": 1.0, "gain": 1.0, "core": 0.0,
		"feather": Vector2(0.04, 0.16)},
]
## The drone tip marker: a sliver along the last few per cent of the blade.
const TIP_FRACTION := 0.07
const TIP_WIDTH := 0.16
## Warm gold-amber, the lead's #FFB040 -- not the traffic orange the first pass used.
const VENT_HUE := Color(1.00, 0.69, 0.25)
## The portcullis bars are lit gold metal in the concept, not black.
const BAR_HUE := Color(1.00, 0.70, 0.28)
const TIP_HUE := Color(0.24, 0.92, 1.00)
## Modest: these are lit gaps in a machine, not light bars. The first pass ran them hot enough that
## the middle of the grille tonemapped to white, which is not what the concept does.
const IDLE_GAIN := 0.32
const LIT_GAIN := 0.90

var visor: Array[MeshInstance3D] = []
var vent: Array[MeshInstance3D] = []
var tips: Array[MeshInstance3D] = []
## Where the grilles landed, in SKELETON space at the rest pose. Reported so a gate can assert the
## visor is on the face and not on the chin.
var visor_at := Vector3.ZERO
var vent_at := Vector3.ZERO

## One material per grille (each patch has its own feather), all driven from `update()`.
var _vent_mats: Array[ShaderMaterial] = []
## Each panel's own multiplier on `_gain`, index-aligned with `_vent_mats`.
var _vent_gain: Array[float] = []
var _tip_mat: StandardMaterial3D
var _gain: float = IDLE_GAIN
var _gain_target: float = IDLE_GAIN
var _tint: float = 0.0
## 1 powered, 0 dead: the mech's own power-down (lead r8).
var _power: float = 1.0
var _attached: int = 0
## Overdrive amber, the same hue `Hero3Shade.OVERDRIVE` uses.
const OVERDRIVE_HUE := Color(1.00, 0.72, 0.30)


func setup(skeleton: Skeleton3D, body: MeshInstance3D, armour_surface: int) -> void:
	_tip_mat = _emissive(TIP_HUE)
	var verts := _bone_verts(skeleton, body, armour_surface)
	for spec: Dictionary in PATCHES:
		var bone_name := String(spec["bone"])
		var idx := skeleton.find_bone(bone_name)
		var axis_x := skeleton.get_bone_global_rest(idx).origin.x if idx >= 0 else 0.0
		var made := Hero3Panel.build(verts.get(bone_name, [] as Array[Vector3]), spec, axis_x)
		if made.is_empty():
			push_warning("Hero3Glow: no front patch on %s" % spec["bone"])
			continue
		var node := _sheet(made["mesh"] as ArrayMesh, spec)
		# captured BEFORE `_attach`, which rewrites the transform into bone space
		var at: Vector3 = made["at"]
		_attach(skeleton, bone_name, node)
		if bone_name == "Head":
			visor.append(node)
			visor_at = at
		else:
			vent.append(node)
			vent_at = at
	# index-aligned with `Hero3Rig.DRONE_BONES`, holes and all: the per-drone hide API (lead r8
	# item 4) addresses a drone by index and has to be able to ask about one whose tip failed to build
	tips.resize(Hero3Rig.DRONE_BONES.size())
	for i in Hero3Rig.DRONE_BONES.size():
		var bone_name := Hero3Rig.DRONE_BONES[i]
		var tip := _tip(skeleton, bone_name, verts.get(bone_name, [] as Array[Vector3]))
		if tip == null:
			continue
		_attach(skeleton, bone_name, tip)
		tips[i] = tip


## Hide one drone's modelled cyan tip along with its blade (lead r8 item 4). `index` is 0-based and
## matches `Hero3Rig.DRONE_BONES`.
func set_tip_hidden(index: int, hidden: bool) -> void:
	if index < 0 or index >= tips.size():
		push_warning("Hero3Glow: no drone tip at index %d" % index)
		return
	var tip := tips[index]
	if tip != null:
		tip.visible = not hidden


## `lit` is 0 at rest and 1 while the hero is boosting, in overdrive or charging; `tint` is the
## overdrive blend, which takes the cyan tips amber with the rest of the accents. `power` is the
## mech's own power-down (lead r8): the modelled openings and the drone tips go dark with it.
func set_state(lit: float, tint: float, power: float = 1.0) -> void:
	_gain_target = lerpf(IDLE_GAIN, LIT_GAIN, clampf(lit, 0.0, 1.0))
	_tint = clampf(tint, 0.0, 1.0)
	_power = clampf(power, 0.0, 1.0)


func update(delta: float) -> void:
	_gain = lerpf(_gain, _gain_target, clampf(delta * 8.0, 0.0, 1.0))
	var hue := VENT_HUE.lerp(OVERDRIVE_HUE, _tint)
	for i in _vent_mats.size():
		_vent_mats[i].set_shader_parameter(&"glow_color", hue)
		_vent_mats[i].set_shader_parameter(&"glow_gain", _gain * _vent_gain[i] * _power)
	_tip_mat.albedo_color = TIP_HUE.lerp(OVERDRIVE_HUE, _tint) * _gain * _power


func _emissive(hue: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = hue * IDLE_GAIN
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## The node for one opening: the conformed sheet `Hero3Panel` built, with this opening's own material.
func _sheet(mesh: ArrayMesh, spec: Dictionary) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER) as Shader
	mat.set_shader_parameter(&"feather", spec["feather"])
	mat.set_shader_parameter(&"stripes", float(spec["stripes"]))
	mat.set_shader_parameter(&"duty", float(spec["duty"]))
	mat.set_shader_parameter(&"bar_color", BAR_HUE)
	mat.set_shader_parameter(&"centre", float(spec["centre"]))
	mat.set_shader_parameter(&"core_gain", float(spec["core"]))
	_vent_mats.append(mat)
	_vent_gain.append(float(spec["gain"]))
	var node := MeshInstance3D.new()
	node.name = "GlowPanel"
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the mesh carries its own skeleton-space positions, so `_attach` only has to undo the bone rest
	return node


## The panels are MEASURED in skeleton space, but a `BoneAttachment3D` child is placed in BONE space,
## so the desired skeleton transform has to come back through the bone's rest pose. Without this the
## visor was parented correctly and then flown 13 m above the helm.
func _attach(skeleton: Skeleton3D, bone: String, node: MeshInstance3D) -> void:
	_attached += 1
	var idx := skeleton.find_bone(bone)
	if idx < 0:
		push_error("Hero3Glow: missing bone %s" % bone)
		return
	node.transform = skeleton.get_bone_global_rest(idx).affine_inverse() * node.transform
	var attach := BoneAttachment3D.new()
	attach.name = "Glow_%s_%d" % [bone, _attached]
	attach.bone_idx = idx
	skeleton.add_child(attach)
	attach.add_child(node)

## A sliver along the far end of a drone blade, aimed down the bone -> tip axis.
func _tip(skeleton: Skeleton3D, bone_name: String, pts: Array[Vector3]) -> MeshInstance3D:
	if pts.size() < 4:
		return null
	var idx := skeleton.find_bone(bone_name)
	if idx < 0:
		return null
	var origin := skeleton.get_bone_global_rest(idx).origin
	var far := pts[0]
	var best := -1.0
	for p in pts:
		var d := p.distance_squared_to(origin)
		if d > best:
			best = d
			far = p
	var axis := far - origin
	var length := axis.length()
	if length < 0.2:
		return null
	var dir := axis / length
	var centre := origin + dir * (length * (1.0 - TIP_FRACTION * 0.5))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(TIP_WIDTH, TIP_WIDTH, length * TIP_FRACTION)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _tip_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.basis = _aim(dir)
	node.position = centre
	return node


## A basis whose -Z runs along `dir`, so a box sized on Z is a bar pointing that way.
func _aim(dir: Vector3) -> Basis:
	var back := -dir
	var up := Vector3.UP if absf(back.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(back).normalized()
	return Basis(x, back.cross(x).normalized(), back)


## Every vertex of the armour surface, grouped by the bone that carries it. One walk, reused by the
## visor, the grille and the seven tips.
##
## The ARMOUR surface only: the joint mechanisms and the inner cores are separate surfaces on the
## same mesh and the cores are lofted through the bone, so including them drags the head's bounding
## box 50 cm below the helm and puts the visor on the chin.
func _bone_verts(skeleton: Skeleton3D, body: MeshInstance3D, armour_surface: int) -> Dictionary:
	var out: Dictionary = {}
	if body.mesh == null or body.skin == null:
		push_error("Hero3Glow: the body mesh has no skin to measure")
		return out
	var bind := PackedInt32Array()
	for b in body.skin.get_bind_count():
		var bone := body.skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(String(body.skin.get_bind_name(b)))
		bind.append(bone)
	for s in body.mesh.get_surface_count():
		if s != armour_surface:
			continue
		var arrays := body.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or verts.is_empty():
			continue
		var per := int(bones.size() / verts.size())
		for i in verts.size():
			var top := -1
			var w := -1.0
			for j in per:
				if weights[i * per + j] > w:
					w = weights[i * per + j]
					top = int(bones[i * per + j])
			if top < 0:
				continue
			var bone_name := skeleton.get_bone_name(bind[top])
			if not out.has(bone_name):
				out[bone_name] = [] as Array[Vector3]
			(out[bone_name] as Array[Vector3]).append(verts[i])
	return out


func report() -> Dictionary:
	var built := 0
	for tip in tips:
		if tip != null:
			built += 1
	return {"visor_panels": visor.size(), "vent_panels": vent.size(), "tips": built,
			"visor_at": visor_at, "vent_at": vent_at, "gain": snappedf(_gain, 0.01),
			"power": snappedf(_power, 0.01)}
