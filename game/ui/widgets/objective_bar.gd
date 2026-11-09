extends HudWidget
## Objective readout (brief §5, look review item 3): ONE line at top-left, medium weight, ink-outlined,
## over a backing strip that fades out to the right. The text comes from `Events.objective_changed`
## (the flow unit); the spire count is drawn once, as the three diamonds after the line.
##
## It used to be a dim "OBJECTIVE 目标" header, a white line and a second "0 / 3 HIVES 蚀巢" counter,
## all printed straight onto a white-hot sky at about 1.6:1 contrast, saying the same thing twice.

const MARGIN := Vector2(56.0, 46.0)
const STRIP_H := 34.0            ## px tall the backing strip is
const STRIP_FADE := 120.0        ## px over which the strip fades to nothing at its right end
const STRIP_ALPHA := 0.45
const HINT_TIME := 8.0           ## s a hint line stays up before it retires itself

var objective: String = ""
var done: int = 0
var total: int = 3

var _hint: String = ""
var _hint_t: float = 0.0
var _raw: String = ""


func _ready() -> void:
	super()
	# The flow joins its hint onto the objective string with "   ·   "; it gets its own line here and
	# retires after `HINT_TIME` instead of running off the end of the block (item 3.5).
	watch_keys = PackedStringArray(["objective", "spires_done"])


func update_hud(delta: float) -> void:
	_hint_t = maxf(_hint_t - delta, 0.0)
	var raw := data.str_of("objective")
	if raw != _raw:
		_raw = raw
		var parts := _split_hint(raw)
		_hint = _localise(parts[0])
		objective = _localise(parts[1])
		_hint_t = HINT_TIME if _hint != "" else 0.0
	done = int(data.num("spires_done"))
	total = maxi(int(data.num("spires_total", 3.0)), 1)
	visible = data.alive() and (objective != "" or total > 0)


## The flow emits one string with both languages and the count baked in — "摧毁蚀巢 0/3  DESTROY THE
## HIVE SPIRES". The HUD prints one language and shows the count once, as the diamonds after the line
## (items 3.3, 3.4); the flow side can drop its own "%d/%d" whenever it wants, this strips it either way.
func _localise(raw: String) -> String:
	if raw == "":
		return ""
	var parts := raw.split("  ", false)
	var line := parts[0] if (HudLocale.zh() or parts.size() < 2) else parts[parts.size() - 1]
	var re := RegEx.new()
	if re.compile("\\s*\\d+\\s*/\\s*\\d+\\s*") == OK:
		line = re.sub(line, " ")
	return line.strip_edges()


## "摧毁蚀巢   ·   按住冲刺接近" -> ["按住冲刺接近", "摧毁蚀巢"]. The separator is the flow's (see
## `flow/flow_progress.gd`); anything after it is a hint, not part of the objective.
func _split_hint(raw: String) -> Array:
	var at := raw.find("   ·   ")
	if at < 0:
		return ["", raw]
	return [raw.substr(at + 7).strip_edges(), raw.substr(0, at).strip_edges()]


## The block stops short of the compass tape, which starts at x 490 in the 1600 px layout.
const BLOCK_W := 410.0


func block_rect() -> Rect2:
	var h := STRIP_H + (24.0 if _hint_t > 0.0 else 0.0)
	return Rect2(Vector2(MARGIN.x - 8.0, MARGIN.y - STRIP_H + 6.0), Vector2(BLOCK_W + 8.0, h))


func chrome_rect() -> Rect2:
	return block_rect()


func _draw() -> void:
	var r := block_rect()
	_draw_strip(r)
	var base := Vector2(MARGIN.x, MARGIN.y)
	var after := base.x
	if objective != "":
		text(base, objective, HudPalette.SIZE_BODY, HudPalette.WHITE,
				HORIZONTAL_ALIGNMENT_LEFT, BLOCK_W - 80.0)
		after += minf(text_w(objective, HudPalette.SIZE_BODY), BLOCK_W - 80.0)
	# The count appears ONCE, as the diamonds after the line (item 3.4), placed off the text width so a
	# short objective does not leave them floating and a long one does not push them onto the compass.
	for i in total:
		var c := Vector2(after + 18.0 + float(i) * 18.0, base.y - 5.0)
		HudPalette.draw_diamond(self, c, 5.5, HudPalette.GOLD if i < done else HudPalette.TEXT_DIM,
				1.5, i < done)
	if _hint_t > 0.0 and _hint != "":
		var col := HudPalette.TEXT_DIM
		col.a = clampf(_hint_t / 1.5, 0.0, 1.0)
		text(base + Vector2(0.0, 24.0), _hint, HudPalette.SIZE_SMALL, col,
				HORIZONTAL_ALIGNMENT_LEFT, BLOCK_W)


## A dark strip under the text, solid behind the words and fading to nothing at its right end, so the
## line reads on a white sky without drawing a box (item 3.2).
func _draw_strip(r: Rect2) -> void:
	var solid := r.size.x - STRIP_FADE
	draw_rect(Rect2(r.position, Vector2(solid, r.size.y)), HudPalette.panel_fill(STRIP_ALPHA), true)
	var steps := 8
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var a := STRIP_ALPHA * (1.0 - t0) * (1.0 - t0)
		draw_rect(Rect2(Vector2(r.position.x + solid + STRIP_FADE * t0, r.position.y),
				Vector2(STRIP_FADE * (t1 - t0) + 1.0, r.size.y)), HudPalette.panel_fill(a), true)
