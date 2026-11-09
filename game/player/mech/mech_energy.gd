class_name MechEnergy
extends RefCounted
## EN gauge and Overdrive meter of the hero mech (SPEC §4, skills-catalog §4.1). Owned by PlayerMech;
## components spend through `PlayerMech.consume_energy`.
## EN: 1,000 max. Ground regen 500/s once 0.6 s passed without spending, air regen 120/s after 0.9 s,
## and regen keeps running during the (free) ground boost. Hitting 0 is an **Outage**: a 1.5 s lockout
## with no regen, then an instant +250; dash and ascend stay blocked until 300 EN is back. Flight pauses
## regen entirely. OD: 0-100 %, no gain while the Overdrive is running (the skills unit activates it).
##
## Clock (CONTRACTS §3): EN and OD are player-clock meters, so `tick()` takes `Feel.player_delta` and
## every per-second cost is charged on `MechLocomotion.pdelta`, not on the real movement clock —
## otherwise a global hit-stop would drain the gauge at full speed while the regen behind it froze.

signal depleted()

var tuning: MechTuning
var energy: float = 0.0
var energy_max: float = 1000.0
var overdrive: float = 0.0
var overdrive_active: bool = false

var _idle_t: float = 0.0        ## seconds since the last spend (drives the regen delay)
var _outage_pause: float = 0.0  ## seconds left of the post-zero lockout
var _restart_locked: bool = false  ## dash / ascend blocked until `outage_restart` EN is back


func _init(t: MechTuning) -> void:
	tuning = t
	energy_max = t.energy_max
	energy = energy_max


## True while the mech is locked out of every EN cost.
func is_outage() -> bool:
	return _outage_pause > 0.0


## True while dash / ascend are still blocked after an Outage (SPEC §4 "need >= 300 to restart").
func restart_locked() -> bool:
	return _restart_locked and energy < tuning.outage_restart


func outage_left() -> float:
	return _outage_pause


## Discrete cost (dash, skill). `big_move` marks the moves that need the post-Outage restart reserve.
func consume(amount: float, big_move: bool = false) -> bool:
	return _spend(amount, false, big_move)


## Per-frame cost (ascend, assault): spends what is left and returns false once it hits 0.
func drain(amount: float, big_move: bool = false) -> bool:
	return _spend(amount, true, big_move)


func _spend(amount: float, partial: bool, big_move: bool) -> bool:
	if amount <= 0.0:
		return true  # the ground boost is free and never blocks anything
	if is_outage() or (big_move and restart_locked()):
		return false
	if energy < amount and not partial:
		return false
	energy = maxf(energy - amount, 0.0)
	_idle_t = 0.0
	if energy > 0.0:
		return true
	_outage_pause = tuning.outage_pause
	_restart_locked = true
	depleted.emit()
	Events.energy_depleted.emit()
	return false


## Gains (perfect guard, execution) also clear the restart lock.
func add_energy(amount: float) -> void:
	if amount <= 0.0:
		return
	energy = minf(energy + amount, energy_max)
	if energy >= tuning.outage_restart:
		_restart_locked = false


## `pct` is in percent points; the caller scales by the low-HP bonus.
func add_overdrive(pct: float) -> void:
	if overdrive_active or pct <= 0.0:
		return
	overdrive = clampf(overdrive + pct, 0.0, tuning.od_max)


func set_overdrive_active(on: bool) -> void:
	if on == overdrive_active:
		return
	overdrive_active = on
	if not on:
		overdrive = 0.0
	Events.overdrive_changed.emit(on)


## Tools/tests: full gauge, no Outage, empty OD, so a scripted run starts from a known state.
func debug_reset() -> void:
	energy = energy_max
	overdrive = 0.0
	overdrive_active = false
	_idle_t = 0.0
	_outage_pause = 0.0
	_restart_locked = false


## Call once per physics tick. `regen_paused` is true while flying (SPEC §4 flight).
func tick(delta: float, grounded: bool, regen_paused: bool) -> void:
	if _outage_pause > 0.0:
		_outage_pause = maxf(_outage_pause - delta, 0.0)
		if _outage_pause <= 0.0:
			energy = minf(energy + tuning.outage_grant, energy_max)
			_idle_t = 1e9  # the reboot top-up lands with regen already running
		return
	var delay := tuning.regen_delay_ground if grounded else tuning.regen_delay_air
	if _idle_t < delay:
		_idle_t += delta
		return
	if regen_paused or energy >= energy_max:
		return
	var rate := tuning.regen_ground if grounded else tuning.regen_air
	energy = minf(energy + rate * delta, energy_max)
	if energy >= tuning.outage_restart:
		_restart_locked = false
