extends Node
## AimSystem test (camera-aim). Run: tools/godot.sh test res://player/aim/tests/test_aim.gd
## Builds a grey-box range with five dummy Targetables, a real CameraRig and an AimSystem, then checks
## the crosshair ray, soft lock, hard lock (select / switch / D-pad switch / LOS loss / death) and the
## missile box. Numbers under test: SPEC §5 — soft lock 7°/300 m, hard lock 450 m with 0.5 s LOS grace,
## paint box 24°×16°; SPEC §3 — the pad's D-pad ← / → switches the hard lock.

const RIG := preload("res://player/camera/camera_rig.tscn")
const AIM := preload("res://player/aim/aim_system.tscn")

## Minimal damageable actor: Targetable.actor() walks up until it finds take_hit.
class Dummy extends StaticBody3D:
	var alive: bool = true
	func take_hit(_hit: HitInfo) -> void:
		pass
	func is_alive() -> bool:
		return alive


const WALL_Z := -600.0
const WALL_THICK := 4.0

var _fails: int = 0
var _rig: Node3D
var _aim: Node
var _targets: Array[Targetable] = []
var _lock_events: Array[Node3D] = []


func _ready() -> void:
	await _build()
	await _test_aim_point()
	await _test_soft_lock()
	await _test_hard_lock()
	await _test_dpad_switch()
	await _test_targets_in_view()
	await _test_los_loss()
	await _test_death_releases()
	_report()


func _build() -> void:
	_box("wall", Vector3(0.0, 30.0, WALL_Z), Vector3(400.0, 120.0, WALL_THICK))
	var player := Node3D.new()
	player.name = "Player"
	add_child(player)
	Game.register_player(player)
	_rig = RIG.instantiate() as Node3D
	add_child(_rig)
	_aim = AIM.instantiate()
	player.add_child(_aim)
	Events.lock_changed.connect(func(t: Node3D) -> void: _lock_events.append(t))
	await _ticks(4)
	# SPEC §5 gives the view a default pitch of −8°; this test aims level so the geometry is readable.
	_rig.call(&"set_look", 0.0, 0.0)
	await _ticks(2)


func _test_aim_point() -> void:
	# No targets yet: the crosshair ray must stop on the wall's front face (Layers.MASK_PLAYER_ATTACK).
	var expected := WALL_Z + WALL_THICK * 0.5
	_check(absf(_aim.aim_point().z - expected) < 0.5,
			"aim_point hits the wall face at z=%.1f (got %.2f)" % [expected, _aim.aim_point().z])
	_check(absf(_aim.aim_point().y - 12.5) < 0.5, "the ray leaves the camera at the 12.5 m pivot (%.2f)"
			% _aim.aim_point().y)
	# The contract the HUD depends on: the aim ray must pass through the SCREEN CENTRE, i.e. the point it
	# returns projects to the middle of the frame (lead, weapons integration).
	var centre := _screen_fraction(_aim.aim_point())
	_check(centre.distance_to(Vector2(0.5, 0.5)) < 0.01,
			"the aim point sits on the screen-centre reticle (%.3f, %.3f)" % [centre.x, centre.y])
	# Parallax: a muzzle 40 m to the right must still be pointed at that same crosshair point.
	var muzzle := Vector3(40.0, 11.0, 0.0)
	var dir: Vector3 = _aim.aim_dir_from(muzzle)
	var want: Vector3 = (_aim.aim_point() - muzzle).normalized()
	_check(dir.distance_to(want) < 0.01, "aim_dir_from corrects the muzzle parallax (%.4f off)"
			% dir.distance_to(want))
	_spawn_targets()
	await _ticks(4)


func _test_soft_lock() -> void:
	var soft := _aim.soft_target() as Targetable
	_check(soft == _targets[0], "soft lock picks the target under the crosshair (%s)" % _name_of(soft))
	_check(_aim.look_speed_scale() < 1.0, "aim assist slows the look rate over a target")
	_check(_aim.assist_delta(1.0 / 120.0).length() < 0.2, "mouse magnetism stays mild")
	# Turning away by 60° puts every dummy outside the 7° mouse cone (SPEC §5). The turn has to be large:
	# the camera orbits the mech at 42 m, so a 30° swing only moves the near dummies ~20° off the reticle.
	_rig.call(&"set_look", 60.0, 0.0)
	await _ticks(4)
	_check(_aim.soft_target() == null, "nothing soft-locks outside the 7° mouse cone")
	# ... and nothing beyond the 300 m soft-lock range either.
	_rig.call(&"set_look", 0.0, 0.0)
	# The cockpit has its own axis: it sits on the mech's centreline, 12 m left of the third-person ray,
	# so the range gets a target on the pilot's line of sight for the first-person check.
	_rig.call(&"set_first_person", true)
	await _ticks(60)
	var eye: Vector3 = _rig.call(&"aim_origin")
	var eye_target := _spawn_target("tp", eye + (_rig.call(&"look_dir") as Vector3) * 120.0)
	await _ticks(4)
	_check(_aim.soft_target() == eye_target, "soft lock holds in first person (%s)"
			% _name_of(_aim.soft_target()))
	eye_target.get_parent().free()
	_rig.call(&"set_first_person", false)
	await _ticks(600)          # the arm pushes back out to 42 m at 10 m/s (SPEC §5)


func _test_hard_lock() -> void:
	_rig.call(&"set_look", 0.0, 0.0)
	await _ticks(4)
	_aim.toggle_lock()
	await _ticks(2)
	var hard := _aim.hard_target() as Targetable
	_check(hard == _targets[0], "hard lock selects the target on the crosshair (%s)" % _name_of(hard))
	_check(_lock_events.size() == 1 and _lock_events[0] == hard, "Events.lock_changed fired once")
	# A flick takes the NEAREST target on that side (angle first, SPEC §5): t1 sits 18° right of the
	# reticle, while the far centre dummy is dead on it and so is not a step to the right.
	var before := _yaw_of(_targets[0])
	_aim.switch_target(1.0)
	await _ticks(2)
	var picked := _aim.hard_target() as Targetable
	_check(picked != null and _yaw_of(picked) > before + 1.0,
			"a right flick moves the lock right (%.1f° → %.1f°, %s)" % [
					before, _yaw_of(picked) if picked != null else 0.0, _name_of(picked)])
	_check(picked == _nearest_on_side(before, 1.0),
			"it picks the nearest target on that side (%s)" % _name_of(picked))
	_aim.switch_target(-1.0)
	await _ticks(2)
	_check(_yaw_of(_aim.hard_target()) < _yaw_of(picked) - 1.0,
			"a left flick moves the lock back (%.1f°)" % _yaw_of(_aim.hard_target()))
	_check(_aim.soft_target() == _aim.hard_target(), "a hard lock drives the assist target")
	_aim.toggle_lock()
	await _ticks(2)
	_check(_aim.hard_target() == null, "lock_on toggles the hard lock off")
	_check(_lock_events.size() == 4 and _lock_events[3] == null, "release is announced with null")


## SPEC §3 / CONTRACTS §5: the pad's D-pad ← / → is the discrete twin of the look flick — same selection,
## one switch per press, dead when a flick would be dead. Raw joypad events go through
## `Input.parse_input_event`, so core's PadInput does the button → action translation exactly as it does
## for a real pad (this is the consumer half of the binding; core owns the producer half).
func _test_dpad_switch() -> void:
	_rig.call(&"set_look", 0.0, 0.0)
	await _ticks(4)
	var events := _lock_events.size()
	await _press_dpad(JOY_BUTTON_DPAD_RIGHT)
	_check(_aim.hard_target() == null and _lock_events.size() == events,
			"D-pad → with no hard lock changes nothing and acquires none (%d events)"
			% (_lock_events.size() - events))
	_aim.toggle_lock()
	await _ticks(2)
	var centre := _aim.hard_target() as Targetable
	_check(centre == _targets[0], "hard lock on the centre dummy before the D-pad test (%s)"
			% _name_of(centre))
	var want_right := _nearest_on_side(_yaw_of(centre), 1.0)
	events = _lock_events.size()
	await _press_dpad(JOY_BUTTON_DPAD_RIGHT)
	var right := _aim.hard_target() as Targetable
	_check(right == want_right, "D-pad → switches to the nearest target on the right (%s, wanted %s)"
			% [_name_of(right), _name_of(want_right)])
	_check(_lock_events.size() == events + 1, "a 0.25 s D-pad hold fires exactly one lock_changed (%d)"
			% (_lock_events.size() - events))
	events = _lock_events.size()
	await _press_dpad(JOY_BUTTON_DPAD_LEFT)
	var back := _aim.hard_target() as Targetable
	_check(back == centre, "D-pad ← switches back to the centre dummy (%s)" % _name_of(back))
	_check(_lock_events.size() == events + 1, "D-pad ← fires exactly one lock_changed (%d)"
			% (_lock_events.size() - events))
	# During a cinematic both flick paths are dead (the rig returns before `_update_look`, and the
	# cinematic disables the look channel), so the D-pad must not switch either.
	var shots: Array = [{"offset": Vector3(0.0, 12.0, 40.0), "look": Vector3.ZERO, "fov": 55.0,
			"t": 0.0}]
	_rig.call(&"request_cinematic", shots, 1.0)
	await _ticks(4)
	_check(_aim.hard_target() == centre, "the lock survives the cinematic framing (%s)"
			% _name_of(_aim.hard_target()))
	events = _lock_events.size()
	await _press_dpad(JOY_BUTTON_DPAD_RIGHT)
	_check(_aim.hard_target() == centre and _lock_events.size() == events,
			"D-pad → during a cinematic does not switch (%s, %d events)"
			% [_name_of(_aim.hard_target()), _lock_events.size() - events])
	_rig.call(&"end_cinematic")
	await _ticks(4)
	_check(_aim.hard_target() == centre, "the lock is still the centre dummy after the cinematic (%s)"
			% _name_of(_aim.hard_target()))
	_aim.toggle_lock()
	await _ticks(2)


## A raw pad press-and-release through the real input pipeline, held 30 physics ticks (0.25 s) so a
## reader that switches on "held" instead of on the press edge shows up as more than one switch.
func _press_dpad(button: int) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button as JoyButton
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await _ticks(30 if pressed else 4)


func _test_targets_in_view() -> void:
	_targets[3].priority = 2.0     # elite: priority outranks the closer one
	var all: Array[Targetable] = _aim.targets_in_view(5, 450.0)
	_check(all.size() == 2, "missile box (24°×16°) holds only the two targets near the crosshair (%d)"
			% all.size())
	_check(all.size() > 0 and all[0] == _targets[3], "targets_in_view sorts by priority first")
	var capped: Array[Targetable] = _aim.targets_in_view(1, 600.0)
	_check(capped.size() == 1, "targets_in_view respects max_count")
	_check(_aim.targets_in_view(5, 100.0).is_empty(), "max_range is honoured")
	_check(_aim.targets_in_view(5, 1000.0).size() == 2, "the 450 m lock range caps an oversized request")
	_targets[3].priority = 1.0


func _test_los_loss() -> void:
	_aim.toggle_lock()
	await _ticks(2)
	_check(_aim.hard_target() != null, "locked again before the sight blocker goes up")
	_box("blocker", Vector3(0.0, 20.0, -60.0), Vector3(300.0, 80.0, 4.0))
	await _ticks(36)             # 0.3 s: still inside the 0.5 s grace (SPEC §5)
	_check(_aim.hard_target() != null, "lock survives 0.3 s of blocked sight")
	await _ticks(48)             # past 0.5 s in total
	_check(_aim.hard_target() == null, "lock drops after 0.5 s without line of sight")


func _test_death_releases() -> void:
	for gone in ["blocker", "t0"]:                   # clear the sight line and the centre target
		var node := get_node_or_null(NodePath(gone))
		if node != null:
			node.free()
	_rig.call(&"set_look", 0.0, 0.0)
	await _ticks(4)
	_aim.toggle_lock()
	await _ticks(2)
	var hard := _aim.hard_target() as Targetable
	_check(hard != null, "re-acquires a lock once the sight line is clear (%s)" % _name_of(hard))
	if hard != null:
		(hard.get_parent() as Dummy).alive = false
		await _ticks(4)
		_check(_aim.hard_target() == null, "a dead target releases the lock")


# --- helpers --------------------------------------------------------------------------------------

## Five targets around the crosshair — centre, right, left, far centre, high left — placed RELATIVE TO
## THE AIM RAY. The third-person camera sits 12 m right of the mech's centreline and 42 m behind it
## (SPEC §5 framing), so world-axis geometry would sit several degrees off the reticle at these ranges.
func _spawn_targets() -> void:
	var spots := [_on_axis(0.0, 0.0, 120.0), _on_axis(18.0, 0.0, 120.0), _on_axis(-18.0, 0.0, 120.0),
			_on_axis(0.0, 0.0, 400.0), _on_axis(-20.0, 10.0, 160.0)]
	for i in spots.size():
		_targets.append(_spawn_target("t%d" % i, spots[i]))


## A point `dist` metres along the view axis, `yaw_deg` / `pitch_deg` off the reticle.
func _on_axis(yaw_deg: float, pitch_deg: float, dist: float) -> Vector3:
	var origin: Vector3 = _rig.call(&"aim_origin")
	var basis := Basis.looking_at(_rig.call(&"look_dir"), Vector3.UP)
	var local := Vector3(tan(deg_to_rad(yaw_deg)), tan(deg_to_rad(pitch_deg)), -1.0).normalized()
	return origin + basis * (local * dist)


## A lockable dummy at `pos`; returns its Targetable mark.
func _spawn_target(target_name: String, pos: Vector3) -> Targetable:
	var body := Dummy.new()
	body.name = target_name
	body.collision_layer = Layers.ENEMY
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 12.0, 8.0)
	shape.shape = box
	body.add_child(shape)
	var mark := Targetable.new()
	mark.name = "Mark"
	body.add_child(mark)
	add_child(body)
	return mark


func _box(box_name: String, centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = centre
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


## Yaw of a target in the view basis, degrees, + = right of the reticle.
func _yaw_of(t: Node3D) -> float:
	if t == null:
		return 0.0
	var cam := _rig.call(&"camera") as Camera3D
	var local := cam.global_basis.inverse() * (t.global_position - cam.global_position)
	return rad_to_deg(atan2(local.x, -local.z))


## The target a flick in `direction` should land on: the smallest angular step past 1° on that side.
func _nearest_on_side(from_deg: float, direction: float) -> Targetable:
	var best: Targetable = null
	var best_delta := INF
	for t in _targets:
		var delta := (_yaw_of(t) - from_deg) * direction
		if delta > 1.0 and delta < best_delta:
			best_delta = delta
			best = t
	return best


## Where a world point lands on a 16:9 frame through the live camera (0.5, 0.5 = the reticle).
func _screen_fraction(world: Vector3) -> Vector2:
	var cam := _rig.call(&"camera") as Camera3D
	var basis := cam.global_basis
	var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
	var v := world - cam.global_position
	var d := v.dot(-basis.z)
	return Vector2(v.dot(basis.x) / (d * tan_v * (16.0 / 9.0)) * 0.5 + 0.5,
			0.5 - v.dot(basis.y) / (d * tan_v) * 0.5)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _name_of(t: Variant) -> String:
	return "null" if t == null else String((t as Node).get_parent().name)


func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_fails += 1


func _report() -> void:
	print("TEST %s (%d failures)" % ["FAILED" if _fails > 0 else "PASSED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
