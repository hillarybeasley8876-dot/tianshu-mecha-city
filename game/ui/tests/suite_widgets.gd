class_name HudWidgetSuite
extends RefCounted
## Widget behaviour: what shows, what hides, and that the numbers on screen are the numbers in the
## snapshot (brief "Done when": every widget shows/hides correctly, cooldown wipes match values).

static func run(h: HudTestHarness) -> void:
	await _visibility(h)
	await _resources(h)
	await _hotbar(h)
	await _targets(h)
	await _boss_and_radar(h)
	await _boss_card(h)
	await _flight(h)
	await _tutorial(h)
	await _tutorial_life(h)


## CONTRACTS §6: the HUD draws only what the flow asked for, one prompt at a time, and a prompt that
## times out or is performed must stop drawing on that same frame (an earlier drive read past its list).
static func _tutorial(h: HudTestHarness) -> void:
	var tut := h.widget(&"tutorial")
	h.reset_state()
	h.feed({"speed": 0.0})
	await h.settle()
	h.check(not tut.visible, "free play shows no prompt the flow did not ask for")
	tut.call(&"prompt", &"move")
	h.check(StringName(tut.call(&"current_id")) == &"move", "the flow's prompt goes up")
	tut.call(&"prompt", &"look", &"", "自定义  CUSTOM")
	h.check(int(tut.call(&"queued")) == 2, "a second prompt waits its turn")
	await h.settle()
	h.check(tut.visible, "a queued prompt is on screen")
	h.feed({"speed": 16.0})
	await h.settle()
	h.check(StringName(tut.call(&"current_id")) == &"look", "walking dismisses the movement prompt")
	tut.call(&"prompt", &"move")
	h.check(StringName(tut.call(&"current_id")) == &"look", "an answered verb is not offered again")
	tut.call(&"dismiss_prompt", &"look")
	h.check(StringName(tut.call(&"current_id")) == &"", "dismiss_prompt clears the queue")
	await h.settle()
	h.check(not tut.visible, "nothing is drawn once the queue is empty")
	# Every id in the contract table needs a default action and line, or the flow would have to supply
	# them. Read the table itself: the ids above are already retired, so re-prompting proves nothing.
	var defaults: Dictionary = tut.get_script().get_script_constant_map().get("DEFAULTS", {})
	for id: StringName in [&"move", &"look", &"dash", &"boost", &"jump", &"hover", &"fire", &"lock",
			&"melee", &"guard", &"missiles", &"skills"]:
		var def: Array = defaults.get(id, [])
		h.check(def.size() == 2 and String(def[0]) != "" and String(def[1]) != "",
				"prompt id '%s' has a default action and line" % id)
	# A prompt the player never performs retires on its own clock instead of sticking forever.
	tut.call(&"prompt", &"guard")
	tut.call(&"update_hud", 13.0)
	h.check(StringName(tut.call(&"current_id")) == &"", "an unanswered prompt times out")
	h.check(not tut.visible, "nothing is drawn after the last prompt")
	# The public API (CONTRACTS §6) must reach the canopy copy too, or a prompt asked for in the
	# cockpit would never appear — the screen widgets are suppressed there.
	h.hud.call(&"prompt", &"missiles")
	var glass_tut: HudWidget = (h.hud.get(&"glass") as HudGlassHud).widget(&"tutorial")
	h.check(glass_tut != null, "the canopy carries a tutorial widget")
	h.check(glass_tut != null and StringName(glass_tut.call(&"current_id")) == &"missiles",
			"hud.prompt() reaches the canopy copy")
	h.hud.call(&"dismiss_prompt", &"missiles")
	h.check(glass_tut != null and StringName(glass_tut.call(&"current_id")) == &"",
			"hud.dismiss_prompt() clears the canopy copy too")


## hud r6 item 1: LIFE counts from the moment a prompt reaches the FRONT of the queue, and nothing
## ages an empty queue. From the title the HUD runs for as long as the player sits there before the
## flow asks for its first verb, and that prompt used to be popped AND retired on its first frame —
## `W 移动 MOVE` never appeared for anyone who did not press START within about 6 s. Both copies of
## the widget are checked: they run the same script but keep their own queues.
static func _tutorial_life(h: HudTestHarness) -> void:
	h.feed({"speed": 0.0})
	await h.settle()
	var fresh := _fresh_tutorial(h)
	var glass := (h.hud.get(&"glass") as HudGlassHud).widget(&"tutorial")
	for pair: Array in [["screen", fresh], ["canopy", glass]]:
		var who := String(pair[0])
		var w := pair[1] as HudWidget
		if w == null:
			h.check(false, "the %s copy of the tutorial widget exists" % who)
			continue
		w.call(&"update_hud", 13.0)
		h.check(int(w.call(&"queued")) == 0, "%s: a 13 s title leaves the queue empty" % who)
		w.call(&"prompt", &"move")
		w.call(&"update_hud", 0.016)
		h.check(StringName(w.call(&"current_id")) == &"move",
				"%s: the first prompt is not dropped on its first frame" % who)
		h.check(bool(w.visible), "%s: the first prompt is on screen" % who)
		w.call(&"update_hud", 7.0)
		h.check(StringName(w.call(&"current_id")) == &"move" and bool(w.visible),
				"%s: the first prompt holds the front for its full 7 s" % who)
		w.call(&"dismiss_prompt", &"move")
		w.call(&"prompt", &"look")
		w.call(&"update_hud", 7.0)
		h.check(StringName(w.call(&"current_id")) == &"look" and bool(w.visible),
				"%s: the next prompt gets its own full 7 s" % who)
		w.call(&"dismiss_prompt", &"look")
	fresh.queue_free()
	h.reset_state()


## A tutorial widget with an empty retired set, so a prompt can be asked for again after the rest of
## the suite has answered or retired every id in the contract table.
static func _fresh_tutorial(h: HudTestHarness) -> HudWidget:
	var src := h.widget(&"tutorial").get_script() as GDScript
	var w: HudWidget = src.new()
	w.name = "FreshTutorial"
	w.set(&"data", h.data)
	h.hud.add_child(w)
	return w


## Missing keys must hide the widget that needs them (brief §1).
static func _visibility(h: HudTestHarness) -> void:
	h.data.forced = {}
	await h.settle()
	h.check(not h.widget(&"reticle").visible, "empty state: reticle hidden")
	h.check(not h.widget(&"hp").visible, "empty state: armour bar hidden")
	h.check(not h.widget(&"weapon").visible, "empty state: weapon panel hidden")
	h.check(not h.widget(&"hotbar").visible, "empty state: hotbar hidden")
	h.check(not h.widget(&"od").visible, "empty state: OD ring hidden")
	h.check(not h.widget(&"boss_bar").visible, "empty state: boss bar hidden")
	h.check(not h.widget(&"low_hp").visible, "empty state: no low-armour warning")
	h.reset_state()
	await h.settle()
	h.check(h.widget(&"reticle").visible, "full state: reticle visible")
	h.check(h.widget(&"hp").visible, "full state: armour bar visible")
	h.check(h.widget(&"weapon").visible, "full state: weapon panel visible")
	h.check(h.widget(&"hotbar").visible, "full state: hotbar visible")
	h.check(h.widget(&"od").visible, "full state: OD ring visible")
	h.check(not h.widget(&"low_hp").visible, "full state: healthy, no warning")


static func _resources(h: HudTestHarness) -> void:
	h.feed({"hp": 2500.0, "en": 250.0, "od": 100.0, "heat": 0.9, "overheated": true,
			"vent_needle": 0.9, "ammo": 3, "charge": 0.8, "charge_stage": 1})
	await h.settle()
	h.near(h.widget(&"hp").get(&"ratio"), 0.25, "armour bar reads 25 %")
	h.near(h.widget(&"reticle").get(&"en_ratio"), 0.25, "EN arc reads 25 %")
	h.near(h.widget(&"reticle").get(&"heat_ratio"), 0.9, "heat arc reads 90 %")
	h.check(bool(h.widget(&"reticle").get(&"overheated")), "reticle knows the barrel is locked")
	h.near(h.widget(&"od").get(&"fill"), 1.0, "OD ring full at 100 %")
	h.check(int(h.widget(&"weapon").get(&"ammo")) == 3, "weapon panel reads 3 rounds")
	h.check(int(h.widget(&"weapon").get(&"charge_stage")) == 1, "weapon panel reads charge stage 1")
	h.feed({"hp": 900.0})
	await h.settle()
	h.check(h.widget(&"low_hp").visible, "low armour warning under 35 %")
	h.near(h.widget(&"low_hp").get(&"ratio"), 0.09, "low-armour widget reads 9 %")
	h.reset_state()
	await h.settle()
	h.check(not h.widget(&"low_hp").visible, "warning clears back at full armour")


## Cooldown wipes must equal cd / cd_max, and a slot with no keys must grey out rather than throw.
static func _hotbar(h: HudTestHarness) -> void:
	h.feed({
		"rift_step_cd": 3.0, "rift_step_cd_max": 6.0, "rift_step_charges": 0, "rift_step_ready": false,
		"anchor_cd": 4.0, "anchor_cd_max": 8.0, "anchor_charges": 1, "anchor_ready": false,
		"anchor_attached": true,
		"burst_cd": 0.0, "burst_cd_max": 5.0, "burst_charges": 1, "burst_ready": true,
		"missile_cd": 7.0, "missile_locks": 5,
		"charging": 0.65, "combo_step": 2,
	})
	await h.settle()
	var bar := h.widget(&"hotbar")
	h.near(bar.call(&"slot", &"rift_step").get(&"wipe"), 0.5, "rift step wipe = 3/6")
	h.check(not bool(bar.call(&"slot", &"rift_step").get(&"ready_now")), "rift step not ready on cooldown")
	h.near(bar.call(&"slot", &"anchor").get(&"wipe"), 0.5, "anchor wipe = 4/8")
	h.check(bool(bar.call(&"slot", &"anchor").get(&"active")), "anchor lit while attached")
	h.near(bar.call(&"slot", &"burst").get(&"wipe"), 0.0, "burst wipe = 0 when ready")
	h.check(bool(bar.call(&"slot", &"burst").get(&"ready_now")), "burst ready")
	h.near(bar.call(&"slot", &"missiles").get(&"wipe"), 0.5, "missile wipe = 7/14")
	h.check(int(bar.call(&"slot", &"missiles").get(&"lock_count")) == 5, "missile slot shows 5 locks")
	h.near(bar.call(&"slot", &"melee").get(&"charge"), 0.65, "saber slot shows the charge")
	h.check(bool(bar.call(&"slot", &"melee").get(&"active")), "saber slot lit mid-combo")
	# A skill whose component has not landed yet: greyed out, no crash.
	h.check(not bool(bar.call(&"slot", &"fins").get(&"ready_now")), "absent skill data greys the slot")
	h.near(bar.call(&"slot", &"fins").get(&"wipe"), 1.0, "absent skill data shows a full wipe")
	h.reset_state()
	await h.settle()
	h.near(bar.call(&"slot", &"rift_step").get(&"wipe"), 1.0,
			"a slot whose component vanished falls back to greyed-out")


static func _targets(h: HudTestHarness) -> void:
	var e := h.add_enemy(Vector3(0.0, 6.0, -60.0), {"marks": 2, "primed": true})
	var t := e.targetable()
	h.feed({"hard_target": t, "hard_distance": 120.0, "missile_painting": true, "missile_locks": 3})
	await h.settle(30)
	var reticle := h.widget(&"reticle")
	h.check(bool(reticle.get(&"has_target")), "reticle sees the hard lock")
	h.check(bool(reticle.get(&"in_range")), "120 m is inside the rifle's 200 m band")
	h.check(reticle.call(&"reticle_color") == HudPalette.DANGER, "in-range reticle is red (SPEC §5)")
	h.feed({"hard_distance": 400.0})
	await h.settle()
	h.check(not bool(reticle.get(&"in_range")), "400 m is outside the effective band")
	h.check(reticle.call(&"reticle_color").is_equal_approx(
			Color(HudPalette.WHITE.r, HudPalette.WHITE.g, HudPalette.WHITE.b, 0.6)),
			"out-of-range reticle is quiet white (look review item 6: no green in the HUD)")
	h.check(int(h.widget(&"markers").get(&"lock_count")) == 3, "paint box counts 3 locks")
	h.check(bool(h.widget(&"markers").get(&"painting")), "paint box shown while painting")
	var plates := h.widget(&"plates").get(&"plates") as Array
	h.check(plates.size() >= 1, "enemy plate raised for the locked target")
	if plates.size() >= 1:
		var st: Dictionary = plates[0]["state"]
		h.check(bool(st.get("primed", false)), "plate carries the PRIMED flag")
	h.check(h.widget(&"markers").visible, "markers visible with a hard lock")
	h.reset_state()
	await h.settle(30)
	h.check(not bool(reticle.get(&"has_target")), "lock released, reticle back to idle")


static func _boss_and_radar(h: HudTestHarness) -> void:
	h.data.set_boss({"name": "巢母 BROOD TITAN", "hp": 40000.0, "hp_max": 60000.0,
			"cores": [1.0, 0.5, 0.0], "phase": 2, "phases": 3,
			"stability": 3000.0, "stability_max": 9000.0})
	await h.settle()
	var boss := h.widget(&"boss_bar")
	h.check(boss.visible, "boss bar visible with boss data")
	h.check(int(boss.get(&"phase")) == 2, "boss bar shows phase 2")
	h.check((boss.get(&"cores") as PackedFloat32Array).size() == 3, "boss bar has 3 core segments")
	h.near(boss.get(&"ratio"), 40000.0 / 60000.0, "boss HP ratio")
	h.data.clear_boss()
	await h.settle()
	h.check(not boss.visible, "boss bar hides when the boss is gone")
	var blips := h.widget(&"radar").get(&"blips") as Array
	h.check(blips.size() >= 1, "radar shows the live enemy")
	if blips.size() >= 1:
		h.check(StringName(blips[0]["type"]) == &"mantis", "radar classifies the blip")
	# flow r2: a monster freed inside the 0.1 s scan window must not be read by the radar or the
	# plates — both used to call global_position on a freed instance. The prune is asserted through
	# the instance id, never by handing the freed object itself to `Array.has()` (hud r6 item 6: that
	# logs an engine ERROR the suite's own pass line then hides).
	var doomed := h.add_enemy(Vector3(0.0, 4.0, -30.0))
	h.data.enemies.append(doomed)
	var id := doomed.get_instance_id()
	h.check(_holds_id(h.data.enemies, id), "the doomed enemy is in the scan list to begin with")
	doomed.free()
	h.data.poll(0.001)
	h.check(not _holds_id(h.data.enemies, id), "a freed enemy is pruned from the scan list")
	h.check(not h.data.enemies.any(func(e: Variant) -> bool: return not is_instance_valid(e)),
			"no dangling instance is left in the enemy list")


## True when `list` still holds the live object with `id`. Untyped element, `is_instance_valid` first:
## a typed `Node3D` parameter rejects a freed instance before the guard can run.
static func _holds_id(list: Array[Node3D], id: int) -> bool:
	for e: Variant in list:
		if is_instance_valid(e) and (e as Object).get_instance_id() == id:
			return true
	return false


## hud r6 item 5 (mech-move Request 7): flight is a state the HUD has to say out loud.
## `hud_state()["state"]` is "fly" for the whole flight, and the reading is the seconds of EN left,
## measured from the falling gauge — flight pauses EN regen (SPEC §4), so the drop IS the cost.
static func _flight(h: HudTestHarness) -> void:
	var cue := h.widget(&"flight")
	h.check(cue != null, "the HUD carries a flight cue")
	if cue == null:
		return
	h.reset_state()
	h.feed({"state": "run"})
	await h.settle()
	h.check(not cue.visible, "on the ground there is no flight cue")
	# `inject` writes the snapshot the widget reads this frame; `feed` would only reach it after a poll,
	# and the point here is to step the gauge one frame at a time.
	h.data.inject({"state": "fly", "en": 1000.0, "en_max": 1000.0})
	cue.call(&"update_hud", 0.016)
	h.check(cue.visible, "the cue comes up the moment the mech flies")
	h.check(float(cue.get(&"seconds_left")) < 0.0, "no reading until the drain has been measured")
	h.check(String(cue.call(&"reading")) == "100%", "before the first sample the reading is the EN gauge")
	# One frame of the gauge falling is the whole measurement: 80 EN/s over a 16 ms frame.
	h.data.inject({"en": 1000.0 - 80.0 * 0.016})
	cue.call(&"update_hud", 0.016)
	h.near(float(cue.get(&"drain")), 80.0, "the cue measures the flight EN cost", 2.0)
	h.near(float(cue.get(&"seconds_left")), (1000.0 - 80.0 * 0.016) / 80.0,
			"the cue reads the seconds of flight left", 0.1)
	h.check(String(cue.call(&"reading")).ends_with(" s"), "the reading is in seconds")
	h.check(cue.call(&"color") == HudPalette.CYAN, "a full tank flies in cyan (palette: cyan is you)")
	h.check(cue.call(&"chrome_rect").size != Vector2.ZERO, "the cue claims its screen area from the plates")
	# 160 EN at the measured 80 EN/s is 2.0 s — inside the warning band.
	h.data.inject({"en": 160.0})
	cue.call(&"update_hud", (1000.0 - 80.0 * 0.016 - 160.0) / 80.0)
	h.near(float(cue.get(&"seconds_left")), 2.0, "the reading follows the gauge down", 0.05)
	h.check(cue.call(&"color") == HudPalette.AMBER, "under 2.5 s left the reading warns in amber")
	h.check(cue.call(&"label") != "" and not String(cue.call(&"label")).contains(" "),
			"the cue names the state in one language")
	for state: String in ["glide", "fall", "run", "idle"]:
		h.data.inject({"state": state})
		cue.call(&"update_hud", 0.016)
		h.check(not cue.visible, "state '%s' takes the flight cue down" % state)
	h.data.inject({"state": "fly", "en": 900.0})
	cue.call(&"update_hud", 0.016)
	h.check(cue.visible and float(cue.get(&"drain")) == 0.0,
			"a second flight measures its own cost instead of inheriting the last one")
	h.reset_state()


## boss r1: the boss publishes the plate itself, and the intro card is raised by `Events.boss_intro`.
static func _boss_card(h: HudTestHarness) -> void:

	var card := h.widget(&"boss_card")
	h.check(card != null, "the HUD carries a boss title card")
	h.check(not card.visible, "no card until the boss is introduced")
	Events.boss_intro.emit("巢母 BROOD TITAN", "PHASE 1")
	await h.settle()
	h.check(card.visible, "Events.boss_intro raises the card")
	h.check(String(card.get(&"title")) == "巢母 BROOD TITAN", "the card carries the boss name")
	card.call(&"update_hud", 2.6)
	h.check(not card.visible, "the card retires after 2.5 s")
	h.check((h.hud.get(&"glass") as HudGlassHud).widget(&"boss_card") == null,
			"the cinematic card is not painted on the canopy glass")

