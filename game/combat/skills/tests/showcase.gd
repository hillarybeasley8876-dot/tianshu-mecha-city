class_name SkillShowcase
extends Node
## Capture driver for the r1 review: plays the real SkillSystem inside `main.tscn --sandbox` with
## real enemies and the real third-person camera rig (hero ~38 % of screen height), one clip per
## skill, and writes each still at that skill's own peak moment from code.
##
##   tools/godot.sh movie --movie=<abs>/skills_burst.avi --sandbox --skip-menu --god \
##     --enemies=ripper:8,mantis:2,juggernaut:1 --skills-showcase=burst \
##     --shots=<abs captures dir> --timeline=res://combat/skills/tests/timeline_showcase.json
##
## It never fakes a skill: every clip goes through `SkillSystem.try_*`, so the cooldown / EN / input
## path is the one a player uses. `--skills-showcase=all` runs the whole reel in one process.

const SETTLE := 0.6          ## seconds of camera settle after a teleport before anything fires
const ARENA := Vector3(0.0, 8.0, 40.0)

var system: SkillSystem = null
var out_dir: String = ""
var clip: String = "all"

var _player: Node3D = null
var _rig: Node = null


func setup(system_: SkillSystem) -> void:
	system = system_


func start(which: String, dir: String) -> void:
	clip = which
	out_dir = dir
	_run.call_deferred()


func _run() -> void:
	await _wait_for_world()
	if _player == null or _rig == null:
		push_error("SkillShowcase: no player or camera rig in the scene")
		return
	_rig.call(&"set_first_person", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for id: String in _clip_ids():
		await _play(id)
	print("SHOWCASE done")


func _clip_ids() -> PackedStringArray:
	const ALL := ["rift", "anchor", "fins", "ward", "burst", "well", "plunge", "overdrive",
			"lance"]
	if clip == "all":
		return PackedStringArray(ALL)
	return PackedStringArray([clip])


func _play(id: String) -> void:
	print("SHOWCASE clip ", id)
	match id:
		"rift":
			await _clip_rift()
		"anchor":
			await _clip_anchor()
		"fins":
			await _clip_fins()
		"ward":
			await _clip_ward()
		"burst":
			await _clip_burst()
		"well":
			await _clip_well()
		"plunge":
			await _clip_plunge()
		"overdrive":
			await _clip_overdrive()
		"lance":
			await _clip_lance()
		_:
			push_warning("SkillShowcase: unknown clip '%s'" % id)


# --- plumbing ------------------------------------------------------------------------------------

func _wait_for_world() -> void:
	for i in 600:
		if Game.world != null and Game.player != null and Game.camera_rig != null:
			break
		await _frame()
	_player = Game.player as Node3D
	_rig = Game.camera_rig
	await _wait(1.2)
	# the flow unit opens with a drop-in cinematic that parks the camera 90 m out: let it finish (or
	# cut it) before anything is captured, or every still is shot from the cinematic's camera
	await _wait_until(func() -> bool: return not bool(_rig.call(&"is_cinematic")), 20.0)


func _frame() -> void:
	await get_tree().physics_frame


## Waits `seconds` of REAL time (the clips fire slow-mos of their own, so game time is not usable).
func _wait(seconds: float) -> void:
	var until := Feel.real_now() + seconds
	while Feel.real_now() < until:
		await _frame()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("skills_%s.jpg" % name)
	get_viewport().get_texture().get_image().save_jpg(path, 0.9)
	print("SHOWCASE shot -> %s  cam_dist=%.1f %s" % [path,
			_camera_distance(), str(_rig.call(&"hud_state"))])


## Distance from the gameplay camera to the mech: the framing yardstick (the rig targets ~40 % of
## the screen height at its 42 m arm).
func _camera_distance() -> float:
	var cam: Camera3D = _rig.call(&"camera") as Camera3D
	return cam.global_position.distance_to(_player.global_position) if cam != null else -1.0


## Puts the mech on the arena deck with a full gauge, no cooldowns and a clear head, then lets the
## camera settle before the clip fires.
func _place(at: Vector3, yaw_deg: float) -> void:
	if bool(_rig.call(&"is_cinematic")) and _rig.has_method(&"end_cinematic"):
		_rig.call(&"end_cinematic")
	if _player.has_method(&"debug_teleport"):
		_player.call(&"debug_teleport", [at.x, at.y, at.z], yaw_deg)
	if _player.has_method(&"heal"):
		_player.call(&"heal", 99999.0)
	_player.set(&"energy", float(_player.get(&"energy_max")))
	system.reset()
	await _wait(SETTLE)


## Live enemies, nearest first.
## The OD meter is read-only on PlayerMech (CONTRACTS §5), so the meter is filled through the
## unit's own `add_overdrive`.
func _fill_od() -> void:
	if _player.has_method(&"add_overdrive"):
		_player.call(&"add_overdrive", 100.0)


func _enemies() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e != null and e.has_method(&"is_alive") and bool(e.call(&"is_alive")):
			out.append(e)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(_player.global_position) \
				< b.global_position.distance_to(_player.global_position))
	return out


## The nearest live enemy inside `max_range` that is in front of the mech: locking one behind the
## camera puts the whole effect off-frame.
func _front_enemy(max_range: float) -> Node3D:
	var facing := -_player.global_basis.z
	for e in _enemies():
		var to := e.global_position - _player.global_position
		if to.length() > max_range:
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length_squared() > 1.0 and flat.normalized().dot(Vector3(facing.x, 0.0, facing.z)) < 0.2:
			continue
		return e
	return null


func _nearest(max_range: float) -> Node3D:
	for e in _enemies():
		if e.global_position.distance_to(_player.global_position) <= max_range:
			return e
	return null


## Parks a live enemy at a chosen spot so a clip can photograph an effect at a stated range. The
## swarm wanders, and "the fins must read at 100 m" cannot be judged on whatever distance the AI
## happened to pick. `freeze` also stops its own physics so it holds the pose for the whole clip.
## Capture aid only — it never runs in a normal launch.
func _park(e: Node3D, at: Vector3, freeze: bool = false) -> void:
	if e == null or not is_instance_valid(e):
		return
	e.global_position = at
	if e is CharacterBody3D:
		(e as CharacterBody3D).velocity = Vector3.ZERO
	if freeze:
		e.set_physics_process(false)


## Points the real camera rig at a world position (third person, gameplay framing). The angles come
## from the mech's chest, NOT from the camera: the arm orbits the mech, so aiming from the camera
## itself is a feedback loop that walks the view away (tried it — the mech ends up 200 m out).
func _look_at(target: Vector3, pitch_bias: float = 0.0) -> void:
	var to := target - (_player.global_position + Vector3.UP * 11.0)
	if to.length_squared() < 1.0:
		return
	var yaw := rad_to_deg(atan2(-to.x, -to.z))
	var pitch := rad_to_deg(atan2(to.y, Vector2(to.x, to.z).length())) + pitch_bias
	_rig.call(&"set_look", yaw, clampf(pitch, -60.0, 60.0))


## Holds the view on a world point while the rig's spring converges (one `set_look` is not enough:
## the arm eases toward the new angle over ~0.3 s).
func _aim_settle(target: Vector3, pitch_bias: float, seconds: float) -> void:
	var until := Feel.real_now() + seconds
	while Feel.real_now() < until:
		_look_at(target, pitch_bias)
		await _frame()


func _centre_of(e: Node3D) -> Vector3:
	return e.global_position + Vector3.UP * 4.0


## Locks the aim system onto an enemy through its own public entry point.
func _lock(e: Node3D) -> void:
	var aim: Node = _player.call(&"aim") if _player.has_method(&"aim") else null
	if aim == null or e == null:
		return
	for t in e.find_children("*", "Targetable", true, false):
		aim.call(&"lock_to", t)
		return


# --- clips ---------------------------------------------------------------------------------------

## S1: blink behind a locked Ripper. Two stills — the streak mid-transit and the hologram decoy left
## standing at the origin.
func _clip_rift() -> void:
	var e := _nearest(400.0)
	var spot := ARENA
	if e != null:
		spot = e.global_position + Vector3(0.0, 0.0, 60.0)
		spot.y = maxf(e.global_position.y, 8.0)
	await _place(spot, 180.0)
	e = _nearest(120.0)
	if e != null:
		_lock(e)
		await _aim_settle(_centre_of(e), 0.0, 0.45)
	system.try_rift_step()
	# The decoy only stands for 0.6 s and a 1600x900 capture costs ~0.25 s of it, so each read gets
	# its own blink: decoy first (it is live from frame one), then a second blink for the streak.
	await _wait(0.1)
	await _aim_settle(spot + Vector3.UP * 8.0, -2.0, 0.05)
	await _shot("rift_decoy")
	await _place(spot, 180.0)
	if e != null and is_instance_valid(e):
		_lock(e)
		await _aim_settle(_centre_of(e), 0.0, 0.4)
	system.try_rift_step()
	await _wait(0.05)
	if e != null and is_instance_valid(e):
		_look_at(_centre_of(e))
	await _shot("rift_streak")
	await _wait(1.0)


## S2: grapple the sky bridge and reel. The still is mid-reel, where the cable, the latch sparks and
## the speed lines are all live.
func _clip_anchor() -> void:
	await _place(ARENA, 0.0)
	await _aim_settle(_player.global_position + Vector3(0.0, 120.0, -160.0), 26.0, 0.45)
	system.try_anchor()
	await _wait(0.4)
	if system.anchor.is_attached():
		var tip: Vector3 = system.anchor.anchor_point()
		var mid := (_player.global_position + Vector3.UP * 11.0).lerp(tip, 0.7)
		await _aim_settle(mid, 4.0, 0.4)
	await _shot("anchor_reel")
	await _wait(1.2)


## S4 tap: fins on station around a marked target, mid-volley. The target is parked at ~110 m — the
## r2 review asked the volley to read at 100 m, and the swarm never obliges by standing still there.
## Two marks are put on it so the full six-fin volley is what gets photographed (2 + 2 x marks).
func _clip_fins() -> void:
	await _place(ARENA, 180.0)
	var mark := _nearest(400.0)
	var at := _player.global_position
	if mark != null:
		var fwd := -_player.global_basis.z
		fwd.y = 0.0
		at = _player.global_position + fwd.normalized() * 110.0
		_park(mark, at, true)
		var status: Object = system.ctx.status_of(mark)
		if status != null and status.has_method(&"add_marks"):
			status.call(&"add_marks", 2)
		_lock(mark)
		await _aim_settle(_centre_of(mark), 0.0, 0.6)
		_lock(mark)   # the aim system drops a lock it loses sight of; re-assert it before the throw
	system.try_fins()
	await _wait(1.5)
	if mark != null and is_instance_valid(mark):
		_park(mark, at, true)
		_look_at(_centre_of(mark))
		print("SHOWCASE fins target at %.0f m, %d fins" % [
				mark.global_position.distance_to(_player.global_position),
				system.fins.fins_out()])
	await _shot("fins_volley")
	if mark != null and is_instance_valid(mark):
		mark.set_physics_process(true)
	await _wait(1.4)


## S4 hold: the Corona Ward tetrahedron around the hero.
func _clip_ward() -> void:
	await _place(ARENA, 180.0)
	await _aim_settle(_player.global_position + Vector3.UP * 10.0, -6.0, 0.45)
	system.try_ward()
	await _wait(0.7)
	await _shot("ward")
	await _wait(1.0)


## S6: the cyan-white shell at the moment it reaches the 32 m rim.
func _clip_burst() -> void:
	await _place(ARENA, 180.0)
	await _aim_settle(_player.global_position + Vector3.UP * 8.0, -12.0, 0.45)
	system.try_burst()
	await _wait(0.30 + 0.09)
	await _shot("burst_shell")
	await _wait(1.0)


## S7: the violet well, armed, with the inflow running and primed rims on the enemies inside it.
func _clip_well() -> void:
	await _place(ARENA, 180.0)
	var e := _nearest(200.0)
	if e != null:
		_lock(e)
		await _aim_settle(_centre_of(e), -2.0, 0.45)
	system.try_well()
	await _wait(1.9)
	await _aim_settle(system.well.centre() + Vector3.UP * 6.0, -8.0, 0.4)
	await _shot("well_field")
	await _wait(1.2)


## S8: 190 m/s dive from 140 m and the impact column. Two stills — the plasma sheath mid-dive and
## the crater.
func _clip_plunge() -> void:
	var e := _nearest(400.0)
	var over := e.global_position + Vector3(0.0, 150.0, 30.0) if e != null \
			else ARENA + Vector3(0.0, 150.0, 0.0)
	await _place(over, 180.0)
	await _aim_settle(_player.global_position + Vector3(0.0, -60.0, -40.0), -12.0, 0.5)
	Input.action_press(&"melee")
	await _wait(system.tuning.plunge_hold + 0.12)
	Input.action_release(&"melee")
	await _wait(0.35)
	await _shot("plunge_dive")
	await _wait(1.0)
	await _aim_settle(_player.global_position + Vector3.UP * 45.0, 16.0, 0.3)
	await _shot("plunge_impact")
	await _wait(1.2)


## Zenith Overdrive: the gold ignition, the afterimages and the gold rim. Two stills, because the
## r2 review split the read in two — moving (ghosts trailing the mech) and at rest (no ghosts, the
## gold body strips and the rim carry it).
func _clip_overdrive() -> void:
	# out on the empty deck: the r2 complaint was that the ghosts buried the mech, so the read has to
	# be judged against open ground, not against eight Rippers climbing over the hero
	await _place(ARENA + Vector3(0.0, 0.0, -260.0), 180.0)
	_fill_od()
	await _aim_settle(_player.global_position + Vector3.UP * 10.0, -6.0, 0.45)
	system.try_overdrive()
	# the 0.45 s ignition runs inside a 0.3x slow-mo and roots the mech, so nothing moves until it ends
	await _wait_until(func() -> bool: return system.zenith.can_fire_lance(), 4.0)
	# skate across the frame: at the 42 m/s boost the 3 f ghost gap is a 1 m trail, which is what the
	# afterimage cadence is designed to read as — a wake, not five copies of the mech
	Input.action_press(&"move_forward")
	Input.action_press(&"boost")
	await _wait(0.7)
	await _aim_settle(_player.global_position + Vector3.UP * 9.0, -4.0, 0.2)
	await _shot("overdrive")
	Input.action_release(&"boost")
	Input.action_release(&"move_forward")
	await _wait_until(func() -> bool: return system.ctx.planar_speed() < 2.0, 4.0)
	await _wait(0.6)
	await _aim_settle(_player.global_position + Vector3.UP * 10.0, -6.0, 0.35)
	await _shot("overdrive_rest")
	await _wait(1.0)


## Zenith Lance, shot from behind the hero down the beam: the 0.8 s bracket charge and the 3 s beam.
func _clip_lance() -> void:
	await _place(ARENA, 180.0)
	_fill_od()
	# aim down the runway, away from the camera, so the sweep reads from over the mech's shoulder
	await _aim_settle(_player.global_position + Vector3(0.0, 14.0, -300.0), -1.0, 0.5)
	system.try_overdrive()
	# the 0.45 s ignition runs inside a 0.3x slow-mo, so it is ~1.5 real seconds: wait for the state
	await _wait_until(func() -> bool: return system.zenith.can_fire_lance(), 4.0)
	system.zenith.begin_lance()
	await _wait(1.3)
	await _shot("lance_charge")
	await _wait_until(func() -> bool: return not system.zenith.is_charging(), 4.0)
	await _wait(0.35)
	# The beam always converges on the aim at up to 40 deg/s, so a broadside read means out-turning
	# it: swing the view across and shoot while the 800 m beam is still catching up.
	await _aim_settle(_player.global_position + Vector3(320.0, 30.0, -260.0), -2.0, 0.3)
	await _shot("lance_beam")
	await _aim_settle(_player.global_position + Vector3(400.0, 30.0, 40.0), -2.0, 0.35)
	await _shot("lance_sweep")
	await _wait(1.0)


## Real-time wait for a state change, with a cap.
func _wait_until(cond: Callable, timeout: float) -> void:
	var until := Feel.real_now() + timeout
	while Feel.real_now() < until and not bool(cond.call()):
		await _frame()
