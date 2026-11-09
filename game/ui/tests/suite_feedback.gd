class_name HudFeedbackSuite
extends RefCounted
## Combat feedback (brief §6): hit markers and callouts must appear on their event and time out again,
## damage numbers must merge and expire, and the style meter must rise, drop on damage and decay.


static func run(h: HudTestHarness) -> void:
	await _hit_markers(h)
	await _callouts(h)
	await _numbers(h)
	await _style(h)


static func _hit(h: HudTestHarness, amount: float, weak: bool = false, kill: bool = false) -> HitInfo:
	var info := HitInfo.make(amount, HitInfo.BEAM, h.player, &"beam_rifle")
	info.weak_point = weak
	info.final_amount = amount
	if h.enemies.is_empty():
		h.add_enemy(Vector3(0.0, 6.0, -60.0))
	var victim := h.enemies[0]
	info.position = victim.global_position
	if kill:
		Events.enemy_killed.emit(victim, info)
	else:
		Events.hit_landed.emit(info, victim)
	return info


static func _hit_markers(h: HudTestHarness) -> void:
	var marker := h.widget(&"hit_marker")
	await _hit(h, 250.0)
	h.check(marker.visible, "hit marker appears on a landed hit")
	h.check(StringName(marker.get(&"kind")) == &"normal", "ordinary hit = normal kind")
	h.check(marker.call(&"color") == HudPalette.WHITE, "ordinary hit marker is white")
	await h.settle(20)
	h.check(not marker.visible, "hit marker times out after 80 ms")
	await _hit(h, 900.0, true)
	h.check(StringName(marker.get(&"kind")) == &"weak", "weak-point hit = weak kind")
	h.check(marker.call(&"color") == HudPalette.AMBER, "weak-point marker is amber")
	await h.settle(40)
	await _hit(h, 1800.0, false, true)
	h.check(StringName(marker.get(&"kind")) == &"kill", "kill confirm = kill kind")
	h.check(marker.call(&"color") == HudPalette.DANGER, "kill confirm is red")
	h.near(marker.call(&"scale_factor"), 1.6, "kill marker starts on the scale pop", 0.05)
	await h.settle(50)
	h.check(not marker.visible, "kill marker times out after 250 ms")


static func _callouts(h: HudTestHarness) -> void:
	var co := h.widget(&"callouts")
	var info := HitInfo.make(50.0, HitInfo.MELEE, h.player, &"mantis_combo")
	Events.parry_success.emit(info, h.enemies[0] if not h.enemies.is_empty() else null)
	h.check(StringName(co.get(&"current")) == &"parry", "PARRY callout on a perfect parry")
	Events.perfect_dodge.emit(h.enemies[0] if not h.enemies.is_empty() else null)
	h.check(StringName(co.get(&"current")) == &"perfect", "PERFECT callout on a perfect dodge")
	h.feed({"jackpot": true})
	await h.settle()
	h.check(StringName(co.get(&"current")) == &"jackpot", "JACKPOT callout when the window opens")
	h.feed({"jackpot": false, "well_primed": true})
	await h.settle()
	h.feed({"well_primed": false})
	await h.settle()
	h.check(StringName(co.get(&"current")) == &"collapse", "COLLAPSE callout when a prime detonates")
	await h.settle(140)
	h.check(not co.visible, "callout times out after 0.9 s")
	h.reset_state()
	await h.settle()


static func _numbers(h: HudTestHarness) -> void:
	var nums := h.widget(&"numbers")
	await _hit(h, 120.0)
	await _hit(h, 80.0)
	h.check((nums.get(&"numbers") as Array).size() == 1, "two hits inside 150 ms merge into one number")
	if (nums.get(&"numbers") as Array).size() == 1:
		h.near(float((nums.get(&"numbers") as Array)[0]["value"]), 200.0, "merged value = 120 + 80")
	await h.settle(120)
	h.check((nums.get(&"numbers") as Array).is_empty(), "damage numbers expire after 0.7 s")
	h.check(not nums.visible, "damage-number widget hides once empty")


static func _style(h: HudTestHarness) -> void:
	var style := h.widget(&"style")
	style.call(&"set", &"points", 0.0)
	style.call(&"set", &"count", 0)
	for i in 5:
		style.call(&"credit", 30.0, StringName("move_%d" % i))
	h.near(float(style.get(&"points")), 150.0, "five varied moves earn 150 style points")
	h.check(int(style.get(&"count")) == 5, "combo counter follows the hits")
	h.check(String(style.call(&"rank_name")) == "C", "150 points = rank C")
	# A repeat of a move already in the last four earns 35 % (juice §8).
	var before := float(style.get(&"points"))
	style.call(&"credit", 100.0, &"move_4")
	h.near(float(style.get(&"points")) - before, 35.0, "repeated move earns 35 % of its worth")
	Events.player_damaged.emit(HitInfo.make(400.0, HitInfo.MELEE, null, &"mantis_combo"))
	h.check(int(style.get(&"count")) == 0, "taking damage resets the combo count")
	h.check(float(style.get(&"points")) <= 85.0, "taking damage drops two ranks")
	# Decay: the gauge must fall on its own, faster at a higher rank.
	style.call(&"set", &"points", 400.0)
	await h.settle(60)
	h.check(float(style.get(&"points")) < 400.0, "style meter decays over time")
	style.call(&"set", &"points", 0.0)
	style.call(&"set", &"count", 0)
	await h.settle()
