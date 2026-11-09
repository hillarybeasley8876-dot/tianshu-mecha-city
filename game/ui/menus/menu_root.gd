class_name HudMenuRoot
extends CanvasLayer
## Menu stack (brief §9): title, pause, settings, controls, game over, victory, credits and the
## licences page. Every page is a `HudMenuScreen`; this file owns which page is up, the keyboard/pad
## navigation, the live wiring of the settings rows to the `Settings` autoload and the run statistics
## the victory page shows. The row lists themselves live in `HudMenuPages`.
##
## It never calls gameplay directly: pages emit `start_game`, `resume_game`, `retry_game`,
## `abort_to_title` and `quit_game` for the flow unit (CONTRACTS §1: `game/flow/**` owns the
## title/victory flow), and fall back to a sensible local behaviour when no flow scene is present so
## the demo is playable either way.
##
## Two rules the flow unit depends on (lead r16 decisions 3 and 7):
##   * `quit_game` ALWAYS quits the app. PAUSE → ABORT has its own `abort_to_title`.
##   * RETRY unpauses and emits `retry_game`, and the page stays up until the mech is really back —
##     a RETRY that never respawns never closes the page.
##
## And one the mech-move and flow units depend on (hud r7): a death PLAYS OUT before the tree freezes.
## The page is raised in the frame `player_died` fires, but the pause waits for the flow to be in
## `game_over` and for the hero's `death` clip to have settled — `death_hold.gd` owns that clock.

signal start_game()
signal resume_game()
signal retry_game()
signal abort_to_title()
signal quit_game()

enum Page { NONE, TITLE, PAUSE, SETTINGS, CONTROLS, GAME_OVER, VICTORY, CREDITS, LICENCES }

const PAGES: Array[Array] = [
	[Page.TITLE, "天枢  TIANSHU", "云阙城 · MECHA CITY"],
	[Page.PAUSE, "暂停  PAUSED", ""],
	[Page.SETTINGS, "设置  SETTINGS",
		"减弱动态 REDUCE MOTION：屏幕震动与特效闪光调至 0；开启光敏安全后 HUD 停止闪烁"],
	[Page.CONTROLS, "操作  CONTROLS", ""],
	[Page.GAME_OVER, "机体损毁  MECH DESTROYED", "重生于最后清除的蚀巢"],
	[Page.VICTORY, "任务完成  MISSION COMPLETE", "云阙城 · 天枢"],
	[Page.CREDITS, "制作名单  CREDITS", "素材来源与授权 · SOURCES & LICENCES"],
	[Page.LICENCES, "开源许可  LICENCES", ""],
]

var page: int = Page.NONE
var stats: Dictionary = {"time": 0.0, "max_combo": 0, "parries": 0, "perfect_dodges": 0,
	"executions": 0, "kills": 0}
## `back_to` is where ESC / B lands: settings, controls, credits and licences return to whatever
## opened them.
var back_page: int = Page.TITLE
## Test seam (hud r6 item 4c): a suite drives FINISH → CREDITS → quit without ending its own host.
var quit_seam: bool = false
## Set by `_quit_app()`, so a suite can tell a quit was asked for.
var quit_requested: bool = false
## True between a RETRY and the moment the mech is back. While it is set the page stays up.
var awaiting_respawn: bool = false

var _pages: Dictionary = {}
var _title_armed: bool = false
var _screen: Control = null
var _credits_quit: bool = false       ## the credits were opened by victory FINISH: leaving them quits
var _last_real: float = -1.0          ## last frame's Feel.real_now(), see _process
## The GAME_OVER page's death clock (hud r7): the tree freezes when the death has PLAYED OUT, not in
## the frame it was announced. See `death_hold.gd`.
var _death: HudDeathHold = HudDeathHold.new()


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_death.setup(get_tree())
	# A CanvasLayer gives its children no rect, so the pages live under a full-rect Control; without it
	# every page would anchor to a degenerate size and draw its backdrop over a corner of the screen.
	_screen = Control.new()
	_screen.name = "Screen"
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	for spec in PAGES:
		_add_page(int(spec[0]), String(spec[1]), String(spec[2]))
	_build_all()
	Events.player_died.connect(_on_player_died)
	Events.game_won.connect(_on_won)
	Events.parry_success.connect(func(_h: HitInfo, _a: Node) -> void: stats["parries"] += 1)
	Events.perfect_dodge.connect(func(_a: Node) -> void: stats["perfect_dodges"] += 1)
	Events.enemy_killed.connect(_on_kill)
	if not Game.has_flag("skip-menu") and not Game.has_flag("sandbox"):
		show_page(Page.TITLE)

# --- page construction ----------------------------------------------------------------------------

func _add_page(id: int, title: String, sub: String) -> void:
	var s: HudMenuScreen = HudLicencesPage.new() if id == Page.LICENCES else HudMenuScreen.new()
	s.name = Page.keys()[id]
	s.chosen.connect(_on_chosen.bind(id))
	s.value_changed.connect(_on_value_changed)
	_screen.add_child(s)
	_pages[id] = s
	if id == Page.LICENCES:
		(s as HudLicencesPage).build(title, sub)
	else:
		s.set_rows([], title, sub)


func _build_all() -> void:
	_rows(Page.TITLE, HudMenuPages.title())
	(_pages[Page.TITLE] as HudMenuScreen).heading_size = 88
	_rows(Page.PAUSE, HudMenuPages.pause())
	_rows(Page.SETTINGS, HudMenuPages.settings())
	_rows(Page.CONTROLS, HudMenuPages.controls())
	(_pages[Page.CONTROLS] as HudMenuScreen).row_h = 26.0
	_rows(Page.GAME_OVER, HudMenuPages.game_over())
	_rows(Page.VICTORY, HudMenuPages.victory(stats))
	_rows(Page.CREDITS, HudMenuPages.credits())
	var credits := _pages[Page.CREDITS] as HudMenuScreen
	credits.row_h = 25.0
	credits.list_width = 1300.0
	credits.value_ratio = 0.58
	credits.wrap_values = true


## Replaces a page's rows without touching its title and subtitle.
func _rows(id: int, rows: Array[Dictionary]) -> void:
	var s := _pages[id] as HudMenuScreen
	if s != null:
		s.set_rows(rows, s.page_title, s.subtitle)

# --- navigation -----------------------------------------------------------------------------------

func screen() -> HudMenuScreen:
	return _pages.get(page) as HudMenuScreen


func show_page(id: int) -> void:
	for key: int in _pages:
		(_pages[key] as HudMenuScreen).visible = key == id
	page = id
	if id != Page.GAME_OVER:
		_death.clear()
	if id == Page.SETTINGS:
		_refresh_settings()
	var s := screen()
	if s != null:
		s.revealed = id != Page.TITLE
	_title_armed = id == Page.TITLE


## Closes the menu. While a RETRY is waiting for the respawn this is REFUSED: the flow unit closes us
## itself the moment `retry_game` arrives, which is exactly the frame the mech is still dead on
## (flow r5 Request 3 — the page must outlive the respawn).
func close() -> void:
	if awaiting_respawn and not _player_back():
		return
	show_page(Page.NONE)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if page == Page.NONE:
		return
	if page == Page.TITLE and _title_armed and _any_key(event):
		_title_armed = false
		screen().revealed = true
	var s := screen()
	if event.is_action_pressed(&"ui_down"):
		s.move(1)
	elif event.is_action_pressed(&"ui_up"):
		s.move(-1)
	elif event.is_action_pressed(&"ui_right"):
		s.adjust(1)
	elif event.is_action_pressed(&"ui_left"):
		s.adjust(-1)
	elif event.is_action_pressed(&"ui_accept"):
		s.activate()
	elif event.is_action_pressed(&"ui_cancel"):
		_on_cancel()
	else:
		return
	get_viewport().set_input_as_handled()


## "Press any key" on the title (brief §9): any key, mouse button or pad button drops into the menu.
func _any_key(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton


## ESC / pad B. On a page that pauses the tree it must never close without a respawn, so GAME_OVER and
## a waiting RETRY are handled before the generic branch (mech-move r7, flow r5).
func _on_cancel() -> void:
	match page:
		Page.SETTINGS, Page.CONTROLS:
			show_page(back_page)
		Page.CREDITS, Page.LICENCES:
			if _credits_quit:
				_quit_app()
			else:
				show_page(back_page)
		Page.PAUSE:
			_resume()
		Page.GAME_OVER:
			pass
		Page.TITLE:
			pass
		_:
			close()


## The pause key works whether or not a page is open; ESC also closes a page back to the game.
func _toggle_pause() -> void:
	if page == Page.PAUSE:
		_resume()
	elif page == Page.NONE:
		back_page = Page.PAUSE
		show_page(Page.PAUSE)
		_set_paused(true)
	elif page == Page.SETTINGS or page == Page.CONTROLS or page == Page.CREDITS or page == Page.LICENCES:
		_on_cancel()


func _resume() -> void:
	close()
	_set_paused(false)
	resume_game.emit()


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	Events.paused_changed.emit(on)

# --- actions --------------------------------------------------------------------------------------

func _on_chosen(id: StringName, from: int) -> void:
	match id:
		&"start":
			close()
			start_game.emit()
		&"resume":
			_resume()
		&"retry":
			# hud r7: a RETRY pressed while the mech is still collapsing would cut the death short, so
			# the row only arms once the tree has frozen for it (a scripted run never freezes, and its
			# own beat runner presses this row).
			if _death.settling():
				return
			_retry()
		&"quit":
			if from == Page.PAUSE:
				_set_paused(false)
				abort_to_title.emit()
			else:
				_quit_app()
		&"finish":
			# SPEC §8 step 5: FINISH opens the credits; leaving THEM quits, as FINISH used to.
			back_page = Page.VICTORY
			_credits_quit = true
			show_page(Page.CREDITS)
		&"settings":
			back_page = from
			show_page(Page.SETTINGS)
		&"controls":
			back_page = from
			show_page(Page.CONTROLS)
		&"credits":
			back_page = from
			_credits_quit = false
			show_page(Page.CREDITS)
		&"licences":
			back_page = from
			show_page(Page.LICENCES)
		&"back":
			_on_cancel()
		_:
			pass


## RETRY (lead r16 decision 7): unpause FIRST so the mech can tick, then emit, then hold the page
## until the mech is on its feet again. A run with no checkpoint and no flow never closes it.
func _retry() -> void:
	_set_paused(false)
	_death.clear()
	awaiting_respawn = true
	retry_game.emit()


## True once the player exists and is alive again — the flow unit's respawn is what the page waits for.
func _player_back() -> bool:
	var p := Game.player
	return p != null and is_instance_valid(p) and p.has_method(&"is_alive") and bool(p.call(&"is_alive"))


func _quit_app() -> void:
	quit_requested = true
	quit_game.emit()
	if not quit_seam:
		get_tree().quit()


## Settings rows write straight through to the autoload, so every change applies live (brief §9).
func _on_value_changed(id: StringName, value: Variant) -> void:
	Settings.set_value(id, value)


func _refresh_settings() -> void:
	var s := _pages[Page.SETTINGS] as HudMenuScreen
	for spec in HudMenuPages.SETTING_ROWS:
		s.sync(StringName(spec[0]), Settings.get_value(StringName(spec[0])))

# --- the run clock and the death clock (brief §9 victory page, hud r7) ------------------------------

func _process(_delta: float) -> void:
	# The frame delta carries the time scale, so a hit-stop or slow-mo would be under-counted in 用时
	# TIME (audit #6). Feel is PROCESS_MODE_ALWAYS, so its unscaled clock runs here too; the flow unit
	# overwrites this with its own run time when it has one.
	var now := Feel.real_now()
	if _last_real < 0.0:
		_last_real = now
		return
	var dt := minf(now - _last_real, 0.1)
	_last_real = now
	if page == Page.NONE:
		stats["time"] = float(stats["time"]) + dt
	if awaiting_respawn and _player_back():
		awaiting_respawn = false
		show_page(Page.NONE)
	if page == Page.GAME_OVER and _death.at >= 0.0:
		_tick_death()


## The GAME_OVER page's own clock (hud r7). Three outcomes, in order:
##   * the flow revived the mech itself — a scripted run's `respawn`, a checkpoint restore nobody asked
##     the menu for — so the page has done its job and closes;
##   * the flow is in `game_over` and the death has settled: freeze the tree, once;
##   * anything else: keep running, so the clip plays and the flow's own beats keep ticking.
func _tick_death() -> void:
	if _player_back():
		show_page(Page.NONE)
		return
	if _death.frozen or HudDeathHold.scripted():
		return
	if _death.flow_in_game_over() and _death.settled(Feel.real_now()):
		_death.frozen = true
		_set_paused(true)


func _on_player_died() -> void:
	# hud r7: the page goes up at once, but the tree keeps running until the death has played out.
	# Pausing in this frame froze the hero's `death` clip at weight 0 — the mech stood upright under
	# MECH DESTROYED — and stalled every scripted run at the death beat. `_tick_death` does the pause.
	show_page(Page.GAME_OVER)
	_death.arm(Feel.real_now())


func _on_kill(_enemy: Node, hit: HitInfo) -> void:
	stats["kills"] = int(stats["kills"]) + 1
	if hit != null and hit.finisher:
		stats["executions"] = int(stats["executions"]) + 1


func note_combo(count: int) -> void:
	stats["max_combo"] = maxi(int(stats["max_combo"]), count)


func _on_won() -> void:
	_rows(Page.VICTORY, HudMenuPages.victory(stats))
	show_page(Page.VICTORY)
