extends HudWidget
## Enemy plates (brief §3, look review items 2/6/10/11): a name-and-bars readout that floats above the
## enemy it belongs to. A FULL plate is earned — only the hard target, the soft target and elites get
## one, three at most. Everything else in view gets a hostile chevron and a thin HP sliver for three
## seconds after it takes a hit, which is when the player actually wants to read it.
##
## Placement is the other half of the job: plates never sit on the chrome, never on each other, never
## outside a safe rect, and never on the reticle. One pass, no per-enemy nodes, so a 40-enemy fight
## still costs one Control.

const TargetQuery := preload("res://player/aim/target_query.gd")

const WIDTH := 150.0
const HEIGHT := 30.0
const MAX_PLATES := 3
const PLATE_RANGE := 320.0        ## m — beyond lock range a plate is noise
const STAGGER_BLINK := 4.0        ## Hz
const LIFT := 16.0                ## px between the anchor point and the plate
const SAFE_INSET := 0.05          ## fraction of the screen kept clear at every edge
const RETICLE_CLEAR := 70.0       ## px radius round the crosshair no plate may enter
const FADE_NEAR := 60.0           ## m — inside this a plate is full size and full strength
const FADE_FAR := 250.0           ## m — past this it is 0.75× and 0.6 alpha
const SLIVER_W := 60.0
const SLIVER_TIME := 3.0          ## s a hurt enemy's sliver stays up
const LOS_TTL := 0.2              ## s a cached line-of-sight answer is reused for

## type names that always earn a full plate
const ELITES: Array[StringName] = [&"juggernaut", &"hive_spire", &"brood_titan"]

var plates: Array[Dictionary] = []
var slivers: Array[Dictionary] = []
## Chrome rects published by `hud.gd` each frame (compass, radar, bars, hotbar, panels).
var avoid: Array[Rect2] = []

var _blink: float = 0.0
var _rects: Dictionary = {}         ## actor instance id -> the Rect2 its plate landed on
var _hurt: Dictionary = {}          ## actor instance id -> seconds of sliver left
var _los: Dictionary = {}           ## actor instance id -> {"ok": bool, "t": float}
var _query: RefCounted = TargetQuery.new()


func _ready() -> void:
	super()
	Events.hit_landed.connect(_on_hit)


func _on_hit(_hit: HitInfo, receiver: Node) -> void:
	if receiver != null and receiver != Game.player:
		_hurt[receiver.get_instance_id()] = SLIVER_TIME


func update_hud(delta: float) -> void:
	_blink += delta
	plates.clear()
	slivers.clear()
	_rects.clear()
	_tick_timers(delta)
	if not data.alive():
		visible = false
		return
	var seen: Dictionary = {}
	# Priority order: the hard lock, the soft lock, then elites, then nobody.
	for t: Node3D in [data.node("hard_target"), data.node("soft_target")]:
		_consider(t, true, seen)
	for e in data.enemies:
		if plates.size() < MAX_PLATES:
			_consider(e, false, seen)
	for e in data.enemies:
		_consider_sliver(e, seen)
	visible = not plates.is_empty() or not slivers.is_empty()


func _tick_timers(delta: float) -> void:
	for id: int in _hurt.keys():
		_hurt[id] = float(_hurt[id]) - delta
		if float(_hurt[id]) <= 0.0:
			_hurt.erase(id)
	for id: int in _los.keys():
		var e: Dictionary = _los[id]
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0:
			_los.erase(id)


## Adds a full plate for `target` if it is on screen, in range, alive and there is room for it. Only a
## target that actually GOT a plate is marked as seen, so a plain swarmer can still raise its sliver.
func _consider(target: Node3D, locked: bool, seen: Dictionary) -> bool:
	var info := _info(target)
	if info.is_empty() or seen.has(int(info["id"])):
		return false
	var st: Dictionary = info["state"]
	if st.is_empty() or not bool(st.get("alive", true)):
		return false
	if not locked and not _is_elite(st):
		return false
	var p := data.project(info["anchor"] as Vector3)
	if not bool(p["visible"]) or float(p["dist"]) > PLATE_RANGE:
		return false
	if not locked and not _line_of_sight(target, int(info["id"])):
		return false
	var rect := _place(p["pos"] as Vector2, float(p["dist"]))
	if rect.size == Vector2.ZERO:
		return false
	seen[int(info["id"])] = true
	_rects[int(info["id"])] = rect
	plates.append({"rect": rect, "state": st, "dist": p["dist"], "locked": locked})
	return true


## Everything else in view gets a chevron and, for `SLIVER_TIME` after a hit, a 60 px HP sliver.
func _consider_sliver(target: Node3D, seen: Dictionary) -> void:
	if not is_instance_valid(target) or seen.has(target.get_instance_id()):
		return
	if not _hurt.has(target.get_instance_id()):
		return
	var st := data.enemy_state(target)
	if st.is_empty() or not bool(st.get("alive", true)):
		return
	var p := data.project(_anchor_of(target))
	if not bool(p["visible"]) or float(p["dist"]) > PLATE_RANGE:
		return
	if not _line_of_sight(target, target.get_instance_id()):
		return
	seen[target.get_instance_id()] = true
	slivers.append({"pos": p["pos"], "state": st})


## Where one target's readout lives on screen — the one place that knows, so `telegraphs.gd` can sit
## its windup icon just above the plate instead of guessing a height and landing on top of it
## (look review item 2.1). Targets with no plate of their own get the rect the plate WOULD take.
func plate_rect(target: Node3D) -> Rect2:
	if target == null:
		return Rect2()
	var actor := _actor(target)
	if actor != null and _rects.has(actor.get_instance_id()):
		return _rects[actor.get_instance_id()]
	var p := data.project(_anchor_of(target))
	if not bool(p["visible"]):
		return Rect2()
	var at := p["pos"] as Vector2
	return Rect2(at - Vector2(WIDTH * 0.5, HEIGHT + LIFT), Vector2(WIDTH, HEIGHT))


## Above the anchor by default; if that lands on the chrome, another plate or the screen edge, try
## below the target; if that fails too the plate is dropped rather than stacked (items 10.4-10.6).
func _place(anchor: Vector2, dist: float) -> Rect2:
	var s := _distance_scale(dist)
	var size := Vector2(WIDTH, HEIGHT) * s
	for y: float in [-(HEIGHT * s + LIFT), LIFT]:
		var rect := Rect2(Vector2(anchor.x - size.x * 0.5, anchor.y + y), size)
		if _safe(rect) and not _blocked(rect):
			return rect
	return Rect2()


## 1.0 → 0.75 between `FADE_NEAR` and `FADE_FAR`: a plate at 300 m is reference, not a warning.
func _distance_scale(dist: float) -> float:
	return lerpf(1.0, 0.75, clampf((dist - FADE_NEAR) / (FADE_FAR - FADE_NEAR), 0.0, 1.0))


func _safe(rect: Rect2) -> bool:
	var s := screen_size()
	var inset := s * SAFE_INSET
	if rect.position.x < inset.x or rect.position.y < inset.y:
		return false
	return rect.end.x <= s.x - inset.x and rect.end.y <= s.y - inset.y


func _blocked(rect: Rect2) -> bool:
	var grown := rect.grow(4.0)
	for r in avoid:
		if grown.intersects(r):
			return true
	var c := screen_center()
	if grown.intersects(Rect2(c - Vector2.ONE * RETICLE_CLEAR, Vector2.ONE * RETICLE_CLEAR * 2.0)):
		return true
	for plate in plates:
		if grown.intersects(plate["rect"] as Rect2):
			return true
	return false

# --- target geometry ------------------------------------------------------------------------------

## The actor behind a target, its state, the world point the readout hangs off and a stable id.
func _info(target: Node3D) -> Dictionary:
	if not is_instance_valid(target):
		return {}
	var actor := _actor(target)
	if actor == null:
		return {}
	return {"id": actor.get_instance_id(), "actor": actor,
			"state": data.enemy_state(actor as Node3D), "anchor": _anchor_of(target)}


func _actor(target: Node3D) -> Node:
	if target.has_method(&"actor"):
		var a := target.call(&"actor") as Node
		if a != null:
			return a
	return target


## The top of the enemy's bounding box, not its feet (look review item 10.8): a Targetable knows its
## own radius, an EnemyBase its body height, and anything else gets a 3 m guess.
func _anchor_of(target: Node3D) -> Vector3:
	if target is Targetable:
		return target.global_position + Vector3.UP * (target as Targetable).radius
	var h: Variant = target.get(&"body_height")
	if h != null:
		return target.global_position + Vector3.UP * float(h)
	for child in target.get_children():
		if child is Targetable:
			return (child as Node3D).global_position + Vector3.UP * (child as Targetable).radius
	return target.global_position + Vector3.UP * 3.0


## Elites always earn a plate. A hive spire publishes pod counts rather than a type, which is exactly
## what makes it worth plating (look review item 6).
func _is_elite(st: Dictionary) -> bool:
	return ELITES.has(StringName(st.get("type", &""))) or st.has("pods_left")


## Unlocked readouts are only useful if you can actually see the target: one scenery ray, cached for
## `LOS_TTL` so a swarm costs a handful of rays a second, not one per enemy per frame.
func _line_of_sight(target: Node3D, id: int) -> bool:
	if data.player == null or not data.player.is_inside_tree():
		return true
	if _los.has(id):
		return bool((_los[id] as Dictionary)["ok"])
	var space := data.player.get_world_3d().direct_space_state
	var ok := true
	if space != null:
		ok = bool(_query.call(&"has_line_of_sight", space,
				data.player.global_position + Vector3.UP * 4.0, target.global_position))
	_los[id] = {"ok": ok, "t": LOS_TTL}
	return ok

# --- drawing --------------------------------------------------------------------------------------

func _draw() -> void:
	for s in slivers:
		_draw_sliver(s)
	for plate in plates:
		_draw_plate(plate)


## No box (look review item 11.2): a 2 px rule along the top in the target's colour, an outlined
## name and the two bars. A filled rectangle plus four brackets turned the overlay into programmer
## art over the warm city.
func _draw_plate(plate: Dictionary) -> void:
	var st: Dictionary = plate["state"]
	var rect := plate["rect"] as Rect2
	var locked := bool(plate["locked"])
	var primed := bool(st.get("primed", false))
	var staggered := bool(st.get("staggered", false))
	var col := HudPalette.VIOLET if primed else (HudPalette.CYAN if locked else HudPalette.GOLD)
	var a := _distance_alpha(float(plate["dist"]))
	col.a = a
	var pad := 6.0
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0.0), col, 2.0)

	var name_col := HudPalette.WHITE
	name_col.a = a
	text(rect.position + Vector2(pad, 15.0), String(st.get("name", "")), HudPalette.SIZE_TINY,
			name_col, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - pad * 2.0 - 24.0)
	if not locked:
		var dim := HudPalette.TEXT_DIM
		dim.a = a
		text(rect.position + Vector2(pad, 15.0), "%d m" % int(round(float(plate["dist"]))),
				HudPalette.SIZE_TINY, dim, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - pad)

	var hp := clampf(float(st.get("hp", 1.0)) / maxf(float(st.get("hp_max", 1.0)), 1.0), 0.0, 1.0)
	var hp_col := HudPalette.AMBER if staggered else HudPalette.DANGER
	hp_col.a = a
	HudPalette.draw_bar(self, Rect2(rect.position + Vector2(pad, 19.0),
			Vector2(rect.size.x - pad * 2.0, 4.0)), hp, hp_col)

	# A spire has no stability: it shows how many pods are still standing (look review item 6).
	var pods: Variant = st.get("pods_left")
	if pods != null:
		_draw_pods(Rect2(rect.position + Vector2(pad, 25.0), Vector2(rect.size.x - pad * 2.0, 3.0)),
				int(pods), a)
	else:
		_draw_stability(rect, st, staggered, a)
	_draw_marks(rect, int(st.get("marks", 0)), a)


func _distance_alpha(dist: float) -> float:
	return lerpf(1.0, 0.6, clampf((dist - FADE_NEAR) / (FADE_FAR - FADE_NEAR), 0.0, 1.0))


func _draw_stability(rect: Rect2, st: Dictionary, staggered: bool, a: float) -> void:
	var pad := 6.0
	var stab := clampf(float(st.get("stability", 1.0)) / maxf(float(st.get("stability_max", 1.0)), 1.0),
			0.0, 1.0)
	var bar := Rect2(rect.position + Vector2(pad, 25.0), Vector2(rect.size.x - pad * 2.0, 3.0))
	if not staggered:
		HudPalette.draw_bar(self, bar, 1.0 - stab, HudPalette.AMBER)
		return
	var on := HudPalette.pulse(sin(_blink * TAU * STAGGER_BLINK)) > 0.5
	HudPalette.draw_bar(self, bar, 1.0, HudPalette.AMBER if on else HudPalette.TRACK)
	var col := HudPalette.AMBER if on else HudPalette.TEXT_DIM
	col.a = a
	centered(rect.position + Vector2(rect.size.x * 0.5, rect.size.y + 13.0), "STAGGER",
			HudPalette.SIZE_TINY, col)


func _draw_pods(bar: Rect2, pods: int, a: float) -> void:
	var col := HudPalette.GOLD
	col.a = a
	var w := bar.size.x / 4.0
	for i in 4:
		var r := Rect2(bar.position + Vector2(float(i) * w + 1.0, 0.0), Vector2(w - 2.0, bar.size.y))
		draw_rect(r, col if i < pods else HudPalette.TRACK, true)


## Two mark pips on the right edge; filled = a mark the player can spend with a COLLAPSE detonator.
func _draw_marks(rect: Rect2, marks: int, a: float) -> void:
	var base := rect.position + Vector2(rect.size.x - 8.0, rect.size.y - 3.0)
	for i in 2:
		var col := HudPalette.VIOLET if i < marks else HudPalette.TEXT_DIM
		col.a = a
		HudPalette.draw_diamond(self, base - Vector2(float(i) * 9.0, 0.0), 3.0, col, 1.0, i < marks)


## The quiet mark: a hostile chevron over the creature and a sliver of its HP, only while the player
## might still be looking for what they just shot.
func _draw_sliver(s: Dictionary) -> void:
	var at := s["pos"] as Vector2
	var st: Dictionary = s["state"]
	var col := HudPalette.DANGER
	draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, -14.0), at + Vector2(5.0, -6.0),
			at + Vector2(-5.0, -6.0)]), col)
	var hp := clampf(float(st.get("hp", 1.0)) / maxf(float(st.get("hp_max", 1.0)), 1.0), 0.0, 1.0)
	HudPalette.draw_bar(self, Rect2(at - Vector2(SLIVER_W * 0.5, 4.0), Vector2(SLIVER_W, 3.0)),
			hp, col)
