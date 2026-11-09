extends Node
## hero-v3 r8 gate: the per-drone hide API (lead brief r8 item 4, skills r4's Corona Fins).
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_drones.gd
##
##   1  the API exists on the MODEL scene and answers a read-back
##   2  a set bit collapses that drone's bone, and a clear bit restores it
##   3  the modelled cyan tip hides with its blade and comes back with it
##   4  the mask is absolute: 0 shows all seven, and the fan does NOT un-hide a docked-away blade
##   5  the lead's fin mapping: 3 fins a side, `Drone_1` always docked (r16 decisions, skills r4)

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 120.0
## `Drone_1..4` ride `wing_l`, `Drone_5..7` ride `wing_r`.
const WING_L := 0x0F
const WING_R := 0x70
## The lead's mapping: 6 fins, 3 a side, so bit 0 (`Drone_1`) is never deployed.
const FINS_MAX := 6
const MAPPED := 0x7E
## A visible drone's bone basis is orthonormal, so its scale reads 1.0; a hidden one reads
## `Hero3Drones.HIDDEN_SCALE`. Anything between the two is a blade that is still on the back.
const VISIBLE_SCALE := 0.5

var failures: Array[String] = []
var _models: Array[Node3D] = []


func _ready() -> void:
	_api()
	_bits()
	_tips()
	_fan_keeps_hidden()
	for m in _models:
		m.queue_free()
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			print("FAIL ", f)
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


func _spawn() -> Node3D:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	_models.append(model)
	return model


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


## The scale the skinning matrix actually carries for drone `index`, read off the bone POSE: the rig
## writes an absolute basis per drone, so this is the number that decides whether the blade is drawn.
func _scale(model: Node3D, index: int) -> float:
	var skel: Skeleton3D = model.skeleton
	var idx := skel.find_bone(Hero3Rig.DRONE_BONES[index])
	if idx < 0:
		return -1.0
	return skel.get_bone_global_pose(idx).basis.get_scale().x


## `set_drones_docked` only records the mask; the bone write happens on the rig's next update, which
## is the same tick the game runs it on.
func _settle(model: Node3D, ticks: int = 2) -> void:
	for i in ticks:
		model.rig.update(DT)


func _api() -> void:
	var model := _spawn()
	for method in [&"set_drones_docked", &"drones_docked", &"set_drone_deployed",
			&"drone_deployed", &"drone_tip"]:
		_check(model.has_method(method), "Hero3Model has no %s" % method)
	_check(model.drones_docked() == 0, "a fresh model starts with every blade docked")
	_check(Hero3Rig.DRONE_BONES.size() == 7, "the rig no longer carries 7 drones")
	_settle(model)
	for i in 7:
		_check(_scale(model, i) > VISIBLE_SCALE, "drone %d starts hidden" % i)


func _bits() -> void:
	var model := _spawn()
	model.set_drones_docked(1 << 2)
	_check(model.drones_docked() == (1 << 2), "the read-back lost the mask")
	_settle(model)
	_check(_scale(model, 2) < 0.01, "drone 2's blade did not collapse (%.5f)" % _scale(model, 2))
	for i in 7:
		if i == 2:
			continue
		_check(_scale(model, i) > VISIBLE_SCALE,
				"drone %d was hidden by a mask that did not name it" % i)
	model.set_drones_docked(0)
	_settle(model)
	_check(_scale(model, 2) > VISIBLE_SCALE, "drone 2 did not come back")
	# the per-drone spelling has to agree with the mask spelling
	model.set_drone_deployed(5, true)
	_check(model.drone_deployed(5) and not model.drone_deployed(4),
			"set_drone_deployed is not 0-based")
	_check(model.drones_docked() == (1 << 5), "set_drone_deployed did not write through the mask")
	model.set_drone_deployed(5, false)
	_check(model.drones_docked() == 0, "clearing one drone left the mask dirty")
	# out of range has to be refused, not silently accepted
	model.set_drone_deployed(9, true)
	_check(model.drones_docked() == 0, "an out-of-range index was accepted")


func _tips() -> void:
	var model := _spawn()
	var glow: Hero3Glow = model.rig.glow
	_check(glow != null and glow.tips.size() == 7, "the glow lost its 7 tips")
	model.set_drones_docked(0x7F)
	_check(_lit_tips(glow) == 0, "%d cyan tips stayed lit with every drone deployed" % _lit_tips(glow))
	model.set_drones_docked(0)
	_check(_lit_tips(glow) == 7, "%d of 7 tips came back" % _lit_tips(glow))


static func _lit_tips(glow: Hero3Glow) -> int:
	var lit := 0
	for tip in glow.tips:
		if tip != null and tip.visible:
			lit += 1
	return lit


## The fan opens the blades that are still docked; it must not resurrect one the fins took away.
func _fan_keeps_hidden() -> void:
	var model := _spawn()
	model.set_wings(1.0)
	model.set_drones_docked(MAPPED)
	_settle(model, 80)  # FAN_LERP 7.0: the fan is 97 % open after 0.67 s
	var shown := 0
	for i in 7:
		if _scale(model, i) > VISIBLE_SCALE:
			shown += 1
	_check(shown == 1, "%d blades are still on the back with 6 fins out (want 1)" % shown)
	_check(_scale(model, 0) > VISIBLE_SCALE, "Drone_1 must stay docked -- the lead's mapping")
	_check(model.rig.drones.fan() > 0.9, "the fan never opened (%.2f)" % model.rig.drones.fan())
	model.set_drones_docked(0)
	_settle(model, 5)
	shown = 0
	for i in 7:
		if _scale(model, i) > VISIBLE_SCALE:
			shown += 1
	_check(shown == 7, "docking the fins left %d blades hidden" % (7 - shown))
	# the mapping itself: 3 fins a side, 6 in total, none of them Drone_1
	_check(popcount(MAPPED) == FINS_MAX, "the mapped mask is not fins_max")
	_check((MAPPED & 0x01) == 0, "the mapping deploys Drone_1, which the lead keeps docked")
	_check(popcount(MAPPED & WING_L) == 3 and popcount(MAPPED & WING_R) == 3,
			"the mapping is not 3 fins a side")


static func popcount(mask: int) -> int:
	var n := 0
	for i in 7:
		if (mask & (1 << i)) != 0:
			n += 1
	return n
