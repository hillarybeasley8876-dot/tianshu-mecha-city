extends HudWidget
## Target markers (brief §3): the hard-lock diamond with its range readout, the 24°×16° missile paint
## box with one lock diamond per painted target and the "n/12" counter, and the off-screen threat
## arrows that point at enemies currently winding up an attack (red when it is unblockable).

const PAINT_H_DEG := 16.0            ## SPEC §5 missile paint box, vertical
const PAINT_W_DEG := 24.0            ## ... and horizontal
const PAINT_MIN := 150.0             ## px, so the box stays visible at a wide FOV
const LOCK_ARM := 14.0               ## px half-size of the hard-lock diamond
const LOCK_BOX := 2.6                ## × LOCK_ARM, so diamond and box read as one mark
const NEAR_PX := 90.0                ## px from the crosshair where the reticle takes the range over
const ARROW_RADIUS := 268.0          ## px from the centre the threat arrows orbit at
const RING_RADIUS := 72.0            ## px — on-screen attackers are flagged on a ring at the reticle
const THREAT_TIME := 1.6             ## s an arrow lives after the telegraph it came from
const MAX_LOCK_DIAMONDS := 12
## An attacker this far from the middle of the screen still needs a cue you cannot miss (item 2.3).
const CENTRE_FRACTION := 0.4

## enemy instance id -> {"left": s, "unblockable": bool, "parryable": bool}
var threats: Dictionary = {}
var lock_count: int = 0
var lock_max: int = 12
var painting: bool = false

var _box: Rect2 = Rect2()


func _ready() -> void:
	super()
	Events.enemy_telegraph.connect(_on_telegraph)


func _on_telegraph(enemy: Node, _attack: StringName, kind: StringName) -> void:
	var id := enemy.get_instance_id() if enemy != null else 0
	if id == 0:
		return
	threats[id] = {"left": THREAT_TIME, "node": enemy,
			"unblockable": kind == &"unblockable", "parryable": kind == &"parryable"}


## The threat arrow lives as long as the attack it warns about, so it runs on the world clock
## (audit #3): a hit-stop must not make the warning outlast the swing.
func world_clock() -> bool:
	return true


func update_hud(delta: float) -> void:
	for id: int in threats.keys():
		var t: Dictionary = threats[id]
		t["left"] = float(t["left"]) - delta
		if float(t["left"]) <= 0.0 or not is_instance_valid(t["node"]):
			threats.erase(id)
	lock_count = int(data.num("missile_locks"))
	lock_max = maxi(int(data.num("missile_locks_max", MAX_LOCK_DIAMONDS)), 1)
	painting = data.flag("missile_painting")
	_box = _paint_rect()
	var hard := data.node("hard_target")
	visible = data.alive() and (hard != null or painting or not threats.is_empty())


## Screen-space rect of the paint box, derived from the camera FOV so it matches the aim system's cone.
func _paint_rect() -> Rect2:
	var s := screen_size()
	if data.camera == null:
		var w := s.x * PAINT_W_DEG / 90.0
		var h := s.y * PAINT_H_DEG / 62.0
		return Rect2(s * 0.5 - Vector2(w, h) * 0.5, Vector2(w, h))
	var vfov := data.camera.fov
	var aspect := s.x / maxf(s.y, 1.0)
	var hfov := rad_to_deg(2.0 * atan(tan(deg_to_rad(vfov) * 0.5) * aspect))
	var h := maxf(s.y * PAINT_H_DEG / maxf(vfov, 1.0), PAINT_MIN)
	var w := maxf(s.x * PAINT_W_DEG / maxf(hfov, 1.0), PAINT_MIN)
	return Rect2(s * 0.5 - Vector2(w, h) * 0.5, Vector2(w, h))


func _draw() -> void:
	_draw_hard_lock()
	if painting:
		_draw_paint_box()
	_draw_threats()


## One lock mark per target: a diamond with a bracket box tight enough that they read as one glyph,
## not as a second target next to the reticle (look review item 1). Inside `NEAR_PX` of the crosshair
## the reticle prints the range instead, so nothing lands on the gauges.
func _draw_hard_lock() -> void:
	var t := data.node("hard_target")
	if t == null:
		return
	var p := data.project(t.global_position)
	if not bool(p["visible"]):
		return
	var at := p["pos"] as Vector2
	var col := HudPalette.CYAN
	var box := LOCK_ARM * LOCK_BOX
	HudPalette.draw_diamond(self, at, LOCK_ARM, col, 1.5)
	HudPalette.draw_brackets(self, Rect2(at - Vector2(box, box), Vector2(box, box) * 2.0),
			Color(col.r, col.g, col.b, 0.5), 7.0, 1.0)
	if at.distance_to(screen_center()) <= NEAR_PX:
		return
	centered(at + Vector2(0.0, box + 16.0), "%d m" % int(round(float(p["dist"]))),
			HudPalette.SIZE_NUM, col, true)


func _draw_paint_box() -> void:
	var col := HudPalette.AMBER if lock_count == 0 else HudPalette.DANGER
	HudPalette.draw_brackets(self, _box, col, 18.0, 1.5)
	for i in mini(lock_count, MAX_LOCK_DIAMONDS):
		var a := TAU * float(i) / float(MAX_LOCK_DIAMONDS) - PI * 0.5
		var r := _box.size * 0.42
		HudPalette.draw_diamond(self, _box.get_center() + Vector2(cos(a) * r.x, sin(a) * r.y),
				4.0, HudPalette.CYAN, 0.0, true)
	var label := "%d/%d" % [lock_count, lock_max]
	centered(Vector2(_box.get_center().x, _box.end.y + 24.0), label, HudPalette.SIZE_NUM, HudPalette.WHITE, true)


## A windup the player cannot miss (look review item 2.3): every unblockable and ranged attacker gets a
## small tell on a 72 px ring hugging the reticle, pointing at it. An attacker off screen keeps the big
## orbiting arrow at the screen edge. The shape carries the same meaning as `telegraphs.gd` —
## unblockable is a triangle with a bang, parryable a glint diamond, anything else a chevron — so
## colour is never the only channel (critic #12).
func _draw_threats() -> void:
	var c := screen_center()
	var s := screen_size()
	for id: int in threats:
		var t: Dictionary = threats[id]
		var n := t["node"] as Node3D
		if not is_instance_valid(n):
			continue
		var p := data.project(n.global_position)
		var on_screen := bool(p["visible"])
		var off := (p["pos"] as Vector2) - c
		if on_screen and absf(off.x) <= s.x * 0.2 and absf(off.y) <= s.y * 0.2:
			continue
		var dir := data.screen_direction(n.global_position) if not on_screen else off.normalized()
		var at := c + dir * (RING_RADIUS if on_screen else ARROW_RADIUS)
		var fade := clampf(float(t["left"]) / 0.4, 0.0, 1.0)
		var col := HudPalette.AMBER
		if bool(t["unblockable"]):
			col = HudPalette.DANGER
		elif bool(t["parryable"]):
			col = HudPalette.WHITE
		col.a = fade
		var r := 12.0 if on_screen else 15.0
		if bool(t["unblockable"]):
			HudPalette.draw_warning_triangle(self, at, r, col, 2.2)
		elif bool(t["parryable"]):
			HudPalette.draw_glint_diamond(self, at, r * 0.86, col)
		else:
			var perp := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([at + dir * r, at - dir * r * 0.6 + perp * r * 0.6,
					at - dir * r * 0.6 - perp * r * 0.6]), col)
