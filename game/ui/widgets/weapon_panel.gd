extends HudWidget
## Weapon panel (brief §4): the equipped primary's name, its magazine and the reload bar, bottom-right
## so it never competes with the reticle. The rifle shows its two-stage charge as pips; the gatling
## shows belt count and leans on the reticle's heat arc for its temperature.

const WIDTH := 340.0
const HEIGHT := 66.0
const MARGIN := Vector2(56.0, 64.0)   ## px from the bottom-right corner
## px reserved at the left end for the overdrive ring (`od_ring.gd`), which hangs off this panel.
const OD_GUTTER := 78.0
const CORNER_CUT := 6.0               ## px, the 45° cut on the outer corner (look review item 11.3)

## One language per label (look review item 8.4): "P1 贯光步枪  PIERCE-LIGHT" was two names for one gun.
const NAMES_ZH: Dictionary = {&"beam_rifle": "P1 贯光步枪", &"gatling": "P2 雷纺机炮"}
const NAMES_EN: Dictionary = {&"beam_rifle": "P1 PIERCE-LIGHT", &"gatling": "P2 THUNDER SPINDLE"}

var weapon: StringName = &""
var ammo: int = 0
var ammo_max: int = 1
var reloading: bool = false
var swapping: bool = false
var charge: float = 0.0
var charge_stage: int = 0


func _ready() -> void:
	super()
	watch_keys = PackedStringArray(["ammo", "reloading", "swapping", "weapon", "charge_stage"])


## An empty or reloading gun is the one number the player must not miss (look review item 9).
func urgent() -> bool:
	return reloading or swapping or ammo <= 0


func update_hud(_delta: float) -> void:
	visible = data.alive() and data.has("ammo")
	if not visible:
		return
	weapon = StringName(data.str_of("weapon"))
	ammo = int(data.num("ammo"))
	ammo_max = maxi(int(data.num("ammo_max", 1.0)), 1)
	reloading = data.flag("reloading")
	swapping = data.flag("swapping")
	charge = clampf(data.num("charge"), 0.0, 1.0)
	charge_stage = int(data.num("charge_stage"))


func panel_rect() -> Rect2:
	var s := screen_size()
	return Rect2(Vector2(s.x - MARGIN.x - WIDTH, s.y - MARGIN.y - HEIGHT), Vector2(WIDTH, HEIGHT))


func chrome_rect() -> Rect2:
	return panel_rect()


func display_name() -> String:
	var table := NAMES_ZH if HudLocale.zh() else NAMES_EN
	return String(table.get(weapon, String(weapon).to_upper()))


## 0..1 phase of the "busy" sweep. Feel's unscaled clock, not the wall clock: a Movie Maker capture
## spends about 70 ms of wall time per 1/60 s game frame, which made the sweep strobe (CONTRACTS §3,
## audit #4). Split out so the test can read it.
func sweep_phase() -> float:
	return fmod(Feel.real_now() * 0.9, 1.0)


func _draw() -> void:
	var r := panel_rect()
	# One deliberate panel shape with a 45° cut on the outer corner and a horizontal gradient from ink
	# to clear — no four cyan corner ticks, which read as a debug overlay (look review item 11.3).
	_draw_shape(r)
	var x := OD_GUTTER
	text(r.position + Vector2(x, 20.0), display_name(), HudPalette.SIZE_SMALL, HudPalette.CYAN,
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - x - 12.0, false, false)
	var col := HudPalette.TEXT_DIM if (reloading or swapping) else HudPalette.WHITE
	if ammo <= 0 and not reloading:
		col = HudPalette.AMBER
	text(r.position + Vector2(x, HEIGHT - 8.0), str(ammo), HudPalette.SIZE_HEAD, col,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, false, false)
	var w := text_w(str(ammo), HudPalette.SIZE_HEAD)
	text(r.position + Vector2(x + 6.0 + w, HEIGHT - 9.0), "/ %d" % ammo_max, HudPalette.SIZE_SMALL,
			HudPalette.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false, false)
	_draw_state(r)


## The panel silhouette (look review item 11.3): a horizontal ink gradient that is solid where the
## numbers sit and dissolves toward the screen centre, with a 45° cut on the outer top-left corner.
## No corner brackets — a bracket now means "locked" and nothing else.
func _draw_shape(r: Rect2) -> void:
	var steps := 12
	for i in steps:
		var x0 := r.position.x + r.size.x * float(i) / float(steps)
		var x1 := r.position.x + r.size.x * float(i + 1) / float(steps)
		var a := lerpf(0.62, 0.05, float(i) / float(steps))
		var pts := PackedVector2Array()
		if i == 0:
			pts.append(Vector2(x0, r.position.y + CORNER_CUT))
			pts.append(Vector2(x0 + CORNER_CUT, r.position.y))
		else:
			pts.append(Vector2(x0, r.position.y))
		pts.append(Vector2(x1, r.position.y))
		pts.append(Vector2(x1, r.end.y))
		pts.append(Vector2(x0, r.end.y))
		draw_colored_polygon(pts, HudPalette.panel_fill(a))
	draw_line(Vector2(r.position.x + CORNER_CUT, r.position.y),
			Vector2(r.end.x, r.position.y),
			Color(HudPalette.CYAN.r, HudPalette.CYAN.g, HudPalette.CYAN.b, 0.45), 1.0)


func _draw_state(r: Rect2) -> void:
	var track := Rect2(r.position + Vector2(WIDTH * 0.45, HEIGHT - 16.0), Vector2(WIDTH * 0.47, 6.0))
	if reloading or swapping:
		# No reload progress in hud_state(), so the bar sweeps: it says "busy", not "how much left".
		var t := sweep_phase()
		HudPalette.draw_bar(self, Rect2(track.position, Vector2(track.size.x, track.size.y)),
				0.0, HudPalette.TRACK)
		draw_rect(Rect2(track.position + Vector2(t * track.size.x * 0.7, 0.0),
				Vector2(track.size.x * 0.3, track.size.y)), HudPalette.AMBER, true)
		var label := "RELOADING" if reloading else "SWITCHING"
		text(track.position + Vector2(0.0, -7.0), label, HudPalette.SIZE_TINY, HudPalette.AMBER)
		return
	if weapon == &"gatling":
		text(track.position + Vector2(0.0, -7.0), "BELT", HudPalette.SIZE_TINY, HudPalette.TEXT_DIM)
		return
	for i in 2:
		var on := charge_stage > i
		var p := Rect2(track.position + Vector2(float(i) * 26.0, 0.0), Vector2(20.0, 5.0))
		HudPalette.draw_bar(self, p, 1.0 if on else 0.0, HudPalette.CYAN if on else HudPalette.TRACK)
		if not on and i == charge_stage:
			HudPalette.draw_bar(self, p, clampf(charge * 2.0 - float(i), 0.0, 1.0), HudPalette.CYAN_DIM)
	text(track.position + Vector2(0.0, -7.0), "CHARGE", HudPalette.SIZE_TINY, HudPalette.TEXT_DIM)
