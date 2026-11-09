extends HudWidget
## Reticle cluster (brief §2, skills-catalog §4.9, look review items 1/5/6): the dynamic weapon
## reticle at screen centre with a slim 90° EN arc hugging its left and the heat arc on its right
## (only while the gatling is actually hot). The arcs are 3 px at radius 64 and carry no captions, so
## the centre of the screen stays legible over a bright city and never crosses the lock mark.

const ARC_RADIUS := 64.0
const ARC_WIDTH := 3.0
const ARC_SWEEP := 90.0                  ## degrees each gauge sweeps (look review item 5)
const TRACK_ALPHA := 0.2                 ## an empty gauge must not read as a heavy dark band
const RIFLE_EFFECTIVE := 200.0           ## m, SPEC §6 "full damage ≤ 200 m"
const GATLING_EFFECTIVE := 180.0         ## m, SPEC §5 mid band ceiling (tuning choice)
const SOFT_RADIUS := 34.0                ## px, half-size of the soft-lock bracket
const CROSS_GAP := 8.0                   ## px of clear space at the very centre
const OVERHEAT_BLINK := 6.0              ## Hz the heat arc flashes while the barrel is locked
const HEAT_SHOW := 0.05                  ## heat fraction above which the arc is worth drawing
const EN_IDLE_HIDE := 1.5                ## s at full, unspent EN before the arc fades away
const NEAR_LOCK_PX := 90.0               ## px — inside this the reticle owns the range readout

var weapon: StringName = &"beam_rifle"
var en_ratio: float = 1.0
var heat_ratio: float = 0.0
var overheated: bool = false
var vent_needle: float = 0.0
var vent_mark: float = 0.0
var charge: float = 0.0
var charge_stage: int = 0
var spread: float = 0.0                  ## px the gatling circle opens by
var in_range: bool = false               ## hard target inside the weapon's effective range
var has_target: bool = false             ## any hard target at all
var ads: bool = false
var blocked: bool = false                ## scenery is stopping the shot (lead notes)
var block_dist: float = -1.0
var en_alpha: float = 1.0                ## the EN arc fades once it has sat full and unspent
var heat_shown: bool = false             ## gatling out, barrel hot, or overheated
## Where the soft-lock bracket goes this frame — Vector2.INF when there is nothing to bracket. Kept
## out of `_draw` so the placement is testable and the draw stays a pure function of it.
var soft_lock_at: Vector2 = Vector2.INF

var _blink: float = 0.0
var _en_full_t: float = 0.0
var _last_en: float = 1.0


## True on the bright half of a `rate` Hz blink. With Settings `photosensitive` on, `HudPalette.motion`
## is 0 and this sits still on the alarm colour instead of flashing (lead notes, critic #12).
func _blink_on(rate: float) -> bool:
	return HudPalette.pulse(sin(_blink * TAU * rate)) > 0.5


func update_hud(delta: float) -> void:
	visible = data.alive() and data.has("weapon")
	if not visible:
		return
	_blink += delta
	weapon = StringName(data.str_of("weapon", "beam_rifle"))
	en_ratio = data.ratio("en", "en_max", 1.0)
	heat_ratio = clampf(data.num("heat"), 0.0, 1.0)
	overheated = data.flag("overheated")
	vent_needle = clampf(data.num("vent_needle"), 0.0, 1.0)
	vent_mark = clampf(data.num("vent_mark"), 0.0, 1.0)
	charge = clampf(data.num("charge"), 0.0, 1.0)
	charge_stage = int(data.num("charge_stage"))
	ads = data.flag("ads")
	blocked = data.flag("shot_blocked")
	block_dist = data.num("block_dist", -1.0)

	var dist := data.num("soft_distance", -1.0)
	has_target = data.node("hard_target") != null
	if has_target:
		dist = data.num("hard_distance", -1.0)
	var effective := RIFLE_EFFECTIVE if weapon != &"gatling" else GATLING_EFFECTIVE
	in_range = has_target and dist >= 0.0 and dist <= effective
	spread = _gatling_spread()
	_tick_en(delta)
	soft_lock_at = _soft_lock_point()
	# Look review item 5: an empty gatling gauge is a dark band that means nothing — draw HEAT only
	# when the gun is out, the barrel is actually hot, or it has locked up.
	heat_shown = weapon == &"gatling" or heat_ratio > HEAT_SHOW or overheated


## The soft target's screen position, or INF when there is nothing to bracket: never while a hard lock
## is up (look review item 1), never for a target that is off screen.
func _soft_lock_point() -> Vector2:
	if data == null or has_target:
		return Vector2.INF
	var t := data.node("soft_target")
	if t == null:
		return Vector2.INF
	var p := data.project(t.global_position)
	return p["pos"] as Vector2 if bool(p["visible"]) else Vector2.INF


## EN sits at 100 % through most of a fight, where a permanent full ring is pure noise. After
## `EN_IDLE_HIDE` seconds untouched it fades to a third and comes straight back on any spend
## (look review items 5/9).
func _tick_en(delta: float) -> void:
	if en_ratio >= 0.999 and is_equal_approx(_last_en, en_ratio) and not data.flag("outage"):
		_en_full_t += delta
	else:
		_en_full_t = 0.0
	_last_en = en_ratio
	en_alpha = lerpf(1.0, 0.35, clampf(_en_full_t / EN_IDLE_HIDE, 0.0, 1.0))


## The gatling's cone is not in hud_state(); the reticle shows it growing while the barrel spins up
## (brief §2 "circle with spread"). Falls back to heat, which rises with sustained fire.
func _gatling_spread() -> float:
	if weapon != &"gatling":
		return 0.0
	var cone := data.num("spread", -1.0)
	if cone < 0.0:
		cone = heat_ratio * 0.9
	return lerpf(26.0, 54.0, clampf(cone, 0.0, 1.0))


## Hostile-red while the locked target sits inside the weapon's effective range, quiet white while it
## is out of it (look review item 6: one colour per meaning — red is "the enemy", white is "you").
func reticle_color() -> Color:
	if not has_target:
		return HudPalette.CYAN
	if in_range:
		return HudPalette.DANGER
	return Color(HudPalette.WHITE.r, HudPalette.WHITE.g, HudPalette.WHITE.b, 0.6)


func _draw() -> void:
	var c := screen_center()
	var col := reticle_color()
	if blocked:
		col = Color(col.r, col.g, col.b, 0.35)
	_draw_en_arc(c)
	_draw_heat_arc(c)
	if weapon == &"gatling":
		_draw_gatling(c, col)
	else:
		_draw_rifle(c, col)
	if blocked:
		_draw_blocked(c, col)
	_draw_soft_lock()
	_draw_near_range(c)
	if ads:
		draw_arc(c, ARC_RADIUS + 16.0, deg_to_rad(-14.0), deg_to_rad(14.0), 12, HudPalette.CYAN_DIM, 1.5, true)


## A target that projects almost onto the crosshair would have its lock box cut by the gauges, so the
## reticle prints the range just outside its own ring and `markers.gd` leaves the label alone
## (look review item 5.5).
func _draw_near_range(c: Vector2) -> void:
	var t := data.node("hard_target") if data != null else null
	if t == null:
		return
	var p := data.project(t.global_position)
	if not bool(p["visible"]) or (p["pos"] as Vector2).distance_to(c) > NEAR_LOCK_PX:
		return
	centered(c + Vector2(ARC_RADIUS + 26.0, 26.0), "%d m" % int(round(float(p["dist"]))),
			HudPalette.SIZE_SMALL, HudPalette.CYAN, true, true)


## Scenery in the way: the reticle greys out and a hatched barrier plate appears under it with the
## distance, so "my shot is hitting a wall" never reads as "I missed" (lead notes, critic #12).
func _draw_blocked(c: Vector2, col: Color) -> void:
	var at := c + Vector2(0.0, 54.0)
	HudPalette.draw_barrier_icon(self, at, 9.0, HudPalette.AMBER)
	var label := "BLOCKED" if block_dist < 0.0 else "BLOCKED %dm" % int(round(block_dist))
	centered(at + Vector2(0.0, 22.0), label, HudPalette.SIZE_TINY, HudPalette.AMBER, true)
	draw_line(c + Vector2(-10.0, 0.0), c + Vector2(10.0, 0.0), Color(col.r, col.g, col.b, 0.3), 1.5)


## EN: left arc, filled from the bottom-left upward. Empty (Outage) pulses the track red. No caption —
## the arc is always on the left and the colour says the rest (look review item 5.4).
func _draw_en_arc(c: Vector2) -> void:
	var a0 := deg_to_rad(180.0 - ARC_SWEEP * 0.5)
	var a1 := deg_to_rad(180.0 + ARC_SWEEP * 0.5)
	var col := HudPalette.CYAN
	if en_ratio <= 0.001 or data.flag("outage"):
		col = HudPalette.AMBER if _blink_on(2.0) else HudPalette.DANGER
		en_alpha = 1.0
	col.a = en_alpha
	HudPalette.draw_gauge(self, c, ARC_RADIUS, a0, a1, en_ratio, col, ARC_WIDTH, TRACK_ALPHA)


## HEAT: right arc, only while the gatling is hot (brief §2, look review item 5.2). The vent mark is a
## static tick; the needle is where the current heat sits, so the player sees the vent window coming.
func _draw_heat_arc(c: Vector2) -> void:
	if not heat_shown:
		return
	var a0 := deg_to_rad(ARC_SWEEP * 0.5)
	var a1 := deg_to_rad(-ARC_SWEEP * 0.5)
	var col := HudPalette.AMBER
	if overheated:
		col = HudPalette.AMBER if _blink_on(OVERHEAT_BLINK) else HudPalette.DANGER
	HudPalette.draw_gauge(self, c, ARC_RADIUS, a0, a1, heat_ratio, col, ARC_WIDTH, TRACK_ALPHA)
	_draw_needle(c, a0, a1, vent_mark, HudPalette.WHITE, ARC_WIDTH + 6.0)
	_draw_needle(c, a0, a1, vent_needle, HudPalette.DANGER if overheated else HudPalette.WHITE, ARC_WIDTH + 2.0)


func _draw_needle(c: Vector2, a0: float, a1: float, t: float, col: Color, length: float) -> void:
	var a := lerpf(a0, a1, clampf(t, 0.0, 1.0))
	var dir := Vector2(cos(a), sin(a))
	var mid := ARC_RADIUS + ARC_WIDTH * 0.5
	draw_line(c + dir * (mid - length * 0.5), c + dir * (mid + length * 0.5), col, 2.0)


## Rifle: a thin four-arm cross with a clear centre and one charge pip per stage lighting up around it
## (brief §2). The pip ring grows with the charge so the release timing is readable.
func _draw_rifle(c: Vector2, col: Color) -> void:
	var arm := 27.0
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + dir * CROSS_GAP, c + dir * arm, col, 1.5)
	draw_circle(c, 1.6, col)
	if charge <= 0.001:
		return
	var r := arm + 12.0
	draw_arc(c, r, deg_to_rad(-90.0), deg_to_rad(-90.0) + TAU * charge, 40, HudPalette.CYAN, 2.5, true)
	for i in charge_stage:
		var a := deg_to_rad(45.0 + 90.0 * float(i))
		HudPalette.draw_diamond(self, c + Vector2(cos(a), sin(a)) * (r + 9.0), 3.5, HudPalette.WHITE, 0.0, true)


## Gatling: an open circle whose radius is the current cone, plus four ticks on the diagonals.
func _draw_gatling(c: Vector2, col: Color) -> void:
	draw_arc(c, spread, 0.0, TAU, 40, col, 1.5, true)
	draw_circle(c, 1.6, col)
	for i in 4:
		var a := deg_to_rad(45.0 + 90.0 * float(i))
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (spread - 4.0), c + dir * (spread + 4.0), col, 1.5)


## Soft lock: four short corner ticks ON the target, deliberately quieter than the hard-lock diamond
## (markers.gd). Never drawn while a hard lock is up — two brackets for one target reads as two
## targets (look review item 1).
func _draw_soft_lock() -> void:
	if soft_lock_at == Vector2.INF:
		return
	var col := HudPalette.CYAN_DIM
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := soft_lock_at + Vector2(SOFT_RADIUS * sx, SOFT_RADIUS * sy)
			draw_line(corner, corner - Vector2(8.0 * sx, 0.0), col, 1.5)
			draw_line(corner, corner - Vector2(0.0, 8.0 * sy), col, 1.5)
