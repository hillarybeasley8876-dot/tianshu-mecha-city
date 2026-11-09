extends "res://player/camera/tests/camera_test_base.gd"
## The real intro hands the view back (camera-aim, lead r7 item 2). Builds the REAL `flow/game_flow.tscn`
## over the REAL `player/camera/camera_rig.tscn` — not `flow/tests/flow_fake_rig.gd` — parks a
## 100 000 s vista shot on the rig exactly the way `GameFlow._title()` does, then lets the flow's own
## `_enter_tutorial()` call `end_cinematic()` and walks the hero 60 m.
##
## The gate is the lead's: 1 s after `end_cinematic()` the rig is within 1 m of its follow position,
## the hero is on screen, and the shot list is gone. Pre-fix (`end_cinematic()` restoring the look and
## the arm but never cancelling the shot list) the rig stays frozen on the vista and the hero walks
## out of frame.
##
## Run: tools/godot.sh test res://player/camera/tests/test_camera_flow.gd -- --sandbox --flow --spawn=0,1,60

const FLOW_SCENE := "res://flow/game_flow.tscn"
## Exactly `GameFlow._title()`'s shot: a fixed vista held for 100 000 s.
const VISTA: Array[Dictionary] = [{"offset": Vector3(46.0, 30.0, 96.0), "fov": 62.0, "t": 0.0}]
const VISTA_SECONDS := 100000.0
const WALK_SPEED := 16.0  ## m/s, PlayerMech's run speed
## The follow spring's designed steady-state lag is 2v/omega = 2 x 16 / 10 = 3.2 m; the band leaves
## the spring's own overshoot room without letting a frozen rig through.
const WALK_LAG := 4.5
const START := Vector3(0.0, 1.0, 60.0)

## Stand-in hero: the surface `GameFlow` and `CameraRig` touch on the intro path (CONTRACTS §2).
class FlowPlayer extends Node3D:
	var hp: float = 10000.0
	var hp_max: float = 10000.0
	var energy: float = 1000.0
	var energy_max: float = 1000.0
	var invuln_left: float = 0.0
	var velocity: Vector3 = Vector3.ZERO

	func _ready() -> void:
		add_to_group(&"player")
		Game.register_player(self)

	func aim() -> Node:
		return null

	func model() -> Node3D:
		return null

	func is_grounded() -> bool:
		return true

	func is_flying() -> bool:
		return false

	func is_boosting() -> bool:
		return false

	func move_state() -> StringName:
		return &"run"

	func heal(amount: float) -> void:
		hp = minf(hp + amount, hp_max)

	func add_energy(amount: float) -> void:
		energy = minf(energy + amount, energy_max)

	func invulnerable_for(seconds: float) -> void:
		invuln_left = maxf(invuln_left, seconds)

	func is_invulnerable() -> bool:
		return invuln_left > 0.0

	func apply_impulse(_v: Vector3) -> void:
		pass


var _flow: Node = null
var _hero: FlowPlayer = null


func _ready() -> void:
	await _build_flow()
	await _test_hand_back()
	_report()


## A flat floor, a `PlayerSpawn` marker the flow reads for its own start, the stand-in hero, the live
## rig and the live flow — in the order `main.tscn` builds them.
func _build_flow() -> void:
	_probe.radius = 0.5
	_box("ground", Vector3(0.0, -10.0, 0.0), Vector3(2000.0, 20.0, 2000.0))
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	Game.world = world
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = START
	world.add_child(spawn)
	_hero = FlowPlayer.new()
	_hero.name = "Player"
	_hero.position = START
	world.add_child(_hero)
	_player = _hero
	_rig = RIG.instantiate() as Node3D
	add_child(_rig)
	_cam = _rig.call(&"camera") as Camera3D
	var packed := load(FLOW_SCENE) as PackedScene
	if packed == null:
		_check(false, "cannot load " + FLOW_SCENE)
		return
	_flow = packed.instantiate()
	_flow.name = "GameFlow"
	_flow.set(&"auto_waves", false)
	add_child(_flow)
	await _ticks(30)
	_check(Game.camera_rig == _rig, "the real rig registered itself as Game.camera_rig")
	_check(String(_flow.call(&"state_name")) == "tutorial",
			"the real flow reached the tutorial (state %s)" % _flow.call(&"state_name"))
	_rig.call(&"snap_to_player")
	await _ticks(30)


## Park the title vista on the rig, let the flow hand the view back, then walk the hero and check that
## the rig is following again.
func _test_hand_back() -> void:
	_rig.call(&"request_cinematic", VISTA, VISTA_SECONDS)
	await _ticks(4)
	_check(bool(_rig.call(&"is_cinematic")), "the 100 000 s vista shot took the view")
	var held := _rig.global_position
	# The flow's own transition into the tutorial is what calls end_cinematic() (game_flow.gd:200);
	# `_go` early-outs because the flow is already there, so only the hand-back runs.
	_flow.call(&"_enter_tutorial")
	await _ticks(4)
	_check(not bool(_rig.call(&"is_cinematic")), "end_cinematic() cleared the shot list")
	_check(held.distance_to(_rig.global_position) > 1.0,
			"the rig re-seated itself instead of holding the vista (%.1f m)" %
			held.distance_to(_rig.global_position))
	# The lead's gate, literally: 1 s after end_cinematic() the rig is on its follow position.
	await _ticks(120)
	_check(_rig.global_position.distance_to(_chest()) < 1.0,
			"1 s after the hand-back the rig is within 1 m of its follow position (%.2f m)"
			% _rig.global_position.distance_to(_chest()))
	# Then it has to KEEP following: 1 s of running, sampled every tick.
	var worst := 0.0
	var off := 0
	for i in 120:
		_hero.position.z -= WALK_SPEED / 120.0
		await get_tree().physics_frame
		worst = maxf(worst, _rig.global_position.distance_to(_chest()))
		var uv := _project_point(_hero.global_position)
		if is_nan(uv.x) or uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
			off += 1
	_check(worst < WALK_LAG, "the rig tracks a 16 m/s run (worst lag %.2f m, band %.1f m)"
			% [worst, WALK_LAG])
	_check(off == 0, "the hero is on screen every tick of that second (%d ticks off)" % off)
	await _ticks(120)
	_check(_rig.global_position.distance_to(_chest()) < 1.0,
			"and it settles back onto the follow position when the hero stops (%.2f m)"
			% _rig.global_position.distance_to(_chest()))
	_check(float(_rig.call(&"hud_state")[&"arm_length"]) > 41.0,
			"the arm is back to its 42 m street length (%.1f m)"
			% float(_rig.call(&"hud_state")[&"arm_length"]))


## Where the rig's follow spring is steering it: the chest pivot above the hero's feet.
func _chest() -> Vector3:
	return _hero.global_position + Vector3.UP * 12.5
