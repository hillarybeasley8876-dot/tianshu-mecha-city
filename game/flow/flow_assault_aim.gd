class_name FlowAssaultAim
extends RefCounted
## The E2E bot's hands (split out of `FlowDebugAssault`): it points the camera rig at a world
## position by hand and works the trigger, the reload and the skills. Choosing a target and a place
## to stand is `FlowAssaultTargets` and `FlowAssaultMove`; this file never looks at the world.
##
## It aims the rig itself rather than through the hard lock: `CameraLock.track` points the pivot at
## the target and then adds the CONTRACTS §5 large-target pitch offset (up to +12°), which is right
## for framing a 60 m spire and wrong for putting a shot through a 6 m pod — with the lock held, the
## crosshair sat 1,400 m past the pod and nothing was ever hit. The shot is still the real one, from
## the real muzzle, through `aim_dir_from`.

## Degrees: how close the aim ray has to pass to the target before the bot pulls the trigger. A 6 m
## pod at 66 m is 5°, so this is the angle at which the shot actually lands on it.
const AIM_CONE_DEG := 2.0
## m: how far the crosshair may sit from the locked target before the bot counts the shot as blocked.
## A camera behind a flyover has line of sight from the mech and no shot at all — the aim point, not
## the ray, is what says so.
const AIM_TOLERANCE := 12.0
## The Pierce-Light is a charge weapon: it shoots on trigger RELEASE, so a bot that simply holds fire
## gets exactly one round. The bot TAPS it (r5 brief item 7): a tap is `max_hits` 1, which is the
## player-facing gate — a hive whose pods only a piercing charged shot can reach is broken for the
## player, and a bot that proves the fight with charges would hide exactly that.
const TRIGGER_HOLD := 0.08
const TRIGGER_GAP := 0.12
## s between reload checks. The Pierce-Light has no auto-reload: a charged shot that empties the
## magazine leaves it at 0/9 with `reloading` never set, and a bot that only pulls the trigger shoots
## exactly three rounds and then stands there for the rest of the beat.
const RELOAD_EVERY := 2.0
## s the bot holds the reload action down so a physics tick can see it.
const RELOAD_HOLD := 0.2
const SKILL_EVERY := 7.0
const SKILL_ACTIONS: Array[StringName] = [&"burst", &"fins"]

## True while the bot has a target inside the aim cone and wants the trigger tapped.
var firing: bool = false

var _trigger_down: bool = false
var _trigger_t: float = 0.0
var _reload_t: float = 0.0
var _reload_hold: float = 0.0
var _skill_t: float = SKILL_EVERY
var _skills: int = 0


func reset() -> void:
	_skill_t = SKILL_EVERY


## Point the rig at a world position. Absolute yaw/pitch in the rig's own convention (`_yaw.rotation.y
## = yaw`, `_pitch.rotation.x = pitch`, −Z forward, positive pitch up), measured from the camera — a
## delta off `look_dir()` drifts, because the lock tracker and the aim assist both write the same two
## numbers between one call and the next.
func point_at(player: Node3D, at: Vector3) -> void:
	var rig := Game.camera_rig
	if rig == null or not rig.has_method(&"set_look"):
		return
	var from: Vector3 = player.global_position
	if rig.has_method(&"camera"):
		var cam := rig.call(&"camera") as Camera3D
		if cam != null:
			from = cam.global_position
	var dir := (at - from)
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	rig.call(&"set_look", rad_to_deg(atan2(-dir.x, -dir.z)), rad_to_deg(asin(dir.y)))


## Degrees between the aim ray and the target, measured from the origin the aim ray actually starts
## at (the rig's arm tip, `CameraRig.aim_origin`), not from the camera behind it.
func view_off(want: Targetable) -> float:
	var rig := Game.camera_rig
	if rig == null or not rig.has_method(&"look_dir"):
		return 0.0
	var dir: Vector3 = rig.call(&"look_dir")
	var from := FlowDebugView.eye()
	if rig.has_method(&"aim_origin"):
		from = rig.call(&"aim_origin") as Vector3
	var to := (want.global_position - from)
	if to.length_squared() < 0.01:
		return 0.0
	return rad_to_deg(dir.angle_to(to.normalized()))


## How far the crosshair sits from a target: the honest measure of "can this shot land".
func crosshair_off(target: Targetable) -> float:
	if not Game.player.has_method(&"aim"):
		return 0.0
	var aim := Game.player.call(&"aim") as Node
	if aim == null or not aim.has_method(&"aim_point"):
		return 0.0
	var point: Vector3 = aim.call(&"aim_point")
	return point.distance_to(target.global_position)


## Diagnostic: the angle between where the view is looking and where the target is, in degrees.
func view_vs(want: Targetable) -> String:
	var rig := Game.camera_rig
	if rig == null or not rig.has_method(&"look_dir"):
		return "view ?"
	var angles: Vector2 = rig.call(&"look_angles") if rig.has_method(&"look_angles") else Vector2.ZERO
	var hard := "-"
	if Game.player.has_method(&"aim"):
		var aim := Game.player.call(&"aim") as Node
		var t: Targetable = aim.call(&"hard_target") as Targetable if aim != null \
				and aim.has_method(&"hard_target") else null
		hard = String(t.name) if t != null else "none"
	return "view %.0f deg off target (look %.0f,%.0f pitch, lock %s)" % [view_off(want),
			angles.x, angles.y, hard]


## The aim point the crosshair is on, or `Vector3.INF` when there is no aim system under the mech.
func aim_point() -> Vector3:
	if not Game.player.has_method(&"aim"):
		return Vector3.INF
	var aim := Game.player.call(&"aim") as Node
	if aim == null or not aim.has_method(&"aim_point"):
		return Vector3.INF
	return aim.call(&"aim_point") as Vector3


## The weapon system under the mech (the node whose `hud_state` carries the ammo), or null.
func weapon() -> Node:
	var player := Game.player
	if player == null:
		return null
	for child in player.get_children():
		if not child.has_method(&"hud_state"):
			continue
		var state: Dictionary = child.call(&"hud_state")
		if state.has("ammo") and state.has("ammo_max"):
			return child
	return null


## The magazine as the E2E log prints it: `9/9`, or `0/9 RELOADING`.
func magazine(gun: Node) -> String:
	if gun == null:
		return "-"
	var state: Dictionary = gun.call(&"hud_state")
	return "%d/%d%s" % [int(state.get("ammo", -1)), int(state.get("ammo_max", -1)),
			" RELOADING" if bool(state.get("reloading", false)) else ""]


## The reload timer, on the world clock (CONTRACTS §3: it paces nothing the player sees).
func tick_reload(delta: float) -> void:
	_reload_t -= delta
	if _reload_t <= 0.0:
		_reload_t = RELOAD_EVERY
		_reload()


## Reload when the magazine is not full. `Rifle.reload()` no-ops on a full magazine, so this is safe
## to call on a timer.
func _reload() -> void:
	var gun := weapon()
	if gun == null:
		return
	var state: Dictionary = gun.call(&"hud_state")
	if bool(state.get("reloading", false)):
		return
	if int(state.get("ammo", 0)) >= int(state.get("ammo_max", 0)):
		return
	# Held for a few frames, not tapped: the weapon system reads `reload` from `_physics_process`, and
	# a press and release inside one idle frame are already over by the time it looks.
	Input.action_press(&"reload")
	_reload_hold = RELOAD_HOLD


## Throw a skill in now and then (brief: pods and core with real weapons AND skills), on the same
## world-clock timer as the reload.
func tick_skill(delta: float, wanted: bool) -> void:
	if not wanted:
		return
	_skill_t -= delta
	if _skill_t > 0.0:
		return
	_skill_t = SKILL_EVERY
	var action := SKILL_ACTIONS[_skills % SKILL_ACTIONS.size()]
	_skills += 1
	Input.action_press(action)
	Input.action_release(action)


## Tap the trigger: hold for a stage-1 charge, let go, hold again. Driven from `_process`, NOT from
## `_physics_process`: a simulated `Input.action_press` made inside a physics tick does not survive to
## the readers (PadInput and tools/autoplay.gd both press from the idle frame for the same reason).
func tick_trigger(delta: float) -> void:
	if _reload_hold > 0.0:
		_reload_hold -= delta
		if _reload_hold <= 0.0:
			Input.action_release(&"reload")
	if not firing:
		return
	_trigger_t -= delta
	if _trigger_t > 0.0:
		return
	if _trigger_down:
		Input.action_release(&"fire")
		_trigger_down = false
		_trigger_t = TRIGGER_GAP
	else:
		Input.action_press(&"fire")
		_trigger_down = true
		_trigger_t = TRIGGER_HOLD


## Let go of the trigger and the reload — the bot never leaves the player holding fire.
func release() -> void:
	if _reload_hold > 0.0:
		_reload_hold = 0.0
		Input.action_release(&"reload")
	if _trigger_down:
		Input.action_release(&"fire")
		_trigger_down = false
	firing = false
