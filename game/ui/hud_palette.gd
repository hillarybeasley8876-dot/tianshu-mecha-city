class_name HudPalette
extends RefCounted
## HUD colours, fonts and the handful of primitives every widget draws with (ART.md §2 palette,
## brief §10). Everything the HUD puts on screen goes through here so the whole overlay stays one
## visual language: thin lines, angular brackets, translucent dark panels, cyan primary.

const FONT_PATH := "res://ui/fonts/NotoSansSC-Regular.otf"
const DISPLAY_PATH := "res://ui/fonts/Rajdhani-SemiBold.ttf"

# --- palette (sRGB, ART.md §2) ---------------------------------------------------------------------
# One colour, one meaning (look review item 6). Before this table green meant both "objective" and
# "Ripper", and red meant both "in range" and "unblockable", so the overlay fought itself and the
# monsters' own acid-green glow swallowed the HUD green.
#   CYAN   — you and your systems (reticle, EN, kit, own gauges)
#   GOLD   — objectives and navigation (compass tag, radar spire, waypoints)
#   DANGER — the enemy (blips, plate HP, unblockable windups, damage)
#   AMBER  — warnings only (empty, low, overheat, busy)
#   VIOLET — primed, marks, the boss
#   WHITE  — neutral readout (out-of-range reticle, ammo, distances)
const CYAN := Color("4fe6ff")            ## hero primary: self and systems
const CYAN_DIM := Color("4fe6ff", 0.45)
const AMBER := Color("f2a33a")           ## warnings only
const DANGER := Color("ff4d5a")          ## hostile: enemies, damage, unblockable
const GOLD := Color("ffd36b")            ## objective and navigation
const VIOLET := Color("b04cff")          ## primed / marks / boss
const WHITE := Color("e9edf2")           ## neutral readout
const INK := Color("0b1220")             ## panel fill and type outline
const PANEL_ALPHA := 0.55
const TRACK := Color("1c2633")           ## unfilled gauge track
const TEXT_DIM := Color("e9edf2", 0.8)   ## was 0.55: dim captions vanished on a sunlit sky (item 8)

# --- type -----------------------------------------------------------------------------------------
## Sizes are VIRTUAL pixels in a 1600×900 layout (lead r1 MUST-FIX 1: nothing readable below 14 px).
## `ui_scale` multiplies them — and the whole overlay geometry — with the window height and the
## `hud_scale` setting, so the same layout is legible at 1280×720 and at 2560×1440.
const MIN_LABEL := 14             ## px, the smallest type the HUD is allowed to set
const SIZE_TINY := 14
const SIZE_SMALL := 16
const SIZE_BODY := 19             ## objective lines, prompt text
const SIZE_NUM := 20              ## damage numbers, ammo, distances
const SIZE_HEAD := 22
const SIZE_HUGE := 44
const OUTLINE_PX := 3            ## ink ring round labels drawn straight over the scene

static var _font: Font = null
static var _display: Font = null
## 1.0 at 1600×900 with `hud_scale` at 1.0. Set once a frame by `hud.gd` (and by the canopy HUD).
static var ui_scale: float = 1.0
## 1.0 normally, 0.0 with Settings `photosensitive`: every pulse, blink and pop in the HUD collapses
## to a steady value (lead notes, critic #12) — information stays, motion goes.
static var motion: float = 1.0


## The overlay draws into a layout scaled by `ui_scale`, so this returns the size to pass to
## `draw_string` such that the type lands at `base`×scale device px and NEVER below 14 device px
## (lead r1 MUST-FIX 1) — including when the player turns `hud_scale` down.
static func fs(base: int) -> int:
	return maxi(base, int(ceil(float(MIN_LABEL) / maxf(ui_scale, 0.05))))


## A 0..1 pulse amplitude: `t` is the raw oscillation, this returns the motion-scaled version.
static func pulse(t: float) -> float:
	return 0.5 + 0.5 * t * motion


## The Chinese-capable face: Noto Sans CJK SC (SIL OFL, see ui/licenses/OFL-NotoSansSC.txt).
static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH) as Font
		if _font == null:
			push_error("HudPalette: font missing at %s, falling back to the default theme font" % FONT_PATH)
	return _font


## The face the HUD actually draws in (look review item 8.3): Rajdhani SemiBold (SIL OFL, see
## ui/licenses/OFL-Rajdhani.txt), a condensed Latin face with narrow even digits — what ammo, distances
## and armour need to stay legible over a sunlit city. Noto Sans SC is registered as its fallback, so a
## mixed "312 m 蚀巢" string still renders in one pass.
static func display_font() -> Font:
	if _display == null:
		var f := load(DISPLAY_PATH) as FontFile
		if f == null:
			push_error("HudPalette: display font missing at %s, using the CJK face" % DISPLAY_PATH)
			return font()
		var fallbacks: Array[Font] = []
		var cjk := font()
		if cjk != null:
			fallbacks.append(cjk)
		f.fallbacks = fallbacks
		_display = f
	return _display


## Resolves the font to something drawable even when the file failed to load.
static func font_or(theme_font: Font) -> Font:
	var f := display_font()
	if f != null:
		return f
	f = font()
	return f if f != null else theme_font


static func panel_fill(alpha: float = PANEL_ALPHA) -> Color:
	return Color(INK.r, INK.g, INK.b, alpha)

# --- primitives -----------------------------------------------------------------------------------

## Translucent dark plate with a one-pixel cyan rule along its top edge (brief §10).
static func draw_panel(ci: CanvasItem, rect: Rect2, alpha: float = PANEL_ALPHA,
		rule: Color = CYAN_DIM) -> void:
	ci.draw_rect(rect, panel_fill(alpha), true)
	if rule.a > 0.0:
		ci.draw_line(rect.position, rect.position + Vector2(rect.size.x, 0.0), rule, 1.0)


## Four angular corner brackets around `rect`, `len` px per arm — the HUD's signature frame.
static func draw_brackets(ci: CanvasItem, rect: Rect2, col: Color, len: float = 10.0,
		width: float = 1.5) -> void:
	var a := rect.position
	var b := rect.end
	ci.draw_line(a, a + Vector2(len, 0.0), col, width)
	ci.draw_line(a, a + Vector2(0.0, len), col, width)
	ci.draw_line(Vector2(b.x, a.y), Vector2(b.x - len, a.y), col, width)
	ci.draw_line(Vector2(b.x, a.y), Vector2(b.x, a.y + len), col, width)
	ci.draw_line(Vector2(a.x, b.y), Vector2(a.x + len, b.y), col, width)
	ci.draw_line(Vector2(a.x, b.y), Vector2(a.x, b.y - len), col, width)
	ci.draw_line(b, b - Vector2(len, 0.0), col, width)
	ci.draw_line(b, b - Vector2(0.0, len), col, width)


static func draw_diamond(ci: CanvasItem, center: Vector2, r: float, col: Color,
		width: float = 1.5, filled: bool = false) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0.0, -r), center + Vector2(r, 0.0),
		center + Vector2(0.0, r), center + Vector2(-r, 0.0),
	])
	if filled:
		ci.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, col, width, true)


## Flat-top hexagon outline, the 48 px skill-slot frame from skills-catalog §4.9.
static func draw_hex(ci: CanvasItem, center: Vector2, r: float, col: Color,
		width: float = 1.5, filled: bool = false) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * float(i) - 90.0)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	if filled:
		ci.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, col, width, true)


## Horizontal gauge: dark track, then `fill` (0..1) of it in `col`.
static func draw_bar(ci: CanvasItem, rect: Rect2, fill: float, col: Color,
		track: Color = TRACK) -> void:
	ci.draw_rect(rect, Color(track.r, track.g, track.b, 0.75), true)
	var w := rect.size.x * clampf(fill, 0.0, 1.0)
	if w > 0.0:
		ci.draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), col, true)


## Gauge arc; angles in radians, counter-clockwise from +X as Godot's draw_arc expects. `track_a` is
## how loudly the empty part of the gauge reads: the reticle's EN/heat arcs sit on a bright sky, where
## a heavy dark track looked like a solid bar (look review item 5).
static func draw_gauge(ci: CanvasItem, center: Vector2, radius: float, a0: float, a1: float,
		fill: float, col: Color, width: float = 6.0, track_a: float = 0.8) -> void:
	ci.draw_arc(center, radius, a0, a1, 48, Color(TRACK.r, TRACK.g, TRACK.b, track_a), width, true)
	var end := lerpf(a0, a1, clampf(fill, 0.0, 1.0))
	if absf(end - a0) > 0.002:
		ci.draw_arc(center, radius, a0, end, 40, col, width, true)


## One line of text with the HUD font; `pos` is the baseline-left (or baseline-centre/right).
## The size always goes through `fs()` so no label can fall under the 14 px readability floor.
## The 3 px ink outline is ON by default (look review item 8.1): the HUD is drawn straight over a city
## that runs from white-hot sky to black shadow, and unoutlined type measured about 1.6:1 against the
## sky. Pass `outline = false` only for type sitting inside an opaque panel, where the ring is mud.
## `shadow` adds a 1 px dark copy underneath, for floating readouts that move over the world.
static func draw_text(ci: CanvasItem, theme_font: Font, pos: Vector2, text: String, size: int,
		col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0,
		shadow: bool = false, outline: bool = true) -> void:
	var f := font_or(theme_font)
	var fs_size := fs(size)
	if outline:
		ci.draw_string_outline(f, pos, text, align, width, fs_size, OUTLINE_PX,
				Color(INK.r, INK.g, INK.b, col.a * 0.9))
	if shadow:
		ci.draw_string(f, pos + Vector2(1.0, 1.0), text, align, width, fs_size,
				Color(INK.r, INK.g, INK.b, col.a * 0.85))
	ci.draw_string(f, pos, text, align, width, fs_size, col)


## Width in px the given string will take — used to centre labels without a Label node.
static func text_width(theme_font: Font, text: String, size: int) -> float:
	var f := font_or(theme_font)
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs(size)).x

# --- accessibility shapes (lead notes, critic #12: never colour alone) -----------------------------

## Red triangle with a bang: the ONE shape that means "unblockable, get out" (critic #12).
static func draw_warning_triangle(ci: CanvasItem, center: Vector2, r: float, col: Color,
		width: float = 2.0) -> void:
	var pts := PackedVector2Array([center + Vector2(0.0, -r), center + Vector2(r * 0.92, r * 0.7),
			center + Vector2(-r * 0.92, r * 0.7), center + Vector2(0.0, -r)])
	ci.draw_polyline(pts, col, width, true)
	var stem := center + Vector2(0.0, -r * 0.28)
	ci.draw_line(stem, center + Vector2(0.0, r * 0.18), col, width)
	ci.draw_circle(center + Vector2(0.0, r * 0.45), width * 0.6, col)


## White glint diamond: a parryable tell. The inner tick is the "glint" and it scales with `motion`,
## so with photosensitive mode on it sits still at half brightness instead of twinkling.
static func draw_glint_diamond(ci: CanvasItem, center: Vector2, r: float, col: Color,
		t: float = 0.0) -> void:
	draw_diamond(ci, center, r, col, 1.8)
	var g := 0.45 + 0.55 * pulse(sin(t))
	var inner := col
	inner.a *= g
	ci.draw_line(center + Vector2(-r * 0.4, 0.0), center + Vector2(r * 0.4, 0.0), inner, 1.5)
	ci.draw_line(center + Vector2(0.0, -r * 0.4), center + Vector2(0.0, r * 0.4), inner, 1.5)


## Violet ring around a weak point (critic #12): a ring is a shape no other marker in the HUD uses.
static func draw_weak_ring(ci: CanvasItem, center: Vector2, r: float, col: Color,
		width: float = 2.0) -> void:
	ci.draw_arc(center, r, 0.0, TAU, 28, col, width, true)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(center + d * (r - 3.0), center + d * (r + 3.0), col, width)


## Height chevron for the compass and the radar: `up` true draws ▲, false ▼ (vertical wayfinding).
static func draw_chevron(ci: CanvasItem, center: Vector2, size: float, up: bool, col: Color) -> void:
	var s := 1.0 if up else -1.0
	ci.draw_colored_polygon(PackedVector2Array([center + Vector2(0.0, -size * s),
			center + Vector2(size, size * 0.6 * s), center + Vector2(-size, size * 0.6 * s)]), col)


## "Your shot is stopped by scenery": a hatched barrier plate the reticle dims behind.
static func draw_barrier_icon(ci: CanvasItem, center: Vector2, size: float, col: Color) -> void:
	var r := Rect2(center - Vector2(size, size * 0.7), Vector2(size * 2.0, size * 1.4))
	ci.draw_rect(r, Color(col.r, col.g, col.b, col.a * 0.25), true)
	ci.draw_rect(r, col, false, 1.5)
	for i in 3:
		var x := r.position.x + r.size.x * (float(i) + 1.0) / 4.0
		ci.draw_line(Vector2(x - 3.0, r.end.y - 1.0), Vector2(x + 3.0, r.position.y + 1.0), col, 1.5)
