class_name SkillOverdriveState
extends RefCounted
## The Zenith Overdrive's window (skills-catalog §4.5): the 0.45 s ignition, the 12 s buff window, the
## 3 s aftermath and the EN regen multiplier each of them carries. Split out of `SkillSystem` so that
## file stays the router its header says it is; every public name on the system (`try_overdrive`,
## `end_overdrive`, `is_overdrive_active`, ...) still answers, from here.
##
## What is NOT here: the buff arithmetic the skills read. Damage +25 % / impact +30 % live on
## `SkillContext.damage_mult / impact_mult`, because every skill multiplies through the context.
##
## Two ways the window closes, and they differ in exactly one thing — the aftermath:
##   `end()`         the Lance finished, or the player pressed out of it: 3 s of halved EN regen and
##                   no dash, the price of spending an Overdrive.
##   `end_on_death()` the pilot died: the same three effects, and NO aftermath. A revived mech does
##                   not inherit a penalty for an Overdrive it never got to spend.

var system: SkillSystem = null
var _player: Node = null
var _active: bool = false
var _left: float = 0.0
var _aftermath: float = 0.0
var _ignite: float = 0.0
## What the mech was last TOLD. The mech instances this component before its model / aim siblings are
## guaranteed ready, so the push happens on the first tick after a change rather than at the change.
var _pushed: bool = false


func setup(system_: SkillSystem) -> void:
	system = system_


## Called from `SkillSystem._refresh()` every tick with the current parent.
func attach(player: Node) -> void:
	_player = player
	if player != null and player.has_method(&"set_overdrive_active") and _pushed != _active:
		_pushed = _active
		player.call(&"set_overdrive_active", _active)


func active() -> bool:
	return _active


func left() -> float:
	return _left if _active else 0.0


func aftermath() -> float:
	return _aftermath


func igniting() -> bool:
	return _ignite > 0.0


## The meter is the mech's own (`MechEnergy.overdrive`); this is only the gate on it.
func full() -> bool:
	if _player == null:
		return false
	return float(_player.get(&"overdrive")) >= system.tuning.od_required


## skills-catalog §4.5: a full meter, then 0.45 s of super armour at 0.3x time. Activating resets
## every cooldown and fills the EN gauge.
func begin() -> bool:
	if _active or _ignite > 0.0 or system.zenith.is_firing() or not full():
		return false
	system.reset_all_cooldowns()
	if _player != null and _player.has_method(&"add_energy"):
		_player.call(&"add_energy", float(_player.get(&"energy_max")))
	_ignite = system.tuning.od_ignite
	_left = system.tuning.od_duration
	_active = true
	_pushed = false
	_aftermath = 0.0
	Events.skill_used.emit(&"overdrive")
	system.zenith.ignite()
	return true


## The voluntary end: the Lance sequence finished (it calls this) or the window ran out. A corpse
## pays nothing — `end_on_death()` already ran and a beam that outlives its pilot must not hand the
## EN drain to the next life through this path.
func end() -> void:
	if _player_dead():
		end_on_death()
		return
	if not _active and _aftermath > 0.0:
		return
	_close()
	_aftermath = system.tuning.aftermath


func end_on_death() -> void:
	if _active or _left > 0.0 or _ignite > 0.0:
		_close()
	_aftermath = 0.0


## The window itself: the buff flag drops, the vignette closes, `set_overdrive_active(false)` zeroes
## the OD meter and emits exactly one `overdrive_changed(false)` (audio stops its Overdrive loop on
## it) and the model is told. Charges, cooldowns and EN are untouched.
func _close() -> void:
	_active = false
	_left = 0.0
	_ignite = 0.0
	_pushed = false
	if system.vfx != null:
		system.vfx.vignette.close()
	if _player != null and _player.has_method(&"set_overdrive_active"):
		_player.call(&"set_overdrive_active", false)
	if _player != null and _player.has_method(&"model"):
		var m: Node = _player.call(&"model")
		if m != null and m.has_method(&"set_overdrive"):
			m.call(&"set_overdrive", false)


## CONTRACTS §5 / mech-move r7: `PlayerMech.is_alive()` is the single death predicate (the same one
## SkillInput gates every press on).
func _player_dead() -> bool:
	if _player == null or not _player.has_method(&"is_alive"):
		return false
	return not bool(_player.call(&"is_alive"))


## The player clock (CONTRACTS §3): the window and the aftermath freeze in a global hit-stop and run
## at full speed in witch time.
func tick(delta: float) -> void:
	_aftermath = maxf(_aftermath - delta, 0.0)
	if _ignite > 0.0:
		_ignite = maxf(_ignite - delta, 0.0)
	if _active and not system.zenith.is_firing():
		_left = maxf(_left - delta, 0.0)
		# skills-catalog §4.5: the Lance fires automatically with 1.0 s left, and always at the end.
		if _left <= system.tuning.od_lance_at and system.zenith.can_fire_lance():
			system.zenith.begin_lance()
		elif _left <= 0.0:
			system.zenith.begin_lance()
	_energy(delta)


## skills-catalog §4.5: EN regen x3 while the Overdrive runs, -50 % during the 3 s aftermath.
## PlayerMech only exposes `add_energy` and the `energy` setter, so the multiplier is applied as a
## top-up / draw on top of the mech's own regen rather than by reaching into MechEnergy.
func _energy(delta: float) -> void:
	if _player == null or not _player.has_method(&"add_energy"):
		return
	var rate := _regen_rate()
	if _active:
		_player.call(&"add_energy", rate * (system.tuning.od_regen - 1.0) * delta)
	elif _aftermath > 0.0:
		_player.set(&"energy", maxf(float(_player.get(&"energy"))
				- rate * (1.0 - system.tuning.aftermath_regen) * delta, 0.0))


func _regen_rate() -> float:
	var t := system.ctx.mech_tuning()
	if t == null:
		return 500.0
	return float(t.get(&"regen_ground") if system.ctx.grounded() else t.get(&"regen_air"))


func hud() -> Dictionary:
	return {
		"od": float(_player.get(&"overdrive")) if _player != null else 0.0,
		"od_max": system.tuning.od_required,
		"overdrive_active": _active,
		"overdrive_left": _left,
		"overdrive_igniting": _ignite > 0.0,
		"lance_ready": _active and system.zenith.can_fire_lance(),
		"aftermath": _aftermath,
	}


func reset() -> void:
	_active = false
	_left = 0.0
	_ignite = 0.0
	_aftermath = 0.0
	_pushed = false
