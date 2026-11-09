extends HudWidget
## Armour bar (brief §4): a segmented HP gauge in the bottom-left corner. Segments are 1,000 AP each so
## the player can read "two bars left" at a glance; the bar flashes red and shakes for 0.25 s on every
## hit that gets through the defences.

const SEGMENTS := 10
const WIDTH := 420.0
const HEIGHT := 20.0
const MARGIN := Vector2(56.0, 64.0)   ## px from the bottom-left corner
const SEG_GAP := 3.0
const FLASH_TIME := 0.25
const SHAKE_PX := 5.0

var ratio: float = 1.0
var hp: float = 0.0
var hp_max: float = 1.0
var flash: float = 0.0

var _shake_seed: float = 0.0


func _ready() -> void:
	super()
	Events.player_damaged.connect(_on_damaged)
	watch_keys = PackedStringArray(["hp"])


func _on_damaged(_hit: HitInfo) -> void:
	flash = FLASH_TIME
	_shake_seed = randf() * TAU


func update_hud(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(flash - delta, 0.0)
	visible = data.alive() and data.has("hp")
	if not visible:
		return
	hp = data.num("hp")
	hp_max = maxf(data.num("hp_max", 1.0), 1.0)
	ratio = clampf(hp / hp_max, 0.0, 1.0)


## Low armour is the one state the bar must shout about; above that it is reference (item 9).
func urgent() -> bool:
	return ratio < 0.35 or flash > 0.0


func bar_rect() -> Rect2:
	var s := screen_size()
	return Rect2(Vector2(MARGIN.x, s.y - MARGIN.y - HEIGHT), Vector2(WIDTH, HEIGHT))


func chrome_rect() -> Rect2:
	return bar_rect().grow(10.0)


## Segment 0 is the leftmost; each is 1/SEGMENTS of the bar with a gap so the count is countable.
func segment_rect(i: int) -> Rect2:
	var r := bar_rect()
	var w := (WIDTH - SEG_GAP * float(SEGMENTS - 1)) / float(SEGMENTS)
	return Rect2(r.position + Vector2(float(i) * (w + SEG_GAP), 0.0), Vector2(w, r.size.y))


func fill_color() -> Color:
	if flash > 0.0:
		return HudPalette.DANGER.lerp(HudPalette.WHITE, flash / FLASH_TIME * 0.5)
	if ratio < 0.15:
		return HudPalette.DANGER
	if ratio < 0.35:
		return HudPalette.AMBER
	return HudPalette.CYAN


func _draw() -> void:
	var r := bar_rect()
	var off := Vector2.ZERO
	if flash > 0.0:
		off.x = sin(_shake_seed + (FLASH_TIME - flash) * 60.0) * SHAKE_PX * (flash / FLASH_TIME)
	# A 4 px ink strip behind the segments (look review item 8.6): cyan segments sat directly on the
	# hero's own cyan-lit armour and vanished.
	draw_rect(Rect2(r.position + off - Vector2(0.0, 4.0), Vector2(WIDTH, HEIGHT + 8.0)),
			HudPalette.panel_fill(0.5), true)
	for i in SEGMENTS:
		var seg := segment_rect(i)
		seg.position += off
		var filled := clampf(ratio * float(SEGMENTS) - float(i), 0.0, 1.0)
		draw_rect(seg, Color(HudPalette.TRACK.r, HudPalette.TRACK.g, HudPalette.TRACK.b, 0.8), true)
		if filled > 0.0:
			draw_rect(Rect2(seg.position, Vector2(seg.size.x * filled, seg.size.y)), fill_color(), true)
	var label := HudLocale.pick("装甲", "ARMOUR")
	text(r.position + off + Vector2(2.0, -9.0), label, HudPalette.SIZE_TINY, HudPalette.TEXT_DIM)
	var value := "%d / %d" % [int(round(hp)), int(round(hp_max))]
	text(r.position + off + Vector2(2.0, -9.0), value, HudPalette.SIZE_NUM, HudPalette.WHITE,
			HORIZONTAL_ALIGNMENT_RIGHT, WIDTH)
