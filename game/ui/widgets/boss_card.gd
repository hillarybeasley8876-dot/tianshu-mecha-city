extends HudWidget
## Boss title card (lead note, boss r1): `Events.boss_intro(title, subtitle)` puts the enemy's name
## across the middle of the screen for a beat before the fight, the way a kaiju film names its monster.
##
## It is the one element allowed over the centre — it is a cinematic card, not an instrument, and it
## is gone in CARD_TIME. Photosensitive-safe: the card slides and fades, it never strobes, and
## `HudPalette.motion` flattens the wipe to a plain fade.

const CARD_TIME := 2.5        ## s the card stays up (brief §5 / lead note)
const IN_TIME := 0.35         ## s of wipe-in at the start
const OUT_TIME := 0.5         ## s of fade-out at the end
const WIDTH := 900.0
const HEIGHT := 150.0

var title: String = ""
var subtitle: String = ""

var _t: float = CARD_TIME        ## starts retired; `show_card` rewinds it


func _ready() -> void:
	super()
	Events.boss_intro.connect(show_card)


## Tests, the flow unit and the capture harness can raise the card directly.
func show_card(card_title: String, card_subtitle: String = "") -> void:
	title = card_title
	subtitle = card_subtitle
	_t = 0.0
	visible = true
	queue_redraw()


func update_hud(delta: float) -> void:
	_t += delta
	if _t >= CARD_TIME:
		visible = false
		return
	visible = true


## 0 while the card wipes in, 1 for the hold, back to 0 over OUT_TIME — the alpha and slide both
## read from this, so the whole card has one motion curve.
func reveal() -> float:
	if _t < IN_TIME:
		return clampf(_t / IN_TIME, 0.0, 1.0)
	var left := CARD_TIME - _t
	return clampf(left / OUT_TIME, 0.0, 1.0) if left < OUT_TIME else 1.0


## Sits above the reticle cluster and below the boss bar: a title card that lands on the crosshair
## reads as a bug, and this one is only up for CARD_TIME anyway.
func card_rect() -> Rect2:
	var s := screen_size()
	return Rect2(Vector2((s.x - WIDTH) * 0.5, s.y * 0.24), Vector2(WIDTH, HEIGHT))


func _draw() -> void:
	var a := reveal()
	if a <= 0.0 or title == "":
		return
	var ease := a * a * (3.0 - 2.0 * a)
	var r := card_rect()
	var slide := (1.0 - ease) * 26.0 * HudPalette.motion
	var at := r.position + Vector2(0.0, slide)
	# Darker than the usual plate: the card lands over sky and pale concrete, where a 55 % panel
	# leaves the name sitting on a bright field.
	HudPalette.draw_panel(self, Rect2(at, r.size), 0.72 * a, HudPalette.VIOLET)
	HudPalette.draw_brackets(self, Rect2(at, r.size), Color(HudPalette.VIOLET.r,
			HudPalette.VIOLET.g, HudPalette.VIOLET.b, a), 22.0, 2.0)
	centered(at + Vector2(r.size.x * 0.5, 74.0), title, HudPalette.SIZE_HUGE,
			Color(HudPalette.WHITE.r, HudPalette.WHITE.g, HudPalette.WHITE.b, a))
	if subtitle != "":
		centered(at + Vector2(r.size.x * 0.5, 112.0), subtitle, HudPalette.SIZE_BODY,
				Color(HudPalette.VIOLET.r, HudPalette.VIOLET.g, HudPalette.VIOLET.b, a * 0.9))
