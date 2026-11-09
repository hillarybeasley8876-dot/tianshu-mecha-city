class_name MonsterPlaceholderModel
extends Node3D
## Placeholder monster body (enemies-owned). Primitive silhouette at the right size and colours with
## the FINAL model API (CONTRACTS §6) so swapping in `enemies/models/<type>/<type>_model.tscn`
## changes nothing else: set_locomotion(state, speed), play_action(id) -> float, socket(name),
## hit_pause(s), set_hit_flash(v). Extras the placeholder needs for readability (telegraph glint,
## armour plate break) are additive: a real model may ignore them.
##
## Colours (brief): dark carapace #1B1E24, acid-green #9BFF3A glow lines, violet #B04CFF weak points.

const MAT_CARAPACE := 0
const MAT_GLOW := 1
const MAT_WEAK := 2
const MAT_PLATE := 3

const CARAPACE := Color("1b1e24")
const GLOW := Color("9bff3a")
const WEAK := Color("b04cff")
const PLATE := Color("5b6675")   ## armour plate: lighter than the carapace so the break reads
const GLINT := Color("ffffff")
const DANGER := Color("ff2a1f")
const AMBER := Color("ffb020")   ## staggered tell (juice §7: amber = in finisher range)

## Placeholder "clip lengths" (seconds) so callers get a sane duration before the real animations exist.
const ACTIONS: Dictionary = {
	&"idle": 1.0, &"attack": 0.6, &"attack_1": 0.5, &"attack_2": 0.5, &"attack_3": 0.9,
	&"grab": 1.1, &"leap": 0.9, &"lob": 1.0, &"dive": 1.2, &"charge": 1.6, &"slam": 1.4,
	&"strafe": 0.8, &"chaff": 1.2, &"hit_light": 0.3, &"hit_heavy": 0.5, &"stagger": 1.4,
	&"death": 1.2, &"roar": 1.2, &"sidestep": 0.45,
}

@export var body_type: StringName = &"ripper"

var _mats: Array[StandardMaterial3D] = []
var _meshes: Array[MeshInstance3D] = []
var _plates: Array[MeshInstance3D] = []
var _sockets: Dictionary = {}
var _visual: Node3D
var _flash: float = 0.0
var _pause_left: float = 0.0
var _bob: float = 0.0
var _locomotion: StringName = &"idle"
var _speed: float = 0.0
var _tell: float = 0.0
var _tell_kind: StringName = EnemyAttack.UNBLOCKABLE
var _tell_light: OmniLight3D
var _tell_parry: MeshInstance3D = null
var _tell_danger: MeshInstance3D = null
var _tell_nodes: Array[Dictionary] = []
var _staggered: bool = false


func _ready() -> void:
	_build()


func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_make_materials()
	var rows: Array = MonsterBodyParts.PARTS.get(body_type, [])
	if rows.is_empty():
		push_warning("MonsterPlaceholderModel: no parts for type '%s'" % body_type)
	for row: Array in rows:
		_add_part(row)
	for socket_name: StringName in MonsterBodyParts.SOCKETS.get(body_type, {}):
		var m := Marker3D.new()
		m.name = String(socket_name)
		m.position = MonsterBodyParts.SOCKETS[body_type][socket_name]
		add_child(m)
		_sockets[socket_name] = m
	_tell_light = OmniLight3D.new()
	_tell_light.name = "TellLight"
	_tell_light.omni_range = 34.0
	_tell_light.shadow_enabled = false   ## budget: CONTRACTS §2 allows only 16 shadow casters
	_tell_light.visible = false
	add_child(_tell_light)
	# Above the head, not inside the chest: a light inside the body washes the whole silhouette out.
	var mouth: Vector3 = MonsterBodyParts.SOCKETS.get(body_type, {}).get(&"mouth", Vector3.ZERO)
	_tell_light.position = mouth + Vector3.UP * 3.0
	_make_tell_shapes(mouth)


## SPEC §7.1: an unblockable is never signalled by colour alone. Two silhouettes hover over the
## monster and only the right one shows: a compact upright **diamond** for parryable (you may stand
## and guard) and a wide inverted **wedge** for unblockable (get out of the way). The shapes differ
## in outline, size and aspect, so the tell survives colour-blindness, a bright city behind the
## monster, and 100 m of distance. They are unshaded, depth-test-free and turned to the camera in
## `_process`, so nothing — armour, scenery or a bad angle — can swallow the tell.
func _make_tell_shapes(above: Vector3) -> void:
	var top := above + Vector3.UP * 5.0
	_tell_parry = _tell_shape(_diamond_mesh(), top, 1.0, deg_to_rad(45.0), GLINT)
	_tell_danger = _tell_shape(_wedge_mesh(), top, 2.4, PI, DANGER)


## Shape *and* colour both carry the kind, so neither channel is ever the only one (SPEC §7.1).
func _tell_shape(mesh: Mesh, at: Vector3, scale: float, roll: float, colour: Color) \
		-> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "TellShape"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _tell_material(colour)
	mi.visible = false
	mi.top_level = true
	add_child(mi)            ## global_position is only legal once the node is in the tree
	mi.global_position = at
	_tell_nodes.append({"node": mi, "roll": roll, "scale": scale, "at": at})
	return mi


func _tell_material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(colour.r, colour.g, colour.b, 0.92)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = 6.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true     ## the tell must never be lost behind the monster's own armour
	return m


## A square; the caller rolls it 45° so it reads as a diamond.
func _diamond_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(2.2, 2.2, 0.3)
	return m


## A wide triangular prism: the caller rolls it 180° so the point aims down at the monster.
func _wedge_mesh() -> Mesh:
	var m := PrismMesh.new()
	m.size = Vector3(4.4, 2.6, 0.3)
	m.left_to_right = 0.5
	return m


## Turns the visible tell to the camera and pulses it with the windup, so the shape grows into the
## hit instead of snapping on. Costs nothing when no tell is up: only telegraphing monsters run it.
func _face_tells() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var flat := cam.global_transform.basis
	for row: Dictionary in _tell_nodes:
		var mi := row["node"] as MeshInstance3D
		if not mi.visible:
			continue
		var pulse: float = 1.0 + 0.35 * _tell
		mi.global_transform = Transform3D(flat * Basis(Vector3(0, 0, 1), float(row["roll"])), \
				global_position + (row["at"] as Vector3)) * Transform3D().scaled(Vector3.ONE \
				* float(row["scale"]) * pulse)


## A near-black carapace needs a rim or the silhouette disappears against a bright city. The rim keeps
## the briefed #1B1E24 albedo and only lifts the edges.
func _make_materials() -> void:
	var defs: Array[Array] = [
		[CARAPACE, 0.0, 0.7], [GLOW, 4.0, 0.0], [WEAK, 3.0, 0.0], [PLATE, 0.0, 0.5],
	]
	for d: Array in defs:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(d[0], 1.0)
		m.roughness = 0.55
		m.metallic = 0.4
		var rim := float(d[2])
		if rim > 0.0:
			m.rim_enabled = true
			m.rim = rim
			m.rim_tint = 0.4
		var emit := float(d[1])
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = d[0]
			m.emission_energy_multiplier = emit
		_mats.append(m)


func _add_part(row: Array) -> void:
	var mi := MeshInstance3D.new()
	var size: Vector3 = row[2]
	var mat: int = int(row[3])
	match String(row[0]):
		"cap":
			# size = (cross-section diameter, length along local Y, cross-section diameter);
			# rotation lays the capsule down when the body is longer than it is tall.
			var c := CapsuleMesh.new()
			c.radius = minf(size.x, size.z) * 0.5
			c.height = maxf(size.y, c.radius * 2.0 + 0.01)
			mi.mesh = c
		"sph":
			var s := SphereMesh.new()
			s.radius = maxf(size.x, maxf(size.y, size.z)) * 0.5
			s.height = s.radius * 2.0
			mi.mesh = s
		"cyl":
			var cy := CylinderMesh.new()
			cy.top_radius = size.x * 0.5
			cy.bottom_radius = size.x * 0.5
			cy.height = size.y
			mi.mesh = cy
		_:
			var b := BoxMesh.new()
			b.size = size
			mi.mesh = b
	mi.position = row[1]
	mi.rotation_degrees = row[4]
	mi.material_override = _mats[mat]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_visual.add_child(mi)
	_meshes.append(mi)
	if mat == MAT_PLATE:
		_plates.append(mi)


# --- model API (CONTRACTS §6) -------------------------------------------------------------------

func set_locomotion(state: StringName, speed: float) -> void:
	_locomotion = state
	_speed = speed
	if state != &"stagger":
		_visual.rotation_degrees.z = 0.0


## Returns the clip length so callers can time gameplay against the animation.
func play_action(id: StringName, _blend: float = 0.08) -> float:
	var len_s := float(ACTIONS.get(id, 0.6))
	if id == &"stagger":
		_visual.rotation_degrees.z = 9.0
	return len_s


func socket(name: StringName) -> Node3D:
	var s: Node3D = _sockets.get(name)
	if s == null:
		push_warning("MonsterPlaceholderModel(%s): no socket '%s'" % [body_type, name])
		return self
	return s


## Local hit-stop: the placeholder has no AnimationTree, so this pauses its procedural bob and the
## vibration is driven by EnemyBase on this node's local position (juice §2.3).
func hit_pause(seconds: float) -> void:
	_pause_left = maxf(_pause_left, seconds)


func set_hit_flash(v: float) -> void:
	_flash = clampf(v, 0.0, 1.0)
	_apply_emission()


# --- placeholder extras -------------------------------------------------------------------------

## White glint = parryable, red glow = unblockable (SPEC §7 counters). v = 0..1 intensity.
## The tell has to be unmistakable at 100 m, so it drives three things at once: the glow lines, a
## body-wide emission in the tell colour, and a non-shadowing light at the chest.
func set_telegraph(kind: StringName, v: float) -> void:
	_tell_kind = kind
	_tell = clampf(v, 0.0, 1.0)
	_apply_emission()


## Staggered monsters keep an amber tell for the whole window, so the player can see the finisher
## opening from any distance (juice §7 ladder).
func set_stagger(on: bool) -> void:
	_staggered = on
	_visual.rotation_degrees.z = 9.0 if on else 0.0
	_apply_emission()


## Juggernaut armour plates break off one by one (SPEC §7).
func break_plate() -> bool:
	if _plates.is_empty():
		return false
	var p: MeshInstance3D = _plates.pop_front()
	p.visible = false
	return true


func plates_left() -> int:
	return _plates.size()


func visual_root() -> Node3D:
	return _visual


func _process(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	if _locomotion == &"idle" or _speed < 0.5:
		_bob += delta * 1.6
		_visual.position.y = sin(_bob) * 0.06
	else:
		_bob += delta * (2.0 + _speed * 0.08)
		_visual.position.y = absf(sin(_bob)) * 0.12
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_apply_emission()
	if _tell > 0.02:
		_face_tells()


## One place decides the emission of every material: hit flash (white) and telegraph tell
## (white glint / red) both live on the carapace, and they must not fight over it.
func _apply_emission() -> void:
	var tell_colour := GLINT if _tell_kind == EnemyAttack.PARRYABLE else DANGER
	var carapace := _mats[MAT_CARAPACE]
	# The carapace itself stays dark through a tell: lighting the whole body flattens the silhouette
	# (juice §12 readability). The tell lives on the glow lines, the plates and the beacon light.
	carapace.emission_enabled = _flash > 0.001
	carapace.emission = Color(1, 1, 1)
	carapace.emission_energy_multiplier = _flash * 5.0
	var line_colour := GLOW.lerp(tell_colour, _tell)
	var line_energy := lerpf(4.0, 12.0, _tell)
	if _staggered and _tell <= 0.01:
		line_colour = AMBER
		line_energy = 9.0
	_mats[MAT_GLOW].emission = line_colour
	_mats[MAT_GLOW].emission_energy_multiplier = line_energy
	_mats[MAT_WEAK].emission = WEAK.lerp(tell_colour, _tell * 0.6)
	_mats[MAT_PLATE].emission_enabled = _tell > 0.001
	_mats[MAT_PLATE].emission = tell_colour
	_mats[MAT_PLATE].emission_energy_multiplier = _tell * 1.2
	_tell_light.light_color = tell_colour
	_tell_light.light_energy = _tell * 2.2
	_tell_light.visible = _tell > 0.02
	# The shape cue: only the shape that matches the attack kind is ever shown.
	_tell_parry.visible = _tell > 0.02 and _tell_kind == EnemyAttack.PARRYABLE
	_tell_danger.visible = _tell > 0.02 and _tell_kind == EnemyAttack.UNBLOCKABLE
