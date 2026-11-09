extends Node
## hero-v3 r5 evidence harness: the REAL game (`res://main.tscn`, the real PlayerMech, the real
## Tianshu, the real physics and feel) filmed from a fixed SIDE camera.
##
##   tools/godot.sh drive --scene=res://player/model/hero3/tests/hero3_city_shot.tscn \
##       --timeline=res://player/model/hero3/tests/timeline_drop.json --shots=... \
##       --stub=camera --skip-menu --no-enemies --spawn=-560,7.5,600,54.2 \
##       --side=144.2 --dist=44 --height=13 --look=8
##
## The lead's r5 brief asks for a SIDE view of a drop and a landing. The game's own third-person rig
## sits 42 m behind the mech (`CameraRig.ARM_LENGTH`), so a knee fold and a 2.3 m pelvis drop are
## invisible from there -- this puts the same game on a profile camera instead. `--stub=camera` keeps
## the rig out of the way so this is the only camera in the tree.

const MAIN := "res://main.tscn"

var cam: Camera3D
var side_deg: float = 144.2
var dist: float = 44.0
var height: float = 13.0
var look: float = 8.0
## The flight pose's own numbers, printed at 4 Hz so a drive log carries the lean and the bank
## AGAINST the speed and the yaw rate that produced them (lead r8 item 3). `PlayerMech.telemetry()`
## is mech-move's file this round, so the model reports itself instead.
var _telemetry_t: float = 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var eq := arg.find("=")
		if eq <= 0:
			continue
		var key := arg.substr(2, eq - 2)
		var value := arg.substr(eq + 1)
		match key:
			"side": side_deg = float(value)
			"dist": dist = float(value)
			"height": height = float(value)
			"look": look = float(value)
	var main := (load(MAIN) as PackedScene).instantiate()
	main.name = "Main"
	add_child(main)
	cam = Camera3D.new()
	cam.name = "SideCamera"
	cam.fov = 42.0
	cam.far = 4000.0
	add_child(cam)
	print("SHOT side %.1f deg, %.0f m out, %.0f m up, looking %.0f m"
			% [side_deg, dist, height, look])


func _process(delta: float) -> void:
	if cam == null:
		return
	var p := Game.player as Node3D
	if p == null:
		return
	var offset := Basis(Vector3.UP, deg_to_rad(side_deg)) * Vector3(0.0, 0.0, dist)
	var eye := p.global_position + offset + Vector3.UP * height
	var at := p.global_position + Vector3.UP * look
	cam.global_position = eye
	cam.look_at(at, Vector3.UP)
	if not cam.current:
		cam.make_current()
	_telemetry_t += delta
	if _telemetry_t >= 0.25:
		_telemetry_t = 0.0
		_report(p)


## `PLUME state=.. speed=.. throttle=..` for every model that answers `model_state()`, and
## `FLIGHT blend=.. speed=.. yaw_rate=.. lean=.. bank=.. thrust=..` beside it while there is a flight
## pose to report. The plume line is what tells a capture WHICH frame is which throttle (lead r10):
## `MechContact.thruster_level` is 0.0 on the ground, 0.45 in a hover, 0.8 on a dash and 1.0 in an
## assault, and the shots are timed by hand.
func _report(p: Node3D) -> void:
	var model := p.call(&"model") as Node3D if p.has_method(&"model") else null
	if model == null or not model.has_method(&"model_state"):
		return
	var st: Dictionary = model.call(&"model_state")
	var rig: Dictionary = st.get("rig", {})
	print("PLUME state=%s speed=%.1f throttle=%.2f"
			% [st.get("state", "?"), st.get("speed", 0.0), rig.get("thruster_level", 0.0)])
	var f: Dictionary = st.get("flight", {})
	if f.is_empty():
		return
	var shade: Dictionary = rig.get("shade", {})
	print("FLIGHT state=%s blend=%.2f speed=%.1f yaw_rate=%.1f lean=%.1f bank=%.1f thrust=%s "
			% [st.get("state", "?"), f.get("blend", 0.0), f.get("speed", 0.0),
			f.get("yaw_rate", 0.0), f.get("lean", 0.0), f.get("bank", 0.0),
			str(f.get("thrust", Vector3.ZERO))]
		+ "dying=%s power=%.2f" % [str(st.get("dying", false)), shade.get("power", 1.0)])
