extends HudWidget
## Telegraph icons (lead notes, critic #12; look review item 2): the shape-coded read on what an enemy
## is winding up, and the violet ring that marks where a weak point was hit. Colour is never the only
## channel — parryable is a white glint DIAMOND, unblockable a red TRIANGLE with a bang, a ranged tell
## a pair of amber chevrons. The audio unit already sounds `alarm_warning` on an unblockable tell, so
## this is the visual half of that pair.
##
## The icon sits just above the enemy's plate, using the ONE placement helper `enemy_plates.gd` owns,
## so it can never print over the name and HP bar the way a fixed pixel offset did. It carries no
## caption in combat: shape plus colour is the code, and the tutorial teaches it once. The ring tells
## near the reticle live in `markers.gd`, where the player's eye already is.

const TELL_TIME := 1.4            ## s an icon lives after its telegraph event
const WEAK_TIME := 1.1            ## s the weak-point ring stays on the impact point
const ICON_R := 15.0              ## px half-size of the icon
const PLATE_GAP := 14.0           ## px between the plate's top edge and the icon's centre
const MAX_RINGS := 8

## enemy instance id -> {"node", "kind", "left"}
var tells: Dictionary = {}
var rings: Array[Dictionary] = []

var _t: float = 0.0


func _ready() -> void:
	super()
	Events.enemy_telegraph.connect(_on_telegraph)
	Events.hit_landed.connect(_on_hit)


func _on_telegraph(enemy: Node, _attack: StringName, kind: StringName) -> void:
	if enemy == null:
		return
	tells[enemy.get_instance_id()] = {"node": enemy, "kind": kind, "left": TELL_TIME}


## A weak-point or crit hit leaves a violet ring on the impact point: the shape tells the player where
## the soft spot was, long after the amber hit marker has gone.
func _on_hit(hit: HitInfo, receiver: Node) -> void:
	if hit == null or receiver == Game.player or receiver == null:
		return
	if not (hit.weak_point or hit.crit):
		return
	if rings.size() >= MAX_RINGS:
		rings.pop_front()
	rings.append({"at": hit.position, "age": 0.0})


## A windup lasts as long as the attack does, so it runs on the world clock: in a hit-stop the tell
## must stay up exactly as long as the enemy is still winding up (audit #3).
func world_clock() -> bool:
	return true


func update_hud(delta: float) -> void:
	_t += delta
	for id: int in tells.keys():
		var t: Dictionary = tells[id]
		t["left"] = float(t["left"]) - delta
		if float(t["left"]) <= 0.0 or not is_instance_valid(t["node"]):
			tells.erase(id)
	var kept: Array[Dictionary] = []
	for r in rings:
		r["age"] = float(r["age"]) + delta
		if float(r["age"]) < WEAK_TIME:
			kept.append(r)
	rings = kept
	visible = data.alive() and (not tells.is_empty() or not rings.is_empty())


func tell_count() -> int:
	return tells.size()


## Icon and colour for one telegraph kind — the single place the mapping lives. There is no caption:
## three layers of text stacked in one corner was the least legible thing in the frame (item 2.2).
func spec_for(kind: StringName) -> Dictionary:
	match kind:
		&"unblockable":
			return {"col": HudPalette.DANGER}
		&"parryable":
			return {"col": HudPalette.WHITE}
		_:
			return {"col": HudPalette.AMBER}


func _draw() -> void:
	for r in rings:
		_draw_ring(r)
	for id: int in tells:
		var t: Dictionary = tells[id]
		var n := t["node"] as Node3D
		if is_instance_valid(n):
			_draw_tell(n, StringName(t["kind"]), float(t["left"]))


func _draw_ring(r: Dictionary) -> void:
	var p := data.project(r["at"] as Vector3)
	if not bool(p["visible"]):
		return
	var age := float(r["age"]) / WEAK_TIME
	var col := HudPalette.VIOLET
	col.a = 1.0 - age * age
	HudPalette.draw_weak_ring(self, p["pos"] as Vector2, lerpf(14.0, 30.0, age), col, 2.0)


## The plates own placement, so ask them: the icon goes `PLATE_GAP` above whatever rect the enemy's
## readout landed on, and falls back to the lock point when that enemy has no plate at all.
func _draw_tell(n: Node3D, kind: StringName, left: float) -> void:
	var spec := spec_for(kind)
	var col := spec["col"] as Color
	# The icon holds full strength for most of its life and only fades in the last 0.3 s.
	col.a = clampf(left / 0.3, 0.0, 1.0)
	var at := _icon_at(n)
	if at == Vector2.INF:
		return
	match kind:
		&"unblockable":
			HudPalette.draw_warning_triangle(self, at, ICON_R, col, 2.2)
		&"parryable":
			HudPalette.draw_glint_diamond(self, at, ICON_R, col, _t * 6.0)
		_:
			for i in 2:
				var y := at.y + float(i) * 8.0 - 4.0
				draw_polyline(PackedVector2Array([Vector2(at.x - ICON_R, y + 6.0),
						Vector2(at.x, y - 4.0), Vector2(at.x + ICON_R, y + 6.0)]), col, 2.2, true)


func _icon_at(n: Node3D) -> Vector2:
	var plates := _plates()
	if plates != null:
		var rect: Rect2 = plates.call(&"plate_rect", n)
		if rect.size != Vector2.ZERO:
			return Vector2(rect.get_center().x, rect.position.y - PLATE_GAP)
	var p := data.project(n.global_position + Vector3.UP * 2.0)
	if not bool(p["visible"]):
		return Vector2.INF
	return (p["pos"] as Vector2) - Vector2(0.0, 60.0)


## The plate widget is a sibling under the same parent (`hud.gd`'s `Widgets` table, or the canopy's).
func _plates() -> Node:
	if get_parent() == null:
		return null
	return get_parent().get_node_or_null(^"plates")
