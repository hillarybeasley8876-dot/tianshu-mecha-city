extends Node
## hud r7 regression: with the menus LIVE, a death has to PLAY OUT before the tree freezes.
##
## Every other HUD run drives `ui/hud.tscn` against fake actors, so nothing proved what happens on the
## real tree. `menu_root.gd:_on_player_died()` used to call `_set_paused(true)` in the SAME frame
## `Events.player_died` fired, which froze the hero's `death` clip (`Hero3Model`, blended in over
## 0.08 s from weight 0 and advanced in `_physics_process`) at weight 0: the mech stood upright under
## MECH DESTROYED, and any run whose beat runner is pausable — `FlowDebug`, the whole-city E2E —
## stalled at the death beat for ever.
##
## This boots the REAL `main.tscn` — real `PlayerMech`, real `Hero3Model`, real `flow/game_flow.tscn`,
## real `ui/hud.tscn` with its menus — kills the mech with a hit nothing can eat (`unblockable` walks
## past every damage filter, `defense_system.gd:215`) and ticks through. It asserts, in order:
##   * `player_died` fires once, the page is up in that frame and flow is in `game_over`;
##   * the tree is NOT paused while the death plays, and the corpse ignores the key it died holding;
##   * the `death` clip reaches weight 1.0 and the cockpit socket has dropped, at the pause;
##   * the tree is paused afterwards and nothing physics-ticks behind the page;
##   * a real ENTER key event fires `retry_game` with the page still up and the mech still dead, and
##     the page only closes after the flow's respawn has put the mech back at the checkpoint.
##
##   tools/godot.sh test res://ui/tests/test_death_pause.gd --timeout=600 \
##     -- --sandbox --flow --spawn=0,1,60 --no-enemies --no-post

const BOOT_TIMEOUT := 240.0     ## s the sandbox world + flow may take to come up
const KILL_AFTER := 2.0         ## s on the ground before the killing blow, so the hero is settled
const PAUSE_TIMEOUT := 12.0     ## s the death may take to settle before the tree freezes (> HudDeathHold.CAP)
const RESPAWN_TIMEOUT := 8.0    ## s the flow's respawn may take after RETRY
const CLOSE_TIMEOUT := 3.0      ## s the page may take to close after the mech is back
## mech-move's own numbers: standing, the `cockpit` socket (CONTRACTS §5) sits ~13 m above the model
## origin; the held death clip drops the pelvis 5.8 m and lays the mech out (`death_dead_phase.gd`).
const SLUMP_FRACTION := 0.75
const FRAME := 1.0 / 120.0      ## the test host runs `--fixed-fps 120`

var _flow: Node = null
var _menus: HudMenuRoot = null
var _ticks: TickProbe = null
var _deaths: int = 0
var _checks: int = 0
var _fails: PackedStringArray = PackedStringArray()
var _finished: bool = false


## A pausable physics-tick counter: the only honest proof that the tree really froze, because it stops
## the moment `get_tree().paused` goes true. The test node itself is PROCESS_MODE_ALWAYS.
class TickProbe:
	extends Node

	var ticks: int = 0

	func _physics_process(_delta: float) -> void:
		ticks += 1


func _ready() -> void:
	# The tree pauses mid-test, so the test body itself has to survive it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ticks = TickProbe.new()
	_ticks.name = "TickProbe"
	_ticks.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_ticks)
	Events.player_died.connect(func() -> void: _deaths += 1)
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("cannot load res://main.tscn")
		_finish()
		return
	add_child(packed.instantiate())
	print("DEATHPROBE boot: main.tscn instanced")
	if not await _until(func() -> bool: return Game.world_built() and _player() != null,
			BOOT_TIMEOUT, "world"):
		_finish()
		return
	_flow = _find_flow(get_tree().root)
	_menus = Game.hud.get(&"menus") as HudMenuRoot if Game.hud != null else null
	if _flow == null or _menus == null:
		_fail("no flow node (%s) or no menus (%s) in the tree" % [str(_flow != null),
				str(_menus != null)])
		_finish()
		return
	if not await _until(func() -> bool: return _state() == &"tutorial", BOOT_TIMEOUT, "tutorial"):
		_finish()
		return
	await _real(KILL_AFTER)
	var standing := _cockpit_h()
	print("DEATHPROBE standing: cockpit %.2f m, hero at %s, flow=%s" % [standing, str(_at()),
			String(_state())])
	_check(standing > 8.0, "the hero is standing before the killing blow (cockpit %.2f m)" % standing)
	await _kill()
	await _death_phase(standing)
	await _retry_phase()
	_finish()

# --- the death ------------------------------------------------------------------------------------

## One unblockable hit that nothing can eat. `_invuln_t` is cleared first: the drop-in and the respawn
## grace both write a mercy window, and `MechDamage.take_hit` returns early inside one.
func _kill() -> void:
	var p := _player()
	var dmg := p.call(&"damage") as Object
	if dmg != null:
		dmg.set(&"_invuln_t", 0.0)
	await _frames(2)
	var hit := HitInfo.make(float(p.get(&"hp_max")) * 1.5, HitInfo.CRUSH, null, &"hud_death_probe")
	hit.unblockable = true
	hit.position = _at()
	p.call(&"take_hit", hit)
	print("DEATHPROBE KILL final=%.0f hp=%.0f alive=%s paused=%s" % [hit.final_amount,
			float(p.get(&"hp")), str(p.call(&"is_alive")), str(get_tree().paused)])


## From the killing blow to the frozen tree: the page, the pose, the input gate and the pause.
func _death_phase(standing: float) -> void:
	_check(_deaths == 1, "the killing blow announces exactly one death (got %d)" % _deaths)
	_check(_menus.page == HudMenuRoot.Page.GAME_OVER,
			"the game-over page is up in the death frame (page %d)" % _menus.page)
	_check(_state() == &"game_over", "flow is in game_over in the death frame (%s)" % String(_state()))
	_check(not get_tree().paused, "the death frame itself does not freeze the tree")
	_check(float(_player().get(&"hp")) <= 0.0, "the mech is at 0 hp")
	# The corpse ignores the key it died holding (mech-move's death gate), so nothing the player
	# presses during the settle may act. W is held right across the pause and released after it.
	var at0 := _at()
	_key(KEY_W, true)
	var best := 0.0
	var t0 := Feel.real_now()
	while not get_tree().paused and Feel.real_now() - t0 < PAUSE_TIMEOUT:
		await get_tree().process_frame
		best = maxf(best, _clip_weight())
	var waited := Feel.real_now() - t0
	_key(KEY_W, false)
	var slumped := _cockpit_h()
	var walked := _flat(_at() - at0)
	print("DEATHPROBE settle: paused=%s after %.2f s, clip=%s weight %.2f (best %.2f), cockpit %.2f m"
			% [str(get_tree().paused), waited, String(_clip_id()), _clip_weight(), best, slumped]
			+ " (standing %.2f), W moved the corpse %.2f m" % [standing, walked])
	_check(walked < 0.5, "W held through the death moves the corpse %.2f m" % walked)
	_check(get_tree().paused, "the tree freezes once the death has settled (waited %.2f s)" % waited)
	_check(best >= 1.0, "the death clip reaches weight 1.0 before the pause (best %.2f)" % best)
	_check(_clip_id() == &"death", "the clip held at the pause is the death clip (%s)"
			% String(_clip_id()))
	_check(_clip_weight() >= 1.0, "the death clip is at full weight in the frozen frame (%.2f)"
			% _clip_weight())
	_check(slumped > 0.0 and slumped < standing * SLUMP_FRACTION,
			"the cockpit socket has dropped before the freeze (%.2f m vs %.2f m standing)"
			% [slumped, standing])
	_check(_state() == &"game_over", "flow is still in game_over at the pause (%s)" % String(_state()))
	var ticks := _ticks.ticks
	await _frames(6)
	_check(_ticks.ticks == ticks, "nothing physics-ticks behind the game-over page")

# --- the retry ------------------------------------------------------------------------------------

## A real ENTER key event through `Input.parse_input_event` — `Input.action_press` never reaches
## `menu_root.gd:_input`, which is the path a player's own key takes.
func _retry_phase() -> void:
	var seen := {"fired": 0, "page": -1}
	_menus.retry_game.connect(func() -> void:
		seen["fired"] = int(seen["fired"]) + 1
		seen["page"] = _menus.page)
	var cp := _flow.call(&"checkpoint") as FlowCheckpoint
	_check(cp != null, "the tutorial wrote a checkpoint to respawn at")
	_check(not _alive(), "the mech is dead when RETRY is pressed")
	_key(KEY_ENTER, true)
	await _frames(2)
	_key(KEY_ENTER, false)
	print("DEATHPROBE RETRY fired=%d page=%d alive_now=%s paused=%s" % [int(seen["fired"]),
			int(seen["page"]), str(_alive()), str(get_tree().paused)])
	_check(int(seen["fired"]) == 1, "a real ENTER press fires retry_game once (got %d)"
			% int(seen["fired"]))
	# This handler runs AFTER the flow's own `_on_retry_pressed`, so by now `flow.respawn()` has already
	# called `menus.close()` and revived the mech. The page still being up here is the proof that the
	# close was REFUSED while the mech was dead (flow r5 Request 3) — the page outlives the respawn.
	_check(int(seen["page"]) == HudMenuRoot.Page.GAME_OVER,
			"the flow's own close() during the respawn is refused: the page is still up (page %d)"
			% int(seen["page"]))
	_check(not get_tree().paused, "RETRY unpauses so the mech can tick again")
	var back := await _until(func() -> bool: return _alive(), RESPAWN_TIMEOUT, "respawn")
	_check(back, "the flow's respawn puts the mech back on its feet")
	if cp != null:
		var flat := _flat(_at() - cp.at.origin)
		print("DEATHPROBE respawned at %s, checkpoint '%s' at %s (%.2f m flat, %.2f m in y)"
				% [str(_at()), String(cp.id), str(cp.at.origin), flat, absf(_at().y - cp.at.origin.y)])
		# Y is the capsule's own push-out of the floor (`--spawn` writes the marker, not the body), so
		# the checkpoint's own y is not the mech's: only the ground position is the flow's contract.
		_check(flat < 2.0, "the mech is back on the checkpoint's ground (%.2f m away)" % flat)
	var closed := await _until(func() -> bool: return _menus.page == HudMenuRoot.Page.NONE,
			CLOSE_TIMEOUT, "page close")
	_check(closed, "the page closes after the respawn, not before")
	_check(not _menus.awaiting_respawn, "the respawn wait is over")
	_check(float(_player().get(&"hp")) > 0.0, "the mech is at full health again")

# --- helpers --------------------------------------------------------------------------------------

## The flow node, found by the one method every flow exposes. The hud must not name the class.
func _find_flow(node: Node) -> Node:
	if node.has_method(&"state_name"):
		return node
	for child in node.get_children():
		var found := _find_flow(child)
		if found != null:
			return found
	return null


func _state() -> StringName:
	return StringName(_flow.call(&"state_name")) if _flow != null else &""


## The `cockpit` socket in metres above the model origin, read exactly the way the mech-move death
## probe reads it. -1 when the build has no hero model.
func _cockpit_h() -> float:
	var m := _model()
	if m == null or not m.has_method(&"socket"):
		return -1.0
	var c := m.call(&"socket", &"cockpit") as Node3D
	return -1.0 if c == null else c.global_position.y - m.global_position.y


func _player() -> Node:
	var p := Game.player
	return p if p != null and is_instance_valid(p) else null


func _alive() -> bool:
	var p := _player()
	return p != null and bool(p.call(&"is_alive"))


func _model() -> Node3D:
	var p := _player()
	if p == null or not p.has_method(&"model"):
		return null
	return p.call(&"model") as Node3D


func _clips() -> Object:
	var m := _model()
	return m.get(&"clips") as Object if m != null else null


func _clip_id() -> StringName:
	var c := _clips()
	return StringName(c.call(&"current")) if c != null else &""


func _clip_weight() -> float:
	var c := _clips()
	return float(c.call(&"weight")) if c != null else -1.0


func _at() -> Vector3:
	return (Game.player as Node3D).global_position


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _real(seconds: float) -> void:
	var until := Feel.real_now() + seconds
	while Feel.real_now() < until:
		await get_tree().process_frame


func _until(cond: Callable, limit_s: float, label: String) -> bool:
	var spent := 0.0
	while not bool(cond.call()) and spent < limit_s:
		await get_tree().process_frame
		spent += FRAME
	print("DEATHPROBE wait %s: %s after %.2f s" % [label, "ok" if bool(cond.call()) else "TIMEOUT",
			spent])
	return bool(cond.call())


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_fails.append(label)


func _fail(label: String) -> void:
	_checks += 1
	_fails.append(label)
	print("FAIL " + label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("TEST %d checks, %d failed" % [_checks, _fails.size()])
	for line in _fails:
		print("TEST FAIL ", line)
	get_tree().quit(1 if _fails.size() > 0 else 0)
