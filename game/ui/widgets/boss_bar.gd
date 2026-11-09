extends HudWidget
## Boss bar (brief §5): the Brood Titan's plate under the compass. Its HP is split into one segment per
## exposed core so the player can see which cores are still alive, with the phase shown as pips.
##
## The boss unit does not publish a hud_state() yet, so the data comes from `HudData.set_boss()`
## (driven by `Events.boss_phase` and, until then, by the flow unit or a test).

const WIDTH := 760.0
const HEIGHT := 52.0
const TOP := 96.0
const SEG_GAP := 4.0

var boss_name: String = "巢母 BROOD TITAN"
var ratio: float = 1.0
var cores: PackedFloat32Array = PackedFloat32Array()
var phase: int = 1
var phases: int = 3
var stagger: float = 1.0


func _ready() -> void:
	super()
	Events.boss_phase.connect(_on_phase)


func _on_phase(p: int) -> void:
	phase = maxi(p, 1)


func bar_rect() -> Rect2:
	var s := screen_size()
	return Rect2(Vector2((s.x - WIDTH) * 0.5, TOP), Vector2(WIDTH, HEIGHT))


func chrome_rect() -> Rect2:
	return bar_rect()


func update_hud(_delta: float) -> void:
	var b: Variant = data.state.get("boss")
	visible = data.alive() and b is Dictionary and not (b as Dictionary).is_empty()
	if not visible:
		return
	var d := b as Dictionary
	boss_name = String(d.get("name", boss_name))
	ratio = clampf(float(d.get("hp", 1.0)) / maxf(float(d.get("hp_max", 1.0)), 1.0), 0.0, 1.0)
	phase = maxi(int(d.get("phase", phase)), 1)
	phases = maxi(int(d.get("phases", phases)), 1)
	stagger = clampf(float(d.get("stability", 1.0)) / maxf(float(d.get("stability_max", 1.0)), 1.0), 0.0, 1.0)
	cores = PackedFloat32Array()
	var raw: Variant = d.get("cores", [])
	if raw is Array or raw is PackedFloat32Array:
		for c: Variant in raw:
			cores.append(clampf(float(c), 0.0, 1.0))


func _draw() -> void:
	var r := bar_rect()
	HudPalette.draw_panel(self, r, 0.5)
	HudPalette.draw_brackets(self, r, HudPalette.VIOLET, 14.0, 1.5)
	text(r.position + Vector2(14.0, 20.0), boss_name, HudPalette.SIZE_BODY, HudPalette.WHITE)
	text(r.position + Vector2(14.0, 20.0), "PHASE %d" % phase, HudPalette.SIZE_SMALL,
			HudPalette.VIOLET, HORIZONTAL_ALIGNMENT_RIGHT, WIDTH - 28.0)
	_draw_cores(r)
	_draw_stability(r)


## One bar per exposed core; a core at 0 is drawn hollow, which is the "kill this one next" signal.
func _draw_cores(r: Rect2) -> void:
	var n := maxi(cores.size(), 1)
	var w := (WIDTH - 24.0 - SEG_GAP * float(n - 1)) / float(n)
	for i in n:
		var seg := Rect2(r.position + Vector2(12.0 + float(i) * (w + SEG_GAP), 28.0), Vector2(w, 8.0))
		var fill := cores[i] if i < cores.size() else ratio
		HudPalette.draw_bar(self, seg, fill, HudPalette.DANGER if fill > 0.0 else HudPalette.TRACK)
		if fill <= 0.0:
			HudPalette.draw_brackets(self, seg, HudPalette.TEXT_DIM, 4.0, 1.0)


func _draw_stability(r: Rect2) -> void:
	var track := Rect2(r.position + Vector2(12.0, 41.0), Vector2(WIDTH - 24.0, 4.0))
	HudPalette.draw_bar(self, track, 1.0 - stagger, HudPalette.AMBER)
