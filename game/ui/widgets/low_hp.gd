extends HudWidget
## Low-armour warning (brief §6, juice-impact §11.3): a red edge vignette that pulses with a heartbeat
## under 35 % AP and doubles its rate under 15 %. Never colour alone: the vignette is paired with the audio
## unit's heartbeat loop (it owns the sound, same 35 % threshold) and the "LOW ARMOUR" caption.

const WARN := 0.35              ## juice §11.3 heartbeat threshold
const CRITICAL := 0.15          ## ... and the faster one
const BPM_WARN := 80.0
const BPM_CRITICAL := 120.0
const BAND_DEPTH := 0.12        ## fraction of the screen the vignette reaches in

var ratio: float = 1.0
var beat: float = 0.0           ## 0..1 phase inside the current beat

var _timer: float = 0.0


func update_hud(delta: float) -> void:
	ratio = data.ratio("hp", "hp_max", 1.0)
	visible = data.alive() and ratio < WARN
	if not visible:
		beat = 0.0
		return
	var bpm := BPM_WARN if ratio >= CRITICAL else BPM_CRITICAL
	_timer += delta
	var period := 60.0 / bpm
	if _timer >= period:
		_timer -= period
		beat = 0.0
	beat = minf(beat + delta / period, 1.0)


## Strength of the vignette this frame: a heartbeat-shaped spike on top of a steady low glow. With
## Settings `photosensitive` on, `HudPalette.motion` is 0 and only the steady glow is left — the sound
## and the caption still carry the warning (lead notes, critic #12).
func intensity() -> float:
	var base := inverse_lerp(WARN, 0.0, ratio) * 0.45
	var spike := pow(1.0 - beat, 6.0) * 0.55 * HudPalette.motion
	return clampf(base + spike, 0.0, 1.0)


func _draw() -> void:
	var s := screen_size()
	var col := HudPalette.DANGER
	var a := intensity()
	# Four vertex-coloured trapezoids: one linear ramp per edge, so the vignette is a gradient rather
	# than a stack of visible bands.
	var dx := s.x * BAND_DEPTH
	var dy := s.y * BAND_DEPTH
	var edge := Color(col.r, col.g, col.b, a * 0.5)
	var clear := Color(col.r, col.g, col.b, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, dy), Vector2(0, dy)]),
			PackedColorArray([edge, edge, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, s.y - dy), Vector2(s.x, s.y - dy),
			Vector2(s.x, s.y), Vector2(0, s.y)]),
			PackedColorArray([clear, clear, edge, edge]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(dx, 0), Vector2(dx, s.y), Vector2(0, s.y)]),
			PackedColorArray([edge, clear, clear, edge]))
	draw_polygon(PackedVector2Array([Vector2(s.x - dx, 0), Vector2(s.x, 0),
			Vector2(s.x, s.y), Vector2(s.x - dx, s.y)]),
			PackedColorArray([clear, edge, edge, clear]))
	var label := HudLocale.pick("装甲告急", "LOW ARMOUR") if ratio >= CRITICAL \
			else HudLocale.pick("危险", "CRITICAL")
	centered(Vector2(s.x * 0.5, s.y - 300.0), label, HudPalette.SIZE_BODY,
			Color(1.0, 1.0, 1.0, clampf(a, 0.35, 1.0)))
