extends HudWidget
## Flight cue (hud r6 item 5, mech-move Request 7): `hud_state()["state"]` reads "fly" from the moment
## the mech takes off until it glides, lands or toggles flight off, and nothing on screen said so — the
## one state that spends EN at 80–120/s with no regen behind it was invisible.
##
## The reading is the number the player can act on: seconds of flight left. It is MEASURED from the EN
## this widget already watches — flight pauses EN regen entirely (SPEC §4), so the observed drop IS the
## flight cost. Nothing is copied out of `mech_tuning.gd`, so a re-tune needs no HUD edit, and the boost
## toggle's 80 ↔ 120 EN/s shows up on its own.

const FLY := "fly"
## EN/s below which a "drop" between two frames is rounding noise rather than a drain.
const MIN_SAMPLE := 1.0
## Per-sample blend, so the assault-boost toggle settles on the new cost in about a fifth of a second.
const SMOOTH := 0.2
## s of flight left before the readout turns amber — long enough to pick a landing.
const WARN_SECONDS := 2.5
## px from the screen centre. Left of the crosshair, beside the EN arc it belongs to, well clear of the
## 64 px gauge ring, the 72 px threat ring and the tutorial prompt under the cluster.
const OFFSET := Vector2(-118.0, 0.0)
const RULE_H := 42.0

var flying: bool = false
var seconds_left: float = -1.0      ## -1 until the first drain sample lands
var drain: float = 0.0              ## EN/s, measured from the falling EN gauge

var _en_prev: float = -1.0


func _ready() -> void:
	super()
	# The edge signal (CONTRACTS §6): taking off starts a fresh measurement, so a second flight never
	# inherits the first one's rate.
	Events.flight_changed.connect(func(on: bool) -> void:
		if on:
			_reset())


func update_hud(delta: float) -> void:
	flying = data.has("state") and data.str_of("state") == FLY
	visible = data.alive() and flying
	if not visible:
		if _en_prev >= 0.0:
			_reset()
		return
	var en := data.num("en")
	if _en_prev >= 0.0 and delta > 0.0:
		_sample((_en_prev - en) / delta)
	_en_prev = en
	seconds_left = en / drain if drain > MIN_SAMPLE else -1.0


func _sample(rate: float) -> void:
	if rate <= MIN_SAMPLE:
		return
	drain = rate if drain <= 0.0 else lerpf(drain, rate, SMOOTH)


func _reset() -> void:
	_en_prev = -1.0
	drain = 0.0
	seconds_left = -1.0


## Amber only to warn (palette rule: cyan is you, amber is a warning); cyan the rest of the flight.
func color() -> Color:
	if seconds_left >= 0.0 and seconds_left < WARN_SECONDS:
		return HudPalette.AMBER
	return HudPalette.CYAN


## Seconds of flight left once the drain is known, and the EN percentage for the frame or two before
## the first sample lands — an actionable number either way, never a dash.
func reading() -> String:
	if seconds_left < 0.0:
		return "%d%%" % int(round(data.ratio("en", "en_max", 0.0) * 100.0))
	return "%.1f s" % seconds_left


func label() -> String:
	return HudLocale.pick("飞行", "FLIGHT")


func cue_rect() -> Rect2:
	var c := screen_center() + OFFSET
	var w := maxf(text_w(label(), HudPalette.SIZE_SMALL), text_w(reading(), HudPalette.SIZE_NUM))
	return Rect2(Vector2(c.x - 10.0 - w, c.y - RULE_H * 0.5), Vector2(w + 12.0, RULE_H))


func chrome_rect() -> Rect2:
	return cue_rect() if visible else Rect2()


func _draw() -> void:
	var c := screen_center() + OFFSET
	var col := color()
	var r := cue_rect()
	text(Vector2(r.position.x, c.y - 4.0), label(), HudPalette.SIZE_SMALL, HudPalette.TEXT_DIM)
	text(Vector2(r.position.x, c.y + 18.0), reading(), HudPalette.SIZE_NUM, col)
	draw_line(Vector2(c.x, r.position.y), Vector2(c.x, r.end.y), col, 2.0)
