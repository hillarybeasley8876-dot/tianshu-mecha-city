class_name MeleeCharge
extends RefCounted
## The Dawn Edge's hold-to-charge input (skills-catalog §4.3 "hold ≥30 f"): a press always starts a
## chain move on the same frame, and if the button is STILL held 30 frames later the saber enters its
## charge stance; letting go then fires the charged slash. That keeps a tap answering within a frame
## (SPEC §1) without giving up the AC6-style hold.
##
## `poll()` returns what the button did this tick so the melee system can act on it.

enum Edge { NONE, PRESSED, RELEASED_CHARGED }

var charging: bool = false
var charge_ticks: int = 0

var _held: bool = false
var _hold_ticks: int = 0


## One tick of the melee button. `can_charge` is the melee system's "am I free to start a charge?"
## (idle or inside a cancel window).
func poll(can_charge: bool) -> Edge:
	var held := Input.is_action_pressed(&"melee")
	var pressed := held and not _held
	var released := not held and _held
	_held = held
	if pressed:
		_hold_ticks = 0
		return Edge.PRESSED
	if released:
		return _release()
	if held:
		_hold_ticks += 1
		if not charging and _hold_ticks >= MeleeTable.ticks(MeleeTable.CHARGE_FRAMES) and can_charge:
			begin()
		if charging:
			charge_ticks += 1
	return Edge.NONE


func begin() -> void:
	charging = true
	charge_ticks = 0


func _release() -> Edge:
	if not charging:
		return Edge.NONE
	charging = false
	charge_ticks = 0
	return Edge.RELEASED_CHARGED


## 0..1 for the HUD. The bar starts at half when the stance opens, because the first 30 frames of the
## hold already counted toward it.
func ratio() -> float:
	if not charging:
		return 0.0
	var need := float(MeleeTable.ticks(MeleeTable.CHARGE_FRAMES))
	return clampf((float(charge_ticks) + need) / (need * 2.0), 0.0, 1.0)


func reset() -> void:
	charging = false
	charge_ticks = 0
	_held = false
	_hold_ticks = 0
