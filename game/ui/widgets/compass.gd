extends HudWidget
## Compass tape (brief §5, look review item 4): a 620 px ribbon at top centre carrying cardinal ticks
## and objective marks. Exactly ONE objective carries a label — the nearest standing spire, in gold,
## with its horizontal distance — and every other mark is a bare diamond. Markers that would fall off
## the tape collapse into a single edge arrow with a count, so nothing ever prints twice or hangs off
## the end onto bare sky.

const WIDTH := 620.0
const HEIGHT := 44.0
const TOP := 34.0
const SPAN_DEG := 180.0          ## degrees of heading visible across the tape
const TICK_DEG := 15.0
const LABEL_GAP := 70.0          ## px — a label this close to one already drawn is skipped
const HEIGHT_SUFFIX := 15.0      ## m of height difference before the ▲/▼ suffix is worth printing

const CARDINALS: Dictionary = {0.0: "N", 90.0: "E", 180.0: "S", 270.0: "W"}

var heading_deg: float = 0.0

var _label_rect: Rect2 = Rect2()   ## where this frame's one objective label landed


func chrome_rect() -> Rect2:
	return strip_rect().grow(8.0)


func strip_rect() -> Rect2:
	var s := screen_size()
	return Rect2(Vector2((s.x - WIDTH) * 0.5, TOP), Vector2(WIDTH, HEIGHT))


func update_hud(_delta: float) -> void:
	visible = data.alive() and data.player != null
	if not visible:
		return
	var fwd := _forward()
	heading_deg = fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)


func _forward() -> Vector3:
	if data.camera != null:
		return -data.camera.global_basis.z
	return Vector3.FORWARD


## Bearing of a world point relative to the camera's heading, wrapped to −180..180 degrees.
func bearing_to(p: Vector3) -> float:
	var fwd := _forward()
	var to := p - _origin()
	to.y = 0.0
	if to.length_squared() < 0.01:
		return 0.0
	var a := rad_to_deg(atan2(to.x, -to.z))
	var f := rad_to_deg(atan2(fwd.x, -fwd.z))
	return wrapf(a - f, -180.0, 180.0)


## Bearing -> x on the tape, clamped so off-tape markers pin to the edges.
func x_for(bearing: float) -> float:
	var t := clampf(bearing / (SPAN_DEG * 0.5), -1.0, 1.0)
	return strip_rect().get_center().x + t * WIDTH * 0.5


func _origin() -> Vector3:
	return data.player.global_position if data.player != null else Vector3.ZERO


## The one mark that earns a label: the nearest standing spire, or the boss once it is closer.
func primary_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n: Node3D in [data.boss] + data.spires:
		if not is_instance_valid(n):
			continue
		var d := n.global_position.distance_to(_origin())
		if d < best_d:
			best_d = d
			best = n
	return best


func _draw() -> void:
	var r := strip_rect()
	# No fill: a flat navy band turned grey-brown mud over the warm sky (look review item 11.1).
	draw_line(r.position + Vector2(0.0, r.size.y), r.position + Vector2(r.size.x, r.size.y),
			Color(HudPalette.CYAN.r, HudPalette.CYAN.g, HudPalette.CYAN.b, 0.35), 1.0)
	_draw_ticks(r)
	# The heading notch is drawn BEFORE the marks, as a notch above the tape, so it can never slice
	# through a label (item 4.6).
	var cx := r.get_center().x
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 5.0, r.position.y - 9.0),
			Vector2(cx + 5.0, r.position.y - 9.0), Vector2(cx, r.position.y - 1.0)]), HudPalette.CYAN)
	_draw_markers()


func _draw_ticks(r: Rect2) -> void:
	var first := ceilf((heading_deg - SPAN_DEG * 0.5) / TICK_DEG) * TICK_DEG
	for i in int(SPAN_DEG / TICK_DEG) + 2:
		var deg := first + float(i) * TICK_DEG
		var x := x_for(wrapf(deg - heading_deg, -180.0, 180.0))
		if x < r.position.x or x > r.end.x:
			continue
		var cardinal: String = CARDINALS.get(fposmod(deg, 360.0), "")
		var tall := 12.0 if cardinal != "" else 6.0
		draw_line(Vector2(x, r.end.y - tall), Vector2(x, r.end.y), HudPalette.CYAN_DIM, 1.0)
		if cardinal != "":
			centered(Vector2(x, r.position.y + 14.0), cardinal, HudPalette.SIZE_SMALL, HudPalette.WHITE)


## Every spire and the boss get a mark; only the primary one gets text. Marks whose bearing falls off
## the tape collapse into one arrow per edge carrying a count.
func _draw_markers() -> void:
	var primary := primary_target()
	var edges := {"left": 0, "right": 0}
	_label_rect = Rect2()
	var spire := HudLocale.pick("蚀巢", "SPIRE")
	var titan := HudLocale.pick("巢母", "TITAN")
	for n: Node3D in data.spires:
		_marker(n, HudPalette.GOLD, spire, primary == n, edges)
	if data.boss != null:
		_marker(data.boss, HudPalette.VIOLET, titan, primary == data.boss, edges)
	_draw_edge_counts(edges)


## One objective mark: a diamond on the tape and, for the primary mark only, "蚀巢 312 m" underneath.
## The number is the HORIZONTAL distance — printing the height difference there read as a distance and
## lied to the player (item 4.2) — and the ▲/▼ suffix only appears past 15 m of height difference.
func _marker(n: Node3D, col: Color, label: String, primary: bool, edges: Dictionary) -> void:
	var r := strip_rect()
	var bearing := bearing_to(n.global_position)
	var x := x_for(bearing)
	if absf(bearing) > SPAN_DEG * 0.5:
		edges["left" if bearing < 0.0 else "right"] = int(edges["left" if bearing < 0.0 else "right"]) + 1
		return
	HudPalette.draw_diamond(self, Vector2(x, r.position.y + 24.0), 5.0, col, 0.0, true)
	if not primary:
		return
	var to := n.global_position - _origin()
	var flat := Vector2(to.x, to.z).length()
	var line := "%s %d m" % [label, int(round(flat))]
	if absf(to.y) > HEIGHT_SUFFIX:
		line += " %s%d" % ["▲" if to.y > 0.0 else "▼", int(round(absf(to.y)))]
	var hw := text_w(line, HudPalette.SIZE_SMALL) * 0.5
	# Keep the whole label inside the tape (item 4.4).
	var at := Vector2(clampf(x, r.position.x + hw + 6.0, r.end.x - hw - 6.0), r.end.y - 8.0)
	_label_rect = Rect2(at - Vector2(hw + 4.0, 16.0), Vector2(hw * 2.0 + 8.0, 20.0))
	centered(at, line, HudPalette.SIZE_SMALL, col)


## Objectives behind the player: one arrow per edge with a count, so five spires behind you read as
## "◀ 3" and not as three labels stacked on the same pixel. An edge arrow that would print on top of
## the one objective label is dropped — the label is the more useful of the two (item 4.5).
func _draw_edge_counts(edges: Dictionary) -> void:
	var r := strip_rect()
	for side: String in ["left", "right"]:
		var count := int(edges[side])
		if count <= 0:
			continue
		var sign := -1.0 if side == "left" else 1.0
		var at := Vector2(r.get_center().x + sign * (WIDTH * 0.5 - 34.0), r.position.y + 24.0)
		if _label_rect.has_point(at) or absf(at.x - _label_rect.get_center().x) < LABEL_GAP:
			continue
		var tip := at + Vector2(sign * 7.0, 0.0)
		draw_colored_polygon(PackedVector2Array([tip, at + Vector2(0.0, -6.0), at + Vector2(0.0, 6.0)]),
				HudPalette.GOLD)
		centered(at + Vector2(-sign * 10.0, 5.0), "%d" % count, HudPalette.SIZE_SMALL, HudPalette.GOLD)
