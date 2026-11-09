class_name HudGlassHud
extends Node
## First-person canopy HUD (brief §7, feel-mech-games §15.4): the screen-space widgets are re-created
## inside a SubViewport and that texture is projected onto a curved quad sitting just inside the canopy
## glass the camera-aim unit builds, so in the cockpit the pilot reads the instruments off the glass.
##
## The widgets are the SAME scripts the third-person HUD uses, fed by the SAME `HudData`, so the two
## views can never drift apart. The material is alpha-blended, not additive: over a bright sky an
## additive projection washes out, and the HUD's own dark plates are what give the readouts contrast.

## 1280×720, not 1600×900: the quad covers about 1140×670 screen pixels, so this buffer maps close to
## 1:1 and the HUD's 1 px rules stay crisp instead of being blurred away by a 0.71 downscale. The
## widgets still lay out in virtual 1600×900 pixels (`set_scale` below), so nothing moves.
const VIEWPORT_SIZE := Vector2i(1280, 720)
const LAYOUT := Vector2(1600.0, 900.0)
## Buffer pixels per layout pixel — `hud.gd` multiplies this by `hud_scale` to scale the canopy HUD.
const RATIO := float(VIEWPORT_SIZE.x) / LAYOUT.x

# --- placement in the cockpit's local space (metres, eye at the origin, -Z forward) ---------------
## The quad is sized to the canopy's USABLE area — inside the A-pillars (x ±1.16 m) and above the
## dashboard (y −0.65 m) — so nothing the pilot needs is hidden behind the frame (feel-mech-games §15.4).
const QUAD_CENTER := Vector3(0.0, 0.06, -1.5)
const QUAD_SIZE := Vector2(2.28, 1.34)
const CURVE := 0.14                              ## m the edges bend away from the pilot
const SEGMENTS := Vector2i(20, 12)
const PARALLAX := 0.010                          ## m of lateral lag per rad/s of turn
const PARALLAX_MAX := 0.035
## s the projection must be up before it takes the overlay over from the screen widgets: the rig blends
## into the cockpit over about a second, and a HUD that vanishes for the whole blend reads as a bug.
const HANDOVER_DELAY := 1.2

## Widgets that stay on the screen even in the cockpit: the boss title card is a cinematic, not an
## instrument, and painting it across the canopy would bury the readouts the pilot needs.
const SCREEN_ONLY: Array[StringName] = [&"boss_card"]

var data: HudData = null
var active: bool = false

var _viewport: SubViewport = null
var _root: Control = null
var _quad: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _yaw_prev: float = 0.0
var _offset: float = 0.0
var _up_t: float = 0.0
var _last_real: float = -1.0      ## last frame's Feel.real_now(), see _process


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.handle_input_locally = false
	add_child(_viewport)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_root)


## The canopy layout is always virtual 1600×900 — the same space the screen HUD uses — and `k` is
## `buffer / layout × hud_scale` (see `hud.gd::_apply_scale`), so only the player's preference moves it.
func set_scale(k: float) -> void:
	_root.scale = Vector2(k, k)
	_root.size = LAYOUT


## Mirrors the screen HUD inside the viewport: `hud.gd` hands over the same widget scripts it
## instances for the third-person view, so the two can never drift apart (brief §7).
func build_widgets(d: HudData, widgets: Dictionary, prefs: HudPrefs) -> void:
	data = d
	for key: StringName in widgets:
		if key in SCREEN_ONLY:
			continue
		var w: Control = widgets[key].new()
		w.name = "Glass_" + String(key)
		w.set(&"data", d)
		_root.add_child(w)
		if key == &"numbers":
			w.set(&"prefs", prefs)


## The canopy copy of a widget, so `hud.gd` can forward state that arrives from outside the frame
## loop — in first person the screen widgets are suppressed, and a tutorial prompt the flow asked for
## has to reach the projection instead (CONTRACTS §6).
func widget(key: StringName) -> HudWidget:
	return _root.get_node_or_null(NodePath("Glass_" + String(key))) as HudWidget


## The canopy projection is only allowed to replace the screen HUD once the quad actually exists and
## is on screen; if the cockpit is missing the screen widgets stay up rather than the pilot losing
## every readout (brief §7).
func is_showing() -> bool:
	# `is_visible_in_tree`, not `visible`: the quad hangs under the cockpit, which the camera rig hides
	# in third person, so this stays false until the canopy is really in front of the pilot — and for
	# HANDOVER_DELAY after that, so the switch never blanks the readouts mid-blend.
	return active and _quad != null and is_instance_valid(_quad) and _quad.is_visible_in_tree() \
			and _up_t >= HANDOVER_DELAY


## Called by hud.gd when the camera flips between third and first person.
func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	_up_t = 0.0
	# Re-seed the parallax clock and yaw on every entry, or the first frame would measure a turn
	# against whatever the camera was doing seconds ago.
	_last_real = -1.0
	_offset = 0.0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on:
		_attach()
	if _quad != null:
		_quad.visible = on


## Parents the projection quad under the camera rig's canopy group. The canopy belongs to the
## camera-aim unit; this only adds a child at runtime and degrades to the rig itself if it is absent.
func _attach() -> void:
	if _quad != null and is_instance_valid(_quad):
		return
	var host := _host()
	if host == null:
		return
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color.WHITE
	_material.albedo_texture = _viewport.get_texture()
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.disable_receive_shadows = true
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_quad = MeshInstance3D.new()
	_quad.name = "CanopyHud"
	_quad.mesh = _curved_quad()
	_quad.material_override = _material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 1.0
	_quad.position = QUAD_CENTER
	host.add_child(_quad)


func _host() -> Node3D:
	var rig := Game.camera_rig
	if rig == null:
		return null
	var cockpit := rig.get_node_or_null(^"Cockpit") as Node3D
	if cockpit != null:
		var canopy := cockpit.get_node_or_null(^"Canopy") as Node3D
		if canopy != null:
			return canopy
	return cockpit if cockpit != null else rig


## A cylindrical section: flat in the middle, bending away at the edges the way a canopy does, so the
## readouts near the pillars do not look pasted on.
func _curved_quad() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for j in SEGMENTS.y + 1:
		for i in SEGMENTS.x + 1:
			var u := float(i) / float(SEGMENTS.x)
			var v := float(j) / float(SEGMENTS.y)
			var x := (u - 0.5) * QUAD_SIZE.x
			var y := (v - 0.5) * QUAD_SIZE.y
			var bend := CURVE * pow(absf(x) / (QUAD_SIZE.x * 0.5), 2.0)
			verts.append(Vector3(x, y, bend))
			uvs.append(Vector2(u, 1.0 - v))
	for j in SEGMENTS.y:
		for i in SEGMENTS.x:
			var a := j * (SEGMENTS.x + 1) + i
			var b := a + 1
			var c := a + SEGMENTS.x + 1
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Slight parallax: the projection slides against a turn and settles, the way a real reflector sight
## would (brief §7). Runs only while the cockpit is up. The camera rig turns on real time, so the rate
## has to be measured in real seconds too: dividing a real yaw step by the time-scaled frame delta
## overestimated it 20x in a hit-stop (audit #5).
func _process(_delta: float) -> void:
	if not active or _quad == null or data == null or data.camera == null:
		_up_t = 0.0
		_last_real = -1.0
		return
	var now := Feel.real_now()
	if _last_real < 0.0:
		_last_real = now
		_yaw_prev = _yaw(data.camera)
	var dt := clampf(now - _last_real, 0.0, 0.1)
	_last_real = now
	_up_t += dt
	var yaw := _yaw(data.camera)
	var rate := wrapf(yaw - _yaw_prev, -PI, PI) / maxf(dt, 0.0001)
	_yaw_prev = yaw
	var want := clampf(-rate * PARALLAX, -PARALLAX_MAX, PARALLAX_MAX)
	_offset = lerpf(_offset, want, 1.0 - exp(-8.0 * dt))
	_quad.position = QUAD_CENTER + Vector3(_offset, 0.0, 0.0)


func _yaw(cam: Camera3D) -> float:
	var fwd := -cam.global_basis.z
	return atan2(fwd.x, -fwd.z)
