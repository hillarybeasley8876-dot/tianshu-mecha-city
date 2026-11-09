class_name BossPresentationSuite
extends RefCounted
## The boss unit's presentation and integration checks (lead review r2): the skyline walker stays out
## of free play, the titan answers the camera's large-target framing contract, the Crown rim breaks
## through the `&"crown_rim_segment"` group whoever built it, the intro raises the title card, and the
## death beat topples the body over the rim instead of dissolving it.

const SETTLE := 0.25


static func run(h: BossTestHarness) -> void:
	_walker_gate(h)
	_framing(h)
	await _rim_segments(h)
	await _intro_title(h)
	await _death_topple(h)


## CONTRACTS §2: `--sandbox` is FREE PLAY — a unit test on the grey box has no titan on the horizon,
## unless flow or the boss test asked for one.
static func _walker_gate(h: BossTestHarness) -> void:
	h.check("walker.sandbox_free", not BossDirector.walker_wanted(true, false, false),
			"the skyline walker spawned in a plain --sandbox run")
	h.check("walker.sandbox_flow", BossDirector.walker_wanted(true, true, false),
			"--sandbox --flow lost the skyline walker")
	h.check("walker.sandbox_boss_test", BossDirector.walker_wanted(true, false, true),
			"--sandbox --boss-test lost the skyline walker")
	h.check("walker.city", BossDirector.walker_wanted(false, false, false),
			"the real map has no skyline walker")


## CONTRACTS §5: the rig reads `framing_height()` off the hard-locked actor and, at ≥ 30 m, lengthens
## its arm and raises its pitch so the hero and the titan's head share the frame.
static func _framing(h: BossTestHarness) -> void:
	h.reset_titan()
	var t := h.titan
	h.check("framing.has", t.has_method(&"framing_height"),
			"BroodTitan does not implement framing_height()")
	var got: float = t.call(&"framing_height")
	h.near("framing.height", got, BossTuning.HEIGHT, 0.01)
	h.check("framing.over_30", got >= 30.0, "framing height %.1f is below the contract's 30 m" % got)


## CONTRACTS §6: the Crown rim is a group of segments with a bearing meta, and phase 2 breaks some of
## them for real — collision off, mesh tipped away.
static func _rim_segments(h: BossTestHarness) -> void:
	h.reset_titan()
	var arena := h.arena
	var tagged := 0
	for body: Node3D in arena.segments:
		if body.is_in_group(BossArena.RIM_GROUP) and body.has_meta(&"angle_deg"):
			tagged += 1
	h.check("rim.group", tagged == arena.segments.size(),
			"%d of %d rim segments are in %s with a bearing" % [tagged, arena.segments.size(),
			BossArena.RIM_GROUP])
	var before := arena.broken_segments.size()
	var taken := arena.break_segments()
	h.check("rim.broke", taken.size() == BossTuning.RIM_SEGMENTS_BROKEN,
			"phase 2 broke %d wedges, wanted %d" % [taken.size(), BossTuning.RIM_SEGMENTS_BROKEN])
	h.check("rim.tracked", arena.broken_segments.size() == before + taken.size(),
			"broken_segments did not record the break")
	var body := arena.segments[taken[0]]
	var shape := _shape_of(body)
	h.check("rim.collision_off", shape != null and shape.disabled,
			"the broken wedge still collides, so the hole is a lie")
	await h.step(1.8)
	h.check("rim.fell", body.position.y < -20.0,
			"the broken wedge is still at y %.1f" % body.position.y)
	arena.restore_segments()
	h.check("rim.restored", arena.broken_segments.is_empty(),
			"the checkpoint did not put the rim back")
	h.check("rim.collision_on", shape != null and not shape.disabled,
			"the restored wedge has no collision")


static func _shape_of(body: Node3D) -> CollisionShape3D:
	for child in body.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


## CONTRACTS §6: the intro roar raises `Events.boss_intro(title, subtitle)` — the HUD draws the card,
## audio plays the stinger. The director owns the beat, so the harness calls the beat it owns.
static func _intro_title(h: BossTestHarness) -> void:
	h.reset_titan()
	var seen: Array = []
	var spy := func(title: String, subtitle: String) -> void: seen.append([title, subtitle])
	Events.boss_intro.connect(spy)
	var director := BossDirector.new()
	director.name = "BossDirector"
	director.arena = h.arena
	director.fight_started = true
	director.titan = h.titan
	h.root.add_child(director)
	director.announce()
	await h.step(SETTLE)
	Events.boss_intro.disconnect(spy)
	director.queue_free()
	h.check("intro.emitted", seen.size() == 1, "boss_intro fired %d times" % seen.size())
	if seen.size() == 1:
		var row: Array = seen[0]
		h.check("intro.title", String(row[0]) == BossTuning.DISPLAY_NAME,
				"the card reads '%s'" % String(row[0]))
		h.check("intro.subtitle", String(row[1]) != "", "the card has no subtitle")


## Lead r2: no generic dissolve. The corpse is tilted over the rim, has left the deck, and the edge
## is smoking by the end of the topple.
static func _death_topple(h: BossTestHarness) -> void:
	h.reset_titan()
	var t := h.titan
	var start := t.global_position
	var arena_y := h.arena.global_position.y
	t.hp = 500.0
	h.hit_titan(2000.0)
	h.check("topple.started", not t.is_alive(), "the titan survived the killing blow")
	# The killing blow's 0.2x slow-mo runs the whole beat on the scaled clock, so the suite polls the
	# beat's own progress instead of guessing real seconds.
	var waited := 0.0
	while waited < 8.0 and float(t.collapse_state()["progress"]) < 0.5:
		await h.step(0.1)
		waited += 0.1
	var mid: Dictionary = t.collapse_state()
	h.check("topple.midway", float(mid["progress"]) >= 0.5,
			"the topple only reached %.2f after %.1f real s" % [float(mid["progress"]), waited])
	var tilted: float = absf(t.model.rotation_degrees.x) if t.model != null else 0.0
	h.check("topple.tilting", tilted > 5.0,
			"the body is still upright (%.1f°) halfway through the topple" % tilted)
	h.check("topple.blast_chain", int(mid["blasts"]) >= BossTuning.COLLAPSE_BLASTS / 2,
			"only %d of %d blasts had fired by the halfway point" % [int(mid["blasts"]),
			BossTuning.COLLAPSE_BLASTS])
	while waited < 14.0 and float(t.collapse_state()["progress"]) < 1.0:
		await h.step(0.1)
		waited += 0.1
	h.check("topple.all_blasts", int(t.collapse_state()["blasts"]) == BossTuning.COLLAPSE_BLASTS,
			"the chain fired %d of %d blasts" % [int(t.collapse_state()["blasts"]),
			BossTuning.COLLAPSE_BLASTS])
	var fell := absf(t.model.rotation_degrees.x) if t.model != null else 0.0
	h.near("topple.angle", fell, BossTuning.COLLAPSE_FALL_DEG, 6.0)
	var out := t.global_position - start
	out.y = 0.0
	h.check("topple.outward", out.length() > 20.0,
			"the corpse moved %.1f m outward, so it fell on the deck, not over the rim" % out.length())
	h.check("topple.below_deck", t.global_position.y < arena_y - 20.0,
			"the corpse is at %.1f, still above the deck at %.1f" % [t.global_position.y, arena_y])
	h.check("topple.no_dissolve", t.model != null and t.model.visible,
			"the boss dissolved instead of falling")
