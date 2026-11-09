extends HudWidget
## Hit markers (brief §2, juice-impact §8): the confirmation that a shot connected. White X for a
## normal hit, amber for a weak point / crit, red plus an expanding ring for a kill, cyan for a
## stagger. 80 ms for the ordinary case so it reads as a tick, not a decoration.

const NORMAL_TIME := 0.08        ## s, juice §8 "white X, 80 ms"
const SPECIAL_TIME := 0.25       ## s, kill / stagger stay long enough to notice
const POP_TIME := 0.25           ## s the scale pop takes (brief §2)
const POP_SCALE := 1.6
const ARM := 13.0                ## px from the centre to the tip of each stroke
const KILL_ARM := 17.0

var kind: StringName = &""
var left: float = 0.0            ## s remaining; <= 0 = nothing on screen
var total: float = NORMAL_TIME

var _age: float = 0.0


func _ready() -> void:
	super()
	Events.hit_landed.connect(_on_hit)
	Events.enemy_killed.connect(_on_kill)
	Events.enemy_staggered.connect(_on_stagger)


## Player-sourced hits only: an enemy hitting another enemy must not light the player's reticle.
func _from_player(hit: HitInfo) -> bool:
	if hit == null:
		return false
	var p := Game.player
	return p != null and hit.source != null and (hit.source == p or p.is_ancestor_of(hit.source))


func _on_hit(hit: HitInfo, receiver: Node) -> void:
	if not _from_player(hit) or receiver == Game.player:
		return
	if hit.finisher:
		return
	flash(&"weak" if (hit.weak_point or hit.crit) else &"normal")


func _on_kill(_enemy: Node, hit: HitInfo) -> void:
	if _from_player(hit):
		flash(&"kill")


func _on_stagger(_enemy: Node, hit: HitInfo) -> void:
	if _from_player(hit):
		flash(&"stagger")


## Tests, tools and scripted beats can drive the marker directly.
func flash(k: StringName) -> void:
	kind = k
	total = NORMAL_TIME if k == &"normal" else SPECIAL_TIME
	left = total
	_age = 0.0
	visible = true
	queue_redraw()


func update_hud(delta: float) -> void:
	if left <= 0.0:
		visible = false
		return
	left -= delta
	_age += delta
	visible = true
	if left <= 0.0:
		visible = false


## 1.0 at the start of the pop, easing to POP_SCALE then settling — juice §8's "pop then relax".
func scale_factor() -> float:
	var t := clampf(_age / POP_TIME, 0.0, 1.0)
	return lerpf(POP_SCALE, 1.0, t * t * (3.0 - 2.0 * t))


func color() -> Color:
	match kind:
		&"weak": return HudPalette.AMBER
		&"kill": return HudPalette.DANGER
		&"stagger": return HudPalette.CYAN
		_: return HudPalette.WHITE


func _draw() -> void:
	var c := screen_center()
	var s := scale_factor()
	var col := color()
	col.a = clampf(left / minf(total, POP_TIME), 0.0, 1.0)
	match kind:
		&"weak":
			# A weak point is a SHAPE, not a colour: an amber diamond ring around the impact (critic #12).
			HudPalette.draw_weak_ring(self, c, (ARM + 4.0) * s, col, 2.2 * s)
			draw_circle(c, 2.0 * s, col)
		&"kill":
			_draw_cross(c, KILL_ARM * s, 5.0 * s, 4.0 * s, col)
			var t := 1.0 - clampf(left / total, 0.0, 1.0)
			draw_arc(c, lerpf(6.0, 34.0, t), 0.0, TAU, 32,
					Color(col.r, col.g, col.b, col.a * (1.0 - t)), 2.0, true)
		&"stagger":
			_draw_cross(c, ARM * s, 5.0 * s, 4.0 * s, col)
			HudPalette.draw_brackets(self, Rect2(c - Vector2(ARM, ARM) * 1.5 * s,
					Vector2(ARM, ARM) * 3.0 * s), col, 6.0 * s, 2.0)
		_:
			_draw_cross(c, ARM * s, 5.0 * s, 4.0 * s, col)


## The plain confirmation: four thin diagonal strokes with a clear centre.
func _draw_cross(c: Vector2, arm: float, gap: float, width: float, col: Color) -> void:
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var dir := d.normalized()
		draw_line(c + dir * gap, c + dir * arm, col, width)
