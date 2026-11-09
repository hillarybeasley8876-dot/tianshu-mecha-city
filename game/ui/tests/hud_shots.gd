extends Node
## Capture driver for the HUD unit (brief "Done when"): boots the real `main.tscn` in the sandbox,
## then walks the overlay through the states the review needs and leaves each one on screen long
## enough for `tools/godot.sh shot --times=...` to photograph it.
##
##   tools/godot.sh shot --scene=res://ui/tests/hud_shots.tscn --out=hud --hud=combat \
##       --sandbox --skip-menu --enemies=mantis:2,ripper:3 --times=1.4,2.9,4.4,5.9,7.4,8.9,10.9
##   ... --hud=menus --times=1.4,2.9,4.4,5.9
##
## It writes HUD state through `HudData`'s forced-snapshot mode, which is the same path the unit test
## uses, so what the capture shows is exactly what the test asserts.

const STEP := 1.5              ## s each state holds
const START := 1.0             ## s before the first state
const MIN_LOCK := 45.0         ## m, ignore swarmers that are already on top of the mech
const MAX_LOCK := 280.0        ## m, SPEC §5 hard lock band
## EN/s the capture harness drains while a flight step is up — the mech's own flight cost, so the cue
## measures the number it would measure in a real flight.
const FLIGHT_COST := 80.0
## s after boot before the title path presses START; the drop-in lands about 5 s later, so `move` is
## up from ~15.4 s and `look` takes over at ~22.4 s (hud r6 item 1's shot list).
const TITLE_PRESS_AT := 10.0

var _hud: Node = null
var _data: HudData = null
var _menus: HudMenuRoot = null
var _steps: Array[Callable] = []
var _mode: String = "combat"
var _t: float = 0.0
var _step: int = -1
var _locked: Node3D = null
var _numbers_t: float = 0.0
var _flight_step: int = -1
var _title_press_at: float = -1.0
var _title_presses: int = 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hud="):
			_mode = arg.trim_prefix("--hud=")
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		push_error("hud_shots: cannot load res://main.tscn")
		return
	add_child(packed.instantiate())
	await get_tree().process_frame
	await get_tree().process_frame
	_hud = Game.hud
	if _hud == null:
		push_error("hud_shots: main.tscn did not instance ui/hud.tscn (check --stub)")
		return
	_data = _hud.get(&"data") as HudData
	_menus = _hud.get(&"menus") as HudMenuRoot
	if _mode == "title":
		# The REAL title path: no forced snapshot, no page driving. The harness only presses ENTER
		# through the input pipeline, exactly as `test_title_tutorial.gd` does headless.
		_data.use_forced = false
		_title_press_at = TITLE_PRESS_AT
		return
	_data.use_forced = true
	_data.forced = _idle_state()
	_steps = _combat_steps() if _mode == "combat" else _menu_steps()


func _process(delta: float) -> void:
	if _data == null:
		return
	_t += delta
	if _mode == "title":
		_tick_title()
		return
	if _steps.is_empty():
		return
	_tick_combat(delta)
	_tick_flight(delta)
	var want := int((_t - START) / STEP)
	if want < 0 or want == _step or want >= _steps.size():
		return
	_step = want
	print("HUDSTEP %d at t=%.2f" % [want, _t])
	_steps[want].call()


# --- states ---------------------------------------------------------------------------------------

## A plausible idle snapshot: full EN, rifle up, no target.
func _idle_state() -> Dictionary:
	return {
		"alive": true, "hp": 8400.0, "hp_max": 10000.0, "en": 880.0, "en_max": 1000.0,
		"od": 62.0, "od_max": 100.0, "overdrive_active": false, "outage": false,
		"state": "idle", "speed": 0.0,
		"weapon": "beam_rifle", "ammo": 11, "ammo_max": 15, "reloading": false, "swapping": false,
		"charge": 0.0, "charge_stage": 0, "heat": 0.18, "overheated": false,
		"vent_needle": 0.18, "vent_mark": 0.7, "superheated": false,
		"missile_cd": 0.0, "missile_locks": 0, "missile_locks_max": 12, "missile_painting": false,
		"guarding": false, "perfect_window": false, "catch_count": 0, "guard_break": false,
		"guard_break_left": 0.0, "parries": 0,
		"combo_step": 0, "charging": 0.0, "execution_available": false, "jackpot": false,
		"rift_step_cd": 0.0, "rift_step_cd_max": 6.0, "rift_step_charges": 1, "rift_step_ready": true,
		"anchor_cd": 0.0, "anchor_cd_max": 8.0, "anchor_charges": 2, "anchor_ready": true,
		"fins_cd": 2.4, "fins_cd_max": 7.0, "fins_charges": 0, "fins_ready": false,
		"burst_cd": 0.0, "burst_cd_max": 9.0, "burst_charges": 1, "burst_ready": true,
		"well_cd": 5.1, "well_cd_max": 11.0, "well_charges": 0, "well_ready": false,
		"hard_target": null, "soft_target": null, "first_person": false, "ads": false,
		"soft_distance": -1.0, "hard_distance": -1.0, "in_view": 0,
	}


## The nearest lock point that is worth locking AND worth photographing: at least `MIN_LOCK` away, so
## a swarmer climbing the mech does not steal the frame, inside the lock band, and on screen.
func _nearest_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var origin := Game.player.global_position if Game.player != null else Vector3.ZERO
	var cam := _camera()
	for n in get_tree().get_nodes_in_group(&"targetable"):
		var t := n as Node3D
		if t == null:
			continue
		var d := t.global_position.distance_to(origin)
		if d < MIN_LOCK or d > MAX_LOCK or d >= best_d:
			continue
		if cam != null and (cam.is_position_behind(t.global_position) or not _on_screen(cam, t)):
			continue
		best = t
		best_d = d
	return best


func _camera() -> Camera3D:
	var rig := Game.camera_rig
	return rig.call(&"camera") as Camera3D if rig != null and rig.has_method(&"camera") else null


func _on_screen(cam: Camera3D, node: Node3D) -> bool:
	var at := node.global_position
	var p := cam.unproject_position(at)
	var s := cam.get_viewport().get_visible_rect().size
	return p.x > s.x * 0.15 and p.x < s.x * 0.85 and p.y > s.y * 0.15 and p.y < s.y * 0.85


## A stand-in hive spire for the compass and the radar: the world unit has not put anything in the
## `&"hive_spire"` group yet, and the vertical wayfinding (SPIRE ▲ +96 m) is worth photographing.
func _spawn_spire(at: Vector3) -> void:
	var n := Node3D.new()
	n.name = "FakeSpire"
	add_child(n)
	n.add_to_group(&"hive_spire")
	n.global_position = at


## Step list for `--hud=combat`; each entry leaves the HUD in one reviewable state.
func _combat_steps() -> Array[Callable]:
	return [
		_idle, _combat, _overheat, _overdrive, _low_hp, _boss, _flight, _first_person, _flight_canopy,
	]


func _menu_steps() -> Array[Callable]:
	return [
		_title_wait, _title_menu, _pause, _settings, _controls, _credits, _credits_end,
		_licences, _licences_ofl, _victory, _victory_credits, _game_over,
	]


## The real title path (hud r6 item 1): main.tscn with the real flow, no --skip-menu and no --sandbox.
## The ENTER presses are on the wall clock, so the frames line up with `--times`.
func _tick_title() -> void:
	if _title_presses >= 2 or _t < _title_press_at:
		return
	_press_enter()
	_title_presses += 1
	_title_press_at = _t + 0.4
	print("HUDSTEP title press %d at t=%.2f" % [_title_presses, _t])


## ENTER through the real input pipeline: `Input.action_press` never reaches `menu_root.gd:_input`.
func _press_enter() -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_ENTER
		ev.keycode = KEY_ENTER
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _title_wait() -> void:
	_menus.show_page(HudMenuRoot.Page.TITLE)
	_menus.screen().revealed = false


func _title_menu() -> void:
	_menus.show_page(HudMenuRoot.Page.TITLE)
	_menus.screen().revealed = true


func _pause() -> void:
	_menus.show_page(HudMenuRoot.Page.PAUSE)


func _settings() -> void:
	_menus.show_page(HudMenuRoot.Page.SETTINGS)


func _controls() -> void:
	_menus.show_page(HudMenuRoot.Page.CONTROLS)


## Credits: every audio pack and music track, and the AI-content labels (ACCEPTANCE §5).
func _credits() -> void:
	_menus.show_page(HudMenuRoot.Page.CREDITS)


## The credits scrolled to their last row, so the ENGINE & FONTS block and the LICENCES entry are in
## frame (hud r6 item 3/4: every row has to be reachable and readable).
func _credits_end() -> void:
	_menus.show_page(HudMenuRoot.Page.CREDITS)
	var s := _menus.screen()
	s.index = s.rows.size() - 1
	s.move(0)


## The LICENCES page at the top: the Godot MIT text.
func _licences() -> void:
	_menus.show_page(HudMenuRoot.Page.CREDITS)
	_menus.screen().index = _row(_menus.screen(), "licences")
	_menus.screen().activate()


## The LICENCES page scrolled to the OFL body.
func _licences_ofl() -> void:
	var s := _menus.screen()
	for i in s.rows.size():
		if String(s.rows[i].get("label", "")).contains("SIL OPEN FONT LICENSE"):
			s.index = i
			s.move(0)
			return


## SPEC 8 step 5: victory FINISH opens the credits.
func _victory_credits() -> void:
	_menus.show_page(HudMenuRoot.Page.VICTORY)
	_menus.screen().index = _row(_menus.screen(), "finish")
	_menus.screen().activate()


func _row(s: HudMenuScreen, id: String) -> int:
	for i in s.rows.size():
		if String(s.rows[i].get("id", "")) == id:
			return i
	return 0


## Victory with a plausible run behind it, so the stats page shows real numbers.
func _victory() -> void:
	_menus.stats = {"time": 1284.0, "max_combo": 47, "parries": 22, "perfect_dodges": 9,
			"executions": 6, "kills": 138}
	Events.game_won.emit()


func _game_over() -> void:
	Events.player_died.emit()


func _idle() -> void:
	_data.forced = _idle_state()
	Events.objective_changed.emit("摧毁三座蚀巢  DESTROY THE THREE HIVE SPIRES")
	_data.set_spires(1, 3)
	# The flow asks for the prompt (CONTRACTS §6) — free play on its own shows nothing.
	_hud.call(&"prompt", &"move")


## Locked target, missile paint at 6/12, a stagger plate, damage numbers and the style meter up.
func _combat() -> void:
	var t := _nearest_target()
	var d := 140.0
	if t != null and Game.player != null:
		d = Game.player.global_position.distance_to(t.global_position)
	_data.forced = _idle_state()
	_data.forced.merge({
		"hp": 6100.0, "en": 430.0, "weapon": "gatling", "ammo": 214, "ammo_max": 600,
		"heat": 0.55, "vent_needle": 0.55, "charge": 0.9, "charge_stage": 1,
		"hard_target": t, "hard_distance": d, "soft_target": t, "soft_distance": d,
		"missile_painting": true, "missile_locks": 6,
		"burst_cd": 6.2, "burst_ready": false, "burst_charges": 0,
	}, true)
	var style: HudWidget = _hud.call(&"widget", &"style")
	for i in 9:
		style.call(&"credit", 42.0, StringName("move_%d" % i))
	var co: HudWidget = _hud.call(&"widget", &"callouts")
	co.call(&"say", &"parry")
	_hud.call(&"dismiss_prompt", &"move")
	if Game.player != null:
		_spawn_spire(Game.player.global_position + Vector3(120.0, 96.0, -180.0))
	_locked = t


## Keeps the combat frame populated: damage numbers live 0.7 s, so a single burst at the start of the
## step would be gone by the time the capture fires.
func _tick_combat(delta: float) -> void:
	if _step != 1 or _locked == null or not is_instance_valid(_locked):
		return
	_numbers_t += delta
	if _numbers_t >= 0.25:
		_numbers_t = 0.0
		_spawn_numbers(_locked)
	# Hold the meter up against the sandbox's incoming fire — every hit costs two ranks (style_meter.gd),
	# so without this the review frame catches the meter at zero and never sees it.
	var style: HudWidget = _hud.call(&"widget", &"style")
	if float(style.get(&"points")) < 460.0:
		style.call(&"credit", 30.0, &"beam_rifle")


func _overheat() -> void:
	_data.forced.merge({"weapon": "gatling", "ammo": 96, "heat": 1.0, "overheated": true,
			"vent_needle": 1.0, "superheated": true, "en": 120.0}, true)


func _overdrive() -> void:
	_data.forced.merge({"od": 100.0, "heat": 0.3, "overheated": false, "vent_needle": 0.3,
			"superheated": false, "en": 760.0, "hp": 6100.0, "missile_painting": false,
			"missile_locks": 0}, true)


func _low_hp() -> void:
	_data.forced.merge({"hp": 780.0, "od": 74.0, "en": 240.0}, true)


## Fake boss plate (the boss unit has not landed yet) plus the objective moving to the final fight.
func _boss() -> void:
	_data.forced.merge({"hp": 5200.0, "en": 900.0, "od": 100.0}, true)
	Events.objective_changed.emit("击杀巢母  KILL THE BROOD TITAN")
	_data.set_spires(3, 3)
	_data.set_boss({"name": "巢母 BROOD TITAN", "hp": 41000.0, "hp_max": 60000.0,
			"cores": [1.0, 0.62, 0.0], "phase": 2, "phases": 3,
			"stability": 2600.0, "stability_max": 9000.0})
	# The intro card lives 2.5 s, so it is still up when the capture fires one step in (lead, boss r1).
	Events.boss_intro.emit("巢母 BROOD TITAN", "蚀巢之母  THE HIVE MOTHER")


## Flight (hud r6 item 5): the cue beside the reticle, with a real EN drain behind it so the reading
## is the seconds left rather than the fallback percentage. `_tick_flight` walks the gauge down at the
## cost the mech really pays, which is what the cue measures.
func _flight() -> void:
	_data.forced = _idle_state()
	_data.forced.merge({"state": "fly", "en": 940.0, "en_max": 1000.0, "speed": 50.0}, true)
	_flight_step = _step


## The same cue on the canopy glass: first person is already up from the step before.
func _flight_canopy() -> void:
	_data.forced.merge({"state": "fly", "en": 520.0}, true)
	_flight_step = _step


## Flight drains EN with no regen behind it (SPEC §4), so walking the gauge down here is exactly what
## the widget sees in a real flight.
func _tick_flight(delta: float) -> void:
	if _step != _flight_step:
		return
	_data.forced["en"] = maxf(float(_data.forced.get("en", 0.0)) - FLIGHT_COST * delta, 0.0)


## Cockpit view: the camera rig switches to first person and the canopy projection takes over. It is
## driven through `set_first_person` rather than a synthetic key press — the action only lands while the
## mech is in a state that reads input, which made the capture flaky.
func _first_person() -> void:
	_data.forced.merge({"first_person": true, "hp": 5200.0, "en": 690.0, "od": 100.0}, true)
	# The action, not `set_first_person`: the rig only collapses the arm through the path the player
	# uses, and the capture has to show what the player sees.
	Input.action_press(&"camera_toggle")
	await get_tree().create_timer(0.1).timeout
	Input.action_release(&"camera_toggle")


func _spawn_numbers(target: Node3D) -> void:
	var nums: HudWidget = _hud.call(&"widget", &"numbers")
	if nums == null or target == null:
		return
	for i in 3:
		var amount := 420.0 + float(i) * 130.0
		var at := target.global_position + Vector3(float(i) * 2.0, 2.0, 0.0)
		nums.call(&"spawn", amount, at, &"crit" if i == 1 else &"normal", target.get_instance_id())
