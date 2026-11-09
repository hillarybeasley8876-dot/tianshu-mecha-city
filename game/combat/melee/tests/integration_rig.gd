class_name MeleeIntegrationRig
extends RefCounted
## The rig half of the real integration (`integration.gd` owns the beats): the scripted hooks into
## the shipping game — spawning through the real `EnemySpawner`, hard-locking through
## `AimSystem.lock_to`, staggering through the real `StatusComponent`, tapping real input actions and
## saving stills from inside a beat.
##
## Split out so the beat list stays readable; nothing here is melee-specific except the defaults.

const STEP := 1.0 / 120.0
# r12 §3: derived from the project directory — a literal home path breaks on any other checkout.
const OUT_DIR_REL := "captures"
## Lazy: a static initialiser runs before the autoloads exist (city-art r12 §3 `ArtRepo`).
static var OUT_DIR: String = ""
const MAX_SHOTS := 12
const SETTLE_TICKS := 600      ## how long a beat waits for the mech to land after a teleport
const LOCK_TRIES := 4          ## the aim cone is measured from the camera, which lags the body turn
const SPAWN_Y := 3.0           ## the mech's capsule centre on the sandbox floor


var host: Node = null          ## the integration scene (for the tree, the viewport and the counters)
var player: Node3D = null
var spawner: Node = null

var shots: int = 0
var results: PackedStringArray = PackedStringArray()
var failed: int = 0


func setup(host_: Node, player_: Node3D, spawner_: Node) -> void:
	host = host_
	player = player_
	spawner = spawner_


func report(beat: String, ok: bool, detail: String) -> void:
	if not ok:
		failed += 1
	results.append("%s %s — %s" % ["PASS" if ok else "FAIL", beat, detail])
	print("INT %s %s — %s" % ["PASS" if ok else "FAIL", beat, detail])


func spawn(type: StringName, at: Vector3) -> Node3D:
	if spawner == null:
		return null
	return spawner.call(&"spawn", type,
			Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), at)) as Node3D


## Clears the field so each beat starts from a known state, refills the gauge (a beat that ends in a
## guard break must not poison the next one) and waits for the mech to be back on the ground.
func clear_field() -> void:
	if spawner != null:
		spawner.call(&"clear")
	refill()
	await wait(0.1)
	settle()
	await wait(0.15)


func refill() -> void:
	player.set(&"energy", float(player.get(&"energy_max")))
	if player.has_method(&"heal"):
		player.call(&"heal", float(player.get(&"hp_max")))


## Waits for the mech to land: an airborne mech picks the AIR chain and a ground beat would silently
## prove something else.
func settle() -> void:
	for _i in SETTLE_TICKS:
		if bool(player.call(&"is_grounded")):
			break
		await host.get_tree().physics_frame
	await wait(0.2)


func aim_target() -> Node:
	var aim: Node = player.call(&"aim")
	return aim.call(&"hard_target") as Node if aim != null and aim.has_method(&"hard_target") \
			else null


## Faces the target and takes a hard lock the way the game does: `AimSystem.lock_to` is the
## scripted-sequence entry point (CONTRACTS §4) and hands the melee system a `Targetable`, the same
## path a human pressing `lock_on` produces. A monster with no lock point yet gets one, and the lock
## is verified rather than assumed — `_update_hard` drops a lock whose target leaves the hard cone,
## and that cone is measured from the CAMERA, which lags the body turn.
func face_and_lock(target: Node3D) -> bool:
	if target == null:
		return false
	var aim: Node = player.call(&"aim")
	if aim == null or not aim.has_method(&"lock_to"):
		return false
	var marker := lock_point(target)
	if marker == null:
		return false
	for _attempt in LOCK_TRIES:
		var to: Vector3 = target.global_position - player.global_position
		to.y = 0.0
		if to.length_squared() > 0.01:
			player.look_at(player.global_position + to, Vector3.UP)
		await wait(0.35)
		aim.call(&"lock_to", marker)
		await wait(0.15)
		if aim.call(&"hard_target") != null:
			return true
	return false


## The `Targetable` lock point on an enemy; monsters without one get a marker at their centre.
func lock_point(target: Node3D) -> Node:
	for node in target.find_children("*", "Targetable", true, false):
		return node as Node
	var marker := Targetable.new()
	marker.name = "ScriptedLock"
	target.add_child(marker)
	marker.actor_path = marker.get_path_to(target)
	marker.global_position = target.global_position + Vector3.UP * 4.0
	return marker


## Puts the mech `metres` along the target's own facing, looking back at it — the geometry the
## execution cone (±60° of the VICTIM's facing, CONTRACTS §6) is measured in.
func stand_in_front(target: Node3D, metres: float) -> void:
	var forward := -target.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var spot := target.global_position + forward * metres
	teleport(Vector3(spot.x, SPAWN_Y, spot.z))
	var eye := Vector3(target.global_position.x, SPAWN_Y, target.global_position.z)
	player.look_at(eye, Vector3.UP)


func stagger(target: Node3D) -> void:
	var status: Variant = target.get(&"status")
	if status != null and status.has_method(&"add_impact"):
		status.call(&"add_impact", 99999.0)


func teleport(at: Vector3) -> void:
	if player.has_method(&"debug_teleport"):
		player.call(&"debug_teleport", [at.x, at.y, at.z], 0.0)


func flat_gap(target: Node3D) -> float:
	if target == null or not is_instance_valid(target):
		return INF
	var d: Vector3 = target.global_position - player.global_position
	d.y = 0.0
	return d.length()


func distinct(list: Array[StringName]) -> int:
	var seen: Dictionary = {}
	for id in list:
		seen[id] = true
	return seen.size()


func tap(action: StringName, hold_ticks: int) -> void:
	Input.action_press(action)
	for _i in hold_ticks:
		await host.get_tree().physics_frame
	Input.action_release(action)


func wait(seconds: float) -> void:
	for _i in maxi(int(round(seconds / STEP)), 1):
		await host.get_tree().physics_frame


## Waits until `system.phase` is one of `phases`, or the timeout runs out. A beat that has to land a
## press inside a cancel window drives off the state machine, not a stopwatch: a hit-stop holds the
## move clock, so a fixed wait drifts in and out of the window.
func wait_phase(system: Node, phases: Array, timeout: float = 1.5) -> void:
	for _i in maxi(int(round(timeout / STEP)), 1):
		if system.get(&"phase") in phases:
			return
		await host.get_tree().physics_frame


## A still from inside the beat, saved at the next post-draw so the frame is the rendered one.
func shot(tag: String) -> void:
	shots += 1
	if shots > MAX_SHOTS:
		return
	await RenderingServer.frame_post_draw
	if OUT_DIR.is_empty():
		OUT_DIR = ArtRepo.at(OUT_DIR_REL)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/melee_int_%02d_%s.jpg" % [OUT_DIR, shots, tag]
	host.get_viewport().get_texture().get_image().save_jpg(path, 0.85)
	print("INT shot -> ", path)
