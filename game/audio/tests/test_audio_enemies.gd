extends Node
## Enemy sound routing: every archetype reaches a telegraph tell and a death cry, the boss/large
## split reads the archetype id, and the ids the enemies unit calls directly actually sound.
##
## reviews/audio-r5.md: the router classified every enemy as unknown because it looked for
## `type_id` / `archetype` / `type` while EnemyBase declares `enemy_type`. That silently muted the
## per-archetype telegraph tells and the boss/large split for the whole game.
##
## Runnable on its own (`tools/godot.sh test res://audio/tests/test_audio_enemies.gd`) and run by
## test_audio.gd, whose failure count it adds to.

const ARCHETYPES: Array[StringName] = [&"ripper", &"mantis", &"spitter", &"harrier",
		&"juggernaut", &"titan"]
## Ids other units pass to Audio directly, with no Events signal behind them.
const DIRECT_IDS: Array[StringName] = [&"juggernaut_slam", &"juggernaut_plate_break",
		&"core_rupture", &"telegraph_unblockable"]

var fails: int = 0


func _ready() -> void:
	if get_parent() != get_tree().root:
		return   # driven by test_audio.gd
	await get_tree().process_frame
	await run_checks()
	print("TEST audio enemies: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


## Returns the failure count so a parent suite can add it (test_audio.gd).
func run_checks() -> int:
	_routing()
	await _direct_ids_sound()
	return fails


func _check(ok: bool, msg: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		fails += 1


func _routing() -> void:
	var router := Audio.router
	var no_tell: Array[StringName] = []
	var no_death: Array[StringName] = []
	for type_id in ARCHETYPES:
		var fake := _FakeEnemy.new()
		fake.enemy_type = type_id
		if router.enemy_type(fake) != type_id:
			no_tell.append(type_id)
			no_death.append(type_id)
		else:
			if not Audio.events.has(router.telegraph_sound(type_id)):
				no_tell.append(type_id)
			if not Audio.events.has(router.death_sound(type_id)):
				no_death.append(type_id)
		fake.free()
	_check(no_tell.is_empty(), "every archetype has a telegraph tell (%s)" % [no_tell])
	_check(no_death.is_empty(), "every archetype has a death cry (%s)" % [no_death])
	_check(_classify(&"titan", true) and _classify(&"juggernaut", false),
			"a titan reads as boss and a juggernaut does not")
	_check(not _classify(&"ripper", true) and not _classify(&"ripper", false),
			"a ripper is neither boss nor large")
	var unresolved: Array[StringName] = []
	for id in DIRECT_IDS:
		if Audio.resolve(id) == null:
			unresolved.append(id)
	_check(unresolved.is_empty(), "the ids other units call directly resolve (%s)" % [unresolved])


## Resolving is not enough: the id has to start a voice. `juggernaut_plate_break` and
## `juggernaut_slam` have no Events signal behind them, so a broken alias would leave them silent
## with nothing else in the suite noticing.
func _direct_ids_sound() -> void:
	Audio.stop_all()
	await get_tree().process_frame
	var silent: Array[StringName] = []
	for id in DIRECT_IDS:
		var event: SoundEvent = Audio.resolve(id)
		Audio.play(id, Vector3.ZERO)
		await get_tree().process_frame
		if Audio.pool.active_count(event.id) < 1:
			silent.append(id)
		Audio.stop_all()
		await get_tree().process_frame
	_check(silent.is_empty(), "every directly-called enemy id starts a voice (%s)" % [silent])
	Audio.stop_all()


## is_boss (boss=true) or is_large (boss=false) for a stand-in carrying this archetype id.
func _classify(type_id: StringName, boss: bool) -> bool:
	var node := _FakeEnemy.new()
	node.enemy_type = type_id
	var answer: bool = Audio.router.is_boss(node) if boss else Audio.router.is_large(node)
	node.free()
	return answer


class _FakeEnemy:
	extends Node3D
	var enemy_type: StringName = &"ripper"
