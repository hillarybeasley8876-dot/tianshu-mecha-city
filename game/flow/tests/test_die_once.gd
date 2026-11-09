extends Node
## One `die` announces one death (lead brief flow-r5b item 3; mech-move r7b item 8, their Request 18).
##
## `FlowDebug.die` writes hp to 0 directly, because `--god` zeroes the damage in `PlayerMech` and the
## real path cannot land. It used to emit `Events.player_died` itself as well — and `MechDamage.sync()`
## emits on the next physics tick when it sees hp reach 0, so one debug death announced twice and the
## GAME_OVER page, the audio stinger and the flow's own respawn all ran twice. The announcement is the
## mech's: flow only writes the HP.
##
##   tools/godot.sh test res://flow/tests/test_die_once.gd
##
## Runs the REAL `PlayerMech` (so the real `MechDamage` latch is in the loop) with a `FlowDebug` beside
## it, in the core sandbox.

const SANDBOX := preload("res://core/sandbox/sandbox.tscn")
const PLAYER := preload("res://player/player_mech.tscn")
## Physics ticks to give the mech's own `sync()` after a `die`. It runs at the top of every tick, so
## one is enough; thirty proves nothing arrives late.
const SETTLE := 30

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _deaths: int = 0
var _player: PlayerMech = null
var _debug: FlowDebug = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := SANDBOX.instantiate() as Node3D
	add_child(world)
	Game.world = world
	_player = PLAYER.instantiate() as PlayerMech
	add_child(_player)
	_debug = FlowDebug.new()
	_debug.name = "FlowDebug"
	add_child(_debug)
	# No `--flow-script`, so the node arms nothing and runs no timeline of its own: the test drives
	# `_run` directly, which is the same entry point a scripted run uses.
	_debug.setup(null)
	Events.player_died.connect(func() -> void: _deaths += 1)
	await _step(SETTLE)
	_check("setup.alive", _player.is_alive(), "the mech did not come up alive")
	_check("setup.quiet", _deaths == 0, "%d deaths before the first die" % _deaths)

	_debug.call(&"_run", {"cmd": "die", "args": []})
	_check("die.hp", _player.hp <= 0.0, "die left the mech at %.0f HP" % _player.hp)
	_check("die.silent_on_the_spot", _deaths == 0,
			"die announced the death itself (%d emissions before the mech's own tick)" % _deaths)
	await _step(SETTLE)
	_check("die.once", _deaths == 1,
			"one die produced %d player_died emissions, want 1" % _deaths)
	_check("die.dead", not _player.is_alive(), "the mech is still alive after die")

	# The latch has to release on the revive, or the SECOND death of a run is never announced. This is
	# the revive `FlowProgress._restore_player` performs (set hp, then heal).
	_player.hp = _player.hp_max
	_player.heal(_player.hp_max)
	await _step(SETTLE)
	_check("revive.alive", _player.is_alive(), "the revive did not take")
	_check("revive.quiet", _deaths == 1, "the revive announced a death (%d)" % _deaths)
	_debug.call(&"_run", {"cmd": "die", "args": []})
	await _step(SETTLE)
	_check("die.again", _deaths == 2,
			"the second die produced %d emissions in total, want 2" % _deaths)
	_finish()


func _step(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


func _check(id: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failures.append("%s: %s" % [id, detail])


func _finish() -> void:
	print("TEST %d checks, %d failed" % [_checks, _failures.size()])
	for line in _failures:
		print("TEST FAIL ", line)
	print("PASS" if _failures.is_empty() else "FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)
