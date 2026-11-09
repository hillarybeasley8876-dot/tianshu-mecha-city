extends HudWidget
## Combat callouts (brief §6): the four big words that name a payoff the instant it happens — PERFECT
## (dodge inside the i-frames), PARRY (Mirror Guard), JACKPOT (an execution window opened) and COLLAPSE
## (an Undertow prime detonated). Brief, centred and low, so they never fight the reticle.

const LIFE := 0.9
const POP_TIME := 0.16
const CENTER_DROP := 260.0        ## px above the bottom edge

const TEXTS: Dictionary = {
	&"perfect": ["PERFECT", "完美闪避", Color("3effb0")],
	&"parry": ["PARRY", "镜返", Color("4fe6ff")],
	&"jackpot": ["JACKPOT", "处决", Color("f2a33a")],
	&"collapse": ["COLLAPSE", "引井崩塌", Color("b04cff")],
}

var current: StringName = &""
var age: float = 0.0

var _was_jackpot: bool = false
var _was_primed: bool = false


func _ready() -> void:
	super()
	Events.perfect_dodge.connect(func(_a: Node) -> void: say(&"perfect"))
	Events.parry_success.connect(func(_h: HitInfo, _a: Node) -> void: say(&"parry"))


## Shows `id` immediately, replacing whatever was on screen — the newest payoff wins.
func say(id: StringName) -> void:
	if not TEXTS.has(id):
		return
	current = id
	age = 0.0
	visible = true


func update_hud(delta: float) -> void:
	_watch_edges()
	if current == &"":
		visible = false
		return
	age += delta
	visible = age < LIFE and data.alive()
	if not visible:
		current = &""


## JACKPOT and COLLAPSE have no Events signal yet (see status/hud.md → Requests), so they are read off
## the edges of the melee and Undertow hud_state() flags.
func _watch_edges() -> void:
	var jackpot := data.flag("jackpot")
	if jackpot and not _was_jackpot:
		say(&"jackpot")
	_was_jackpot = jackpot
	var primed := data.flag("well_primed")
	if _was_primed and not primed:
		say(&"collapse")
	_was_primed = primed


func center_point() -> Vector2:
	var s := screen_size()
	return Vector2(s.x * 0.5, s.y - CENTER_DROP)


## One word, one language (look review item 8.4): the payoff callout used to print "PARRY" with "镜返"
## under it. The rule line and the colour stay; the second language goes.
func _draw() -> void:
	if current == &"":
		return
	var row: Array = TEXTS[current]
	var t := clampf(age / LIFE, 0.0, 1.0)
	var pop := 1.0 + 0.5 * (1.0 - clampf(age / POP_TIME, 0.0, 1.0))
	var col := row[2] as Color
	col.a = 1.0 if t < 0.7 else 1.0 - (t - 0.7) / 0.3
	var c := center_point()
	var size := int(round(float(HudPalette.SIZE_HUGE) * pop))
	var word := HudLocale.pick(String(row[1]), String(row[0]))
	var w := text_w(word, size)
	centered(c - Vector2(0.0, 8.0 * pop), word, size, col)
	draw_line(c + Vector2(-w * 0.6, 16.0), c + Vector2(w * 0.6, 16.0),
			Color(col.r, col.g, col.b, col.a * 0.6), 1.5)
