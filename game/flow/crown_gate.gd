class_name FlowCrownGate
extends Node
## The way onto the Crown and the fight's front door (SPEC §8, MAP §2). It owns the trigger volume over
## the deck and the Ascension Catapult at S4 that is the only way up. The boss unit's Crown arena is
## its own: `BossArena.armed` is set when the fight starts, so the deck's return catapult never runs
## during the district (flow r3 used to park the arena here — removed, lead r4 item 1).
##
## Split out of `game_flow.gd` so the state machine there is only states.

signal reached_crown()

## MAP §2: the Crown deck is +224 at the map centre and the boss arena; the gate is a trigger over the
## crown itself, big enough that the catapult's arc passes through it on the way up. Passing through
## it is not arriving: `tick()` asks `FlowCrownDeck.touched_down()` (r5 brief item 2).
const CROWN_AT := Vector3(0.0, 224.0, 0.0)
const CROWN_SIZE := Vector3(420.0, 200.0, 420.0)
## `city_markers.gd` puts every spawn zone 20 m above the floor it names, so the pad and the landing
## both have to come down by that much or they float inside the geometry (lead r16 decision 1).
const ZONE_LIFT := 20.0

var catapult: FlowAscensionCatapult = null

var _gate: Area3D = null
var _in_gate: bool = false


func build() -> void:
	_build_gate()
	_build_catapult()


func _build_gate() -> void:
	_gate = Area3D.new()
	_gate.name = "CrownGate"
	_gate.collision_layer = Layers.TRIGGER
	_gate.collision_mask = Layers.PLAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = CROWN_SIZE
	shape.shape = box
	shape.position = CROWN_AT
	_gate.add_child(shape)
	add_child(_gate)
	_gate.body_entered.connect(func(body: Node3D) -> void:
		_in_gate = body.is_in_group(&"player"))
	_gate.body_exited.connect(func(body: Node3D) -> void:
		_in_gate = not body.is_in_group(&"player"))


## The catapult is built from the map's own `S4` / `B1` spawn zones when the world has them, so it
## stands where the level design put it and nowhere else. The sandbox has no Crown, so it has none.
func _build_catapult() -> void:
	if Game.has_flag("sandbox"):
		return
	catapult = FlowAscensionCatapult.new()
	catapult.name = "AscensionCatapult"
	add_child(catapult)
	catapult.place(pad_at(), landing())


## The pad sits ON the S4 ring, not 20 m up inside a Crown rib: the zone node carries that lift
## (`city_markers.gd`), so it comes straight back off (lead r16 decision 1, verifier part 2).
func pad_at() -> Vector3:
	return _zone_or(FlowAscensionCatapult.PAD_ZONE, FlowAscensionCatapult.PAD_FALLBACK) \
			- Vector3.UP * ZONE_LIFT


## Where the arc ends: a probed point on the fighting floor on the S4 side of the deck, NOT the `B1`
## zone box centre (which is the Ø80 core's axis, 20 m up, and lands the hero on the core's roof).
func landing() -> Vector3:
	return FlowCrownDeck.fight_point(get_tree())


func _zone_or(id: StringName, fallback: Vector3) -> Vector3:
	for node in FlowWorld.world_group(&"spawn_zone"):
		if StringName(node.get_meta(&"zone_id", node.name)) == id:
			return node.global_position
	push_warning("FlowCrownGate: no '%s' spawn zone — the catapult uses the layout fallback" % id)
	return fallback


## The third spire is down: light the catapult (brief §1).
func open() -> void:
	if catapult != null:
		catapult.open()


## Called every physics tick while the gate is the current objective. The Crown is 224 m up and the
## catapult throws the hero through the gate's volume on the way, so the fight starts when the mech is
## actually standing on the deck — a real touchdown, not a trigger box and not `is_grounded()`, which
## the arc's capsule reads as true every time it overlaps a deck tile (r5 brief item 2).
func tick() -> void:
	if not _in_gate or Game.player == null:
		return
	if catapult != null and catapult.flying:
		return
	if Game.player.global_position.y < CROWN_AT.y:
		return
	if not FlowCrownDeck.touched_down(get_tree(), Game.player):
		return
	_in_gate = false
	reached_crown.emit()
