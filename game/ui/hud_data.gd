class_name HudData
extends RefCounted
## The HUD's only coupling to gameplay (CONTRACTS §5): each frame it merges `Game.player.hud_state()`
## with every PlayerMech component that implements one, plus the camera rig, into a single flat
## dictionary. Components land at different times, so a missing component or key simply means the
## widget that reads it hides itself (brief §1).
##
## It also keeps the two world queries the overlay needs but no component provides: the nearby enemy
## list (radar / plates / threat arrows) and the hive-spire / boss markers for the compass.

const ENEMY_SCAN_INTERVAL := 0.1     ## s between radar sweeps; ≤40 enemies, no need for 120 Hz
const RADAR_RANGE := 300.0           ## m, brief §5
const PLATE_RANGE := 320.0           ## m, enemy plates are only useful out to lock range
## Blocked-shot cue (lead notes): scenery this close in front of the muzzle stops the shot.
const BLOCK_RANGE := 30.0

var state: Dictionary = {}           ## merged snapshot for this frame
## Test / capture override: when `use_forced` is on, `forced` IS the snapshot and no component is read.
var forced: Dictionary = {}
var use_forced: bool = false
var enemies: Array[Node3D] = []      ## live enemies, sorted by distance
var spires: Array[Node3D] = []       ## hive-spire markers (group &"hive_spire"), may be empty
var boss: Node3D = null              ## group &"boss", may be null
var player: Node3D = null
var camera: Camera3D = null
var first_person: bool = false
## The scale `hud.gd` puts on its root Control (`window_height / 900 × hud_scale`, or the canopy
## ratio in first person). Widgets draw inside that root, so a screen position in canvas pixels has to
## be divided by it to land on the target. 1.0 until `hud.gd` publishes one (tests, tools).
var ui_scale: float = 1.0

var _components: Array[Node] = []
var _refs_t: float = 99.0
var _scan_t: float = 99.0
var _boss_state: Dictionary = {}
var _objective: String = ""
var _spires_done: int = 0
var _spires_total: int = 3


func _init() -> void:
	Events.objective_changed.connect(_on_objective)


## Rebuilds the component list. Called on spawn and then cheaply every second while it is empty.
func refresh_refs() -> void:
	player = Game.player
	_components.clear()
	if player == null:
		return
	if player.has_method(&"hud_state"):
		_components.append(player)
	for child in player.get_children():
		if child.has_method(&"hud_state"):
			_components.append(child)
	var rig := Game.camera_rig
	if rig != null and rig.has_method(&"hud_state"):
		_components.append(rig)


## One frame of HUD data. Safe to call with no player at all (menus, boot).
func poll(delta: float) -> void:
	_refs_t += delta
	_scan_t += delta
	if use_forced:
		_poll_forced()
		return
	if _refs_t >= 1.0:
		_refs_t = 0.0
		if _components.is_empty() or player != Game.player:
			refresh_refs()
	state = {}
	for c in _components:
		if is_instance_valid(c):
			state.merge(c.call(&"hud_state"), true)
	_finish_poll()


func _poll_forced() -> void:
	state = forced.duplicate()
	_finish_poll()


func _finish_poll() -> void:
	state["objective"] = _objective
	state["spires_done"] = _spires_done
	state["spires_total"] = _spires_total
	_prune()
	_sync_boss()
	if not _boss_state.is_empty():
		state["boss"] = _boss_state
	camera = _find_camera()
	first_person = bool(state.get("first_person", false))
	if _scan_t >= ENEMY_SCAN_INTERVAL:
		_scan_t = 0.0
		_scan_world()
	if not use_forced:
		_scan_blocker()


## A monster freed inside the 0.1 s scan window would still be in `enemies` / `spires`, and the radar
## and plates read it every frame (flow r2). Cheap enough to do on every poll at ≤40 entries.
func _prune() -> void:
	# Untyped lambdas: a typed `Node3D` parameter rejects a freed instance before the check can run.
	if enemies.any(func(e: Variant) -> bool: return not is_instance_valid(e)):
		enemies = enemies.filter(func(e: Variant) -> bool: return is_instance_valid(e))
	if spires.any(func(s: Variant) -> bool: return not is_instance_valid(s)):
		spires = spires.filter(func(s: Variant) -> bool: return is_instance_valid(s))
	if boss != null and not is_instance_valid(boss):
		boss = null


## The boss publishes the plate the boss bar reads (CONTRACTS §6), so it is picked up like any other
## actor. `set_boss()` stays the override for tests and for a boss that does not implement it.
func _sync_boss() -> void:
	if use_forced or boss == null or not boss.has_method(&"hud_state"):
		return
	var d: Variant = boss.call(&"hud_state")
	if d is Dictionary and not (d as Dictionary).is_empty():
		_boss_state = d


## Is the player's line of fire stopped by scenery within `BLOCK_RANGE`? Drives the reticle's
## blocked-shot cue (lead notes, critic #12). One ray per frame, scenery only — an enemy in the way is
## a target, not a wall.
func _scan_blocker() -> void:
	state["shot_blocked"] = false
	state["block_dist"] = -1.0
	if player == null or camera == null or not player.is_inside_tree() or not alive():
		return
	var space := player.get_world_3d().direct_space_state
	if space == null:
		return
	var from := player.global_position + Vector3.UP * 4.0
	var dir := -camera.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * BLOCK_RANGE,
			Layers.MASK_SIGHT)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		state["shot_blocked"] = true
		state["block_dist"] = from.distance_to(hit["position"] as Vector3)


## Fake data for tests, the capture harness and the title screen: merges `extra` over a plausible
## idle snapshot so widgets can be exercised without a player.
func inject(extra: Dictionary) -> void:
	state.merge(extra, true)

# --- accessors (never throw on a missing key) -----------------------------------------------------

func num(key: String, fallback: float = 0.0) -> float:
	return float(state.get(key, fallback))


func has(key: String) -> bool:
	return state.has(key) and state[key] != null


func flag(key: String, fallback: bool = false) -> bool:
	return bool(state.get(key, fallback))


func str_of(key: String, fallback: String = "") -> String:
	return String(state.get(key, fallback))


func node(key: String) -> Node3D:
	var n: Variant = state.get(key)
	return n as Node3D if is_instance_valid(n) else null


func ratio(key: String, max_key: String, fallback: float = 0.0) -> float:
	var m := num(max_key, 0.0)
	return fallback if m <= 0.0 else clampf(num(key) / m, 0.0, 1.0)


func alive() -> bool:
	return flag("alive", true)

# --- world scan -----------------------------------------------------------------------------------

func _scan_world() -> void:
	enemies.clear()
	var origin := player.global_position if player != null else Vector3.ZERO
	for n in _group(&"enemy"):
		var e := n as Node3D
		if e == null or (e.has_method(&"is_alive") and not bool(e.call(&"is_alive"))):
			continue
		if e.global_position.distance_squared_to(origin) <= RADAR_RANGE * RADAR_RANGE:
			enemies.append(e)
	enemies.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	spires.clear()
	for n in _group(&"hive_spire"):
		var s := n as Node3D
		if s != null:
			spires.append(s)
	if not spires.is_empty():
		_spires_done = maxi(_spires_total - spires.size(), 0)
	var b := _group(&"boss")
	boss = b[0] as Node3D if not b.is_empty() else null


func _group(name: StringName) -> Array[Node]:
	if player == null or not player.is_inside_tree():
		return []
	return player.get_tree().get_nodes_in_group(name)


func _find_camera() -> Camera3D:
	var rig := Game.camera_rig
	if rig != null and rig.has_method(&"camera"):
		return rig.call(&"camera") as Camera3D
	return null

# --- screen projection ----------------------------------------------------------------------------

## World point -> screen pixels in the widgets' layout space. `visible` is false when the point is
## behind the camera or off the canvas. `unproject_position` speaks root-canvas pixels (1920×1080 under
## the project's stretch), the widgets draw in 1600×900 layout pixels under `ui_scale`, so the point is
## divided by that scale — the on-screen test stays in canvas space, where the viewport rect lives.
func project(world_pos: Vector3) -> Dictionary:
	if camera == null:
		return {"pos": Vector2.ZERO, "visible": false, "dist": INF}
	var behind := camera.is_position_behind(world_pos)
	var p := camera.unproject_position(world_pos)
	var size := camera.get_viewport().get_visible_rect().size
	var on := not behind and p.x >= 0.0 and p.y >= 0.0 and p.x <= size.x and p.y <= size.y
	var d := INF if player == null else player.global_position.distance_to(world_pos)
	return {"pos": p / maxf(ui_scale, 0.05), "visible": on, "dist": d}


## Screen direction from the centre toward `world_pos`, normalised — drives off-screen threat arrows.
func screen_direction(world_pos: Vector3) -> Vector2:
	if camera == null:
		return Vector2.UP
	var local := camera.global_transform.affine_inverse() * world_pos
	var v := Vector2(local.x, -local.y)
	return Vector2.UP if v.length_squared() < 0.0001 else v.normalized()


func enemy_state(e: Node3D) -> Dictionary:
	if e == null or not e.has_method(&"hud_state"):
		return {}
	return e.call(&"hud_state") as Dictionary

# --- flow events ----------------------------------------------------------------------------------

func _on_objective(text: String) -> void:
	_objective = text


## Tests and the flow unit can drive the spire counter directly until it emits an event for it.
func set_spires(done: int, total: int = 3) -> void:
	_spires_done = done
	_spires_total = total


## Boss plate data (brief §5): name, hp/hp_max, cores (Array of 0..1), phase.
func set_boss(data: Dictionary) -> void:
	_boss_state = data


func clear_boss() -> void:
	_boss_state.clear()
