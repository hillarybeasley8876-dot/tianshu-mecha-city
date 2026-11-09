class_name BossPlate
extends RefCounted
## The Brood Titan's HUD plate (boss unit). CONTRACTS §6: a node in group `&"boss"` implements
## `hud_state()` with name, hp, hp_max, phase and one entry per core — that is this file, kept out of
## `BroodTitan` so the actor stays inside the folder's 400-line rule.
##
## It also owns the push: while the HUD does not poll the boss, the titan hands it a new plate
## whenever the pool has moved by a visible amount.

## Last pool value handed to the HUD, so a 150k bar is not rebuilt every frame for 3 HP of chip.
static var _last_pushed: float = 0.0


static func plate(titan: BroodTitan) -> Dictionary:
	var core_states: Array[Dictionary] = []
	var core_ratios: Array[float] = []
	for core: BossCore in titan.cores:
		core_states.append(core.hud_state())
		core_ratios.append(core.ratio())
	return {
		"name": BossTuning.DISPLAY_NAME, "type": titan.enemy_type,
		"hp": titan.hp, "hp_max": titan.hp_max, "phase": titan.phase,
		"phases": BossTuning.PHASE_COUNT,
		"stability": titan.status.stability, "stability_max": titan.status.stability_max,
		"staggered": titan.status.is_staggered(), "cores": core_ratios,
		"core_states": core_states, "alive": titan.alive,
	}


static func push(titan: BroodTitan) -> void:
	if absf(titan.hp - _last_pushed) < titan.hp_max * 0.002:
		return
	_last_pushed = titan.hp
	var hud := Game.hud
	if hud == null or not is_instance_valid(hud) or not (&"data" in hud):
		return
	var data: Variant = hud.get(&"data")
	if data != null and data.has_method(&"set_boss"):
		data.call(&"set_boss", plate(titan))


## A restored boss is a full pool again: forget the last plate so the bar jumps back with it.
static func reset() -> void:
	_last_pushed = 0.0
