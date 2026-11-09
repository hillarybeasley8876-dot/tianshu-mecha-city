class_name HudAccessSuite
extends RefCounted
## Accessibility and wayfinding (lead notes + critic #12): the type floor, the shape-coded telegraphs
## and hit markers, the blocked-shot cue, vertical wayfinding on the radar, and the photosensitive /
## damage-number switches. Everything here is about what the player can READ, not how it animates.


static func run(h: HudTestHarness) -> void:
	await _type_scale(h)
	await _telegraphs(h)
	await _blocked_shot(h)
	await _layers(h)
	await _switches(h)


## No label may fall under 14 device px, whatever the window or the `hud_scale` setting (r1 MUST-FIX 1).
static func _type_scale(h: HudTestHarness) -> void:
	h.check(HudPalette.SIZE_TINY >= HudPalette.MIN_LABEL, "the smallest type constant clears the floor")
	await h.settle()
	h.check(HudPalette.ui_scale > 0.5, "the HUD applied a layout scale")
	h.check(float(HudPalette.fs(10)) * HudPalette.ui_scale >= float(HudPalette.MIN_LABEL) - 0.5,
			"a 10 px label still lands at 14 device px or more")
	var before := HudPalette.ui_scale
	Settings.set_value(&"hud_scale", 1.4)
	await h.settle()
	h.check(HudPalette.ui_scale > before, "hud_scale 1.4 grows the overlay")
	h.check(float(HudPalette.fs(HudPalette.SIZE_TINY)) * HudPalette.ui_scale >= 19.0,
			"hud_scale 1.4 scales the type with it")
	Settings.set_value(&"hud_scale", 0.8)
	await h.settle()
	h.check(float(HudPalette.fs(HudPalette.SIZE_TINY)) * HudPalette.ui_scale >= 13.9,
			"hud_scale 0.8 still keeps type at the 14 px floor")
	Settings.set_value(&"hud_scale", 1.0)
	await h.settle()


## Telegraphs are shapes first: a triangle means unblockable, a glint diamond parryable (critic #12),
## and the icon hangs off the enemy's plate rather than a fixed height that landed on its name bar
## (look review item 2).
static func _telegraphs(h: HudTestHarness) -> void:
	var tel := h.widget(&"telegraphs")
	h.check(tel != null, "the telegraph widget is in the HUD")
	var e := h.add_enemy(Vector3(0.0, 12.0, 0.0))
	tel.set(&"tells", {})
	Events.enemy_telegraph.emit(e, &"slam", &"unblockable")
	await h.settle()
	h.check(int(tel.call(&"tell_count")) == 1, "an unblockable telegraph raises an icon")
	var spec: Dictionary = tel.call(&"spec_for", &"unblockable")
	h.check((spec["col"] as Color) == HudPalette.DANGER, "unblockable is danger red")
	h.check(not spec.has("label"), "the in-combat caption is gone: shape plus colour is the code")
	h.check((tel.call(&"spec_for", &"parryable") as Dictionary)["col"] == HudPalette.WHITE,
			"parryable is white, not a colour-only cue")
	h.check(bool(tel.visible), "the icon is on screen while the windup runs")
	var at: Vector2 = tel.call(&"_icon_at", e)
	var plate: Rect2 = (h.widget(&"plates") as HudWidget).call(&"plate_rect", e)
	h.check(plate.size != Vector2.ZERO and at.y < plate.position.y,
			"the icon sits above the enemy's plate, never across its name and bars")
	tel.call(&"update_hud", 1.5)
	h.check(int(tel.call(&"tell_count")) == 0, "the icon expires with its windup")
	h.check(not tel.visible, "nothing is drawn once the windup is over")
	# The threat arrow for the same tell must carry the unblockable flag for its own shape.
	var mk := h.widget(&"markers")
	mk.set(&"threats", {})
	Events.enemy_telegraph.emit(e, &"slam", &"unblockable")
	await h.settle()
	h.check(bool((mk.get(&"threats") as Dictionary).values()[0]["unblockable"]),
			"the off-screen arrow knows the attack is unblockable")


## Scenery in front of the muzzle has to say so, or a blocked shot reads as a miss (lead notes).
static func _blocked_shot(h: HudTestHarness) -> void:
	h.reset_state()
	await h.settle()
	h.check(not bool(h.widget(&"reticle").get(&"blocked")), "clear line: no blocked cue")
	h.feed({"shot_blocked": true, "block_dist": 12.0})
	await h.settle()
	h.check(bool(h.widget(&"reticle").get(&"blocked")), "scenery in the way raises the blocked cue")
	h.near(float(h.widget(&"reticle").get(&"block_dist")), 12.0, "the cue carries the distance")
	h.reset_state()
	await h.settle()


## Vertical wayfinding: a blip above or below the player must be distinguishable on a flat disc. The
## threshold is now 25 m (look review item 7.4) — in a city stacked three layers deep, 12 m turned
## almost every blip into a hollow ring plus a chevron and the disc into a smear.
static func _layers(h: HudTestHarness) -> void:
	h.reset_state()
	var up := h.add_enemy(Vector3(20.0, 60.0, 20.0), {}, &"harrier")
	var level := h.add_enemy(Vector3(-20.0, 0.0, 20.0), {}, &"ripper")
	h.data._scan_world()
	await h.settle()
	var radar := h.widget(&"radar")
	var blips: Array = radar.get(&"blips")
	h.check(blips.size() >= 2, "both enemies reached the radar")
	var above := _blip_for(blips, up)
	var flat := _blip_for(blips, level)
	h.check(float(above["dy"]) > 0.0, "the harrier reads as above the player")
	h.check(float(above["layer"]) > 0.0, "an enemy off your level is shaded")
	h.check(absf(float(flat["dy"])) <= 25.0, "an enemy on your level is not shaded")


static func _blip_for(blips: Array, e: Node3D) -> Dictionary:
	for b: Dictionary in blips:
		if b["node"] == e:
			return b
	return {"dy": 0.0, "layer": 0.0}


## The two player switches the HUD owns a stake in: photosensitive silences its pulses, damage numbers
## can be turned off (SPEC §9).
static func _switches(h: HudTestHarness) -> void:
	var nums := h.widget(&"numbers")
	nums.set(&"numbers", [])
	Settings.set_value(&"damage_numbers", false)
	nums.call(&"spawn", 500.0, h.player.global_position, &"normal", 1)
	h.check((nums.get(&"numbers") as Array).is_empty(), "damage numbers obey the setting")
	Settings.set_value(&"damage_numbers", true)
	Settings.set_value(&"photosensitive", true)
	await h.settle()
	h.near(HudPalette.motion, 0.0, "photosensitive mode stops the HUD's motion")
	Settings.set_value(&"photosensitive", false)
	await h.settle()
	h.near(HudPalette.motion, 1.0, "motion comes back when the setting is off")
