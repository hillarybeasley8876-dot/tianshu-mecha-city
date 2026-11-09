class_name BossArena
extends Node3D
## The Crown deck B1 (boss unit). MAP §2/§4: a CIRCULAR Ø300 m deck at +224 with three rim steps,
## four 24 m fins at 45°, and a Ø80 m central core the titan circles and the player uses as cover.
## Nothing here needs the city: the arena is built from primitives so `--boss-test` gets the real
## fight geometry in the sandbox before city-build lands the Spire.
##
## It also owns the two arena hazards: rim segments that break away in phase 2, and the catapult that
## throws a player who fell off back onto the deck within CATAPULT_TIMEOUT (brief §4).

signal segment_broke(index: int)

## CONTRACTS §6: whoever built a rim wedge, the boss breaks it through this group.
const RIM_GROUP := &"crown_rim_segment"

## The city builds the Crown deck itself from `data/map/city_layout.json` (`B1_crown`: the three
## rising rim steps, the Ø80 core and the fins), so on the real map the arena must NOT draw or
## collide a second copy of it. With this off the arena contributes only what the layout has no way
## to express: the twelve breakable rim wedges and the catapult. It stays on whenever the world has
## no Crown of its own — the sandbox, `--boss-test`, and the city before city-build lands the deck.
@export var build_geometry: bool = true


## CONTRACTS §6: a world that exports the Crown's rim has built the deck, so the arena only breaks
## and catapults. A world with no rim segments (the sandbox, the city before its Crown lands) needs
## the arena to BE the Crown.
static func world_has_crown(tree: SceneTree) -> bool:
	return not tree.get_nodes_in_group(RIM_GROUP).is_empty()

const DECK_THICKNESS := 8.0
## How far the floor probe reaches above and below the arena origin when the world owns the deck.
const PROBE_UP := 120.0
const PROBE_DOWN := 300.0
const SEGMENT_GAP_DEG := 4.0
## Material colours: the crown is Spire concrete with violet hive growth (ART.md palette).
const DECK_COLOUR := Color(0.24, 0.24, 0.28)
const RIM_COLOUR := Color(0.30, 0.28, 0.34)
const FIN_COLOUR := Color(0.34, 0.20, 0.42)
const CORE_COLOUR := Color(0.18, 0.17, 0.22)

var segments: Array[Node3D] = []
var broken_segments: Array[int] = []

var _segment_rest: Dictionary = {}
var _player_off_since: float = 0.0
var _returning: bool = false
## Only a running fight owns the player: before it (the carrier drop passes 400 m, a free flight can
## climb past the Crown) a fall below the deck is just flying, never a catapult back up.
var armed: bool = false


func _ready() -> void:
	add_to_group(&"boss_arena")
	add_to_group(&"landmark")
	_build()


func _build() -> void:
	# Three rings RISING toward the centre (layout `B1_crown.rim_steps`): the top disc at +16 m is the
	# fighting floor around the Ø80 core, the middle ring at +8 m is one step down, and the outer ring
	# at 0 is the 12 wedges that break away in phase 2 — they are the only floor out there, so a
	# broken wedge is a real hole.
	if build_geometry:
		_stack(2, DECK_COLOUR)
		_stack(1, RIM_COLOUR)
		_build_fins()
		_cylinder(CORE_COLOUR, BossTuning.CORE_COVER_RADIUS, BossTuning.CORE_COVER_HEIGHT,
				Vector3(0.0, top_height() + BossTuning.CORE_COVER_HEIGHT * 0.5, 0.0))
		_build_segments()
	else:
		_adopt_city_segments()


## One ring of the ziggurat: a cylinder whose top sits at its `rise` and which reaches all the way
## down to the outer rim's underside, so the steps read as solid architecture from the catapult.
func _stack(index: int, colour: Color) -> void:
	var step: Dictionary = BossTuning.RIM_STEPS[index]
	var rise := float(step["rise"])
	_cylinder(colour, float(step["radius"]), rise + DECK_THICKNESS,
			Vector3(0.0, rise - (rise + DECK_THICKNESS) * 0.5, 0.0))


## Height of the top ring's floor, relative to the arena origin.
func top_height() -> float:
	return float(BossTuning.RIM_STEPS[BossTuning.RIM_STEPS.size() - 1]["rise"])


## Four 24 m fins at 45°, 135°, 225°, 315° (MAP §4, layout `fins`) — the deck's silhouette and the
## cover the player breaks line of sight with when the beam sweeps past.
func _build_fins() -> void:
	for i in BossTuning.FIN_COUNT:
		var angle := deg_to_rad(BossTuning.FIN_ANGLE_DEG) + TAU * float(i) \
				/ float(BossTuning.FIN_COUNT)
		var radius := BossTuning.DECK_RADIUS - BossTuning.FIN_WIDTH * 1.4
		var at := Vector3(cos(angle), 0.0, sin(angle)) * radius
		var body := _slab(FIN_COLOUR, Vector3(BossTuning.FIN_WIDTH, BossTuning.FIN_HEIGHT,
				BossTuning.FIN_WIDTH * 1.6), at + Vector3.UP * BossTuning.FIN_HEIGHT * 0.5)
		# A slab's local X is its width; rotating by the bearing alone would lay the width ALONG the
		# radius. The extra quarter turn puts the width tangentially and the reach radially.
		body.rotation.y = -angle + PI * 0.5


## The outer ring is cut into RIM_SEGMENTS wedges. Each is a real body: breaking one removes its
## collision, so the hole it leaves is genuinely a hole. They join the contract group
## `&"crown_rim_segment"` with the bearing meta, whether the arena built them or adopted the city's.
func _build_segments() -> void:
	var inner := float(BossTuning.RIM_STEPS[1]["radius"])
	var span := 360.0 / float(BossTuning.RIM_SEGMENTS)
	var depth := BossTuning.DECK_RADIUS - inner
	for i in BossTuning.RIM_SEGMENTS:
		var mid := deg_to_rad(span * (float(i) + 0.5))
		var radius := (BossTuning.DECK_RADIUS + inner) * 0.5
		var at := Vector3(cos(mid), 0.0, sin(mid)) * radius
		var width := deg_to_rad(span - SEGMENT_GAP_DEG) * radius
		var body := _slab(RIM_COLOUR, Vector3(width, DECK_THICKNESS, depth),
				at + Vector3.UP * (-DECK_THICKNESS * 0.5))
		body.rotation.y = -mid + PI * 0.5   ## width tangential, depth radial (see _build_fins)
		body.name = "CrownRim%d" % i
		body.add_to_group(RIM_GROUP)
		body.set_meta(&"angle_deg", rad_to_deg(mid))
		segments.append(body)


## CONTRACTS §6: on the real map the city exports the Crown's rim itself, so the arena adopts those
## bodies instead of drawing a second ring on top of the city's deck. Sorted by bearing so the
## indices the director logs match the geometry.
func _adopt_city_segments() -> void:
	var found: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(RIM_GROUP):
		var body := node as Node3D
		if body == null or body == self or segments.has(body):
			continue
		if body.global_position.distance_to(global_position) > BossTuning.DECK_RADIUS * 2.0:
			continue
		found.append(body)
	if found.is_empty():
		return
	found.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return float(a.get_meta(&"angle_deg", 0.0)) < float(b.get_meta(&"angle_deg", 0.0)))
	for body in found:
		segments.append(body)


# --- phase 2 hazard -------------------------------------------------------------------------------

## Phase 2 shakes the deck apart: `RIM_SEGMENTS_BROKEN` wedges fall away, leaving holes the player
## can drop through onto the S4 ring below (brief §4).
func break_segments() -> Array[int]:
	var free: Array[int] = []
	for i in segments.size():
		if i not in broken_segments:
			free.append(i)
	free.shuffle()
	var taken: Array[int] = []
	for i in mini(BossTuning.RIM_SEGMENTS_BROKEN, free.size()):
		taken.append(free[i])
		_drop_segment(free[i])
	Audio.play(&"spire_destroyed", global_position)
	Feel.shake(0.5, global_position)
	return taken


func _drop_segment(index: int) -> void:
	if index < 0 or index >= segments.size():
		return
	broken_segments.append(index)
	var body := segments[index]
	_segment_rest[index] = {"pos": body.position, "rot": body.rotation}
	# A hole, not rubble: the collision goes at once so the fall is honest, and the mesh tips away
	# over a second so the player sees WHY the ground is gone. The city's wedges put their shapes
	# wherever they like, so they are found by type, not by child index.
	var shape := _shape_of(body)
	if shape != null:
		shape.disabled = true
	var vfx := get_tree().get_first_node_in_group(&"vfx_library")
	if vfx != null:
		vfx.call(&"spawn", &"kill_large", body.global_position, Vector3.UP, 2.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(body, ^"rotation:z", deg_to_rad(70.0), 1.2)
	tween.tween_property(body, ^"position:y", body.position.y - 120.0, 1.6)
	segment_broke.emit(index)


func restore_segments() -> void:
	for i in broken_segments:
		var body := segments[i]
		var shape := _shape_of(body)
		if shape != null:
			shape.disabled = false
		if _segment_rest.has(i):
			var rest: Dictionary = _segment_rest[i]
			body.position = rest["pos"]
			body.rotation = rest["rot"]
	broken_segments.clear()
	_segment_rest.clear()


## The segment's own collision shape, whether the arena or the city built it.
func _shape_of(body: Node3D) -> CollisionShape3D:
	for child in body.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	push_warning("BossArena: rim segment '%s' has no CollisionShape3D" % body.name)
	return null


# --- the catapult back up ---------------------------------------------------------------------------

## A player below the deck and outside the core is on the S4 ring. Rather than a death, the catapult
## throws them back onto the deck — inside CATAPULT_TIMEOUT, always (brief §4).
func _physics_process(delta: float) -> void:
	if not armed:
		return
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	if _returning:
		_tick_return(delta, player)
		return
	if not _has_fallen(player):
		_player_off_since = 0.0
		return
	_player_off_since += delta
	if _player_off_since >= BossTuning.CATAPULT_DELAY:
		_launch(player)


## Below the deck is off the arena — full stop. An earlier version also demanded the player be
## outside the core radius, which meant a hero knocked down the Spire's own shaft (directly under the
## core) never triggered the catapult and simply fell out of the fight.
func _has_fallen(player: Node3D) -> bool:
	return player.global_position.y < global_position.y - 12.0


## The return arc is a simple ballistic toss: up onto the deck with a burst of speed, aimed at a
## random point on the ring so it never lands the player back in the same hole.
func _launch(player: Node3D) -> void:
	_returning = true
	# Back onto the top ring at a fresh bearing, so a player is never thrown into the hole they fell
	# through. `ring_point` puts the height on whichever step that bearing lands on.
	var target := ring_point(randf(), 0.55, 6.0)
	player.set_meta(&"boss_catapult_target", target)
	Feel.play(&"anchor_latch", player.global_position, 1.0)
	Audio.play(&"anchor_latch", player.global_position)
	Feel.shake(0.25, player.global_position)


func _tick_return(delta: float, player: Node3D) -> void:
	_player_off_since += delta
	var target: Vector3 = player.get_meta(&"boss_catapult_target", global_position)
	player.global_position = player.global_position.move_toward(target,
			BossTuning.CATAPULT_SPEED * delta)
	if player.global_position.distance_to(target) < 2.0 \
			or _player_off_since > BossTuning.CATAPULT_TIMEOUT:
		_returning = false
		_player_off_since = 0.0
		player.remove_meta(&"boss_catapult_target")
		Audio.play(&"land_heavy", player.global_position)


# --- geometry helpers -------------------------------------------------------------------------------

func _slab(colour: Color, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = at
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _material(colour)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


func _cylinder(colour: Color, radius: float, height: float, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = at
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 48
	mi.mesh = mesh
	mi.material_override = _material(colour)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


func _material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	return mat


## A standing point on the deck for the player, the titan or an add: `t` picks the bearing and
## `radius_fraction` how far out, and the returned height is the top of whichever ziggurat ring that
## radius lands on — so nothing is ever spawned inside a step. When the world built the deck itself the
## step table is not ours, so the height comes from a ray onto the real floor instead.
func ring_point(t: float, radius_fraction: float = 0.7, height: float = 0.0) -> Vector3:
	var angle := TAU * fposmod(t, 1.0)
	var r := BossTuning.DECK_RADIUS * clampf(radius_fraction, 0.05, 0.95)
	var at := global_position + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
	at.y += floor_y_at(at) - global_position.y + height
	return at


## World height of the deck surface at a world position, so movers can stay on the steps.
func floor_y_at(world_pos: Vector3) -> float:
	if build_geometry:
		var r := Vector2(world_pos.x - global_position.x, world_pos.z - global_position.z).length()
		return global_position.y + BossTuning.deck_height_at(r)
	return probe_floor(world_pos)


## The height of the world's own Crown deck under a point, by ray. The city owns that geometry and its
## rim steps are not ours to guess: a titan spawned on `BossTuning`'s table fell straight through a
## deck whose steps are somewhere else.
func probe_floor(world_pos: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return global_position.y
	var from := Vector3(world_pos.x, global_position.y + PROBE_UP, world_pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * PROBE_DOWN,
			Layers.WORLD)
	var hit := space.intersect_ray(query)
	return global_position.y if hit.is_empty() else (hit["position"] as Vector3).y
