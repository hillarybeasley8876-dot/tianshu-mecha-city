extends Node3D
## SKACC — the r4 acceptance driver (windowed). Boots `res://main.tscn` in the sandbox with the REAL
## mech, camera rig, aim system and Hero3, and drives every beat through real input: registered
## actions, `InputEventKey` through `Input.parse_input_event`, pad buttons through the `PadInput`
## autoload, and real `lock_on` presses. Nothing here calls `try_*()` — that is the whole point of the
## round: the suites that did passed while a quick Rift Step tap did nothing in the game.
##
##   tools/godot.sh drive --scene=res://combat/skills/tests/skills_accept.tscn \
##     --timeline=res://combat/skills/tests/timeline_accept.json \
##     --sandbox --skip-menu --god --nan-watch [--skacc-beats=rift_taps,well]
##
## Per beat it prints `SKACC <beat> ok=0|1` plus one line per measured row, and writes gameplay-camera
## stills to `<repo>/captures/skills_r4_<beat>_<what>.jpg`.

const MAIN := "res://main.tscn"
const HZ := 120
## Every beat is staged off the sandbox origin so the stills share one skyline.
const O := Vector3(120.0, 0.0, 120.0)
const SETTLE := 0.8
const BEATS: Array[String] = ["rift_taps", "well", "lance", "fins", "anchor"]

var _player: Node3D = null
var _rig: Node = null
var _aim: Node = null
var _skills: Node = null
var _well: Node = null
var _spawner: Node = null
var _rifle: Node = null
var _name: String = ""
var _ok: bool = true
var _shots_dir: String = ""
var _beats: PackedStringArray = PackedStringArray()

var _used: Dictionary = {}          ## skill id -> Array[int] of physics frames
var _collapse_hits: int = 0
var _collapse_amount: float = 0.0
var _prime_events: int = 0
var _prime_counts: int = 0


func _ready() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	main.name = "Main"
	add_child(main)
	_shots_dir = ProjectSettings.globalize_path("res://../captures")
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	_beats = _requested_beats()
	Events.skill_used.connect(_on_used)
	Events.hit_landed.connect(_on_hit)
	Events.prime_collapsed.connect(_on_prime)
	_run.call_deferred()


## `--skacc-beats=a,b` picks beats; the default is all of them.
func _requested_beats() -> PackedStringArray:
	var raw := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--skacc-beats="):
			raw = arg.substr("--skacc-beats=".length())
	if raw.is_empty():
		return PackedStringArray(BEATS)
	var out := PackedStringArray()
	for name in raw.split(",", false):
		if BEATS.has(String(name)):
			out.append(String(name))
		else:
			push_warning("SKACC: unknown beat '%s'" % name)
	return out if not out.is_empty() else PackedStringArray(BEATS)


func _on_used(id: StringName) -> void:
	if not _used.has(id):
		_used[id] = [] as Array[int]
	(_used[id] as Array).append(Engine.get_physics_frames())


func _on_hit(hit: HitInfo, _receiver: Node) -> void:
	if hit == null or hit.source != _player or hit.weapon != &"collapse":
		return
	_collapse_hits += 1
	_collapse_amount = maxf(_collapse_amount, hit.amount)


func _on_prime(_centre: Vector3, count: int) -> void:
	_prime_events += 1
	_prime_counts += count


func _count(id: StringName) -> int:
	return (_used.get(id, []) as Array).size()


func _latency(id: StringName, n: int, f0: int) -> int:
	var list: Array = _used.get(id, []) as Array
	if n < 0 or n >= list.size():
		return -1
	return int(list[n]) - f0


# --- plumbing --------------------------------------------------------------------------------------

func _run() -> void:
	for _i in 12000:
		_player = Game.player as Node3D
		if _player != null and Game.world_built() and Game.camera_rig != null:
			break
		await get_tree().physics_frame
	if _player == null:
		print("SKACC boot ok=0 no player")
		_quit()
		return
	_rig = Game.camera_rig
	_aim = _player.call(&"aim")
	for c in _player.get_children():
		if c is SkillSystem:
			_skills = c
		elif c is WeaponSystem:
			_rifle = c.get(&"rifle") as Node
	_well = _skills.get(&"well") as Node if _skills != null else null
	_spawner = get_tree().root.find_child("EnemySpawner", true, false)
	_rig.call(&"set_first_person", false)
	await _wait(1.5)
	await _wait_until(func() -> bool: return not bool(_rig.call(&"is_cinematic")), 20.0)
	print("SKACC boot ok=1 rig=%s aim=%s skills=%s well=%s spawner=%s rifle=%s beats=%s" % [
			_rig != null, _aim != null, _skills != null, _well != null, _spawner != null,
			_rifle != null, ",".join(_beats)])
	for name in _beats:
		await _beat(name)
	print("SKACC all done")
	_quit()


func _quit() -> void:
	await _wait(0.4)
	get_tree().set(&"_end_t", 0.0)


func _beat(name: String) -> void:
	_name = name
	_ok = true
	if not await _world_alive():
		print("SKACC %s ok=0 WORLD FROZEN — the mech does not respond to a teleport; the shared tree "
				% name + "is being edited by another unit mid-run, so no row below means anything")
		_ok = false
		return
	_collapse_hits = 0
	_collapse_amount = 0.0
	_prime_events = 0
	_prime_counts = 0
	print("SKACC %s begin" % name)
	match name:
		"rift_taps":
			await _beat_rift_taps()
		"well":
			await _beat_well()
		"lance":
			await _beat_lance()
		"fins":
			await _beat_fins()
		"anchor":
			await _beat_anchor()
		_:
			_ok = false
	print("SKACC %s ok=%d" % [name, 1 if _ok else 0])


## Can the mech still be moved at all? The tree is shared and edited live by other units, so a
## mid-edit flow or city change can leave the world frozen; twenty rows measured against a frozen mech
## would all be misleading. One cheap teleport answers it.
func _world_alive() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var before := _player.global_position
	_player.call(&"debug_teleport", [before.x, before.y - 3.0, before.z], 0.0)
	await _ticks(8)
	var answered := absf(_player.global_position.y - (before.y - 3.0)) > 0.05
	_player.call(&"debug_teleport", [before.x, before.y, before.z], 0.0)
	await _ticks(4)
	return answered


## Records one measured row and folds it into the beat's verdict.
func _row(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_ok = false
	print("SKACC %s %s %s%s" % [_name, label, "ok" if ok else "FAIL", "" if detail == "" else " " + detail])


func _wait(seconds: float) -> void:
	var until := Feel.real_now() + seconds
	while Feel.real_now() < until:
		await get_tree().physics_frame


func _ticks(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _wait_until(cond: Callable, seconds: float) -> bool:
	var until := Feel.real_now() + seconds
	while Feel.real_now() < until:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
	return bool(cond.call())


func _tap(action: StringName, ticks: int = 6) -> void:
	Input.action_press(action)
	await _ticks(ticks)
	Input.action_release(action)


func _key(key: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _joy(button: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _unlock() -> void:
	if _aim != null and _aim.call(&"hard_target") != null:
		_aim.call(&"lock_to", null)


## Full gauge, no cooldowns, no lock, mech on the beat's spot and the camera settled behind it.
func _reset(at: Vector3, yaw_deg: float) -> void:
	for a: StringName in [&"fire", &"well", &"lock_on", &"aim", &"rift_step", &"anchor", &"fins",
			&"overdrive", &"burst", &"melee"]:
		Input.action_release(a)
	_unlock()
	await get_tree().physics_frame
	if _spawner != null:
		_spawner.call(&"clear")
	_player.set(&"energy", float(_player.get(&"energy_max")))
	_player.call(&"heal", float(_player.get(&"hp_max")))
	_player.call(&"debug_teleport", [at.x, at.y, at.z], yaw_deg)
	_rig.call(&"set_look", yaw_deg, -6.0)
	_rig.call(&"snap_to_player")
	_skills.call(&"reset_all_cooldowns")
	await _wait(SETTLE)


func _spawn(type: StringName, at: Vector3) -> Node3D:
	var look := _player.global_position - at
	look.y = 0.0
	return _spawner.call(&"spawn", type, Transform3D(Basis.looking_at(look.normalized(),
			Vector3.UP), at)) as Node3D


func _lock_point(target: Node3D) -> Node3D:
	for node in target.find_children("*", "Targetable", true, false):
		return node as Node3D
	return null


## The rig's own convention: yaw = atan2(-x, -z), pitch up +, measured from `aim_origin`.
func _look_at(p: Vector3) -> void:
	var from: Vector3 = _rig.call(&"aim_origin")
	var dir := (p - from).normalized()
	_rig.call(&"set_look", rad_to_deg(atan2(-dir.x, -dir.z)),
			rad_to_deg(asin(clampf(dir.y, -1.0, 1.0))))


## Real lock: aim at the lock point, press lock_on (Tab / MMB / R3), and confirm the aim system took it.
func _lock(target: Node3D) -> bool:
	for _attempt in 4:
		var lp := _lock_point(target)
		if lp == null:
			return false
		_look_at(lp.global_position)
		await _wait(0.3)
		if _aim.call(&"hard_target") != null:
			return true
		await _tap(&"lock_on", 4)
		await _wait(0.15)
		if _aim.call(&"hard_target") != null:
			return true
	return false


## Points the real aim at a surface whose AIM POINT lands between `min_d` and `max_d` metres of the
## mech, so the cable has something to bite inside its 120 m range. It probes through the aim system
## rather than with its own ray: the aim ray starts at the CAMERA, 45 m behind and above the chest, so
## a hand-rolled ray finds a spot the aim then overshoots (the first version of this beat aimed 125 m
## out and the cable ran out of line). Returns Vector3.INF when the sky is all there is.
func _surface_in_range(min_d: float, max_d: float) -> Vector3:
	for pitch: float in [-6.0, -12.0, -20.0, -30.0, -44.0]:
		_rig.call(&"set_look", 0.0, pitch)
		await _wait(0.25)
		var ap: Vector3 = _aim.call(&"aim_point")
		var d := _flat(ap, _player.global_position)
		if d >= min_d and d <= max_d:
			return ap
	return Vector3.INF


func _v(p: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [p.x, p.y, p.z]


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Degrees a 40 deg/s sweep may cover in one 120 Hz physics tick.
func hz_cap() -> float:
	return 40.0 / float(HZ)


## The ZenithLance node itself (beam_dir and the beam state live there, not on ZenithOverdrive).
func _lance() -> Node:
	return _skills.get(&"zenith").get(&"lance") as Node


func _cam_dist() -> float:
	var cam: Camera3D = _rig.call(&"camera") as Camera3D
	return cam.global_position.distance_to(_player.global_position) if cam != null else -1.0


func _shot(what: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/skills_r4_%s_%s.jpg" % [_shots_dir, _name, what]
	get_viewport().get_texture().get_image().save_jpg(path, 0.9)
	print("SKACC %s shot %s cam_dist=%.1f" % [_name, path, _cam_dist()])


# --- beat: rift_taps --------------------------------------------------------------------------------

## r4 item 1. Every row is a REAL press of a different length or through a different path; each must
## fire `skill_used(rift_step)` no more than 2 physics ticks after the press and move the mech.
func _beat_rift_taps() -> void:
	for ticks: int in [1, 2, 3, 4, 6, 10, 20]:
		await _reset(O + Vector3(0.0, 8.0, 0.0), 0.0)
		var home := _player.global_position
		var n0 := _count(&"rift_step")
		await get_tree().physics_frame
		var f0 := Engine.get_physics_frames()
		Input.action_press(&"rift_step")
		await _ticks(ticks)
		Input.action_release(&"rift_step")
		if ticks == 1:
			await _shot("tap1")
		await _wait(0.5)
		var lat := _latency(&"rift_step", n0, f0)
		var moved := _flat(_player.global_position, home)
		_row("hold_%dt" % ticks, lat >= 0 and lat <= 2 and moved > 10.0,
				"lat=%d moved=%.1fm" % [lat, moved])

	# KEY_C down and up a frame apart
	await _reset(O + Vector3(0.0, 8.0, 0.0), 0.0)
	var home := _player.global_position
	var n0 := _count(&"rift_step")
	await get_tree().process_frame
	var f0 := Engine.get_physics_frames()
	_key(KEY_C, true)
	await get_tree().process_frame
	_key(KEY_C, false)
	await _wait(0.5)
	var lat := _latency(&"rift_step", n0, f0)
	_row("key_c_1f", lat >= 0 and lat <= 2 and _flat(_player.global_position, home) > 10.0,
			"lat=%d moved=%.1fm" % [lat, _flat(_player.global_position, home)])

	# pad RB+B for a frame
	await _reset(O + Vector3(0.0, 8.0, 0.0), 0.0)
	home = _player.global_position
	n0 = _count(&"rift_step")
	await get_tree().process_frame
	_joy(JOY_BUTTON_RIGHT_SHOULDER, true)
	await get_tree().process_frame
	f0 = Engine.get_physics_frames()
	_joy(JOY_BUTTON_B, true)
	await get_tree().process_frame
	_joy(JOY_BUTTON_B, false)
	await get_tree().process_frame
	_joy(JOY_BUTTON_RIGHT_SHOULDER, false)
	await _wait(0.5)
	lat = _latency(&"rift_step", n0, f0)
	_row("pad_rb_b_1f", lat >= 0 and lat <= 2 and _flat(_player.global_position, home) > 10.0,
			"lat=%d moved=%.1fm" % [lat, _flat(_player.global_position, home)])

	# the autoplay "tap": pressed in the process phase, released 3 frames later
	await _reset(O + Vector3(0.0, 8.0, 0.0), 0.0)
	home = _player.global_position
	n0 = _count(&"rift_step")
	await get_tree().process_frame
	f0 = Engine.get_physics_frames()
	Input.action_press(&"rift_step")
	for _i in 3:
		await get_tree().process_frame
	Input.action_release(&"rift_step")
	await _wait(0.5)
	lat = _latency(&"rift_step", n0, f0)
	_row("autoplay_tap_3f", lat >= 0 and lat <= 2 and _flat(_player.global_position, home) > 10.0,
			"lat=%d moved=%.1fm" % [lat, _flat(_player.global_position, home)])
	await _shot("streak")


# --- beat: well -------------------------------------------------------------------------------------

## r4 item 2. A juggernaut 42 m ahead: (a) hard-locked, (b) no lock with the reticle on its body, and
## (c) a stage-2 rifle shot into the primed body, which must resolve one COLLAPSE.
func _beat_well() -> void:
	# (a) hard lock
	await _reset(O + Vector3(0.0, 8.0, 0.0), 0.0)
	var target := _spawn(&"juggernaut", O + Vector3(0.0, 0.0, -42.0))
	await _wait(0.3)
	var locked := await _lock(target)
	_row("hard_lock", locked, "hard_target=%s" % locked)
	await _wait(1.0)
	var armed := await _throw_well(target)
	_row("lock_armed_on_target", armed <= 24.0, "armed %.1f m from the locked body" % armed)
	await _shot("locked_field")

	# (b) no lock, reticle on the body
	await _reset(O + Vector3(0.0, 8.0, 0.0), 0.0)
	target = _spawn(&"juggernaut", O + Vector3(0.0, 0.0, -42.0))
	await _wait(0.3)
	_unlock()
	var lp := _lock_point(target)
	if lp != null:
		_look_at(lp.global_position)
		await _wait(0.4)
		_look_at(lp.global_position)
		await _wait(0.2)
	_row("no_lock", _aim.call(&"hard_target") == null,
			"hard_target=%s" % (_aim.call(&"hard_target") != null))
	armed = await _throw_well(target)
	_row("reticle_armed_on_body", armed <= 24.0, "armed %.1f m from the body under the reticle" % armed)
	await _shot("reticle_field")

	# (c) detonate: hold fire 1.3 s so the rifle reaches stage 2. Counted in PHYSICS TICKS, not
	# `Feel.real_now()`: with every heavy slot busy a frame can take 0.4 s, Godot clamps physics to 8
	# steps a frame, and the rifle's 1.2 s stage-2 charge then needs six times the wall clock. A
	# real-clock hold silently under-charges the shot and the collapse never fires.
	await _reload_rifle()
	var collapsed0 := int(_well.call(&"collapsed_count"))
	_collapse_hits = 0
	_prime_events = 0
	Input.action_press(&"fire")
	await _ticks(160)
	Input.action_release(&"fire")
	await _ticks(120)
	var collapsed := int(_well.call(&"collapsed_count")) - collapsed0
	_row("collapse_resolved", collapsed == 1, "well.collapsed_count +%d" % collapsed)
	_row("collapse_damage", _collapse_hits >= 1 and _collapse_amount >= 890.0,
			"%d collapse hits, biggest %.0f" % [_collapse_hits, _collapse_amount])
	_row("collapse_event", _prime_events == 1 and _prime_counts == 1,
			"%d prime_collapsed events for %d primes" % [_prime_events, _prime_counts])
	await _shot("collapse")


## Presses G (the real `well` action), follows the core until the field arms, and returns the flat
## distance from the field centre to `target` (-1 when it never armed).
func _throw_well(target: Node3D) -> float:
	var waited := 0.0
	while not bool(_well.call(&"can_begin")) and waited < 8.0:
		await get_tree().physics_frame
		waited += 1.0 / float(HZ)
	await _tap(&"well", 6)
	var arm := Vector3.INF
	for _i in 360:
		await get_tree().physics_frame
		if bool(_well.call(&"is_active")):
			arm = _well.call(&"centre")
			break
	await _ticks(180)
	var primed := false
	if is_instance_valid(target):
		var st: Variant = target.get(&"status")
		primed = st != null and bool((st as Object).call(&"is_primed"))
	if arm == Vector3.INF:
		_row("armed", false, "the core never armed")
		return -1.0
	_row("primed", primed, "target_primed=%s" % primed)
	return _flat(arm, target.global_position) if is_instance_valid(target) else -1.0


func _reload_rifle() -> void:
	if _rifle == null:
		return
	var mag := int((_rifle.get(&"tuning") as Object).get(&"magazine"))
	if int(_rifle.get(&"ammo")) < mag:
		await _tap(&"reload", 4)
		await _ticks(260)
	if int(_rifle.get(&"ammo")) < mag:
		_rifle.call(&"reset_state")


# --- beat: lance ------------------------------------------------------------------------------------

## r4 item 3. Hold V to ignite, release, then TAP V to fire the Lance. Stills are taken from the real
## third-person rig at its gameplay arm, level down the runway, mid-sweep, pitched into the sky, and one
## first-person frame.
func _beat_lance() -> void:
	await _reset(O + Vector3(0.0, 8.0, 0.0), 0.0)
	_player.call(&"add_overdrive", 100.0)
	_look_at(O + Vector3(0.0, 60.0, -600.0))
	await _wait(0.3)
	Input.action_press(&"overdrive")
	await _wait(0.6)
	var ignited := bool(_skills.call(&"is_overdrive_active"))
	Input.action_release(&"overdrive")
	_row("hold_ignites", ignited, "overdrive_active=%s after a 0.6 s hold" % ignited)
	_row("hold_does_not_fire", not bool(_skills.get(&"zenith").call(&"is_charging")),
			"charging=%s after the same hold" % bool(_skills.get(&"zenith").call(&"is_charging")))
	await _wait_until(func() -> bool: return bool(_skills.get(&"zenith").call(&"can_fire_lance")), 6.0)
	await _shot("overdrive")

	# level down the runway: the beam should read as a round tube of light with depth
	_rig.call(&"set_look", 0.0, 0.0)
	await _wait(0.5)
	var n0 := 0
	await get_tree().physics_frame
	var f0 := Engine.get_physics_frames()
	Input.action_press(&"overdrive")
	await _ticks(2)
	Input.action_release(&"overdrive")
	var started := await _wait_until(
			func() -> bool: return bool(_skills.get(&"zenith").call(&"is_charging")), 1.0)
	_row("tap_fires_the_lance", started, "charging=%s after a V tap" % started)
	_row("tap_latency", Engine.get_physics_frames() - f0 <= 4,
			"charging started %d ticks after the press" % (Engine.get_physics_frames() - f0))
	await _wait_until(func() -> bool: return bool(_lance().call(&"is_beaming")), 4.0)
	await _wait(0.35)
	_row("gameplay_arm", _cam_dist() > 20.0, "the camera is %.1f m from the mech" % _cam_dist())
	await _shot("beam_level")
	n0 += 1

	# Mid-sweep: the beam may only turn 40 deg/s. Measured PER PHYSICS TICK, not per real second: under
	# a windowed run at 1600x900 a frame can exceed Feel's 0.1 s real_dt clamp, so `Feel.real_now()`
	# under-counts and any real-clock window here would over-measure the sweep.
	var prev: Vector3 = _lance().call(&"beam_dir")
	_rig.call(&"set_look", 34.0, 0.0)
	var worst := 0.0
	var turned := 0.0
	for _i in 60:
		await get_tree().physics_frame
		var now: Vector3 = _lance().call(&"beam_dir")
		var step := rad_to_deg(prev.angle_to(now))
		worst = maxf(worst, step)
		turned += step
		prev = now
	var cap := hz_cap()
	_row("sweep_rate", worst <= cap * 1.5,
			"worst single-tick turn %.3f deg, the 40 deg/s cap is %.3f deg/tick (%.1f deg over 60 ticks)"
			% [worst, cap, turned])
	await _shot("beam_sweep")

	# pitched ~15 deg into the sky, so the beam is read against the r15 sky rather than the deck
	_rig.call(&"set_look", 0.0, 15.0)
	await _wait(0.6)
	await _shot("beam_sky")

	# one first-person frame: the muzzle is 2 m from the lens, so this is the whiteout test
	_rig.call(&"set_first_person", true)
	await _wait(0.4)
	await _shot("beam_first_person")
	_rig.call(&"set_first_person", false)
	await _wait(0.3)
	await _wait_until(func() -> bool: return not bool(_lance().call(&"is_running")), 16.0)


# --- beat: fins -------------------------------------------------------------------------------------

## r4 item 4. A real Z tap at a target locked ~60 m out: the still 0.3 s later must show the blades
## GONE from the back, and the still 0.3 s after the dock must show them back.
func _beat_fins() -> void:
	await _reset(O + Vector3(0.0, 8.0, 0.0), 0.0)
	var target := _spawn(&"spitter", O + Vector3(0.0, 0.0, -60.0))
	await _wait(0.4)
	var took := await _lock(target)
	_row("locked", took, "hard_target=%s" % took)
	await _wait(0.6)
	var n0 := _count(&"fins")
	await _tap(&"fins", 4)
	# the tap fires on the RELEASE, which is the tick after `_tap` returns: settle before counting
	await _ticks(6)
	_row("tap_sends", _count(&"fins") > n0, "skill_used(fins)=%d" % (_count(&"fins") - n0))
	await _wait(0.3)
	var mask: int = int(_player.call(&"model").call(&"drones_docked"))
	_row("blades_leave_the_back", mask != 0, "the hero kept every blade (mask %d)" % mask)
	_row("drone_1_stays_docked", (mask & 1) == 0, "Drone_1 was deployed, no fin maps to it")
	await _shot("out")
	# the volley lands while the blades are still out
	await _wait(1.6)
	await _shot("volley")
	await _wait_until(func() -> bool: return int(_skills.get(&"fins").call(&"fins_out")) == 0, 8.0)
	await _wait(0.3)
	var back: int = int(_player.call(&"model").call(&"drones_docked"))
	_row("blades_return", back == 0, "mask %d after every fin docked" % back)
	await _shot("docked")


# --- beat: anchor -----------------------------------------------------------------------------------

## r4 item 5. The cable must leave a CONTRACTS §5 socket on the LEFT ARM (`hand_l`), not the torso: the
## stills are taken from the gameplay arm while the line is taut, and the run must log no
## `no socket named` at all (the autoplay error counter reports any).
func _beat_anchor() -> void:
	# Aim at a surface the SKILL can actually bite: the sandbox geometry around the origin is the
	# level's, not ours, so the beat probes for a hit inside the 120 m range instead of trusting a
	# hand-picked point that may be open sky.
	await _reset(O + Vector3(0.0, 8.0, 0.0), 0.0)
	var anchor := _skills.get(&"anchor") as Node
	var attached := false
	var states: Array[int] = []
	var aim_pt := Vector3.ZERO
	# The Skyhook carries two charges, so the beat may use both: the sandbox geometry around the
	# origin is the level's, and whether a given line is clear depends on what earlier beats left in
	# the world. Re-probe and re-throw once rather than reporting a miss the skill did not cause.
	for attempt in 2:
		var bite := await _surface_in_range(30.0, 100.0)
		_row("found_a_surface_%d" % attempt, bite != Vector3.INF,
				"nearest usable surface at %s" % _v(bite))
		await _wait(0.3)
		var n0 := _count(&"anchor")
		var from := _player.call(&"model").call(&"socket", &"hand_l") as Node3D
		_row("hand_l_socket_exists", from != null, "socket node=%s" % (from != null))
		var cable_from := from.global_position if from != null else Vector3.ZERO
		var chest := _player.global_position + Vector3.UP * 4.0
		_row("hand_l_is_off_the_torso", cable_from.distance_to(chest) > 3.0,
				"hand_l is %.1f m from the chest pivot" % cable_from.distance_to(chest))
		await get_tree().physics_frame
		var f0 := Engine.get_physics_frames()
		await _tap(&"anchor", 4)
		await _ticks(4)
		_row("tap_fires_%d" % attempt, _count(&"anchor") > n0,
				"skill_used(anchor)=%d" % (_count(&"anchor") - n0))
		_row("fire_latency_%d" % attempt, _latency(&"anchor", n0, f0) <= 4,
				"fired %d ticks after the press" % _latency(&"anchor", n0, f0))
		aim_pt = _aim.call(&"aim_point")
		states.clear()
		for _i in 360:
			await get_tree().physics_frame
			var st := int(anchor.call(&"state"))
			if states.is_empty() or states[-1] != st:
				states.append(st)
			if bool(anchor.call(&"is_attached")):
				attached = true
				break
		if attached:
			break
		await _wait(0.4)
	_row("latched", attached, "attached=%s aim_point=%s flat=%.1fm states=%s" % [attached,
			_v(aim_pt), _flat(aim_pt, _player.global_position), str(states)])
	await _wait(0.35)
	await _shot("cable")
	var tip: Vector3 = _skills.get(&"anchor").call(&"anchor_point")
	var drawn_from := _player.call(&"model").call(&"socket", &"hand_l") as Node3D
	var off := 0.0
	if drawn_from != null:
		off = _flat(drawn_from.global_position, _player.global_position)
	_row("cable_leaves_the_left_arm", off > 2.0,
			"the cable's near end is %.1f m off the body centreline" % off)
	_row("cable_reaches_out", _flat(tip, _player.global_position) > 30.0,
			"anchor point %.1f m out, inside the %.0f m range"
			% [_flat(tip, _player.global_position), float(_skills.get(&"tuning").get(&"anchor_range"))])
	await _wait(1.2)
	await _shot("reel")
	# let go so the next beat starts clean
	await _tap(&"anchor", 4)
	await _wait(0.5)
