class_name HudMenuSuite
extends RefCounted
## Menus (brief §9): every page opens, the cursor navigates from the keyboard and from a pad, values
## apply live to the Settings autoload, and the flow events raise the game-over and victory pages.
##
## The r16 Round 2 gates live here too: PAUSE → RETRY, GAME_OVER holding its page until the respawn,
## pad B, `abort_to_title`, the GAME_OVER pause, the footer hint and the lock glyphs.

const A := JOY_BUTTON_A
const B := JOY_BUTTON_B


static func run(h: HudTestHarness) -> void:
	var m := h.menus()
	m.quit_seam = true              # the suite drives the quit paths without ending its own host
	await _hud_visibility(m, h)
	await _title(m, h)
	await _navigation(m, h)
	await _settings(m, h)
	await _flow_pages(m, h)
	await _game_over(m, h)
	await _game_over_scripted(m, h)
	await _pause_retry(m, h)
	await _abort_and_quit(m, h)
	await _glyphs(m, h)
	await HudCreditsSuite.run(h)
	m.quit_seam = false
	m.show_page(HudMenuRoot.Page.NONE)


## The mech HUD must not sit behind the title logo, but pause and the end pages keep it (brief §9).
static func _hud_visibility(m: HudMenuRoot, h: HudTestHarness) -> void:
	h.reset_state()
	m.show_page(HudMenuRoot.Page.TITLE)
	await h.settle()
	h.check(not h.widget(&"reticle").visible, "title screen hides the mech HUD")
	m.show_page(HudMenuRoot.Page.PAUSE)
	await h.settle()
	h.check(h.widget(&"reticle").visible, "pause keeps the mech HUD readable under the dim")
	m.show_page(HudMenuRoot.Page.NONE)
	await h.settle()


## The title waits for "any key"; a pad button must be enough (brief §8/§9).
static func _title(m: HudMenuRoot, h: HudTestHarness) -> void:
	m.show_page(HudMenuRoot.Page.TITLE)
	h.check(m.page == HudMenuRoot.Page.TITLE, "title page opens")
	h.check(not m.screen().revealed, "title starts on PRESS ANY KEY")
	h.pad_button(A)
	h.check(m.screen().revealed, "a pad button reveals the title menu")
	h.check(m.screen().rows.size() == 5, "title offers start / settings / controls / credits / quit")
	m.show_page(HudMenuRoot.Page.TITLE)
	var key := InputEventKey.new()
	key.pressed = true
	m._input(key)
	h.check(m.screen().revealed, "a keyboard key reveals the title menu too")


static func _navigation(m: HudMenuRoot, h: HudTestHarness) -> void:
	m.show_page(HudMenuRoot.Page.TITLE)
	var s := m.screen()
	s.index = 0
	h.press(&"ui_down")
	h.check(s.index == 1, "ui_down moves the cursor to SETTINGS")
	for _n in 4:
		h.press(&"ui_down")
	h.check(s.index == 0, "the cursor wraps around the title list")
	h.press(&"ui_up")
	h.check(s.index == 4, "ui_up wraps backwards")
	s.index = 1
	h.press(&"ui_accept")
	h.check(m.page == HudMenuRoot.Page.SETTINGS, "accept on SETTINGS opens the settings page")
	h.press(&"ui_cancel")
	h.check(m.page == HudMenuRoot.Page.TITLE, "cancel returns to the page that opened settings")
	s.index = 2
	h.press(&"ui_accept")
	h.check(m.page == HudMenuRoot.Page.CONTROLS, "accept on CONTROLS opens the controls table")
	h.check(m.screen().rows.size() >= 24, "controls page lists the whole SPEC §3 table")
	for want: String in ["Flight", "Zenith Lance", "Pause", "Fullscreen"]:
		h.check(_has_label(m.screen(), want), "the controls page documents '%s'" % want)
	h.check(not m.screen().footer_hint().contains("W / S"),
			"the footer names the keys that navigate, not W / S")
	h.press(&"ui_cancel")
	h.check(m.page == HudMenuRoot.Page.TITLE, "cancel leaves the controls page")


## Settings rows must write through to the autoload the moment they move (brief §9 "applied live").
static func _settings(m: HudMenuRoot, h: HudTestHarness) -> void:
	m.show_page(HudMenuRoot.Page.SETTINGS)
	var s := m.screen()
	var before := bool(Settings.get_value(&"invert_y"))
	var row := HudTestHarness.find_row(s, "invert_y")
	h.check(not row.is_empty(), "settings page has an invert_y row")
	s.index = s.rows.find(row)
	h.press(&"ui_right")
	h.check(bool(Settings.get_value(&"invert_y")) != before, "toggling invert_y writes to Settings")
	h.press(&"ui_right")
	h.check(bool(Settings.get_value(&"invert_y")) == before, "toggling back restores the value")
	var sens := HudTestHarness.find_row(s, "mouse_sensitivity")
	s.index = s.rows.find(sens)
	var v0 := float(Settings.get_value(&"mouse_sensitivity"))
	h.press(&"ui_right")
	h.near(float(Settings.get_value(&"mouse_sensitivity")), v0 + 0.05, "slider steps by its step size")
	Settings.set_value(&"mouse_sensitivity", v0)
	var q := HudTestHarness.find_row(s, "quality")
	s.index = s.rows.find(q)
	var q0: Variant = Settings.get_value(&"quality")
	h.press(&"ui_right")
	h.check(Settings.get_value(&"quality") != q0, "quality cycles to the next preset")
	Settings.set_value(&"quality", q0)
	s.index = s.rows.find(HudTestHarness.find_row(s, "back"))
	h.press(&"ui_accept")
	h.check(m.page != HudMenuRoot.Page.SETTINGS, "BACK leaves the settings page")


static func _flow_pages(m: HudMenuRoot, h: HudTestHarness) -> void:
	# Earlier suites already emitted some of these, so the checks are on the delta.
	var p0 := int(m.stats["parries"])
	var d0 := int(m.stats["perfect_dodges"])
	var k0 := int(m.stats["kills"])
	Events.parry_success.emit(HitInfo.make(10.0, HitInfo.MELEE, null, &"x"), null)
	Events.perfect_dodge.emit(null)
	Events.enemy_killed.emit(null, HitInfo.make(10.0, HitInfo.MELEE, null, &"x"))
	Events.game_won.emit()
	h.check(m.page == HudMenuRoot.Page.VICTORY, "game_won raises the victory page")
	h.check(int(m.stats["parries"]) == p0 + 1, "victory stats counted the parry")
	h.check(int(m.stats["perfect_dodges"]) == d0 + 1, "victory stats counted the perfect dodge")
	h.check(int(m.stats["kills"]) == k0 + 1, "victory stats counted the kill")
	h.check(m.screen().rows.size() >= 7,
			"victory page lists time, combo, kills, parries, dodges, executions")
	# SPEC §8 step 5: FINISH opens the credits, and leaving THEM quits (hud r6 item 4c).
	m.quit_requested = false
	m.screen().index = HudTestHarness.row_index(m.screen(), "finish")
	h.press(&"ui_accept")
	h.check(m.page == HudMenuRoot.Page.CREDITS, "FINISH opens the credits")
	h.check(not m.quit_requested, "FINISH does not quit before the credits have been read")
	h.press(&"ui_cancel")
	h.check(m.quit_requested, "leaving the victory credits quits the app as FINISH used to")
	m.quit_requested = false
	m.show_page(HudMenuRoot.Page.NONE)


## hud r7 (was mech-move r7 + flow r5): the death PLAYS OUT before the tree freezes, and RETRY holds
## the page until the mech is back. The r6 version of this row asserted `paused` in the death frame,
## which is exactly the bug: it froze the hero's `death` clip at weight 0.
static func _game_over(m: HudMenuRoot, h: HudTestHarness) -> void:
	h.player.alive = false
	Events.player_died.emit()
	h.check(m.page == HudMenuRoot.Page.GAME_OVER, "player death raises the game-over page")
	h.check(not h.host.get_tree().paused, "the death frame itself does not freeze the tree")
	# A RETRY pressed while the mech is still collapsing would cut the death short.
	var early := [0]
	m.retry_game.connect(func() -> void: early[0] += 1)
	m.screen().index = 0
	h.press(&"ui_accept")
	h.check(int(early[0]) == 0, "RETRY does not fire while the death is still playing")
	h.check(not h.host.get_tree().paused, "the tree is still running while the death plays")
	await h.wait_real(HudDeathHold.SETTLE + 0.2)
	h.check(h.host.get_tree().paused, "the tree freezes once the death has settled")
	var t0 := h.player.ticks
	await h.settle(4)
	h.check(h.player.ticks == t0, "nothing ticks behind the game-over page")
	h.check(h.widget(&"reticle").visible, "the mech HUD stays readable under the game-over page")
	var fired := [0]
	m.retry_game.connect(func() -> void: fired[0] += 1)
	# The flow unit's `respawn()` closes the menus ITSELF the moment `retry_game` arrives — that close
	# has to be refused while the mech is still dead, or the page vanishes a frame before the respawn
	# (flow r5 Request 3). Wiring the real call here is the only way to prove the guard.
	m.retry_game.connect(func() -> void: m.close())
	m.screen().index = 0
	h.press(&"ui_accept")
	h.check(int(fired[0]) == 1, "RETRY emits retry_game once the death has played out")
	h.check(not h.host.get_tree().paused, "RETRY unpauses so the mech can tick again")
	h.check(m.page == HudMenuRoot.Page.GAME_OVER,
			"RETRY keeps the page up while the mech is still dead")
	h.pad_button(B)
	h.check(m.page == HudMenuRoot.Page.GAME_OVER,
			"pad B on game over never closes the page without a respawn")
	h.press(&"ui_cancel")
	h.check(m.page == HudMenuRoot.Page.GAME_OVER, "ESC on game over does not close it either")
	# The flow unit's respawn is what closes it.
	h.player.alive = true
	await h.settle(3)
	h.check(m.page == HudMenuRoot.Page.NONE, "the page closes the moment the mech is back")
	h.check(not m.awaiting_respawn, "the wait is over once the respawn landed")


## hud r7: a scripted run (`--flow-script`) drives its own beats and revives the mech itself, so the
## page must NOT freeze the tree under it — and it must close when the flow's respawn lands.
static func _game_over_scripted(m: HudMenuRoot, h: HudTestHarness) -> void:
	Game.flags["flow-script"] = "res://flow/tests/e2e_city.json"
	h.player.alive = false
	Events.player_died.emit()
	h.check(m.page == HudMenuRoot.Page.GAME_OVER, "a scripted run still raises the game-over page")
	await h.wait_real(HudDeathHold.SETTLE + 0.2)
	h.check(not h.host.get_tree().paused,
			"a scripted run keeps the tree running so its own beat runner is not stalled")
	var fired := [0]
	m.retry_game.connect(func() -> void: fired[0] += 1)
	m.screen().index = 0
	h.press(&"ui_accept")
	h.check(int(fired[0]) == 1, "a scripted run's RETRY is never gated on the settle")
	# The flow's own `respawn()` revives the mech without the menu asking: the page closes itself.
	h.player.alive = true
	await h.settle(3)
	h.check(m.page == HudMenuRoot.Page.NONE, "a flow-side respawn closes the page too")
	Game.flags.erase("flow-script")


## flow r5 Request 3: PAUSE has its own RETRY row, and it must unpause before it emits.
static func _pause_retry(m: HudMenuRoot, h: HudTestHarness) -> void:
	h.player.alive = false
	m.show_page(HudMenuRoot.Page.NONE)
	h.press(&"pause")
	h.check(m.page == HudMenuRoot.Page.PAUSE, "the pause key opens the pause page")
	h.check(h.host.get_tree().paused, "pause freezes the tree")
	var at := HudTestHarness.row_index(m.screen(), "retry")
	h.check(at >= 0, "PAUSE offers a RETRY FROM CHECKPOINT row")
	var fired := [0]
	m.retry_game.connect(func() -> void: fired[0] += 1)
	m.retry_game.connect(func() -> void: m.close())
	m.screen().index = at
	h.press(&"ui_accept")
	h.check(int(fired[0]) == 1, "PAUSE RETRY emits retry_game")
	h.check(not h.host.get_tree().paused, "PAUSE RETRY unpauses first")
	h.check(m.page == HudMenuRoot.Page.PAUSE, "PAUSE RETRY holds the page until the respawn")
	h.player.alive = true
	await h.settle(3)
	h.check(m.page == HudMenuRoot.Page.NONE, "the HUD is back as soon as the mech is")
	h.check(h.widget(&"reticle").visible, "the HUD is live again after a PAUSE RETRY")


## lead r16 decision 3: PAUSE → ABORT is `abort_to_title`; `quit_game` always quits the app.
static func _abort_and_quit(m: HudMenuRoot, h: HudTestHarness) -> void:
	m.show_page(HudMenuRoot.Page.NONE)
	h.press(&"pause")
	h.check(m.page == HudMenuRoot.Page.PAUSE, "the pause page is up for the ABORT check")
	var aborted := [0]
	m.abort_to_title.connect(func() -> void: aborted[0] += 1)
	m.quit_requested = false
	m.screen().index = HudTestHarness.row_index(m.screen(), "quit")
	h.press(&"ui_accept")
	h.check(int(aborted[0]) == 1, "PAUSE -> ABORT emits abort_to_title")
	h.check(not h.host.get_tree().paused, "ABORT unpauses the tree")
	h.check(not m.quit_requested, "ABORT does not quit the app")
	# VICTORY has no QUIT row on purpose: its FINISH opens the credits and leaving THEM quits, which
	# `_flow_pages` already covers.
	for id: int in [HudMenuRoot.Page.TITLE, HudMenuRoot.Page.GAME_OVER]:
		m.show_page(id)
		m.quit_requested = false
		m.screen().index = HudTestHarness.row_index(m.screen(), "quit")
		h.press(&"ui_accept")
		h.check(m.quit_requested, "QUIT from %s still quits the app" % HudMenuRoot.Page.keys()[id])
	m.show_page(HudMenuRoot.Page.VICTORY)
	h.check(HudTestHarness.row_index(m.screen(), "quit") < 0,
			"the victory page quits through its credits, not a QUIT row")
	m.quit_requested = false
	m.show_page(HudMenuRoot.Page.NONE)


## camera-aim r8: `lock_prev` / `lock_next` are PAD_ONLY, so they must have no keyboard glyph.
static func _glyphs(m: HudMenuRoot, h: HudTestHarness) -> void:
	var g := HudGlyphs.new()
	h.check(not HudGlyphs.KEYBOARD.has(&"lock_prev"), "lock_prev has no keyboard glyph")
	h.check(not HudGlyphs.KEYBOARD.has(&"lock_next"), "lock_next has no keyboard glyph")
	h.check(String(HudGlyphs.PAD.get(&"lock_prev", "")) == "D←", "lock_prev shows the D-pad left")
	h.check(String(HudGlyphs.PAD.get(&"lock_next", "")) == "D→", "lock_next shows the D-pad right")
	h.check(g.glyph(&"lock_next") == "D→",
			"a pad-only action falls back to its real button, never to a key that does nothing")
	h.check(g.glyph(&"lock_on") == "TAB", "lock_on still shows its keyboard binding")
	h.check(g.glyph(&"camera_toggle") == "B", "the camera toggle still shows B")
	m.show_page(HudMenuRoot.Page.CONTROLS)
	h.check(_has_label(m.screen(), "D←→"), "the controls page documents the D-pad lock switch")
	m.show_page(HudMenuRoot.Page.NONE)


static func _has_label(s: HudMenuScreen, needle: String) -> bool:
	for r in s.rows:
		if String(r.get("label", "")).contains(needle) or String(r.get("value", "")).contains(needle):
			return true
	return false
