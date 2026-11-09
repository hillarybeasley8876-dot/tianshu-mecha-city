extends HudWidget
## Contextual tutorial prompts (brief §8, CONTRACTS §6). The flow unit decides WHICH verb is taught
## and when: it calls `Game.hud.prompt(id, action, line)` and the HUD only ever draws what it was
## asked for — free play shows nothing. Each id carries a default action and line so the flow can
## pass a bare id; `dismiss_prompt(id)` retires one early, and the HUD also retires a prompt the
## moment the player performs the verb.

const LIFE := 12.0                ## s a prompt lingers once it is AT THE FRONT before it steps aside
const CENTER_DROP := 360.0        ## px above the bottom edge

## id -> [action, line]. Actions are the names in `core/input_setup.gd` (SPEC §3); the glyph follows
## the last device used, so a pad player is never told to press LMB.
const DEFAULTS: Dictionary = {
	&"move": [&"move_forward", "移动  MOVE"],
	&"look": [&"look_left", "环视  LOOK"],
	&"dash": [&"boost", "冲刺 / 长按滑行  DASH"],
	&"boost": [&"assault", "强攻推进  ASSAULT BOOST"],
	&"jump": [&"jump", "跳跃  JUMP"],
	&"hover": [&"jump", "长按悬停  HOLD TO HOVER"],
	&"fire": [&"fire", "射击，长按蓄力  FIRE"],
	&"lock": [&"lock_on", "锁定目标  LOCK ON"],
	&"melee": [&"melee", "光刃连击  MELEE"],
	&"guard": [&"guard", "轻按格挡反击  GUARD"],
	&"missiles": [&"missiles", "锁定后齐射  MISSILES"],
	&"skills": [&"burst", "技能  SKILLS"],
}

var glyphs: HudGlyphs = null
## s the FRONT prompt has been on screen. It only runs while a prompt is up: the HUD is created long
## before the flow asks for anything (the title can sit there for minutes), and an empty queue that
## aged used to retire the first real prompt on its very first frame (hud r6 item 1).
var age: float = 0.0
var _queue: Array[Dictionary] = []
var _retired: Dictionary = {}


func _ready() -> void:
	super()
	glyphs = HudGlyphs.new()
	Events.boost_started.connect(func(_k: StringName) -> void:
		dismiss_prompt(&"dash")
		dismiss_prompt(&"boost"))
	Events.jumped.connect(func() -> void: dismiss_prompt(&"jump"))
	Events.flight_changed.connect(func(flying: bool) -> void:
		if flying:
			dismiss_prompt(&"hover"))
	Events.weapon_fired.connect(func(_w: StringName, _m: Vector3, _d: Vector3) -> void: dismiss_prompt(&"fire"))
	Events.melee_swing.connect(func(_m: StringName, _s: int) -> void: dismiss_prompt(&"melee"))
	Events.attack_blocked.connect(func(_h: HitInfo) -> void: dismiss_prompt(&"guard"))
	Events.parry_success.connect(func(_h: HitInfo, _a: Node) -> void: dismiss_prompt(&"guard"))
	Events.missiles_locked.connect(func(count: int) -> void:
		if count > 0:
			dismiss_prompt(&"missiles"))
	Events.skill_used.connect(func(skill: StringName) -> void:
		dismiss_prompt(&"skills")
		if skill == &"missiles":
			dismiss_prompt(&"missiles"))
	Events.lock_changed.connect(func(t: Node3D) -> void:
		if t != null:
			dismiss_prompt(&"lock"))


## CONTRACTS §6. Queues one prompt; `action` / `line` default to the table above. An id already
## retired this session, or already waiting, is ignored so the flow can re-ask safely.
func prompt(id: StringName, action: StringName = &"", line: String = "") -> void:
	if id == &"" or _retired.has(id) or _find(id) >= 0:
		return
	var def: Array = DEFAULTS.get(id, [&"", String(id).to_upper()])
	var was_empty := _queue.is_empty()
	_queue.append({
		"id": id,
		"action": action if action != &"" else StringName(def[0]),
		"line": line if line != "" else String(def[1]),
	})
	# A prompt that arrives at an empty queue starts its own LIFE now, not whenever the HUD was built.
	if was_empty:
		age = 0.0
	queue_redraw()


## CONTRACTS §6. Retires a prompt for the rest of the session, whether it is on screen or waiting.
func dismiss_prompt(id: StringName) -> void:
	_retired[id] = true
	var at := _find(id)
	if at >= 0:
		var was_front := at == 0
		_queue.remove_at(at)
		if was_front:
			age = 0.0
		queue_redraw()


func _find(id: StringName) -> int:
	for i in _queue.size():
		if StringName(_queue[i]["id"]) == id:
			return i
	return -1


## The verb on screen, or an empty id when nothing is queued.
func current_id() -> StringName:
	return StringName(_queue[0]["id"]) if not _queue.is_empty() else &""


## Test accessor: how many prompts are waiting.
func queued() -> int:
	return _queue.size()


## The prompt text, adjusted for accessibility settings: with `hold_to_toggle` on, guard is a toggle
## rather than a hold, and saying "轻按" (tap) would be a lie (Settings → Accessibility).
func line_for(id: StringName, base: String) -> String:
	if id == &"guard" and bool(Settings.get_value(&"hold_to_toggle")):
		return "切换格挡反击  GUARD (TOGGLE)"
	return base


func update_hud(delta: float) -> void:
	glyphs.poll()
	_poll_verbs()
	if _queue.is_empty():
		age = 0.0
	else:
		age += delta
		if age > LIFE:
			_retired[current_id()] = true
			_queue.pop_front()
			age = 0.0
	visible = data.alive() and not _queue.is_empty()


## Two verbs have no event of their own — walking and looking are read straight from the input map
## (the same actions the glyphs poll), so the prompt clears on the first real input.
func _poll_verbs() -> void:
	if current_id() == &"move" and data.num("speed") > 1.0:
		dismiss_prompt(&"move")
	if current_id() == &"look" and _look_input():
		dismiss_prompt(&"look")


func _look_input() -> bool:
	for action: StringName in [&"look_left", &"look_right", &"look_up", &"look_down"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false


func center_point() -> Vector2:
	var s := screen_size()
	return Vector2(s.x * 0.5, s.y - CENTER_DROP)


func _draw() -> void:
	if _queue.is_empty():
		return
	var row := _queue[0]
	var glyph := glyphs.glyph(StringName(row["action"]))
	var line := line_for(StringName(row["id"]), String(row["line"]))
	var fade := clampf(minf(age * 3.0, (LIFE - age) * 2.0), 0.0, 1.0)
	var c := center_point()
	var gw := maxf(text_w(glyph, HudPalette.SIZE_BODY) + 20.0, 38.0)
	var box := Rect2(c - Vector2(gw * 0.5 + 14.0 + text_w(line, HudPalette.SIZE_BODY) * 0.5, 20.0),
			Vector2(gw + 28.0 + text_w(line, HudPalette.SIZE_BODY), 40.0))
	draw_rect(box, Color(HudPalette.INK.r, HudPalette.INK.g, HudPalette.INK.b, 0.62 * fade), true)
	HudPalette.draw_brackets(self, box, Color(HudPalette.CYAN.r, HudPalette.CYAN.g, HudPalette.CYAN.b, fade), 8.0, 1.0)
	var key := Rect2(box.position + Vector2(8.0, 8.0), Vector2(gw, 24.0))
	draw_rect(key, Color(HudPalette.CYAN.r, HudPalette.CYAN.g, HudPalette.CYAN.b, 0.22 * fade), true)
	draw_rect(key, Color(HudPalette.CYAN.r, HudPalette.CYAN.g, HudPalette.CYAN.b, fade), false, 1.0)
	text(key.get_center() + Vector2(-text_w(glyph, HudPalette.SIZE_SMALL) * 0.5, 6.0), glyph,
			HudPalette.SIZE_SMALL, Color(HudPalette.WHITE.r, HudPalette.WHITE.g, HudPalette.WHITE.b, fade))
	text(key.end + Vector2(12.0, 18.0), line, HudPalette.SIZE_BODY,
			Color(HudPalette.WHITE.r, HudPalette.WHITE.g, HudPalette.WHITE.b, fade))
