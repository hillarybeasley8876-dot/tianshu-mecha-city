class_name SkillSlots
extends RefCounted
## The cooldown / charge / EN table behind the SkillSystem: one `Slot` per skill id, each holding a
## per-charge recharge timer so a two-charge skill (the Skyhook) refills one line at a time.
##
## Kept separate from SkillSystem so the component file stays about routing: the slot owns the timing
## rules (skills-catalog §4.5 — cooldowns tick 2.5x faster inside the Overdrive, all reset on
## activation) and announces every recharge on `Events.skill_ready`.

## A single-charge skill just keeps `charges_max = 1`.
class Slot extends RefCounted:
	var id: StringName
	var cd_max: float = 1.0
	var cost: float = 0.0
	var charges_max: int = 1
	var charges: int = 1
	var left: float = 0.0

	func _init(id_: StringName, cd_: float, cost_: float, charges_: int) -> void:
		id = id_
		cd_max = cd_
		cost = cost_
		charges_max = charges_
		charges = charges_

	func ready() -> bool:
		return charges > 0

	## Takes one charge and starts its recharge. The caller has already checked `ready()`.
	func spend() -> void:
		charges = maxi(charges - 1, 0)
		left = cd_max

	## Returns true on the tick a charge came back, so the caller can announce it.
	func tick(delta: float, rate: float) -> bool:
		if charges >= charges_max:
			return false
		left -= delta * rate
		if left > 0.0:
			return false
		charges = mini(charges + 1, charges_max)
		left = cd_max if charges < charges_max else 0.0
		return true

	func reset() -> void:
		charges = charges_max
		left = 0.0

	func hud() -> Dictionary:
		return {"%s_cd" % id: maxf(left, 0.0), "%s_cd_max" % id: cd_max,
				"%s_charges" % id: charges, "%s_ready" % id: ready()}


var _slots: Dictionary = {}


func add(id: StringName, cd: float, cost: float, charges: int) -> void:
	_slots[id] = Slot.new(id, cd, cost, charges)


func get_slot(id: StringName) -> Slot:
	return _slots.get(id) as Slot


func ids() -> Array:
	return _slots.keys()


func tick_all(delta: float, rate: float) -> Array[StringName]:
	var recharged: Array[StringName] = []
	for id: StringName in _slots:
		if (_slots[id] as Slot).tick(delta, rate):
			recharged.append(id)
	return recharged


## skills-catalog §4.5: activating the Overdrive resets every cooldown. Returns the ids to announce.
func reset_all() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _slots:
		(_slots[id] as Slot).reset()
		out.append(id)
	return out


func hud_all() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in _slots:
		out.merge((_slots[id] as Slot).hud(), true)
	return out
