extends HudWidget
## Zenith Overdrive ring (brief §4, skills-catalog §4.9, look review item 12): a small ring at the LEFT
## END of the weapon panel, so the bottom centre of the screen belongs to the world. It idles at a
## third of its strength, pulses once it is full and shows the key prompt, turns amber with a countdown
## while the Overdrive runs, and goes white-rimmed when the Zenith Lance is loaded.

const RADIUS := 30.0
const WIDTH := 5.0
const PULSE_HZ := 1.4              ## the "ready" breathing rate
const REST := 0.3                  ## alpha below 100 % — the gauge is information, not an alarm
## Where it sits: the weapon panel's left edge, vertically centred in it.
const PANEL_INSET := Vector2(38.0, 33.0)

var fill: float = 0.0
var active: bool = false
var lance_ready: bool = false
var left: float = 0.0
var glyph: String = "V"

var _t: float = 0.0


func _ready() -> void:
	super()
	watch_keys = PackedStringArray(["od", "overdrive_active"])


func update_hud(delta: float) -> void:
	_t += delta
	visible = data.alive() and data.has("od")
	if not visible:
		return
	fill = data.ratio("od", "od_max", 0.0)
	active = data.flag("overdrive_active")
	lance_ready = data.flag("lance_ready")
	left = data.num("overdrive_left")
	glyph = String(data.state.get("od_glyph", "V"))


## Full only while it matters: running, loaded, or actually charged (look review item 9).
func urgent() -> bool:
	return active or fill >= 0.999


## The ring hangs off the LEFT END of the weapon panel; the panel owns that geometry, so ask it rather
## than repeating its constants (they would drift the first time the panel is retuned).
func center_point() -> Vector2:
	var panel := _panel()
	if panel != null:
		return (panel.call(&"panel_rect") as Rect2).position + PANEL_INSET
	var s := screen_size()
	return Vector2(s.x - 56.0 - 340.0 + PANEL_INSET.x, s.y - 64.0 - 66.0 + PANEL_INSET.y)


func _panel() -> Node:
	if get_parent() == null:
		return null
	return get_parent().get_node_or_null(^"weapon")


func chrome_rect() -> Rect2:
	var c := center_point()
	return Rect2(c - Vector2.ONE * (RADIUS + 6.0), Vector2.ONE * (RADIUS + 6.0) * 2.0)


func _draw() -> void:
	var c := center_point()
	var a0 := deg_to_rad(-210.0)
	var a1 := deg_to_rad(30.0)
	var col := HudPalette.CYAN
	var a := 1.0 if urgent() else REST
	if active:
		col = HudPalette.AMBER
	elif fill >= 0.999:
		col = HudPalette.WHITE.lerp(HudPalette.CYAN, HudPalette.pulse(sin(_t * TAU * PULSE_HZ)))
	col.a = a
	HudPalette.draw_gauge(self, c, RADIUS, a0, a1, fill, col, WIDTH, 0.35 * a)
	if active and left > 0.0:
		_draw_active(c, a0, a1)
	if lance_ready:
		draw_arc(c, RADIUS + 6.0, a0, a1, 40, HudPalette.WHITE, 1.5, true)
	_draw_label(c, a)


## While the Overdrive runs the ring keeps its fill and gains an inner arc that empties with the buff.
func _draw_active(c: Vector2, a0: float, a1: float) -> void:
	var span := maxf(data.num("overdrive_total", 12.0), 0.001)
	draw_arc(c, RADIUS - 8.0, a0, lerpf(a0, a1, clampf(left / span, 0.0, 1.0)), 32,
			HudPalette.AMBER, 2.5, true)


func _draw_label(c: Vector2, a: float) -> void:
	if active:
		centered(c + Vector2(0.0, 4.0), "OD", HudPalette.SIZE_TINY, HudPalette.AMBER)
		return
	if fill >= 0.999:
		var pulse := HudPalette.pulse(sin(_t * TAU * PULSE_HZ))
		centered(c + Vector2(0.0, 6.0), glyph, HudPalette.SIZE_HEAD,
				Color(HudPalette.WHITE.r, HudPalette.WHITE.g, HudPalette.WHITE.b, pulse))
		return
	centered(c + Vector2(0.0, 4.0), "%d" % int(round(fill * 100.0)), HudPalette.SIZE_TINY,
			Color(HudPalette.TEXT_DIM.r, HudPalette.TEXT_DIM.g, HudPalette.TEXT_DIM.b, a))
