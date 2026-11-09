class_name FlowTutorialDirector
extends Node
## Contextual tutorial prompts (brief §4, CONTRACTS §6). Flow owns WHICH verb is taught and WHEN;
## the HUD owns how it is drawn: `Game.hud.prompt(id)` queues one glyph prompt from the HUD's own
## table and `Game.hud.dismiss_prompt(id)` takes it away. Nothing here ever blocks play — a prompt
## that is not answered simply times out and the next one takes its place.
##
## Every verb of brief §4 is taught once, in the order the drop-in teaches them. The verbs are
## retired by the event that proves they were performed, so a player who already knows the verb never
## reads it. Until the HUD ships the API (guarded with `has_method`) the same lines ride on the
## objective text instead — the honest fallback, and the only thing on that line besides objectives.

signal hint_changed(text: String)

const PROMPT_TIME := 7.0        ## s a prompt stays up before the next one takes its place
const SPEED_CHECK_HZ := 10.0    ## how often the "did they move?" readout is polled (lead r3)
## id (CONTRACTS §6), the action whose glyph it shows, the fallback line, the event that retires it
## ("" = time out only).
const PROMPTS: Array[Array] = [
	["move", &"move_forward", "移动  MOVE", &""],
	["look", &"look_left", "环顾四周  LOOK", &""],
	["dash", &"boost", "冲刺闪避  DASH", &"dash"],
	["boost", &"boost", "长按冲刺滑行  BOOST", &"boost"],
	["jump", &"jump", "跳跃  JUMP", &"jumped"],
	["hover", &"jump", "按住跳跃悬停  HOVER", &""],
	["fire", &"fire", "射击，长按蓄力  FIRE", &"fired"],
	["lock", &"lock_on", "锁定目标  LOCK ON", &"locked"],
	["melee", &"melee", "光刃连击  MELEE", &"melee"],
	["guard", &"guard", "轻按格挡反击  GUARD", &"guard"],
	["missiles", &"missiles", "标记目标齐射  MISSILES", &"missiles"],
	["skills", &"rift_step", "战术技能  SKILLS", &"skill"],
]

var active: bool = false

var _index: int = 0
var _age: float = 0.0
var _speed_t: float = 0.0
var _shown: Dictionary = {}
var _text: String = ""


func _ready() -> void:
	Events.jumped.connect(func() -> void: _retire(&"jumped"))
	Events.boost_started.connect(func(kind: StringName) -> void:
			_retire(&"dash" if kind == &"quick" else &"boost"))
	Events.weapon_fired.connect(func(_w: StringName, _m: Vector3, _d: Vector3) -> void:
			_retire(&"fired"))
	Events.melee_swing.connect(func(_m: StringName, _s: int) -> void: _retire(&"melee"))
	Events.attack_blocked.connect(func(_h: HitInfo) -> void: _retire(&"guard"))
	Events.parry_success.connect(func(_h: HitInfo, _a: Node) -> void: _retire(&"guard"))
	Events.lock_changed.connect(func(t: Node3D) -> void:
			if t != null:
				_retire(&"locked"))
	Events.missiles_locked.connect(func(_c: int) -> void: _retire(&"missiles"))
	Events.skill_used.connect(func(_s: StringName) -> void: _retire(&"skill"))
	set_process(false)


## Start teaching from the top of the list.
func begin() -> void:
	active = true
	_index = 0
	_age = 0.0
	_shown.clear()
	_set_text("")
	_show()
	set_process(true)


## Teaching is over: take the prompt down and never put another one up.
func finish() -> void:
	active = false
	set_process(false)
	_dismiss(_current_id())
	_set_text("")


## A death in the yard (r5 brief item 1): teach again, but only the verbs this run has not shown yet
## — brief §4 says every verb is taught ONCE, and a respawn must not read as a fresh player.
func resume() -> void:
	active = true
	_index = 0
	_age = 0.0
	_set_text("")
	_show()
	set_process(true)


func hint_text() -> String:
	return _text


## Test and tool hook: retire the verb on screen and show the next one, without waiting out its time.
func advance() -> void:
	if active:
		_advance()


func _process(delta: float) -> void:
	if not active:
		return
	_age += delta
	# There is no "the player moved" event; the HUD retires the same prompt off the speed readout.
	# Polled at 10 Hz: `hud_state()` builds a Dictionary and this runs for the whole tutorial.
	if _current_id() == &"move":
		_speed_t -= delta
		if _speed_t <= 0.0:
			_speed_t = 1.0 / SPEED_CHECK_HZ
			if _player_speed() > 1.0:
				_advance()
				return
	if _age >= PROMPT_TIME:
		_advance()


func _player_speed() -> float:
	var player := Game.player
	if player == null or not player.has_method(&"hud_state"):
		return 0.0
	return float((player.call(&"hud_state") as Dictionary).get("speed", 0.0))


func _current_id() -> StringName:
	return StringName(PROMPTS[_index][0]) if _index < PROMPTS.size() else &""


func _advance() -> void:
	_dismiss(_current_id())
	_index += 1
	_age = 0.0
	if _index >= PROMPTS.size():
		_set_text("")
		set_process(false)
		return
	_show()


## Ask the HUD for the verb at `_index`; without the HUD API the line rides on the objective text.
func _show() -> void:
	var row := PROMPTS[_index] as Array
	var id := StringName(row[0])
	if _shown.has(id):
		_advance()
		return
	_shown[id] = true
	if _hud_has(&"prompt"):
		Game.hud.call(&"prompt", id)
		return
	_set_text(String(row[2]))


func _retire(event: StringName) -> void:
	if not active or _index >= PROMPTS.size():
		return
	if StringName(PROMPTS[_index][3]) == event:
		_advance()


func _dismiss(id: StringName) -> void:
	if id != &"" and _hud_has(&"dismiss_prompt"):
		Game.hud.call(&"dismiss_prompt", id)


func _hud_has(method: StringName) -> bool:
	return Game.hud != null and Game.hud.has_method(method)


func _set_text(next: String) -> void:
	if next == _text:
		return
	_text = next
	hint_changed.emit(next)
