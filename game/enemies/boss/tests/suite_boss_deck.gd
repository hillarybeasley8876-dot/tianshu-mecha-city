class_name BossDeckSuite
extends RefCounted
## The titan stays on its deck (flow r5 brief item 3). Every summon used to fling the beast 68-134 m
## in a single 1/120 s tick: the AddSpawner was the titan's own child, `EnemySpawner.spawn()` parents
## an add before it places it, so the new adds became the titan's floor for one step and Jolt then
## handed it their ring-point motion as platform velocity. `_stay_on_the_deck` clamped the radius and
## never the height, so a fling that went down far enough left the beast under the Crown for good.
##
## The gate is a per-tick tracker: no tick may move the titan more than `MAX_STEP` metres beyond its
## own walk, over 20 forced summons and a checkpoint restore, and it must still be on the deck after.

## m a single physics tick may move the titan. Measured: its walk, its stagger slide and its own
## knockbacks all stay under 0.9 m, and the fling this suite exists for was 68-150 m.
const MAX_STEP := 3.0
const SUMMONS := 20
const SUMMON_GAP := 0.35         ## s between forced summons
## s of tracking after the restore, and how far the titan may sit from the deck under it.
const AFTER_RESTORE := 8.0
const DECK_BAND := 20.0


## Samples a node's position every physics tick and keeps the largest single-tick move, so a one-frame
## teleport cannot hide between two samples.
class Tracker:
	extends Node

	var worst: float = 0.0
	var clamps: int = 0
	var titan: BroodTitan = null

	var _was: Vector3 = Vector3.ZERO
	var _clamps: int = 0

	func _ready() -> void:
		if titan != null:
			_was = titan.global_position
			_clamps = _clamp_count()

	func _physics_process(_delta: float) -> void:
		if titan == null or not is_instance_valid(titan):
			return
		var now := titan.global_position
		# A tick the deck clamp corrected is a deliberate teleport, not the physics flinging the beast.
		var clamps_now := _clamp_count()
		if clamps_now != _clamps:
			_clamps = clamps_now
			clamps += 1
		else:
			worst = maxf(worst, now.distance_to(_was))
		_was = now

	## `clamp_moves` is the titan's own counter; a build without it simply never reports a correction,
	## so the tracker still measures every tick.
	func _clamp_count() -> int:
		var raw: Variant = titan.get(&"clamp_moves")
		return int(raw) if raw != null else 0


static var _control_worst: float = 0.0


static func run(h: BossTestHarness) -> void:
	h.reset_titan()
	h.player.global_position = h.arena.ring_point(0.25, 0.55, 2.0)
	# One second of settle first: `reset_titan` teleports the beast, and the first `move_and_slide`
	# after a teleport resolves the overlap it lands in. That is a placement artefact, not a fling.
	await h.step(1.0)
	await _control(h)
	await _summons(h)
	await _restore(h)


## The same tracking with no summon at all: whatever the fight does on its own is the baseline the
## summon test has to be read against.
static func _control(h: BossTestHarness) -> void:
	var spawner := h.titan.spawner()
	if spawner != null:
		spawner.clear()
	var tracker := _watch(h)
	await h.step(SUMMONS * SUMMON_GAP)
	_control_worst = tracker.worst
	print("DECKTRACK control (no summon): worst single tick %.2f m, %d clamp corrections"
			% [tracker.worst, tracker.clamps])
	h.check("deck.control_step", tracker.worst <= MAX_STEP,
			"the fight on its own moved the titan %.2f m in one tick (limit %.2f)"
			% [tracker.worst, MAX_STEP])
	tracker.queue_free()


## 20 forced summons with the adds cleared between them: each one spawns six rippers and two harriers,
## which is exactly the beat that flung the titan.
static func _summons(h: BossTestHarness) -> void:
	var tracker := _watch(h)
	for i in SUMMONS:
		var spawner := h.titan.spawner()
		if spawner != null:
			spawner.clear()
		await h.frame()
		BossCombat.summon(h.titan)
		await h.step(SUMMON_GAP)
	print("DECKTRACK %d summons: worst single tick %.2f m, %d clamp corrections, titan at y %.1f (deck %.1f)"
			% [SUMMONS, tracker.worst, tracker.clamps, h.titan.global_position.y,
			h.arena.floor_y_at(h.titan.global_position)])
	h.check("deck.summon_step", tracker.worst <= MAX_STEP,
			"a summon moved the titan %.1f m in one tick (limit %.1f)" % [tracker.worst, MAX_STEP])
	h.check("deck.summon_vs_control", tracker.worst <= _control_worst + 0.5,
			"a summon moved the titan %.2f m in a tick where the fight alone moves it %.2f"
			% [tracker.worst, _control_worst])
	h.check("deck.summon_alive", h.titan.is_alive(), "the titan died during the summon test")
	h.check("deck.summon_on_deck", _on_the_deck(h),
			"after %d summons the titan is at y %.0f, the deck under it is %.0f"
			% [SUMMONS, h.titan.global_position.y,
			h.arena.floor_y_at(h.titan.global_position)])
	tracker.queue_free()


## A checkpoint restore puts the beast back on a deck ring point, and it stays there.
static func _restore(h: BossTestHarness) -> void:
	h.titan.restore_for_checkpoint(2)
	await h.frame()
	h.check("deck.restore_height", _on_the_deck(h),
			"the restore left the titan at y %.0f, the deck under it is %.0f"
			% [h.titan.global_position.y, h.arena.floor_y_at(h.titan.global_position)])
	var tracker := _watch(h)
	await h.step(AFTER_RESTORE)
	print("DECKTRACK %.0f s after the restore: worst single tick %.2f m, %d clamp corrections, titan at y %.1f (deck %.1f)"
			% [AFTER_RESTORE, tracker.worst, tracker.clamps, h.titan.global_position.y,
			h.arena.floor_y_at(h.titan.global_position)])
	h.check("deck.restore_step", tracker.worst <= MAX_STEP,
			"after the restore a tick moved the titan %.1f m (limit %.1f)"
			% [tracker.worst, MAX_STEP])
	h.check("deck.settled", _on_the_deck(h),
			"%.0f s after the restore the titan is at y %.0f, the deck is %.0f"
			% [AFTER_RESTORE, h.titan.global_position.y,
			h.arena.floor_y_at(h.titan.global_position)])
	var out := h.titan.global_position - h.arena.global_position
	out.y = 0.0
	h.check("deck.radius", out.length() <= BossTuning.DECK_RADIUS - BossTuning.RADIUS + 1.0,
			"the titan is %.0f m from the Crown centre, the rim is at %.0f"
			% [out.length(), BossTuning.DECK_RADIUS - BossTuning.RADIUS])
	tracker.queue_free()


static func _on_the_deck(h: BossTestHarness) -> bool:
	return absf(h.titan.global_position.y - h.arena.floor_y_at(h.titan.global_position)) < DECK_BAND


static func _watch(h: BossTestHarness) -> Tracker:
	var tracker := Tracker.new()
	tracker.name = "TitanTracker"
	tracker.titan = h.titan
	h.world.add_child(tracker)
	return tracker
