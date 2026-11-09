extends Node
## feel r5 item 1: a swarm kill must never freeze the world.
##   tools/godot.sh test res://fx/tests/test_swarm.gd
##
## Built like the acceptance probe (`acc_vfy_probe.gd`): the real core sandbox, the real
## FeelDirector, a real EnemySpawner with `auto_spawn = false`, `enemies/tests/dummy_player.gd` and
## a camera 14 m behind / 7 m above it. Kills go through `EnemyBase.take_hit` with a BALLISTIC
## HitInfo — the gatling's own path (`projectile_manager.gd` `_impact`) — and every rendered frame
## records `Engine.time_scale`.
##
## What it proves:
##   * rippers at gatling pace, in salvos and at 0.45 s: no rendered frame below 0.9, and every
##     victim holds its own wreck for 40 ms (+/- 1 physics tick) while vibrating, then collapses;
##   * 4 mantis 0.6 s apart: <= 1 global stop and <= 1 slow-mo (FEEL.md:43's budgets), the other
##     three victims hold 100 ms locally;
##   * 3 juggernauts 2.5 s apart: <= 1 slow-mo; a kill_large 150 m away: neither;
##   * a kill in witch time never ends the witch time, and a running slow-mo is never cut short;
##   * item 0's `last_stand` and `boss_kill` rows.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const DIRECTOR := "res://fx/feel_director.tscn"
const GROUND := Vector3(0.0, 2.0, 0.0)
const SMALL_HOLD := 0.04
const LARGE_HOLD := 0.1
## FEEL.md:43's budgets, as the director implements them.
const GLOBAL_BUDGET := 2.0
const SLOW_BUDGET := 6.0
## A freeze is a frame under this; the G stop runs at 0.05 and a slow-mo never goes below 0.2.
const FROZEN := 0.1
const SLOWED := 0.6

var _fails: int = 0
var _checks: int = 0
## One physics tick is the tolerance on a victim's hold, read from the host at run time
## (get_physics_process_delta_time) rather than assumed.
var _tick: float = 1.0 / 120.0
var _director: FeelDirector
var _spawner: EnemySpawner
var _player: DummyPlayer
var _cam: Camera3D
var _recording := false
var _min_scale := 1.0
var _freezes := 0
var _was_frozen := false
var _slows := 0
var _was_slow := false
var _rows: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _build()
	await _rippers("A 12 rippers at gatling pace (0.20 s)", 12, 0.20)
	await _salvos()
	await _rippers("C 8 rippers at 0.45 s", 8, 0.45)
	await _mantis()
	await _juggernauts()
	await _distant()
	await _witch_survives_a_kill()
	await _slow_mo_is_not_cut_short()
	await _last_stand()
	await _boss_kill()
	print("TEST feel swarm: %s (%d checks, %d failures)"
			% ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## The sandbox, the director, the camera, the spawner and the stand-in player — the probe's setup.
func _build() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	world.name = "World"
	add_child(world)
	Game.world = world
	var waited := 0
	while not Game.world_built() and waited < 60000:
		await get_tree().physics_frame
		waited += 1
	_director = (load(DIRECTOR) as PackedScene).instantiate() as FeelDirector
	add_child(_director)
	_director.event_played.connect(_on_played)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.global_position = GROUND + Vector3(0.0, 7.0, 14.0)
	_cam.look_at(GROUND + Vector3(0.0, 4.0, -30.0), Vector3.UP)
	_cam.make_current()
	_spawner = EnemySpawner.new()
	_spawner.auto_spawn = false
	add_child(_spawner)
	_player = DummyPlayer.new()
	_player.invulnerable = true
	add_child(_player)
	_player.global_position = GROUND
	Game.player = _player
	_tick = get_physics_process_delta_time()
	await _real_wait(0.5)


# --- rounds -------------------------------------------------------------------------------------

## N rippers killed one every `gap` seconds: the world never freezes, and every victim holds its
## own wreck for 40 ms while vibrating, then collapses.
func _rippers(label: String, count: int, gap: float) -> void:
	var pack := await _spawn_pack(&"ripper", count)
	await _begin()
	var holds: Array[int] = []
	var held_wreck := true
	var vibrated := true
	for e in pack:
		var t0 := Feel.real_now()
		var m := await _kill(e)
		holds.append(m.ticks)
		held_wreck = held_wreck and m.wreck_held
		vibrated = vibrated and m.vibrated
		await _gap(t0, gap)
	await _real_wait(0.5)
	_end()
	_ok(_min_scale >= 0.9, "%s: no rendered frame below 0.9 (min %.3f, %d kills)"
			% [label, _min_scale, holds.size()], "freezes=%d rows=%s" % [_freezes, str(_rows)])
	_ok(_all_hold(holds, SMALL_HOLD), "%s: every victim holds %.0f ms +/- 1 tick (%s)"
			% [label, SMALL_HOLD * 1000.0, _fmt(holds)])
	_ok(held_wreck, "%s: the wreck does not collapse during the hold" % label)
	_ok(vibrated, "%s: the victim vibrates while it is held" % label)
	await _clear(pack)


## Two salvos of six in a single frame, 0.30 s apart — the case the 0.05 s row cooldown used to
## swallow. Every one of the twelve still gets its own hold.
func _salvos() -> void:
	var pack := await _spawn_pack(&"ripper", 12)
	await _begin()
	var holds: Array[int] = []
	var held_wreck := true
	for salvo in 2:
		var t0 := Feel.real_now()
		for i in 6:
			var m := await _kill(pack[salvo * 6 + i])
			holds.append(m.ticks)
			held_wreck = held_wreck and m.wreck_held
		await _gap(t0, 0.30)
	await _real_wait(0.5)
	_end()
	_ok(_min_scale >= 0.9, "B two 6-in-a-frame salvos: no rendered frame below 0.9 (min %.3f)"
			% _min_scale, "freezes=%d rows=%s" % [_freezes, str(_rows)])
	_ok(_all_hold(holds, SMALL_HOLD), "B every one of the 12 salvos victims holds %.0f ms (%s)"
			% [SMALL_HOLD * 1000.0, _fmt(holds)])
	_ok(held_wreck, "B the salvos' wrecks do not collapse during the hold")
	await _clear(pack)


## 4 mantis 0.6 s apart: FEEL.md:43 allows one global stop per 2 s and one slow-mo per 6 s, so three
## of the four victims take their 100 ms locally instead.
func _mantis() -> void:
	var pack := await _spawn_pack(&"mantis", 4)
	await _begin()
	var holds: Array[int] = []
	for e in pack:
		var t0 := Feel.real_now()
		holds.append((await _kill(e)).ticks)
		await _gap(t0, 0.6)
	await _real_wait(0.5)
	_end()
	var without := 0
	for h in holds:
		if h == 0:
			without += 1
	_ok(_freezes <= 1, "D 4 mantis 0.6 s apart: %d global stop (<= 1 per %.0f s)"
			% [_freezes, GLOBAL_BUDGET])
	_ok(_slows <= 1, "D 4 mantis 0.6 s apart: %d slow-mo (<= 1 per %.0f s)" % [_slows, SLOW_BUDGET])
	_ok(without == _freezes,
			"D only the %d victim(s) that took the global stop have no local hold (%s)"
			% [_freezes, _fmt(holds)])
	_ok(_all_hold(holds, LARGE_HOLD), "D the other mantis victims hold %.0f ms +/- 1 tick (%s)"
			% [LARGE_HOLD * 1000.0, _fmt(holds)])
	await _clear(pack)


## 3 juggernauts 2.5 s apart: the 6 s slow-mo budget may only let one through.
func _juggernauts() -> void:
	var pack := await _spawn_pack(&"juggernaut", 3)
	await _begin()
	for e in pack:
		var t0 := Feel.real_now()
		await _kill(e)
		await _gap(t0, 2.5)
	await _real_wait(0.5)
	_end()
	_ok(_slows <= 1, "E 3 juggernauts 2.5 s apart: %d slow-mo (<= 1 per %.0f s)"
			% [_slows, SLOW_BUDGET])
	await _clear(pack)


## A kill_large past half its falloff is the victim's own stop and nothing else (lead decision).
func _distant() -> void:
	var at := GROUND + Vector3(0.0, 0.0, -140.0)
	var e := _spawner.spawn(&"mantis", EnemySpawner.face_towards(at, GROUND))
	if e == null:
		_ok(false, "F a kill_large 150 m away could not be spawned")
		return
	await _real_wait(0.6)
	var d := _cam.global_position.distance_to(e.global_position)
	var f := _director.falloff_factor(_director.event(&"kill_large"), e.global_position)
	await _begin()
	var hold: int = (await _kill(e)).ticks
	await _real_wait(0.6)
	_end()
	_ok(f < 0.5, "F the distant kill is past half its falloff (%.0f m, f %.2f)" % [d, f])
	_ok(_freezes == 0 and _slows == 0,
			"F a kill_large %.0f m away gives no global stop and no slow-mo (%d / %d)"
			% [d, _freezes, _slows])
	_ok(_holds(hold, LARGE_HOLD), "F the distant victim still holds %.0f ms locally (%s)"
			% [LARGE_HOLD * 1000.0, _fmt([hold])])
	await _clear([e] as Array[EnemyBase])


# --- clock and row checks ------------------------------------------------------------------------

## A kill during witch time must not end it: witch time is the player's window and has its own
## clock (core's combining slow_mo).
func _witch_survives_a_kill() -> void:
	var pack := await _spawn_pack(&"mantis", 1)
	_director.reset_rate_limits()
	await _real_wait(0.4)
	Feel.slow_mo(0.3, 1.0, 0.0, 0.0, true)
	await _real_wait(0.1)
	var alive_before := Feel.is_witch_time()
	await _kill(pack[0])
	var still := Feel.is_witch_time()
	var scale := Engine.time_scale
	await _real_wait(1.1)
	_ok(alive_before and still, "G a kill in witch time leaves witch time running (scale %.2f)"
			% scale, "witch before=%s after=%s" % [alive_before, still])
	_ok(not Feel.is_witch_time(), "G witch time still ends on its own clock")
	await _clear(pack)


## A running slow-mo keeps its own clock: the boss death's 0.2x / 1.2 s survives the kill_large that
## plays next to it (the old single clock cut it to 0.35 s).
func _slow_mo_is_not_cut_short() -> void:
	var pack := await _spawn_pack(&"mantis", 1)
	_director.reset_rate_limits()
	await _real_wait(0.4)
	var t0 := Feel.real_now()
	Feel.slow_mo(0.2, 1.2, 0.05, 0.4)
	await _real_wait(0.05)
	await _kill(pack[0])
	# 0.6 s in: the kill_large's own 0.35 s request ended at 0.40 s, so only the 1.2 s one is left and
	# it is still 0.6 s from its 0.4 s ease-out. On the old single clock it read 1.0x here.
	while Feel.real_now() - t0 < 0.6:
		await get_tree().process_frame
	var scale := Engine.time_scale
	while Feel.real_now() - t0 < 1.4:
		await get_tree().process_frame
	_ok(_near(scale, 0.2, 0.03),
			"H the 1.2 s slow-mo still runs at 0.2x 0.6 s in, after the kill_large's own ended (%.3f)"
			% scale)
	_ok(is_equal_approx(Engine.time_scale, 1.0), "H the world is back to 1.0x by 1.4 s (%.3f)"
			% Engine.time_scale)
	await _clear(pack)


## Item 0's `last_stand`: 0.5x held from 0.1 s to 1.3 s of real time, back to 1.0 by 1.6 s, and a
## second play inside the 60 s cooldown changes nothing.
func _last_stand() -> void:
	_director.reset_rate_limits()
	Engine.time_scale = 1.0
	await _real_wait(0.3)
	var t0 := Feel.real_now()
	Feel.play(&"last_stand", _player.global_position)
	var lo := 2.0
	var hi := 0.0
	while Feel.real_now() - t0 < 1.3:
		var e := Feel.real_now() - t0
		if e >= 0.1:
			lo = minf(lo, Engine.time_scale)
			hi = maxf(hi, Engine.time_scale)
		await get_tree().process_frame
	while Feel.real_now() - t0 < 1.6:
		await get_tree().process_frame
	var back := Engine.time_scale
	var second := _director.play(&"last_stand", _player.global_position)
	_ok(_near(lo, 0.5, 0.02) and _near(hi, 0.5, 0.02),
			"I last_stand holds 0.5x from 0.1 s to 1.3 s real (%.3f..%.3f)" % [lo, hi])
	_ok(is_equal_approx(back, 1.0), "I last_stand is back to 1.0x by 1.6 s (%.3f)" % back)
	_ok(not second, "I a second last_stand inside the 60 s cooldown changes nothing")


## Item 0's `boss_kill`: 0.5 s after a kill_large's global stop it still gets its own ~150 ms stop
## and holds 0.2x to 1.2 s — it is exempt from the kill budgets (lead Round 3).
func _boss_kill() -> void:
	var pack := await _spawn_pack(&"mantis", 2)
	_director.reset_rate_limits()
	await _real_wait(0.4)
	await _kill(pack[0])          # kill_large takes the global stop and the slow-mo budget
	await _real_wait(0.5)
	await _begin()
	var t0 := Feel.real_now()
	Feel.play(&"boss_kill", pack[1].global_position)
	while Feel.real_now() - t0 < 0.35:
		await get_tree().process_frame
	var freezes := _freezes
	var frozen_scale := _min_scale
	while Feel.real_now() - t0 < 1.0:
		await get_tree().process_frame
	var scale := Engine.time_scale
	_end()
	_ok(freezes == 1, "J boss_kill still gives one global stop after a kill_large's (%d, min %.2f)"
			% [freezes, frozen_scale])
	_ok(_near(scale, 0.2, 0.03), "J boss_kill holds 0.2x to 1.0 s (%.3f)" % scale)
	await _clear(pack)


# --- helpers ------------------------------------------------------------------------------------

## Spawns `count` of `type` in a loose grid 25-40 m in front of the camera and lets them settle.
func _spawn_pack(type: StringName, count: int) -> Array[EnemyBase]:
	var pack: Array[EnemyBase] = []
	for i in count:
		var at := GROUND + Vector3((float(i % 4) - 1.5) * 12.0, 0.0, -25.0 - floorf(float(i) / 4.0) * 8.0)
		var e := _spawner.spawn(type, EnemySpawner.face_towards(at, GROUND))
		if e != null:
			pack.append(e)
	await _real_wait(0.5)
	return pack


## Kills `e` the way the gatling does and measures the victim's own hold.
## `ticks` counts the physics ticks the enemy itself counted its pause down over (its `_pause_left`,
## not our loop, so the order of `physics_frame` against its `_physics_process` cannot skew it),
## `wreck_held` that `_dead_time` did not advance while it did, `vibrated` that the visual root moved.
func _kill(e: EnemyBase) -> Dictionary:
	var out := {"ticks": 0, "wreck_held": true, "vibrated": false}
	if not is_instance_valid(e) or not e.is_alive():
		return out
	var hit := HitInfo.make(e.hp_max * 3.0, HitInfo.BALLISTIC, _player, &"test_swarm")
	hit.hurtbox_part = &"body"
	e.take_hit(hit)
	var ticks := 0
	var left := float(e.get(&"_pause_left"))
	while left > 0.0 and ticks < 240:
		await get_tree().physics_frame
		var now := float(e.get(&"_pause_left"))
		if now < left:
			ticks += 1
		left = now
		if float(e.get(&"_dead_time")) > 0.0:
			out.wreck_held = false
		if e.model != null and not is_zero_approx(e.model.position.x):
			out.vibrated = true
	out.ticks = ticks
	return out


func _begin() -> void:
	_director.reset_rate_limits()
	await _real_wait(0.3)   # core's own 1 s hit-stop window is not reset, so let it drain
	_min_scale = 1.0
	_freezes = 0
	_was_frozen = false
	_slows = 0
	_was_slow = false
	_rows = {}
	_recording = true


func _end() -> void:
	_recording = false


func _clear(pack: Array[EnemyBase]) -> void:
	for e in pack:
		if is_instance_valid(e):
			e.queue_free()
	await _real_wait(0.6)


func _on_played(id: StringName, _at: Vector3, _s: float) -> void:
	if _recording:
		_rows[id] = int(_rows.get(id, 0)) + 1


func _process(delta: float) -> void:
	if not _recording:
		return
	var s := Engine.time_scale
	_min_scale = minf(_min_scale, s)
	var frozen := s < FROZEN
	if frozen and not _was_frozen:
		_freezes += 1
	_was_frozen = frozen
	var slow := s >= FROZEN and s < SLOWED
	if slow and not _was_slow:
		_slows += 1
	_was_slow = slow


## Waits until `gap` seconds have passed since `t0`, so a victim's own hold does not stretch the
## round's pace (the kills stay exactly `gap` apart, which is what the budgets are written against).
func _gap(t0: float, gap: float) -> void:
	await _real_wait(maxf(gap - (Feel.real_now() - t0), 0.0))


## Every measured hold is within one physics tick of `want`. A victim that took the global stop
## instead has no local hold and is skipped (the caller checks that count separately).
func _all_hold(holds: Array[int], want: float) -> bool:
	var seen := false
	for h in holds:
		if h == 0:
			continue
		seen = true
		if not _holds(h, want):
			return false
	return seen


func _holds(ticks: int, want: float) -> bool:
	return absi(ticks - roundi(want / _tick)) <= 1


func _near(v: float, want: float, tol: float = -1.0) -> bool:
	return absf(v - want) <= tol


func _fmt(holds: Array[int]) -> String:
	var ms: PackedStringArray = []
	for h in holds:
		ms.append("%.0f" % (float(h) * _tick * 1000.0))
	return ",".join(ms)


func _real_wait(seconds: float) -> void:
	var t0 := Feel.real_now()
	var guard := 0
	while Feel.real_now() - t0 < seconds and guard < 100000:
		await get_tree().process_frame
		guard += 1


func _ok(cond: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("PASS %s" % label)
		return
	_fails += 1
	print("FAIL %s %s" % [label, detail])
