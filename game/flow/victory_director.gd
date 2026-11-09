class_name FlowVictoryDirector
extends Node
## The end of the demo (SPEC §8 step 5): a slow-mo beat, an orbit around the hero, the run's time
## handed to the HUD's victory page, and the AI sign-off. `Events.game_won` already puts the victory
## page up (menus unit) — flow only supplies the time and the camera.

signal finished()

const SLOW_SCALE := 0.3
const SLOW_TIME := 1.2
const ORBIT_TIME := 7.0
## Duel-frame orbit (camera-aim): with no hard target the frame's −Z is the hero's facing, so these
## four offsets sweep from behind, to the side, to a low front three-quarter.
const SHOTS: Array[Dictionary] = [
	{"offset": Vector3(0.0, 26.0, 78.0), "fov": 55.0, "t": 0.0},
	{"offset": Vector3(74.0, 18.0, 20.0), "fov": 50.0, "t": 1.8},
	{"offset": Vector3(30.0, 9.0, -70.0), "fov": 46.0, "t": 3.6},
	{"offset": Vector3(-58.0, 34.0, 56.0), "fov": 60.0, "t": 5.4},
]


func begin(run_time: float) -> void:
	Feel.slow_mo(SLOW_SCALE, SLOW_TIME, 0.1, 0.6)
	Audio.music_intensity(0.0)
	Audio.stinger(&"stinger_victory")
	Audio.voice(&"ai_victory", 95.0, 2.4)
	_write_time(run_time)
	var rig := Game.camera_rig
	if rig != null and rig.has_method(&"request_cinematic"):
		rig.call(&"request_cinematic", SHOTS, ORBIT_TIME)
	get_tree().create_timer(ORBIT_TIME, true, false, true).timeout.connect(_done)


## The menus own every other statistic (kills, parries, combo); the clock is flow's.
func _write_time(run_time: float) -> void:
	if Game.hud == null:
		return
	var menus := Game.hud.get(&"menus") as Node
	if menus != null:
		(menus.get(&"stats") as Dictionary)["time"] = run_time


func _done() -> void:
	var rig := Game.camera_rig
	if rig != null and rig.has_method(&"end_cinematic"):
		rig.call(&"end_cinematic")
	finished.emit()
