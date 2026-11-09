class_name FlowAssaultLog
extends RefCounted
## The E2E bot's evidence (split out of `FlowDebugAssault`): the two lines a scripted run is read
## from. Without them a beat that is quietly failing looks exactly like a beat that is slowly
## winning, so the bot says what it is aiming at whenever that changes and what it is doing every
## few seconds. Nothing here changes what the bot does — it only reads `FlowAssaultTargets` and
## `FlowAssaultAim`.

var targets: FlowAssaultTargets = null
var aim: FlowAssaultAim = null


func setup(eyes: FlowAssaultTargets, hands: FlowAssaultAim) -> void:
	targets = eyes
	aim = hands


## What the beat is doing, every few seconds.
func beat(player: Node3D, held: Targetable, firing: bool, tries: int) -> void:
	var spire := targets.spire
	var hp := spire.total_hp() if spire != null and is_instance_valid(spire) else -1.0
	var live := held != null and is_instance_valid(held)
	var off := aim.view_off(held) if live else -1.0
	var cross := aim.crosshair_off(held) if live else -1.0
	print("E2EBOT firing=%s tries=%d view_off=%.1f cross=%.0f spire_hp=%.0f ammo=%s at=%.0f,%.0f,%.0f"
			% [str(firing), tries, off, cross, hp, aim.magazine(aim.weapon()),
			player.global_position.x, player.global_position.y, player.global_position.z])


## One line whenever the bot gains or loses a target, so the E2E log says WHY a beat is not moving.
## Returns the new "had a target" state for the caller to keep.
func aim_change(player: Node3D, want: Targetable, had: bool) -> bool:
	if (want != null) == had:
		return had
	if want != null:
		print("E2EAIM locked %s at %.0f,%.0f,%.0f (crosshair %.0f m off) %s"
				% [want.name, want.global_position.x, want.global_position.y, want.global_position.z,
				aim.aim_point().distance_to(want.global_position), aim.view_vs(want)])
		return true
	var near := targets.nearest(player)
	if near == null:
		print("E2EAIM nothing to shoot at all")
		return false
	var eye := FlowDebugView.eye()
	print("E2EAIM lost: nearest %s valid=%s %.0f m, %s" % [near.name, str(near.is_valid_target()),
			eye.distance_to(near.global_position),
			targets.blocker(eye, near.global_position)])
	return false
