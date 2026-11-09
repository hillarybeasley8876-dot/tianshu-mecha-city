extends HudWidget
## Threat radar (brief §5, look review items 6/7): a 150 m top-down disc in the top-right corner. One
## hostile colour, size by class, elites as filled triangles; objectives in gold. It is deliberately
## quiet — a dark disc, one mid ring, a rim and a handful of marks with nothing written underneath.

const RADIUS := 70.0
const MARGIN := Vector2(56.0, 46.0)
const RANGE := 150.0            ## m — a fight past 150 m is not the fight you are in
const LAYER_FADE := 90.0        ## m of vertical separation at which a blip is at its dimmest
const LAYER_NEAR := 25.0        ## m — inside this the enemy counts as "on your level" (item 7.4)
const MERGE_PX := 4.0           ## blips closer than this on the disc become one dot with a count

## type -> [radius px, elite]. Size is the only channel that separates classes now that every blip
## carries the single hostile colour (look review item 6).
const CLASSES: Dictionary = {
	&"ripper": [2.6, false], &"mantis": [3.6, false], &"spitter": [3.4, false],
	&"harrier": [4.0, false], &"juggernaut": [6.0, true],
}

var blips: Array[Dictionary] = []


func center_point() -> Vector2:
	var s := screen_size()
	return Vector2(s.x - MARGIN.x - RADIUS, MARGIN.y + RADIUS)


func disc_rect() -> Rect2:
	var c := center_point()
	return Rect2(c - Vector2(RADIUS, RADIUS), Vector2(RADIUS, RADIUS) * 2.0)


func chrome_rect() -> Rect2:
	return disc_rect()


func update_hud(_delta: float) -> void:
	blips.clear()
	visible = data.alive() and data.player != null and not data.enemies.is_empty()
	if not visible:
		return
	var origin := data.player.global_position
	var yaw := atan2(_forward().x, -_forward().z)
	for e in data.enemies:
		if not is_instance_valid(e):
			continue
		var to := e.global_position - origin
		var dist := Vector2(to.x, to.z).length()
		if dist > RANGE * 2.0:
			continue
		blips.append({
			"node": e,
			"at": Vector2(to.x, to.z).rotated(yaw) / RANGE * RADIUS,
			"type": _type_of(e),
			"rim": dist > RANGE,
			"layer": clampf(absf(to.y) / LAYER_FADE, 0.0, 1.0),
			"dy": to.y,
			"count": 1,
		})
	blips = _merge(blips)


## EnemyBase exposes `enemy_type`; anything else on the map is treated as a swarmer.
func _type_of(e: Node3D) -> StringName:
	var t: Variant = e.get(&"enemy_type")
	return t as StringName if t != null else &"ripper"


func _forward() -> Vector3:
	if data.camera != null:
		return -data.camera.global_basis.z
	return Vector3.FORWARD


## A dozen Rippers at the same bearing used to pile into a smear of rings; blips landing within
## `MERGE_PX` of one already placed collapse into that one, which then carries a count (item 7.5).
func _merge(raw: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in raw:
		var hit := false
		for m in out:
			if (m["at"] as Vector2).distance_to(b["at"] as Vector2) <= MERGE_PX:
				m["count"] = int(m["count"]) + 1
				m["rim"] = bool(m["rim"]) and bool(b["rim"])
				hit = true
				break
		if not hit:
			out.append(b)
	return out


func _draw() -> void:
	var c := center_point()
	draw_circle(c, RADIUS, HudPalette.panel_fill(0.3))
	draw_arc(c, RADIUS * 0.5, 0.0, TAU, 32,
			Color(HudPalette.CYAN.r, HudPalette.CYAN.g, HudPalette.CYAN.b, 0.16), 1.0, true)
	draw_arc(c, RADIUS, 0.0, TAU, 48, HudPalette.CYAN_DIM, 1.5, true)
	_draw_landmarks(c)
	for b in blips:
		_draw_blip(c, b)
	_draw_player(c)


## One hostile colour, size by class, a filled triangle for an elite. Height still reads: a blip more
## than `LAYER_NEAR` above or below hollows out, dims with the separation and grows a ▲ / ▼ chevron,
## so a vertical city is readable on a flat disc (critic #12).
func _draw_blip(c: Vector2, b: Dictionary) -> void:
	var spec: Array = CLASSES.get(b["type"], [3.0, false])
	var r := float(spec[0])
	var at := c + (b["at"] as Vector2)
	var col := HudPalette.DANGER
	var count := int(b["count"])
	if bool(b["rim"]):
		# Beyond the disc's range: a tick on the rim, so the player still knows it is out there.
		var dir := (b["at"] as Vector2).normalized()
		draw_line(c + dir * (RADIUS - 5.0), c + dir * RADIUS, Color(col.r, col.g, col.b, 0.7), 2.0)
		return
	if bool(spec[1]):
		draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, -r), at + Vector2(r * 0.92, r * 0.7),
				at + Vector2(-r * 0.92, r * 0.7)]), col)
	elif absf(float(b["dy"])) <= LAYER_NEAR:
		draw_circle(at, r, col)
	else:
		col.a = lerpf(0.9, 0.35, float(b["layer"]))
		draw_arc(at, r + 0.5, 0.0, TAU, 12, col, 1.5, true)
		HudPalette.draw_chevron(self, at + Vector2(0.0, -r - 4.5), 3.0, float(b["dy"]) > 0.0, col)
	if count > 1:
		centered(at + Vector2(r + 5.0, -r), "×%d" % count, HudPalette.SIZE_TINY, col)


func _draw_player(c: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 6),
			c + Vector2(0, 3), c + Vector2(-5, 6)]), HudPalette.CYAN)


## Navigation is gold and the boss is violet — never the hostile red and never the monsters' own
## acid green, which is what made objective marks disappear into the hive (look review item 6).
func _draw_landmarks(c: Vector2) -> void:
	var origin := data.player.global_position if data.player != null else Vector3.ZERO
	var yaw := atan2(_forward().x, -_forward().z)
	for s in data.spires:
		var to := s.global_position - origin
		var at := Vector2(to.x, to.z).rotated(yaw) / RANGE * RADIUS
		HudPalette.draw_diamond(self, c + at.limit_length(RADIUS - 4.0), 5.0, HudPalette.GOLD, 0.0, true)
	if data.boss != null:
		var to := data.boss.global_position - origin
		var at := Vector2(to.x, to.z).rotated(yaw) / RANGE * RADIUS
		HudPalette.draw_diamond(self, c + at.limit_length(RADIUS - 4.0), 8.0, HudPalette.VIOLET, 0.0, true)
