class_name HailstormLauncher
extends Node3D
## S3 Hailstorm Volley (雹暴齐射) — hold `missiles` to paint up to 12 locks inside a 24°×16° box around
## the crosshair, release to ripple 12 missiles off both shoulders in 0.5 s. No locks fires a
## half-salvo at the aim point; holding `aim` after release steers the whole swarm (skills-catalog §4.4 S3).
##
## Clock (CONTRACTS §3): the cooldown, the lock rate and the salvo ripple take `Feel.player_delta` —
## the player paints and launches at full speed in witch time. The missiles themselves are world-clock
## (MissileManager), so in witch time the swarm visibly crawls while the launch ripple does not.

const LAUNCH_ARC_DEG := 22.0   ## shoulder launches arc up and out before the bloom
const PUFF_SIZE := 3.4         ## launch dust puff at the rail, sized for the third-person arm
const ID := &"hailstorm"
const SCAN_CANDIDATES := 24

@export var tuning: MissileTuning

var ctx: WeaponContext = null
var locks: Array[Targetable] = []
var painting: bool = false
var cooldown: float = 0.0
var salvos: int = 0

var _lock_timer: float = 0.0
var _paint_time: float = 0.0
var _queue: Array[Dictionary] = []
var _queue_timer: float = 0.0
var _queue_interval: float = 0.05
var _right_socket: bool = false


func _ready() -> void:
	if tuning == null:
		tuning = MissileTuning.new()


func setup(c: WeaponContext) -> void:
	ctx = c
	c.missiles.tuning = tuning


func reset_state() -> void:
	locks.clear()
	_queue.clear()
	painting = false
	cooldown = 0.0
	_paint_time = 0.0


## Put the launcher away mid-paint: the locks are dropped and the paint timers stop. Nothing is
## fired, the cooldown is carry-over (a swap or a death must not hand the player a free salvo back)
## and nothing is announced — a corpse must reach no bus. `WeaponSystem.stop_volley()` is the caller
## the death gate uses; `reset_state()` stays the respawn path.
func cancel() -> void:
	painting = false
	locks.clear()
	_paint_time = 0.0
	_lock_timer = 0.0


func update(player_dt: float, held: bool, released: bool, aim_held: bool) -> void:
	cooldown = maxf(cooldown - player_dt, 0.0)
	_serve_queue(player_dt)
	var in_flight := not _queue.is_empty() or ctx.missiles.active_count() > 0
	ctx.missiles.guided = aim_held and in_flight
	if aim_held:
		ctx.missiles.guided_point = ctx.aim_point()
	if held and cooldown <= 0.0 and _queue.is_empty():
		_paint(player_dt)
	elif painting and (released or not held):
		fire()


func _paint(player_dt: float) -> void:
	if not painting:
		painting = true
		_paint_time = 0.0
		_lock_timer = 0.0
	_paint_time += player_dt
	_lock_timer -= player_dt
	while _lock_timer <= 0.0 and locks.size() < tuning.lock_max:
		if not _add_lock():
			# Nothing lockable right now: drop the debt, or the loop would pay a second of failed
			# painting out as a burst of locks the moment a target enters the box.
			_lock_timer = 0.0
			break
		_lock_timer += tuning.lock_interval
	if locks.size() >= tuning.lock_max or _paint_time >= tuning.paint_auto_fire:
		fire()


## One lock: nearest-underused target inside the paint box with line of sight.
func _add_lock() -> bool:
	var origin := ctx.chest()
	var dir := ctx.aim_dir_from(origin)
	var best: Targetable = null
	var best_count := 99
	for t in ctx.targets_in_view(SCAN_CANDIDATES, tuning.lock_range):
		if _count(t) >= tuning.lock_per_target:
			continue
		if not _in_box(origin, dir, t.global_position):
			continue
		var score := _count(t)
		if score < best_count and ctx.query.has_line_of_sight(origin, t.global_position):
			best = t
			best_count = score
	if best == null:
		return false
	locks.append(best)
	Events.missiles_locked.emit(locks.size())
	return true


func _count(t: Targetable) -> int:
	var n := 0
	for l in locks:
		if l == t:
			n += 1
	return n


## Paint box test: yaw within half of lock_box_h, pitch within half of lock_box_v, in front.
func _in_box(origin: Vector3, dir: Vector3, point: Vector3) -> bool:
	var v := ShotQuery.aligned_basis(dir).inverse() * (point - origin)
	var fwd := -v.z
	if fwd <= 0.1:
		return false
	return absf(rad_to_deg(atan2(v.x, fwd))) <= tuning.lock_box_h_deg * 0.5 \
			and absf(rad_to_deg(atan2(v.y, fwd))) <= tuning.lock_box_v_deg * 0.5


## Release: queue the salvo (12 with locks, 6 dumb ones at the aim point without).
func fire() -> bool:
	if cooldown > 0.0 or not _queue.is_empty() or ctx == null:
		return false
	painting = false
	_paint_time = 0.0
	_queue.clear()
	for t in locks:
		# a target can die between the lock and the launch: its missile then flies to the crosshair
		if is_instance_valid(t) and t.is_inside_tree():
			_queue.append({"target": t, "point": t.global_position})
		else:
			_queue.append({"target": null, "point": ctx.aim_point()})
	if locks.is_empty():
		var p := ctx.aim_point()
		for i in tuning.missiles_free:
			_queue.append({"target": null, "point": p})
	var count := _queue.size()
	_queue_interval = tuning.salvo_time / float(maxi(count, 1))
	_queue_timer = 0.0
	cooldown = tuning.cooldown
	locks.clear()
	salvos += 1
	Events.missiles_locked.emit(0)
	ctx.missiles.begin_salvo()
	ctx.play_action(&"missile_launch")
	return true


func _serve_queue(player_dt: float) -> void:
	if _queue.is_empty():
		return
	_queue_timer -= player_dt
	while _queue_timer <= 0.0 and not _queue.is_empty():
		_launch(_queue.pop_front())
		_queue_timer += _queue_interval


func _launch(entry: Dictionary) -> void:
	var from := ctx.socket(&"missile_r" if _right_socket else &"missile_l")
	_right_socket = not _right_socket
	var target := entry["target"] as Targetable
	var point: Vector3 = entry["point"]
	if target != null and is_instance_valid(target):
		point = target.global_position
	# shoulder launches arc up and out: the bloom has to look like a circus, not a laser line
	var aim_dir := ctx.aim_dir_from(from)
	var side := aim_dir.cross(Vector3.UP).normalized() if absf(aim_dir.dot(Vector3.UP)) < 0.99 \
			else Vector3.RIGHT
	var dir := aim_dir.rotated(side, deg_to_rad(LAUNCH_ARC_DEG)).normalized()
	ctx.missiles.launch(from, dir, target, point)
	# launch puff at the rail: the staggered puffs are what makes the bloom read as a burst. The rails
	# are ~4 m from the cockpit lens, so both the puff and its flash light go through the first-person
	# size rule or a salvo whites out the canopy (lead r5 item 1).
	ctx.sparks.puff(from - dir * 2.0, -dir, ctx.fp_size(PUFF_SIZE))
	ctx.beams.flash(from, Color(1.0, 0.72, 0.36), ctx.fp_light_energy(2.6),
			ctx.fp_light_range(22.0), 3.0)
	Events.weapon_fired.emit(ID, from, dir)
	Feel.play(&"missile_launch", from)
	Audio.play(&"missile_launch", from)


func hud_state() -> Dictionary:
	return {
		"missile_cd": cooldown,
		"missile_locks": locks.size(),
		"missile_locks_max": tuning.lock_max,
		"missile_painting": painting,
	}
