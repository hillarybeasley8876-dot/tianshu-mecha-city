extends HudWidget
## Style meter (brief §6, juice-impact §8): a D→SSS rank on the right edge with the live combo count.
## The rules are the dossier's "mech version": points per landed hit, a repeat of one of the last four
## moves earns 35 %, taking damage drops two ranks, and the gauge drains faster the higher you are
## (3.0 s per rank at D down to 1.2 s at SSS).

const RANKS: PackedStringArray = ["D", "C", "B", "A", "S", "SS", "SSS"]
const RANK_COLORS: PackedColorArray = [
	Color("b9c2cc"), Color("e9edf2"), Color("3effb0"), Color("4fe6ff"),
	Color("f2a33a"), Color("ff8a2b"), Color("ff4d5a"),
]
const POINTS_PER_RANK := 100.0
const DECAY_SLOW := 3.0          ## s to lose one rank at D
const DECAY_FAST := 1.2          ## s to lose one rank at SSS
const REPEAT_VALUE := 0.35       ## juice §8: a repeat of a recent move earns 35 %
const VARIETY_WINDOW := 4        ## moves remembered for the variety check
const DAMAGE_DROP := 2           ## ranks lost when the player is hit
const IDLE_RESET := 1.5          ## s of nothing at all before the combo count restarts (DMC1, juice §8)

const WIDTH := 78.0
const HEIGHT := 210.0
const MARGIN := Vector2(44.0, 0.0)

var points: float = 0.0
var count: int = 0
var rank: int = 0

var _recent: Array[StringName] = []
var _idle: float = 0.0
var _pop: float = 0.0


func _ready() -> void:
	super()
	Events.hit_landed.connect(_on_hit)
	Events.skill_used.connect(func(id: StringName) -> void: credit(30.0, id))
	Events.melee_swing.connect(func(_m: StringName, _s: int) -> void: credit(18.0, &"melee"))
	Events.player_damaged.connect(_on_damaged)
	Events.parry_success.connect(func(_h: HitInfo, _a: Node) -> void: credit(60.0, &"parry"))
	Events.perfect_dodge.connect(func(_a: Node) -> void: credit(60.0, &"dodge"))


func _on_hit(hit: HitInfo, receiver: Node) -> void:
	var p := Game.player
	if hit == null or p == null or receiver == p or hit.source == null:
		return
	if not (hit.source == p or p.is_ancestor_of(hit.source)):
		return
	credit(clampf(hit.final_amount * 0.08, 4.0, 40.0), hit.weapon)


func _on_damaged(_hit: HitInfo) -> void:
	points = maxf(points - POINTS_PER_RANK * float(DAMAGE_DROP), 0.0)
	count = 0
	_recent.clear()
	_pop = 0.0


## Adds points for one move; a move seen in the last four earns REPEAT_VALUE of its worth.
func credit(amount: float, move: StringName) -> void:
	var worth := amount * (REPEAT_VALUE if move in _recent else 1.0)
	_recent.append(move)
	if _recent.size() > VARIETY_WINDOW:
		_recent.pop_front()
	var before := rank
	points += worth
	count += 1
	_idle = 0.0
	rank = clampi(int(points / POINTS_PER_RANK), 0, RANKS.size() - 1)
	if rank > before:
		_pop = 0.3


func rank_name() -> String:
	return RANKS[rank]


## Points lost per second at the current rank.
func decay_rate() -> float:
	var t := float(rank) / float(RANKS.size() - 1)
	return POINTS_PER_RANK / lerpf(DECAY_SLOW, DECAY_FAST, t)


func update_hud(delta: float) -> void:
	_idle += delta
	_pop = maxf(_pop - delta, 0.0)
	if _idle >= IDLE_RESET and count > 0:
		count = 0
		_recent.clear()
	points = maxf(points - decay_rate() * delta, 0.0)
	rank = clampi(int(points / POINTS_PER_RANK), 0, RANKS.size() - 1)
	# At rank D the meter is a "D" over the sky telling you nothing: it only appears once the player
	# has actually started a combo (look review item 9.2).
	visible = data.alive() and rank > 0 and points > 0.5


func bar_rect() -> Rect2:
	var s := screen_size()
	return Rect2(Vector2(s.x - MARGIN.x - WIDTH, (s.y - HEIGHT) * 0.5), Vector2(WIDTH, HEIGHT))


func _draw() -> void:
	var r := bar_rect()
	var col := RANK_COLORS[rank]
	var within := fposmod(points, POINTS_PER_RANK) / POINTS_PER_RANK
	var track := Rect2(Vector2(r.end.x - 6.0, r.position.y), Vector2(4.0, HEIGHT))
	HudPalette.draw_bar(self, Rect2(track.position, Vector2(track.size.x, track.size.y)), 0.0,
			HudPalette.TRACK)
	var h := track.size.y * within
	draw_rect(Rect2(Vector2(track.position.x, track.end.y - h), Vector2(track.size.x, h)), col, true)
	# A dark plate behind the rank: the meter sits over open sky as often as over a building.
	var scale := 1.0 + 0.35 * (_pop / 0.3)
	var size := int(round(float(HudPalette.SIZE_HUGE) * scale))
	var at := Vector2(r.position.x + 26.0, r.end.y - 46.0)
	draw_rect(Rect2(at - Vector2(38.0, float(size)), Vector2(76.0, float(size) + 12.0)),
			HudPalette.panel_fill(0.45), true)
	centered(at, rank_name(), size, col)
	if count > 1:
		centered(Vector2(r.position.x + 26.0, r.end.y - 18.0), "%d HITS" % count,
				HudPalette.SIZE_SMALL, HudPalette.WHITE, true)
