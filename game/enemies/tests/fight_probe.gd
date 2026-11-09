extends Node3D
## Fight integration probe (enemies unit): boots the real `res://main.tscn` — PlayerMech, camera
## rig, HUD, feel and the enemy spawner — and watches the fight through the Events bus only.
## Nothing here fakes a hit: every line it prints comes from the player's own damage pipeline or
## from a monster's telegraph, so the captures and the status file describe the shipping build.
##
## It also *directs* two beats a fixed timeline cannot time, because only the AI knows when it will
## commit: it taps `boost` inside a ripper leap's active window (perfect dodge) and `jump` as a
## juggernaut ring closes. Running, shots and the capture times stay in `fight_timeline.json`.
##
##   tools/godot.sh drive --scene=res://enemies/tests/fight_probe.tscn \
##     --timeline=res://enemies/tests/fight_timeline.json --out=enemies_fight \
##     --shots=6,11,16,21,26,31 --sandbox --enemies=ripper:8,mantis:2,spitter:2,harrier:2,juggernaut:1

const MAIN := "res://main.tscn"
const DODGE_LEAD := 0.06      ## tap boost this long before the leap's active window opens
const JUMP_LEAD := 30.0       ## metres between the closing ring and the player when we jump
const TAP_FRAMES := 4
const SUMMARY_EVERY := 6.0
const SHOT_RANGE := 55.0   ## a tell further away than this is a speck: wait for a closer one
const RING_SHOT_RADIUS := 28.0
const FOLLOW_RANGE := 70.0   ## how far the follow camera will chase the nearest monster

var _t: float = 0.0
var _taps: Dictionary = {}          ## StringName -> frames left held
var _dodge_at: float = -1.0
var _jump_at: float = -1.0
var _summary_at: float = SUMMARY_EVERY
var _player: Node3D = null
var _dodges: int = 0
var _hits_taken: int = 0
var _damage_taken: float = 0.0
var _knockbacks: int = 0
var _telegraphs: int = 0
var _kills: int = 0
var _staggers: int = 0
var _died: bool = false
var _jump_beats: int = 0
var _dodge_beats: int = 0
var _rings: int = 0
var _last_ring: EnemyShockwave = null
var _by_weapon: Dictionary = {}
var _by_telegraph: Dictionary = {}
var _shots: Array[String] = []
var _cam: Camera3D
var _pack_shot: bool = false
var _glint_shot: bool = false
var _red_shot: bool = false
var _dodge_shot: bool = false
var _ring_shot: bool = false
var _ring_jumped: bool = false
var _pending: Array[Dictionary] = []
var _follow: bool = false
var _hurt_shot: bool = false
var _traced: Dictionary = {}   ## monster instance id -> {action id: plays already logged}
var _near_misses: int = 0      ## Feel.play(&"near_miss") calls from enemy fire
var _near_played: int = 0     ## of those, the ones the director actually played (its 0.25 s row)
var _director_node: Node = null


func _ready() -> void:
	var packed := load(MAIN) as PackedScene
	if packed == null:
		push_error("FightProbe: cannot load " + MAIN)
		return
	var main := packed.instantiate()
	main.name = "Main"
	add_child(main)
	_cam = Camera3D.new()
	_cam.name = "ProbeCamera"
	_cam.fov = 62.0
	_cam.far = 4000.0
	add_child(_cam)
	_follow = Game.flag("probe-cam") == "follow"
	Events.enemy_telegraph.connect(_on_telegraph)
	Events.player_damaged.connect(_on_player_damaged)
	Events.perfect_dodge.connect(_on_perfect_dodge)
	Events.player_died.connect(_on_player_died)
	Events.enemy_staggered.connect(_on_staggered)
	Events.enemy_killed.connect(_on_killed)
	Events.world_ready.connect(_on_world_ready, CONNECT_ONE_SHOT)


func _on_world_ready() -> void:
	_player = Game.player
	print("FIGHT world ready, player=%s, launching with the mix from --enemies=" % str(_player))


func _physics_process(delta: float) -> void:
	_t += delta
	_hold_taps()
	_run_pending()
	_trace_actions()
	_drain_near_misses()
	_watch_director()
	if _died or _player == null or not is_instance_valid(_player):
		return
	_director(delta)
	if _follow:
		_follow_cam()
	if _t >= _summary_at:
		_summary_at += SUMMARY_EVERY
		_summary("t=%.0fs" % _t)


# --- director --------------------------------------------------------------------------------

## Two scheduled inputs: the dash that has to land inside the leap, and the jump over the ring.
func _director(_delta: float) -> void:
	if _dodge_at >= 0.0 and _t >= _dodge_at:
		_dodge_at = -1.0
		_dodge_beats += 1
		_tap(&"boost")
		print("FIGHT %.2fs dodge tap (ripper leap active window)" % _t)
	if _jump_at >= 0.0 and _t >= _jump_at:
		_jump_at = -1.0
		_tap(&"jump")
	var ring := _nearest_ring()
	if ring != null and _jump_at < 0.0:
		if ring != _last_ring:
			_last_ring = ring
			_rings += 1
			print("FIGHT %.2fs juggernaut slam ring #%d spawned" % [_t, _rings])
		if not _ring_shot and ring.radius > RING_SHOT_RADIUS:
			_ring_shot = true     ## wait for the ring to open up; at spawn it is a point
			_capture.call_deferred(&"shockwave", ring)
		var gap := Vector2(_player.global_position.x - ring.global_position.x,
				_player.global_position.z - ring.global_position.z).length() - ring.radius
		if gap < JUMP_LEAD and gap > 0.0 and not _ring_jumped:
			_ring_jumped = true    ## one jump per ring; re-arming every frame spams the input
			_jump_at = _t
			_jump_beats += 1
			print("FIGHT %.2fs shockwave closing (%.0f m) — jumping" % [_t, gap])
	elif ring == null:
		_ring_jumped = false
		_last_ring = null
	if not _pack_shot:
		var near := _nearest_enemy(90.0)
		if near != null and _crowd_within(90.0) >= 4:
			_pack_shot = true
			_capture.call_deferred(&"pack", near)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	_taps[action] = TAP_FRAMES


func _hold_taps() -> void:
	for action: StringName in _taps.keys():
		_taps[action] = int(_taps[action]) - 1
		if int(_taps[action]) <= 0:
			Input.action_release(action)
			_taps.erase(action)


## Live slam rings are in group &"enemy_shockwave" (the juggernaut parents them to the spawner).
func _nearest_ring() -> EnemyShockwave:
	for n: Node in get_tree().get_nodes_in_group(&"enemy_shockwave"):
		return n as EnemyShockwave
	return null


# --- captures --------------------------------------------------------------------------------

## The stills are framed by the probe's own camera, not the shipping rig: the rig sits close behind
## the mech, which is right for playing and useless for showing what a 22 m brute is doing to it.
## The beats are real — every shot below is triggered by a live event, not by a clock.
## `--probe-cam=follow` keeps the framing camera on the fight for the whole run, which is what the
## movie wants: the shipping third-person rig sits close behind the mech and hides the pack.
func _follow_cam() -> void:
	if not _cam.current:
		_cam.current = true
	var focus := _nearest_enemy(FOLLOW_RANGE)
	if focus != null:
		_frame(focus)


## Places the camera so the player and `focus` are both in shot, from behind and to one side.
func _frame(focus: Node3D) -> void:
	var to := focus.global_position - _player.global_position
	to.y = 0.0
	var dist := clampf(to.length(), 14.0, 70.0)
	var dir := to.normalized() if to.length() > 0.1 else Vector3.FORWARD
	var side := dir.cross(Vector3.UP)
	_cam.global_position = (_player.global_position - dir * (dist * 0.35 + 17.0)
			+ side * (dist * 0.4 + 13.0) + Vector3.UP * (11.0 + dist * 0.2))
	_cam.look_at(_player.global_position + to * 0.5 + Vector3.UP * 5.0)


func _capture(tag: String, focus: Node3D) -> void:
	if _player == null or not is_instance_valid(_player) or not is_instance_valid(focus):
		return
	_frame(focus)
	if _follow:
		return     ## the follow camera is already current; do not fight it for the viewport
	var previous := get_viewport().get_camera_3d()
	_cam.current = true
	await RenderingServer.frame_post_draw
	var path := "%s/captures/enemies_fight_%s.jpg" % [ProjectSettings.globalize_path("res://.."),
			tag]
	get_viewport().get_texture().get_image().save_jpg(path, 0.88)
	if previous != null and is_instance_valid(previous):
		previous.current = true
	_shots.append(path)
	print("FIGHT %.2fs shot %s -> %s" % [_t, tag, path])


# --- near misses -----------------------------------------------------------------------------

## Enemy fire that passes close without touching the mech (juice §11.3). One line per call, with the
## distance it passed at, so the lead can scrub the movie to the timestamp and hear the flyby.
func _drain_near_misses() -> void:
	for row: Dictionary in EnemyNearMiss.take_log():
		_near_misses += 1
		print("FIGHT %.2fs near_miss %s %.1f m" % [_t, row["attack"], float(row["distance"])])


## The feel director is instanced by main.tscn, so it appears a frame or two after this probe.
func _watch_director() -> void:
	if _director_node != null and is_instance_valid(_director_node):
		return
	_director_node = get_tree().get_first_node_in_group(&"feel_director")
	if _director_node != null and _director_node.has_signal(&"event_played") \
			and not _director_node.is_connected(&"event_played", _on_event_played):
		_director_node.connect(&"event_played", _on_event_played)


func _on_event_played(id: StringName, _at: Vector3, _strength: float) -> void:
	if id == &"near_miss":
		_near_played += 1


# --- events ----------------------------------------------------------------------------------

## Every telegraph is logged; a ripper leap also arms the dash, timed off the attack's own
## telegraph length so the i-frames land in the active window.
func _on_telegraph(enemy: Node, attack: StringName, kind: StringName) -> void:
	_telegraphs += 1
	_by_telegraph[attack] = int(_by_telegraph.get(attack, 0)) + 1
	if _telegraphs <= 30:
		print("FIGHT %.2fs telegraph %s %s (%s)" % [_t, _name_of(enemy), attack, kind])
	if enemy is Node3D and _close_enough(enemy as Node3D, SHOT_RANGE):
		# The tell ramps over the whole windup, so a shot taken on the event catches it at 2 %.
		# Queue it for the peak instead.
		if kind == EnemyAttack.PARRYABLE and not _glint_shot:
			_glint_shot = true
			_shot_at(&"telegraph_glint", enemy as Node3D, _telegraph_length(enemy, attack) * 0.7)
		elif kind == EnemyAttack.UNBLOCKABLE and not _red_shot:
			_red_shot = true
			_shot_at(&"telegraph_red", enemy as Node3D, _telegraph_length(enemy, attack) * 0.7)
	if attack != &"ripper_leap_bite" or _dodge_at >= 0.0 or _died:
		return
	var lead := _telegraph_length(enemy, attack)
	if lead > 0.0:
		_dodge_at = _t + lead - DODGE_LEAD


func _telegraph_length(enemy: Node, id: StringName) -> float:
	if not enemy.has_method(&"attacks"):
		return -1.0
	for a: EnemyAttack in enemy.call(&"attacks"):
		if a.id == id:
			return a.telegraph
	return -1.0


## Queues a capture `delay` seconds out, so the moment it frames is the peak of the beat.
func _shot_at(tag: StringName, focus: Node3D, delay: float) -> void:
	_pending.append({"tag": tag, "focus": focus, "at": _t + maxf(delay, 0.0)})


func _run_pending() -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var p: Dictionary = _pending[i]
		if _t < float(p["at"]):
			continue
		_pending.remove_at(i)
		var focus := p["focus"] as Node3D
		if is_instance_valid(focus):
			_capture.call_deferred(p["tag"], focus)


func _on_player_damaged(hit: HitInfo) -> void:
	_hits_taken += 1
	_damage_taken += hit.final_amount
	_by_weapon[hit.weapon] = int(_by_weapon.get(hit.weapon, 0)) + 1
	if hit.knockback != Vector3.ZERO:
		_knockbacks += 1
	if _hits_taken <= 20:
		print("FIGHT %.2fs player hit by %s: %.0f damage (kind %s, knockback %s)" % [_t, hit.weapon,
				hit.final_amount, hit.kind, str(hit.knockback.length() > 0.0)])
	if hit.final_amount >= 600.0 and not _hurt_shot and hit.source is Node3D:
		_hurt_shot = true
		_capture.call_deferred(&"big_hit", hit.source as Node3D)


func _on_perfect_dodge(attacker: Node) -> void:
	_dodges += 1
	print("FIGHT %.2fs PERFECT DODGE through %s" % [_t, _name_of(attacker)])
	if not _dodge_shot and attacker is Node3D:
		_dodge_shot = true
		_capture.call_deferred(&"perfect_dodge", attacker as Node3D)


func _on_player_died() -> void:
	_died = true
	print("FIGHT %.2fs PLAYER DIED" % _t)
	_summary("death")


func _on_staggered(enemy: Node, _hit: HitInfo) -> void:
	_staggers += 1
	print("FIGHT %.2fs %s staggered" % [_t, _name_of(enemy)])


func _on_killed(enemy: Node, _hit: HitInfo) -> void:
	_kills += 1
	print("FIGHT %.2fs %s killed" % [_t, _name_of(enemy)])


func _name_of(node: Node) -> String:
	return String(node.get(&"enemy_type")) if node != null and is_instance_valid(node) else "?"


## Model trace: one line per one-shot clip a monster plays, with the clip the AnimationPlayer really
## landed on. A telegraph log alone cannot tell a roar that played from one that resolved to idle
## (lead r10 — the juggernaut charge used to announce itself in a neutral stance).
func _trace_actions() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var e := node as EnemyBase
		if e == null:
			continue
		var id := e.get_instance_id()
		var seen: Dictionary = _traced.get(id, {})
		for action: StringName in e.action_plays:
			var plays := int(e.action_plays[action])
			if plays <= int(seen.get(action, 0)):
				continue
			seen[action] = plays
			print("FIGHT %.2fs %s action %s ×%d clip=%s" % [_t, _name_of(e), action, plays,
					_clip_of(e)])
		_traced[id] = seen


func _clip_of(e: EnemyBase) -> String:
	if e.model == null or not is_instance_valid(e.model):
		return "-"
	var ap := e.model.get(&"animation") as AnimationPlayer
	return "-" if ap == null else String(ap.current_animation)


func _close_enough(node: Node3D, range: float) -> bool:
	return _player != null and is_instance_valid(_player) and is_instance_valid(node) \
			and node.global_position.distance_to(_player.global_position) <= range


## Closest living monster within `range` of the player, and how many of them there are.
func _nearest_enemy(range: float) -> Node3D:
	var best: Node3D = null
	var best_d := range
	for e: Node3D in get_tree().get_nodes_in_group(&"enemy"):
		if not e.has_method(&"is_alive") or not bool(e.call(&"is_alive")):
			continue
		var d := e.global_position.distance_to(_player.global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best


func _crowd_within(range: float) -> int:
	var n := 0
	for e: Node3D in get_tree().get_nodes_in_group(&"enemy"):
		if e.has_method(&"is_alive") and bool(e.call(&"is_alive")) \
				and e.global_position.distance_to(_player.global_position) <= range:
			n += 1
	return n


## Per-archetype state line, so a summary shows *why* a monster is not attacking.
func _roster() -> String:
	var parts: Array[String] = []
	for type: StringName in EnemyTypes.ALL:
		for e: Node3D in get_tree().get_nodes_in_group(&"enemy"):
			if StringName(e.get(&"enemy_type")) != type or not bool(e.call(&"is_alive")):
				continue
			parts.append("%s:%s@%.0fm" % [type, e.call(&"state"),
					e.global_position.distance_to(_player.global_position)])
	return " ".join(parts)


func _summary(tag: String) -> void:
	var hp := -1.0
	if _player != null and is_instance_valid(_player) and _player.has_method(&"hud_state"):
		hp = float((_player.call(&"hud_state") as Dictionary).get("hp", -1.0))
	print("FIGHT SUMMARY %s hp=%.0f telegraphs=%d hits_taken=%d damage=%.0f knockbacks=%d"
			% [tag, hp, _telegraphs, _hits_taken, _damage_taken, _knockbacks])
	print("FIGHT SUMMARY %s perfect_dodges=%d/%d shockwave_jumps=%d rings=%d staggers=%d kills=%d"
			% [tag, _dodges, _dodge_beats, _jump_beats, _rings, _staggers, _kills])
	print("FIGHT SUMMARY %s alive=%d hits_by_weapon=%s" % [tag, _alive(), str(_by_weapon)])
	print("FIGHT SUMMARY %s near_miss=%d played_by_director=%d (row cooldown 0.25 s)"
			% [tag, _near_misses, _near_played])
	print("FIGHT SUMMARY %s telegraphs_by_attack=%s" % [tag, str(_by_telegraph)])
	if _player != null and is_instance_valid(_player):
		print("FIGHT SUMMARY %s roster=%s" % [tag, _roster()])
	if _died:
		print("FIGHT SUMMARY outcome=player died through the normal damage pipeline")


func _alive() -> int:
	var n := 0
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		if e.has_method(&"is_alive") and bool(e.call(&"is_alive")):
			n += 1
	return n
