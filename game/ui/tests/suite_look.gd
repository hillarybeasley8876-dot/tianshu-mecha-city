class_name HudLookSuite
extends RefCounted
## The look round (reviews/look/hud.md, 2026-11-02): the frame the user called "有点垃圾" was not
## missing features, it was features fighting each other — two lock brackets for one target, five
## plates stacked on the chrome, a 200 px gauge ring through the lock box, and every widget at 100 %.
## These checks pin the fixes so a later tune cannot quietly put them back.


static func run(h: HudTestHarness) -> void:
	await _one_lock_mark(h)
	await _gauges(h)
	await _plates(h)
	await _attention(h)
	await _chrome(h)


## Look review item 1: a soft-lock bracket used to be drawn at the SCREEN CENTRE while the hard-lock
## diamond sat on the target 90 px away, so one enemy read as two.
static func _one_lock_mark(h: HudTestHarness) -> void:
	h.reset_state()
	var e := h.add_enemy(Vector3(0.0, 6.0, -60.0))
	var t := e.targetable()
	h.feed({"soft_target": t, "soft_distance": 60.0})
	await h.settle()
	var reticle := h.widget(&"reticle")
	var at: Vector2 = reticle.get(&"soft_lock_at")
	h.check(at != Vector2.INF, "a soft lock is marked on the target, not on the crosshair")
	h.check(at != reticle.call(&"screen_center"),
			"the soft-lock bracket is at the target, not at the screen centre")
	h.feed({"hard_target": t, "hard_distance": 60.0})
	await h.settle()
	h.check((reticle.get(&"soft_lock_at") as Vector2) == Vector2.INF,
			"with a hard lock up the reticle draws no second bracket (look review item 1)")


## Look review item 5: 98 px, 7 px wide, 120°, always-on HEAT. The arcs now hug the reticle, the heat
## gauge only appears when the barrel is actually hot, and EN fades once it has sat full.
static func _gauges(h: HudTestHarness) -> void:
	h.reset_state()
	h.feed({"weapon": "beam_rifle", "en": 1000.0, "en_max": 1000.0, "heat": 0.0, "overheated": false})
	await h.settle()
	var reticle := h.widget(&"reticle")
	h.check(not bool(reticle.get(&"heat_shown")), "an empty rifle draws no gatling heat arc")
	h.check(float(reticle.get(&"ARC_RADIUS")) <= 70.0, "the gauges hug the reticle, not a 200 px ring")
	h.feed({"heat": 0.4})
	await h.settle()
	h.check(bool(reticle.get(&"heat_shown")), "a hot barrel brings the heat arc back")
	h.feed({"weapon": "gatling"})
	await h.settle()
	h.check(bool(reticle.get(&"heat_shown")), "the gatling always shows its heat")
	# EN fades once it has been full and unspent, and comes straight back on any spend.
	h.feed({"weapon": "beam_rifle", "en": 1000.0})
	await h.settle(3)
	reticle.call(&"_tick_en", 2.0)
	h.check(float(reticle.get(&"en_alpha")) < 0.9, "full, unspent EN fades out of the way")
	h.feed({"en": 400.0})
	await h.settle(3)
	h.check(float(reticle.get(&"en_alpha")) > 0.9, "spending EN brings the arc straight back")


## Look review item 10: a full plate is EARNED (lock, or an elite), never more than three of them, and
## a plate may not land on the chrome, on another plate or on the reticle. Six enemies are put where
## the chrome is, which is what the user's screenshot had.
static func _plates(h: HudTestHarness) -> void:
	h.reset_state()
	var plates := h.widget(&"plates")
	var chrome := _chrome_rects(h)
	var placed: Array[Rect2] = []
	for r in chrome:
		placed.append(r)
	# Six enemies across the frame: two of them are the locked pair, four are ordinary swarmers.
	var locked: HudFakeActor = null
	for i in 6:
		var at := Vector3(-30.0 + float(i) * 12.0, 6.0, -50.0 - float(i) * 4.0)
		var e := h.add_enemy(at)
		if i == 0:
			locked = e
	h.feed({"hard_target": locked.targetable(), "hard_distance": 50.0})
	await h.settle()
	var drawn: Array = plates.get(&"plates") as Array
	h.check(drawn.size() <= 3, "at most three full plates, however many enemies are in view")
	h.check(not (plates.get(&"avoid") as Array).is_empty(),
			"the chrome hands its rects to the plates")
	var s: Vector2 = plates.call(&"screen_size")
	var safe := s * 0.05
	var inside := true
	var apart := true
	var clear := true
	for i in drawn.size():
		var rect := drawn[i]["rect"] as Rect2
		if rect.position.x < safe.x or rect.position.y < safe.y \
				or rect.end.x > s.x - safe.x or rect.end.y > s.y - safe.y:
			inside = false
		for j in range(i + 1, drawn.size()):
			if rect.intersects(drawn[j]["rect"] as Rect2):
				apart = false
		for r in placed:
			if rect.grow(4.0).intersects(r):
				clear = false
	h.check(inside, "no plate leaves the safe rect inset 5 % from the screen edges")
	h.check(apart, "no two plates overlap")
	h.check(clear, "no plate lands on the chrome")
	# A swarmer nobody has shot gets no readout at all; shooting it raises a sliver for three seconds.
	h.data._scan_world()
	await h.settle()
	var plain := h.enemies[h.enemies.size() - 1]
	h.check((plates.get(&"plates") as Array).size() <= 3, "plain swarmers do not get plates")
	Events.hit_landed.emit(_hit_on(plain), plain)
	await h.settle()
	h.check(not (plates.get(&"slivers") as Array).is_empty(),
			"shooting a swarmer raises its HP sliver (look review item 10.2)")


## Look review item 9: everything used to sit at 100 %, so nothing read as urgent. A widget whose
## numbers have not moved settles to its rest alpha and pops back on any change.
static func _attention(h: HudTestHarness) -> void:
	h.reset_state()
	h.feed({"hp": 9000.0, "hp_max": 10000.0})
	var hp := h.widget(&"hp")
	await h.settle(3)
	for i in 220:
		hp.call(&"_tick_attention", 0.05)
	h.check(hp.modulate.a < 0.9, "a healthy armour bar settles out of the way")
	h.feed({"hp": 2000.0})
	await h.settle(3)
	for i in 3:
		hp.call(&"_tick_attention", 0.05)
	h.check(hp.modulate.a > 0.9, "a change pops the widget back to full strength")
	h.feed({"hp": 9000.0})
	await h.settle(3)
	for i in 220:
		hp.call(&"_tick_attention", 0.05)
	h.check(bool(hp.call(&"urgent")) == false, "full armour is not urgent")
	h.feed({"hp": 1000.0})
	await h.settle(3)
	h.check(bool(hp.call(&"urgent")), "low armour keeps the bar lit whatever else happens")
	h.reset_state()
	await h.settle(3)


## The reticle is what the player is looking at, so it never fades (item 9); and the style meter only
## appears once a combo is actually running (item 9.2).
static func _chrome(h: HudTestHarness) -> void:
	h.reset_state()
	var reticle := h.widget(&"reticle")
	await h.settle(3)
	for i in 200:
		reticle.call(&"_tick_attention", 0.05)
	h.check(is_equal_approx(reticle.modulate.a, 1.0), "the reticle never fades out")
	var style := h.widget(&"style")
	style.set(&"points", 40.0)
	await h.settle(3)
	h.check(not style.visible, "the style meter stays hidden at rank D")
	style.call(&"credit", 300.0, &"rifle")
	await h.settle(3)
	h.check(style.visible, "the meter appears once the player starts a combo")


static func _chrome_rects(h: HudTestHarness) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for key: StringName in h.hud.call(&"widget_keys"):
		var w := h.widget(key)
		if w == null or not w.visible:
			continue
		var r := w.chrome_rect()
		if r.size != Vector2.ZERO:
			out.append(r)
	return out


static func _hit_on(target: Node) -> HitInfo:
	var hit := HitInfo.new()
	hit.final_amount = 120.0
	hit.weapon = &"beam_rifle"
	hit.position = (target as Node3D).global_position
	hit.source = Game.player
	return hit
