extends Node
## Shared plumbing for `death_probe.gd` (mech-move r7): the real-device input, the model-pose read,
## the captures and the kill / RETRY helpers. Split out so both probe files stay under 400 lines.
##
## Run it with the Gates line in `reviews/mech-move-r7.md`:
##   tools/godot.sh drive --scene=res://player/mech/tests/death_probe.tscn \
##     --timeline=res://player/mech/tests/death_probe_end.json --skip-menu --out=mech-move_death
## The capture directory comes from `--outdir` and the file prefix from `--out`, both passed by
## `tools/godot.sh`, so nothing here names a home path.

const TICK := 120.0
const GOD_T := 99999.0

var flow: Node = null
var fired: int = 0
var swings: int = 0
var boosts: int = 0
var steps: int = 0
var died: int = 0
var fails: PackedStringArray = []
var out_dir: String = ""
var tag: String = ""
var _acc_cam: Camera3D = null


func _ready() -> void:
	out_dir = Game.flag("outdir", ProjectSettings.globalize_path("res://captures"))
	tag = Game.flag("out", "mech-move_death")
	DirAccess.make_dir_recursive_absolute(out_dir)
	Events.player_died.connect(func() -> void:
		died += 1
		_log("EVENT player_died #%d hp=%.0f dead=%s" % [died, float(Game.player.get(&"hp")),
				str(_dead_of(Game.player))]))
	Events.weapon_fired.connect(func(_w: StringName, _m: Vector3, _d: Vector3) -> void: fired += 1)
	Events.melee_swing.connect(func(_m: StringName, _s: int) -> void: swings += 1)
	Events.boost_started.connect(func(_k: StringName) -> void: boosts += 1)
	Events.footstep.connect(func(_p: Vector3, _h: bool) -> void: steps += 1)
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	_run.call_deferred()


## Overridden by `death_probe.gd`.
func _run() -> void:
	push_error("death_probe_base: _run() must be overridden")
	get_tree().quit(1)


func _log(msg: String) -> void:
	print("VDEAD t=%.2f %s" % [float(Engine.get_physics_frames()) / TICK, msg])


func _v(p: Vector3) -> String:
	return "%.1f,%.1f,%.1f" % [p.x, p.y, p.z]


func _flat(d: Vector3) -> float:
	return Vector2(d.x, d.z).length()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(s: float) -> void:
	await _frames(int(ceil(s * TICK)))


func _until(cond: Callable, limit_s: float, label: String) -> bool:
	var ticks := 0
	var wall := Time.get_ticks_msec()
	while not bool(cond.call()):
		await get_tree().physics_frame
		ticks += 1
		if ticks > int(limit_s * TICK) or Time.get_ticks_msec() - wall > int(limit_s * 4000.0):
			_log("WAIT TIMEOUT %s" % label)
			return false
	_log("WAIT ok %s after %.1f s game" % [label, float(ticks) / TICK])
	return true


func _state() -> StringName:
	return StringName(flow.call(&"state_name"))


func _menus() -> CanvasLayer:
	return Game.hud.get(&"menus") as CanvasLayer if Game.hud != null else null


func _page() -> int:
	var m := _menus()
	return int(m.get(&"page")) if m != null else -1


func _cursor() -> int:
	var m := _menus()
	var s: Object = m.call(&"screen") as Object if m != null else null
	return int(s.get(&"index")) if s != null else -1


## `MechDamage.dead` is the cached mirror of `PlayerMech.is_alive()` (r16 B3). The probe prints both.
func _dead_of(p: Node) -> bool:
	var d: Object = p.call(&"damage") as Object
	return bool(d.get(&"dead")) if d != null else false


## The mercy window lives on the damage pipeline now, so a scripted kill has to clear it there.
func _clear_invuln(p: Node) -> void:
	(p.call(&"damage") as Object).set(&"_invuln_t", 0.0)


# --- real device events ---------------------------------------------------------------------------

func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _lmb(down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = get_viewport().get_visible_rect().size * 0.5
	ev.global_position = ev.position
	Input.parse_input_event(ev)


func _tap_key(code: Key, hold_s: float) -> void:
	_key(code, true)
	await _secs(hold_s)
	_key(code, false)


# --- model pose -----------------------------------------------------------------------------------

## The held `death` clip drops the pelvis ~5.8 m and lays the mech on the floor; standing, the cockpit
## socket sits ~12 m above the model origin (between the feet).
func _pose(tag_name: String) -> String:
	var p := Game.player
	var m := p.call(&"model") as Node3D
	if m == null:
		return "%s: no model" % tag_name
	var clips: Object = m.get(&"clips") as Object
	var cock := m.call(&"socket", &"cockpit") as Node3D
	var chest := m.call(&"socket", &"chest") as Node3D
	var o := m.global_position.y
	var line := "POSE %s: action=%s clip=%s weight=%.2f cockpit_h=%.1f chest_h=%.1f (m above model origin) state=%s hp=%.0f alive=%s dead=%s" % [
			tag_name, String(m.call(&"current_action")) if m.has_method(&"current_action") else "-",
			String(clips.call(&"current")) if clips != null else "-",
			float(clips.call(&"weight")) if clips != null else -1.0,
			cock.global_position.y - o if cock != null else -1.0,
			chest.global_position.y - o if chest != null else -1.0,
			str(p.call(&"move_state")), float(p.get(&"hp")), str(p.call(&"is_alive")),
			str(_dead_of(p))]
	_log(line)
	return line


# --- captures -------------------------------------------------------------------------------------

func _frame() -> String:
	var drawn := [false]
	var cb := func() -> void: drawn[0] = true
	RenderingServer.frame_post_draw.connect(cb, CONNECT_ONE_SHOT)
	for i in 40:
		await get_tree().process_frame
		if bool(drawn[0]):
			return "drawn"
	if RenderingServer.frame_post_draw.is_connected(cb):
		RenderingServer.frame_post_draw.disconnect(cb)
	RenderingServer.force_draw(false, 0.0)
	return "forced"


func _save(what: String) -> String:
	var path := out_dir.path_join("%s_%s.jpg" % [tag, what])
	get_viewport().get_texture().get_image().save_jpg(path, 0.85)
	return path


## What the player sees: the game camera with the death page up.
func _shot(what: String) -> void:
	var how := await _frame()
	_log("SHOT %s -> %s [%s] page=%d" % [what, _save(what), how, _page()])


## A side close-up from a probe camera with the menu layer hidden for this one frame only, so the pose
## can be read. The page state is not touched (visibility only) and is restored right after.
func _closeup(what: String) -> void:
	var p := Game.player
	var m := p.call(&"model") as Node3D
	var feet := m.global_position if m != null else p.global_position + Vector3.DOWN * 7.5
	var right := p.global_basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.01 else Vector3.RIGHT
	var rig_cam: Camera3D = Game.camera_rig.call(&"camera") as Camera3D if Game.camera_rig != null else null
	if _acc_cam == null:
		_acc_cam = Camera3D.new()
		_acc_cam.name = "DeathProbeCam"
		_acc_cam.fov = 55.0
		_acc_cam.far = 6000.0
		add_child(_acc_cam)
	_acc_cam.global_position = feet + right * 30.0 + Vector3.UP * 12.0
	_acc_cam.look_at(feet + Vector3.UP * 5.0, Vector3.UP)
	_acc_cam.make_current()
	var menus := _menus()
	var was := menus.visible if menus != null else true
	if menus != null:
		menus.visible = false
	await _frame()
	var how := await _frame()
	var path := _save(what)
	if menus != null:
		menus.visible = was
	if rig_cam != null:
		rig_cam.make_current()
	_log("SHOT %s -> %s [%s] (probe close-up, menu layer hidden for the frame; page=%d)" % [what, path,
			how, _page()])


# --- kill / retry ---------------------------------------------------------------------------------

func _kill(tag_name: String) -> void:
	var p := Game.player
	_clear_invuln(p)
	await _frames(2)
	var hit := HitInfo.make(float(p.get(&"hp_max")) * 1.5, HitInfo.EXPLOSIVE, null, &"probe_kill")
	hit.position = p.global_position
	p.call(&"take_hit", hit)
	_log("KILL %s: final %.0f, hp=%.0f alive=%s dead=%s god_flag=%s at %s" % [tag_name, hit.final_amount,
			float(p.get(&"hp")), str(p.call(&"is_alive")), str(_dead_of(p)), str(Game.has_flag("god")),
			_v(p.global_position)])


func _retry(tag_name: String) -> void:
	if _menus() == null:
		await _retry_stubbed(tag_name)
		return
	_log("RETRY %s: page %d cursor %d; pressing ENTER (real key event)" % [tag_name, _page(), _cursor()])
	_key(KEY_ENTER, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_key(KEY_ENTER, false)
	await _frames(3)
	var p := Game.player
	_log("AFTER RETRY %s: page=%d flow=%s hp=%.0f alive=%s dead=%s at %s" % [tag_name, _page(), _state(),
			float(p.get(&"hp")), str(p.call(&"is_alive")), str(_dead_of(p)), _v(p.global_position)])


## `--stub=hud` (r16 Round 2: the corpse must be measured with the menus out of the way, so hud r6's
## GAME_OVER pause cannot mask it). With no page there is nothing to press RETRY on, so the revive is
## the same three calls `flow_progress.gd` `_restore_player` makes (flow's commit 5129b4c).
func _retry_stubbed(tag_name: String) -> void:
	var p := Game.player
	p.set(&"velocity", Vector3.ZERO)
	p.set(&"hp", p.get(&"hp_max"))
	p.call(&"heal", float(p.get(&"hp_max")))
	p.call(&"add_energy", float(p.get(&"energy_max")))
	p.call(&"invulnerable_for", 1.0)
	await _frames(4)
	_log("AFTER RETRY %s (stub=hud, direct restore): hp=%.0f alive=%s dead=%s at %s" % [tag_name,
			float(p.get(&"hp")), str(p.call(&"is_alive")), str(_dead_of(p)), _v(p.global_position)])


func _check(what: String, ok: bool, detail: String) -> void:
	print("VDEAD CHECK %s %s | %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails.append(what + " | " + detail)
