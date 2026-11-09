class_name StatusComponent
extends RefCounted
## Enemy status state (enemies-owned): stability → stagger, marks, primed, slow/pull, combo scaling.
## Numbers are exactly skills-catalog §4.1/§4.6/§4.7 (see EnemyTypes for the per-archetype table).
##
## Stability is a POOL that impact drains (AC6 ACS reading): hits subtract `hit.stagger`, the pool
## regenerates at `decay` × max per second once `decay_delay` seconds passed without impact, and at
## ≤ 0 the enemy staggers for `stagger_time`, then the pool refills and `immunity_time` blocks any
## new stagger (immunity 0 = none, per the swarmer row).

signal staggered(status: StatusComponent)
signal stagger_ended(status: StatusComponent)
signal marks_changed(marks: int)
signal primed_changed(primed: bool)

const MARK_HITS_PER_MARK := 2      ## skills-catalog §4.1: 2 / 4 rifle hits = 1 / 2 marks
const MARK_MAX := 2
const MARK_DECAY := 5.0            ## seconds after the last qualifying hit
const PRIME_TIME := 5.0            ## Undertow / detonator window

const COMBO_FULL_HITS := 6         ## hits 1..6 deal 100 %
const COMBO_STEP := 0.06           ## −6 % per hit afterwards
const COMBO_FLOOR := 0.55          ## never below 55 %
const COMBO_RESET := 1.5           ## seconds without a hit

var stability_max: float = 150.0
var stability: float = 150.0
var decay_rate: float = 0.30       ## fraction of stability_max per second
var decay_delay: float = 0.8
var stagger_time: float = 0.8
var immunity_time: float = 0.0

var marks: int = 0
var primed: bool = false
var slow_factor: float = 1.0       ## 1 = normal, 0.4 = 40 % speed (Undertow well)
var pull_accel: Vector3 = Vector3.ZERO  ## m/s² toward the well this frame

var _since_impact: float = 99.0
var _stagger_left: float = 0.0
var _immune_left: float = 0.0
var _mark_hits: int = 0
var _mark_left: float = 0.0
var _prime_left: float = 0.0
var _slow_left: float = 0.0
var _slow_amount: float = 1.0
var _pull_left: float = 0.0
var _combo_hits: int = 0
var _combo_left: float = 0.0


func configure(stats: Dictionary) -> void:
	stability_max = float(stats.get("stability", stability_max))
	stability = stability_max
	decay_rate = float(stats.get("decay", decay_rate))
	decay_delay = float(stats.get("decay_delay", decay_delay))
	stagger_time = float(stats.get("stagger", stagger_time))
	immunity_time = float(stats.get("immunity", immunity_time))


func reset() -> void:
	stability = stability_max
	marks = 0
	primed = false
	slow_factor = 1.0
	pull_accel = Vector3.ZERO
	_since_impact = 99.0
	_stagger_left = 0.0
	_immune_left = 0.0
	_mark_hits = 0
	_mark_left = 0.0
	_prime_left = 0.0
	_slow_left = 0.0
	_slow_amount = 1.0
	_pull_left = 0.0
	_combo_hits = 0
	_combo_left = 0.0


## Advances timers. `delta` is the enemy's own (hit-stop scaled) delta.
func tick(delta: float) -> void:
	_since_impact += delta
	_tick_combo(delta)
	_tick_marks(delta)
	_tick_prime(delta)
	_tick_slow(delta)
	if _stagger_left > 0.0:
		_stagger_left -= delta
		if _stagger_left <= 0.0:
			_end_stagger()
		return
	if _immune_left > 0.0:
		_immune_left -= delta
	if stability < stability_max and _since_impact >= decay_delay:
		stability = minf(stability_max, stability + decay_rate * stability_max * delta)


func _tick_combo(delta: float) -> void:
	if _combo_left > 0.0:
		_combo_left -= delta
		if _combo_left <= 0.0:
			_combo_hits = 0


func _tick_marks(delta: float) -> void:
	if _mark_left <= 0.0:
		return
	_mark_left -= delta
	if _mark_left <= 0.0:
		_mark_hits = 0
		if marks > 0:
			marks = 0
			marks_changed.emit(0)


func _tick_prime(delta: float) -> void:
	if not primed:
		return
	_prime_left -= delta
	if _prime_left <= 0.0:
		clear_prime()


## The pull keeps its own timer: it must never inherit (or extend) a slow, because a Skyhook yank
## leaves `_slow_amount` at 0.05 and the next well would crawl the monster at 5 % speed (audit #9).
func _tick_slow(delta: float) -> void:
	if _pull_left > 0.0:
		_pull_left -= delta
		if _pull_left <= 0.0:
			pull_accel = Vector3.ZERO
	if _slow_left <= 0.0:
		return
	_slow_left -= delta
	if _slow_left <= 0.0:
		_slow_amount = 1.0
		slow_factor = 1.0
	else:
		slow_factor = _slow_amount


## Poise damage. Returns true when this hit staggered the enemy.
func add_impact(amount: float) -> bool:
	_since_impact = 0.0
	if _stagger_left > 0.0 or _immune_left > 0.0 or amount <= 0.0:
		return false
	stability = maxf(0.0, stability - amount)
	if stability > 0.0:
		return false
	_stagger_left = stagger_time
	stability = 0.0
	staggered.emit(self)
	return true


func _end_stagger() -> void:
	stability = stability_max
	_immune_left = immunity_time
	stagger_ended.emit(self)


func is_staggered() -> bool:
	return _stagger_left > 0.0


func stagger_left() -> float:
	return maxf(_stagger_left, 0.0)


func is_immune() -> bool:
	return _immune_left > 0.0


## Marks from weapon fire (skills-catalog §4.1). Every MARK_HITS_PER_MARK qualifying hits add one,
## capped at MARK_MAX; the decay timer restarts on each qualifying hit.
func add_mark_hit(count: int = 1) -> void:
	_mark_hits += count
	_mark_left = MARK_DECAY
	var want: int = mini(MARK_MAX, _mark_hits / MARK_HITS_PER_MARK)
	if want != marks:
		marks = want
		marks_changed.emit(marks)


func add_marks(n: int) -> void:
	add_mark_hit(n * MARK_HITS_PER_MARK)


func consume_marks() -> int:
	var had := marks
	_mark_hits = 0
	_mark_left = 0.0
	if marks > 0:
		marks = 0
		marks_changed.emit(0)
	return had


## Undertow / detonator prime window.
func prime(duration: float = PRIME_TIME) -> void:
	_prime_left = maxf(_prime_left, duration)
	if not primed:
		primed = true
		primed_changed.emit(true)


func is_primed() -> bool:
	return primed


## COLLAPSE detonators call this instead of writing `primed` themselves, so the HUD plate and any
## other `primed_changed` listener hear about it (CONTRACTS §4). Returns whether a prime was cleared.
func clear_prime() -> bool:
	_prime_left = 0.0
	if not primed:
		return false
	primed = false
	primed_changed.emit(false)
	return true


## Skills hooks: slow (Undertow well) and a per-frame pull acceleration toward the well centre.
func apply_slow(factor: float, duration: float) -> void:
	_slow_amount = clampf(factor, 0.05, 1.0)
	_slow_left = maxf(_slow_left, duration)
	slow_factor = _slow_amount


## A field that pulls writes `pull_accel` from its own physics tick; EnemyBase CONSUMES it here
## instead of `tick()` clearing it, because the enemy's `tick()` runs before its own integration —
## clearing it there meant the pull was always zero by the time it was applied (audit #6/#8).
func apply_pull(accel: Vector3, duration: float) -> void:
	pull_accel = accel
	_pull_left = maxf(_pull_left, duration)


## Reads and withdraws this frame's pull. Returns m/s² toward the field.
func consume_pull() -> Vector3:
	var accel := pull_accel
	pull_accel = Vector3.ZERO
	return accel


## Combo scaling (skills-catalog §4.7): hits 1..6 at 100 %, then −6 % per hit, floor 55 %, reset after
## 1.5 s without a hit, SUSPENDED while the enemy is staggered. Call before applying the damage and
## then `commit_hit()` so the counter advances exactly once per landed hit.
func combo_multiplier() -> float:
	if is_staggered():
		return 1.0
	if _combo_hits < COMBO_FULL_HITS:
		return 1.0
	return maxf(COMBO_FLOOR, 1.0 - COMBO_STEP * float(_combo_hits - COMBO_FULL_HITS + 1))


func commit_hit() -> void:
	_combo_hits += 1
	_combo_left = COMBO_RESET


func combo_hits() -> int:
	return _combo_hits
