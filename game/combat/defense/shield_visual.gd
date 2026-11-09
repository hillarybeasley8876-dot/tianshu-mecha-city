class_name ShieldVisual
extends Node3D
## Mirror Guard visuals (FEEL.md parry_perfect / block / catch_release). r7 rebuilt this surface:
## the old one was a flat hexagonal cylinder 13 m across with ONE alpha everywhere, so it rendered as
## an opaque mint-green tile pasted over the hero and the enemy it was blocking.
##
## What it is now:
##   * a CURVED hexagonal cap the size of the mech's own chest (`DefenseTable.PANEL_RADIUS` 4.6 m),
##     built as a tessellated shell so it catches a fresnel instead of reading as a plane;
##   * a `mirror_shield.gdshader` surface that is nearly empty in the middle and bright on the rim
##     (`MirrorShieldProfile`), in the hero's own seam cyan — the hero and the target stay visible
##     straight through it;
##   * a ripple that travels out of the point a block landed on, a white-gold flash plus a burst of
##     hex shards on a perfect parry, and a fade in/out instead of a visibility pop.
##
## The node lives in world space (`top_level`) so the panel can sit in front of the mech along the
## guard facing without inheriting the model's arm animation.

const HEX_SIDES := 6
const RING_SEGMENTS := 40
## r7: the ring was `fff2c0 * 2.2`, and the r6 capture `captures/melee_int_07_parry_return.jpg` shows
## what that does under ART.md's AgX tonemap — every channel clips and the white-gold hoop arrives as
## a screen-filling white donut. 1.30 is still over the glow threshold (so it blooms) while leaving
## the gold its hue. `DefenseVisualSuite` pins the band that keeps both true.
const RING_ENERGY := 1.30
const RING_BAND := 0.10   ## fraction of the radius the annulus spans

var guarding: bool = false

var _panel: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _shards: ParryShards = null
var _ring: MeshInstance3D = null
var _ring_mesh: ImmediateMesh = null
var _ring_left: float = 0.0
var _ring_plane: Plane = Plane()
var _socket: Node3D = null
var _owner: Node = null
var _fade: float = 0.0          ## 0..1, the shader's `fade` uniform
var _fade_t: float = 0.0        ## seconds since the fade turned that way
var _ripple: float = -1.0       ## seconds since the last block landed, <0 = no ripple
var _ripple_uv: Vector2 = Vector2.ZERO
var _flash: float = 0.0


func _ready() -> void:
	top_level = true
	_owner = get_parent()
	_build_panel()
	_build_ring()
	_shards = ParryShards.new()
	_shards.name = "Shards"
	add_child(_shards)
	set_guard(false)


## A curved hexagonal cap: a polar grid pushed out onto the hexagon's outline and bulged along its
## own normal, so the silhouette is still the Mirror Guard's hexagon but the surface is a shell.
func _build_panel() -> void:
	_panel = MeshInstance3D.new()
	_panel.name = "Panel"
	_panel.mesh = _cap()
	_mat = MirrorShieldProfile.material()
	_panel.material_override = _mat
	_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_panel.visible = false
	add_child(_panel)


## The cap mesh. Ring 0 is the single centre vertex; every other ring is PANEL_SEGMENTS wide and is
## scaled onto the hexagon by `_hex_radius`, so the outline has six straight sides and the interior
## stays a clean radial grid. Normals come from the cap's own slope, which is what makes the fresnel
## rim sweep across it as the guard turns.
func _cap() -> ArrayMesh:
	var r := DefenseTable.PANEL_RADIUS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := DefenseTable.PANEL_RINGS
	var segs := DefenseTable.PANEL_SEGMENTS
	for ring in rings:
		var t0 := float(ring) / float(rings)
		var t1 := float(ring + 1) / float(rings)
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			if ring == 0:
				_point(st, r, 0.0, 0.0)
				_point(st, r, a0, t1)
				_point(st, r, a1, t1)
				continue
			_point(st, r, a0, t0)
			_point(st, r, a0, t1)
			_point(st, r, a1, t1)
			_point(st, r, a0, t0)
			_point(st, r, a1, t1)
			_point(st, r, a1, t0)
	return st.commit()


## One vertex of the cap: `angle` around the hexagon, `t` out from the centre (0..1).
func _point(st: SurfaceTool, radius: float, angle: float, t: float) -> void:
	var dir := Vector3(cos(angle), sin(angle), 0.0)
	var flat := dir * (radius * t * _hex_radius(angle))
	var z := -DefenseTable.PANEL_BULGE * (1.0 - t * t)
	## The slope of the cap in the (radial, z) plane — 0 at the centre, ~25 deg at the rim.
	var slope := 2.0 * DefenseTable.PANEL_BULGE * t
	st.set_normal(Vector3(dir.x * slope, dir.y * slope, -radius).normalized())
	st.set_uv(Vector2(flat.x, flat.y) / radius * 0.5 + Vector2(0.5, 0.5))
	st.set_color(Color.WHITE)
	st.add_vertex(Vector3(flat.x, flat.y, z))


## Scales the unit circle out onto a regular hexagon: 1 on the corners, cos(30 deg) on the sides.
func _hex_radius(angle: float) -> float:
	var a := fmod(angle, TAU / float(HEX_SIDES)) - PI / float(HEX_SIDES)
	return cos(PI / float(HEX_SIDES)) / cos(a)


func _build_ring() -> void:
	_ring_mesh = ImmediateMesh.new()
	_ring = MeshInstance3D.new()
	_ring.name = "PerfectRing"
	_ring.mesh = _ring_mesh
	_ring.material_override = CombatMesh.hdr_vertex()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


## Attaches to the model's `shield_l` socket when one exists (HeroModel API, CONTRACTS §5).
func attach(model: Node) -> void:
	if model != null and model.has_method(&"socket"):
		_socket = model.call(&"socket", &"shield_l") as Node3D


## Raising the guard starts the fade IN; dropping it starts the fade OUT. The panel stays visible
## while it fades out, so the guard leaves instead of popping.
func set_guard(on: bool) -> void:
	if guarding != on:
		_fade_t = 0.0
	guarding = on


## Called every physics tick with the mech's position and guard facing: the panel floats in front of
## the left forearm, on the shield arm rather than over the chest, and stands upright across the
## guard facing so a 140° block reads as a plate held toward the attack.
func place(at: Vector3, facing: Basis) -> void:
	if not guarding and _fade <= 0.0:
		return
	var origin := _arm(at, facing)
	var normal := -facing.z
	var basis := Basis.looking_at(normal, Vector3.UP)
	_panel.global_transform = Transform3D(basis, origin + normal * DefenseTable.PANEL_OFFSET)


## Where the shield arm is: the `shield_l` socket when the model has one, else the mech's left side.
func _arm(at: Vector3, facing: Basis) -> Vector3:
	if _socket != null and is_instance_valid(_socket):
		return _socket.global_position
	return at + Vector3.UP * 9.0 - facing.x * 5.0


## A block landed: a ring travels out of the point it hit (lead r7). The hit position is projected
## into the panel's own UV space, so the ripple starts where the attack actually connected.
func impact(at: Vector3) -> void:
	_ripple = 0.0
	_ripple_uv = _uv_of(at)


## The hit position in the panel's -1..1 UV space, clamped to the panel so a hit that landed past the
## rim still ripples from the edge nearest to it.
func _uv_of(at: Vector3) -> Vector2:
	if _panel == null:
		return Vector2.ZERO
	var local := _panel.global_transform.affine_inverse() * at
	var uv := Vector2(local.x, local.y) / DefenseTable.PANEL_RADIUS
	return uv.limit_length(1.0) if uv.length() > 1.0 else uv


## One step of the surface: the fade envelope, the ripple and the parry flash. Driven from
## `DefenseSystem._physics_process` with PLAYER time, so a hit-stop holds the shield's animation with
## the rest of the mech (CONTRACTS §3) and the numbers are the same headless and in a capture.
func tick(delta: float) -> void:
	_fade = MirrorShieldProfile.fade_step(_fade, guarding, delta)
	_fade_t += delta
	if _ripple >= 0.0:
		_ripple += delta
		if _ripple >= MirrorShieldProfile.RIPPLE_TIME:
			_ripple = -1.0
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
	if _mat != null:
		_mat.set_shader_parameter(&"fade", _fade)
		_mat.set_shader_parameter(&"ripple", _ripple_uniform())
		_mat.set_shader_parameter(&"flash", _flash_uniform())
	if _panel != null:
		_panel.visible = _fade > 0.0
	if _shards != null:
		_shards.tick(delta)


## `ripple` is (origin uv, progress); progress 0 switches the term off in the shader.
func _ripple_uniform() -> Vector3:
	var r := MirrorShieldProfile.ripple_at(_ripple)
	if r.y <= 0.0:
		return Vector3.ZERO
	return Vector3(_ripple_uv.x, _ripple_uv.y, r.x)


func _flash_uniform() -> float:
	return _flash / MirrorShieldProfile.FLASH_TIME


## The white-gold ring that snaps outward on a perfect parry (FEEL.md parry_perfect): a VERTICAL
## shockwave standing between the two fighters, square on to `normal` (the direction of the
## attacker), the panel's own flash, and a burst of hex shards off the panel. `normal` is the guard
## facing.
func flash_perfect(at: Vector3, normal: Vector3 = Vector3.FORWARD) -> void:
	_ring_left = DefenseTable.PERFECT_RING_TIME
	_flash = MirrorShieldProfile.FLASH_TIME
	var n := normal if normal.length_squared() > 0.0001 else Vector3.FORWARD
	var origin := at + Vector3.UP * 8.0 + n.normalized() * DefenseTable.PANEL_OFFSET
	_ring_plane = Plane(n.normalized(), origin)
	_ring.global_transform = Transform3D(Basis.looking_at(n, Vector3.UP), origin)
	_ring.visible = true
	if _shards != null:
		_shards.burst(_panel.global_position if _panel != null else origin, n.normalized())
	CombatVfx.spawn(_owner, &"spark_burst", origin, n, 1.3)
	CombatVfx.flash(_owner, origin, DefenseTable.PERFECT_COLOR, 4.5, 28.0)


func _process(delta: float) -> void:
	if _ring_left <= 0.0:
		return
	_ring_left = maxf(_ring_left - delta, 0.0)
	var k := 1.0 - _ring_left / DefenseTable.PERFECT_RING_TIME
	_draw_ring(_radius(k), _ring_alpha(k))
	if _ring_left <= 0.0:
		_ring_mesh.clear_surfaces()
		_ring.visible = false


## 0 → 18 m in PERFECT_RING_GROW, then it holds while the rest of the life fades out.
func _radius(k: float) -> float:
	var grow := clampf(k * DefenseTable.PERFECT_RING_TIME / DefenseTable.PERFECT_RING_GROW, 0.0, 1.0)
	return DefenseTable.PERFECT_RING_RADIUS * (1.0 - pow(1.0 - grow, 3.0))


func _ring_alpha(k: float) -> float:
	var grow := clampf(k * DefenseTable.PERFECT_RING_TIME / DefenseTable.PERFECT_RING_GROW, 0.0, 1.0)
	return clampf(grow * (1.0 - k) * 2.0, 0.0, 1.0)


## A flat annulus in the ring's own XY plane (the node is already turned to face the attacker), so it
## reads as a hoop standing between the fighters. A line loop would vanish in a capture.
func _draw_ring(radius: float, alpha: float) -> void:
	_ring_mesh.clear_surfaces()
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var hot := Color(DefenseTable.PERFECT_COLOR * RING_ENERGY, alpha)
	var band := maxf(radius * RING_BAND, 0.6)
	for i in RING_SEGMENTS + 1:
		var a := TAU * float(i) / float(RING_SEGMENTS)
		var dir := Vector3(cos(a), sin(a), 0.0)
		_vertex(dir * (radius - band), hot)
		_vertex(dir * (radius + band), Color(hot, 0.0))
	_ring_mesh.surface_end()


func _vertex(at: Vector3, color: Color) -> void:
	_ring_mesh.surface_set_color(color)
	_ring_mesh.surface_set_normal(-_ring.global_basis.z)
	_ring_mesh.surface_add_vertex(at)


## Where the ring stands, for the test that checks it is in front of the shield and square on.
func ring_plane() -> Plane:
	return _ring_plane


## Everything below is read by `DefenseVisualSuite` — the surface has to be measurable headless,
## because the lead's gate on this round is numbers and the captures only confirm them.
func fade() -> float:
	return _fade


func ripple_strength() -> float:
	return MirrorShieldProfile.ripple_at(_ripple).y


func ripple_uv() -> Vector2:
	return _ripple_uv


func flash() -> float:
	return _flash_uniform()


func shards_active() -> int:
	return _shards.active() if _shards != null else 0


func shard_pool() -> int:
	return _shards.pool_size() if _shards != null else 0


func panel_material() -> ShaderMaterial:
	return _mat


func panel_visible() -> bool:
	return _panel != null and _panel.visible


## Where the panel is standing right now, in world space.
func panel_origin() -> Vector3:
	return _panel.global_position if _panel != null else Vector3.ZERO


## The panel's real size, measured off the built mesh: width across the hexagon's corners.
func panel_span() -> float:
	return _panel.mesh.get_aabb().size.x if _panel != null and _panel.mesh != null else 0.0


## How far the cap stands proud of its rim — 0 would mean the flat plane the lead rejected.
func panel_bulge() -> float:
	return _panel.mesh.get_aabb().size.z if _panel != null and _panel.mesh != null else 0.0


func clear() -> void:
	set_guard(false)
	_fade = 0.0
	_fade_t = 0.0
	_ripple = -1.0
	_flash = 0.0
	_ring_left = 0.0
	if _shards != null:
		_shards.clear()
	if _ring_mesh != null:
		_ring_mesh.clear_surfaces()
	if _ring != null:
		_ring.visible = false
	if _panel != null:
		_panel.visible = false

