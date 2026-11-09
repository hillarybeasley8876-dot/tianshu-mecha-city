class_name DefenseSystem
extends Node3D
## Defence component of the PlayerMech (CONTRACTS §5): Mirror Guard (镜返盾), skills-catalog §4.4 S5.
## One button does three things by how long it is held — a tap opens the 167 ms perfect-parry window,
## holding blocks (−70 % in a 140° front arc), and holding past 0.3 s opens the catch field that
## freezes enemy shots and throws them back at 135 %.
##
## It plugs into the player's damage pipeline with `player.add_damage_filter` (CONTRACTS §5): the
## filter returns true when it consumed the hit. `hit.unblockable` always bypasses everything.
##
## hud_state() keys: guarding, perfect_window, catch_count, guard_break, blocked, parries.

enum State { IDLE, PERFECT, BLOCKING, BROKEN }

var field: CatchField = null
var shield: ShieldVisual = null
var dome: CatchDome = null

var state: int = State.IDLE
var parries: int = 0
var blocked_damage: float = 0.0

var _player: Node = null
var _model: Node = null
var _aim: Node = null
var _guard_ticks: int = 0        ## ticks the current guard has been up
var _perfect_ticks: int = 0      ## width of this press's perfect window
var _min_guard_ticks: int = 0
var _break_left: float = 0.0
var _since_release: float = 99.0 ## for the anti-mash window (re-press inside 0.5 s)
var _guard_held: bool = false
var _guard_accum: float = 0.0     ## player-time owed to the guard clock (CONTRACTS §3)
var _filter: Callable = Callable()
var _en_drained: float = 0.0

signal parried(hit: HitInfo, attacker: Node)
signal blocked(hit: HitInfo)
signal guard_broken()


func _ready() -> void:
	field = CatchField.new()
	shield = ShieldVisual.new()
	shield.name = "Shield"
	add_child(shield)
	dome = CatchDome.new()
	dome.name = "CatchDome"
	add_child(dome)
	_filter = _damage_filter
	set_physics_process(true)


## The mech instances components before its model/aim siblings are guaranteed ready, so the refs are
## refreshed every tick until they resolve (the weapon system's convention).
func _refresh() -> void:
	var p := get_parent()
	if p == null:
		return
	_player = p
	if _model == null and p.has_method(&"model"):
		_model = p.call(&"model")
		if _model != null:
			shield.attach(_model)
	if _aim == null and p.has_method(&"aim"):
		_aim = p.call(&"aim")
	if field.player == null:
		field.player = p as Node3D
		field.facing_provider = _facing
	if p.has_method(&"add_damage_filter"):
		p.call(&"add_damage_filter", _filter)


func _physics_process(delta: float) -> void:
	_refresh()
	if _player == null:
		return
	var player_dt := Feel.player_delta(delta)
	var at := (_player as Node3D).global_position
	shield.global_position = at
	dome.global_position = at
	## The surface animates on PLAYER time like the rest of the mech (CONTRACTS §3): a hit-stop holds
	## the ripple and the parry flash with the guard instead of running them out in frozen frames.
	shield.tick(player_dt)
	dome.tick(player_dt)
	_timers(Feel.real_delta(delta), player_dt)
	if _break_left > 0.0:
		return
	_guard(player_dt)
	if state == State.PERFECT:
		_reflect_incoming()
	var facing := _facing()
	shield.place(at, facing)
	dome.place(at + Vector3.UP * DefenseTable.CATCH_ORBIT_HEIGHT, facing)


## Two clocks, as CONTRACTS §3 asks: the anti-mash re-press rule is INPUT timing (real time), while
## the guard-break stun is a player timer (frozen by a global hit-stop, full speed in witch time).
func _timers(real_dt: float, player_dt: float) -> void:
	_since_release += real_dt
	if _break_left > 0.0:
		_break_left = maxf(_break_left - player_dt, 0.0)
		if _break_left <= 0.0:
			state = State.IDLE


# --- input --------------------------------------------------------------------------------------

func _input_guard() -> bool:
	var held := Input.is_action_pressed(&"guard")
	var pressed := held and not _guard_held
	_guard_held = held
	if pressed:
		_start_guard()
	elif not held and state != State.IDLE and _guard_ticks >= _min_guard_ticks:
		_end_guard()
	return held


## A press opens the perfect window. Re-pressing inside 0.5 s of the last release shrinks it to 5 f
## (anti-mash, skills-catalog §4.4), and every guard lasts at least 18 f.
func _start_guard() -> void:
	var spamming := _since_release < DefenseTable.SPAM_WINDOW
	_perfect_ticks = DefenseTable.perfect_ticks(spamming)
	_min_guard_ticks = DefenseTable.ticks(DefenseTable.MIN_GUARD_FRAMES)
	_guard_ticks = 0
	_guard_accum = 0.0
	state = State.PERFECT
	shield.set_guard(true)
	if _model != null and _model.has_method(&"play_action"):
		_model.call(&"play_action", &"guard_up", 0.05)


func _end_guard() -> void:
	var had := field.count()
	if had > 0:
		field.release(_release_aim())
		if _model != null and _model.has_method(&"play_action"):
			_model.call(&"play_action", &"catch_release", 0.05)
	state = State.IDLE
	_guard_ticks = 0
	_guard_accum = 0.0
	_since_release = 0.0
	shield.set_guard(false)
	dome.set_active(false)
	field.clear()
	# hero-v3 r5 item 3: the guard clip is a HOLD, so it only comes down when the guard does.
	if had == 0 and _model != null and _model.has_method(&"stop_action"):
		_model.call(&"stop_action")


## Runs the guard while it is up: the perfect window counts down, then it becomes a block, and past
## 0.3 s the catch field starts eating shots. `delta` is player time (CONTRACTS §3), so the 167 ms
## window is 167 ms of real time in normal play AND in witch time, and a global hit-stop holds it.
func _guard(delta: float) -> void:
	if not _input_guard() and state == State.IDLE:
		return
	if state == State.IDLE or state == State.BROKEN:
		return
	_guard_accum += delta * DefenseTable.PHYSICS_HZ
	_guard_ticks += mini(int(_guard_accum), 8)
	_guard_accum -= float(mini(int(_guard_accum), 8))
	if state == State.PERFECT and _guard_ticks > _perfect_ticks:
		state = State.BLOCKING
	var seconds := float(_guard_ticks) / DefenseTable.PHYSICS_HZ
	var catching := seconds >= DefenseTable.CATCH_HOLD
	dome.set_active(catching)
	_drain(delta, catching)
	if state == State.BROKEN:
		## _drain may have broken the guard in this very tick (EN hit 0) — its clear() let the held
		## rounds go, so the catch must not run and freeze them again with nothing left to release them.
		return
	if catching:
		_catch(delta)
	if field.held_time() >= DefenseTable.CATCH_MAX_TIME and field.count() > 0:
		## skills-catalog §4.4: the field can only hold for 3 s, then it lets go by itself.
		field.release(_release_aim())


func _catch(delta: float) -> void:
	if field.tick(delta) > 0 and _model != null and _model.has_method(&"play_action"):
		_model.call(&"play_action", &"catch_hold", 0.08)


## EN cost: 60/s while blocking, 140/s once the catch field is open. EN 0 breaks the guard.
func _drain(delta: float, catching: bool) -> void:
	var rate := DefenseTable.CATCH_EN_PER_SEC if catching else DefenseTable.BLOCK_EN_PER_SEC
	var want := rate * delta
	_en_drained += want
	if not _player.has_method(&"drain_energy"):
		return
	if not bool(_player.call(&"drain_energy", want, false)):
		_break_guard()


## skills-catalog §4.4: EN 0 under the shield = 1.0 s guard break, fully open.
func _break_guard() -> void:
	_break_left = DefenseTable.GUARD_BREAK_TIME
	state = State.BROKEN
	field.clear()
	shield.set_guard(false)
	dome.set_active(false)
	_guard_ticks = 0
	_guard_accum = 0.0
	if _player.has_method(&"lock_movement"):
		_player.call(&"lock_movement", DefenseTable.GUARD_BREAK_TIME, false)
	Feel.play(&"block", (_player as Node3D).global_position, 1.0)
	guard_broken.emit()


# --- damage pipeline (CONTRACTS §5 add_damage_filter) ---------------------------------------------

## `func(hit: HitInfo) -> bool`; true = consumed. Red-glow attacks (`hit.unblockable`) ignore the
## shield entirely and must be dodged (SPEC §7).
func _damage_filter(hit: HitInfo) -> bool:
	if hit == null or hit.unblockable or state == State.IDLE or state == State.BROKEN:
		return false
	if state == State.PERFECT:
		return _perfect(hit)
	return _block(hit) if _in_block_arc(hit) else false


## skills-catalog §4.4 "Perfect vs projectiles": a shot that flies into the perfect window is turned
## back at its shooter at 135 %. The damage filter cannot see the projectile node, so the window
## sweeps for live shots itself; anything that still slips through is consumed by `_perfect`.
func _reflect_incoming() -> int:
	var space := (_player as Node3D).get_world_3d().direct_space_state
	if space == null:
		return 0
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = DefenseTable.CATCH_RADIUS
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, _origin())
	params.collision_mask = Layers.ENEMY_SHOT
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var n := 0
	for r: Dictionary in space.intersect_shape(params, 16):
		var shot := _reflectable(r["collider"] as Object)
		if shot == null:
			continue
		_reflect(shot)
		n += 1
	return n


func _reflectable(col: Object) -> Node3D:
	if not (col is Node3D):
		return null
	var shot := col as Node3D
	if not bool(shot.get_meta(&"reflectable", false)):
		return null
	if shot.has_method(&"is_reflected") and bool(shot.call(&"is_reflected")):
		return null
	if shot.has_method(&"is_active") and not bool(shot.call(&"is_active")):
		return null
	return shot if _front_of(shot.global_position) else null


## Back to whoever fired it (`meta &"owner"`), else straight down the guard facing.
func _reflect(shot: Node3D) -> void:
	var from := shot.global_position
	var shooter: Object = shot.get_meta(&"owner") as Object if shot.has_meta(&"owner") else null
	var dir := -_facing().z
	if shooter is Node3D and is_instance_valid(shooter):
		dir = (shooter as Node3D).global_position - from
	if dir.length_squared() < 0.0001:
		dir = -_facing().z
	shot.call(&"reflect", dir.normalized() * DefenseTable.REFLECT_SPEED, _player)
	parries += 1
	shield.flash_perfect((_player as Node3D).global_position, -_facing().z)
	Feel.play(&"parry_perfect", from, 1.0)
	_play_parry()
	_reward()
	var hit := HitInfo.make(0.0, HitInfo.BALLISTIC, _player, &"mirror_guard")
	hit.position = from
	Events.parry_success.emit(hit, shooter as Node if shooter is Node else null)


## hero-v3 r5 item 5: a perfect parry is the one defence the mech visibly performs. The clip is
## authored around the guard pose, so it reads as a deflection out of the shield already being up.
func _play_parry() -> void:
	if _model != null and _model.has_method(&"play_action"):
		_model.call(&"play_action", &"parry", 0.04)


## Perfect parry (skills-catalog §4.4): melee costs the attacker 600 stability and 0.6 s of recoil,
## buys both sides 8 f of local hit-stop and opens the 0.8 s Return Cut window.
func _perfect(hit: HitInfo) -> bool:
	if not _in_block_arc(hit):
		return false
	parries += 1
	shield.flash_perfect((_player as Node3D).global_position, _towards(hit))
	Feel.play(&"parry_perfect", hit.position, 1.0)
	_play_parry()
	Feel.local_hit_stop([_player, hit.source],
			DefenseTable.seconds(DefenseTable.PARRY_HITSTOP_FRAMES))
	if hit.parryable:
		_recoil(hit.source)
	state = State.BLOCKING
	_reward()
	Events.parry_success.emit(hit, hit.source)
	parried.emit(hit, hit.source)
	return true


## The attacker eats the parry: −600 stability and 0.6 s stuck in its recovery (StatusComponent API,
## CONTRACTS §4; until the enemies unit lands the call is skipped, never faked).
func _recoil(attacker: Node) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	var status: Variant = attacker.get(&"status")
	if status != null and status.has_method(&"add_impact"):
		status.call(&"add_impact", DefenseTable.PARRY_STABILITY)
	if attacker.has_method(&"set_ai_enabled"):
		attacker.call(&"set_ai_enabled", false)
		_reenable_later(attacker)
	elif attacker.has_method(&"hit_pause"):
		attacker.call(&"hit_pause", DefenseTable.PARRY_RECOIL)


## The AI comes back when the recoil is over; a SceneTreeTimer keeps it honest without a new node. It
## is pausable (`process_always = false`) so a pause menu opened inside the 0.6 s cannot spend the
## recoil for free, and ticked on physics frames so the lockout matches the AI's own step.
##
## The lambda captures the attacker's INSTANCE ID, not the node: a captured Object that is freed
## before the timer fires errors out of the callable itself ("Lambda capture … was freed"), before
## any `is_instance_valid` guard inside the body can run.
func _reenable_later(attacker: Node) -> void:
	if not is_inside_tree():
		return
	var id := attacker.get_instance_id()
	var timer := get_tree().create_timer(DefenseTable.PARRY_RECOIL, false, true)
	timer.timeout.connect(func() -> void:
			var a := instance_from_id(id) as Node
			if a != null and a.has_method(&"set_ai_enabled"):
				a.call(&"set_ai_enabled", true))


func _reward() -> void:
	if _player.has_method(&"add_energy"):
		_player.call(&"add_energy", DefenseTable.PARRY_EN)
	if _player.has_method(&"add_overdrive"):
		_player.call(&"add_overdrive", DefenseTable.PARRY_OD)


## Held block: −70 % damage in the 140° front arc, and 25 EN per 100 damage absorbed on top of the
## per-second drain. The hit is reduced, not eaten, so it returns false.
func _block(hit: HitInfo) -> bool:
	var absorbed := hit.amount * DefenseTable.BLOCK_REDUCTION
	hit.amount -= absorbed
	blocked_damage += absorbed
	_spend(absorbed / 100.0 * DefenseTable.BLOCK_EN_PER_100)
	shield.impact(_hit_point(hit))
	Feel.play(&"block", (_player as Node3D).global_position, 1.0)
	Events.attack_blocked.emit(hit)
	blocked.emit(hit)
	return false


func _spend(amount: float) -> void:
	if amount <= 0.0 or not _player.has_method(&"drain_energy"):
		return
	if not bool(_player.call(&"drain_energy", amount, false)):
		_break_guard()


## Where a block landed, for the shield's ripple (r7). The hit's own position when it carries one,
## else the attacker, else a point out in front of the panel — the ripple must start somewhere real,
## never at the origin.
func _hit_point(hit: HitInfo) -> Vector3:
	if hit != null and hit.position != Vector3.ZERO:
		return hit.position
	if hit != null and hit.source is Node3D and is_instance_valid(hit.source):
		return (hit.source as Node3D).global_position
	return _origin() - _facing().z * DefenseTable.PANEL_OFFSET


## The block arc is measured from the guard facing toward the impact point (FEEL.md / S5 "front 140°").
func _in_block_arc(hit: HitInfo) -> bool:
	if hit.source != null and is_instance_valid(hit.source) and hit.source is Node3D:
		return _front_of((hit.source as Node3D).global_position)
	return _front_of(hit.position) if hit.position != Vector3.ZERO else true


## Direction from the mech to whatever swung at us — the ring stands square on to it, so a parry
## reads on the attacker's side of the shield even when the guard facing lags the hit.
func _towards(hit: HitInfo) -> Vector3:
	if hit == null:
		return -_facing().z
	var point := hit.position
	if hit.source != null and is_instance_valid(hit.source) and hit.source is Node3D:
		point = (hit.source as Node3D).global_position
	var to := point - _origin()
	to.y = 0.0
	return to.normalized() if to.length_squared() > 0.0001 else -_facing().z


func _front_of(point: Vector3) -> bool:
	var to := point - _origin()
	if to.length_squared() < 0.0001:
		return true
	var limit := cos(deg_to_rad(DefenseTable.BLOCK_ARC_DEG * 0.5))
	return (-_facing().z).dot(to.normalized()) >= limit


func _origin() -> Vector3:
	if not (_player is Node3D):
		return Vector3.ZERO
	return (_player as Node3D).global_position + Vector3.UP * 8.0


## Guard facing follows the aim when there is an AimSystem, else the body (CONTRACTS §5).
func _facing() -> Basis:
	if _aim != null and _aim.has_method(&"aim_dir_from") and _player is Node3D:
		var dir: Vector3 = _aim.call(&"aim_dir_from", _origin())
		var flat := Vector3(dir.x, 0.0, dir.z)
		if flat.length_squared() > 0.0001:
			return Basis.looking_at(flat.normalized(), Vector3.UP)
	return (_player as Node3D).global_basis if _player is Node3D else Basis.IDENTITY


## The caught rounds go back where the player is looking, or straight ahead with no aim system.
func _release_aim() -> Vector3:
	if _aim != null and _aim.has_method(&"aim_point"):
		var p: Vector3 = _aim.call(&"aim_point")
		if p != Vector3.ZERO:
			return p
	return _origin() - _facing().z * 100.0


# --- HUD ----------------------------------------------------------------------------------------

func is_guarding() -> bool:
	return state == State.PERFECT or state == State.BLOCKING


func in_perfect_window() -> bool:
	return state == State.PERFECT


func catch_count() -> int:
	return field.count() if field != null else 0


func hud_state() -> Dictionary:
	return {
		"guarding": is_guarding(),
		"perfect_window": in_perfect_window(),
		"catch_count": catch_count(),
		"guard_break": _break_left > 0.0,
		"guard_break_left": _break_left,
		"parries": parries,
		"blocked_damage": blocked_damage,
		"state": State.keys()[state],
	}


func reset() -> void:
	state = State.IDLE
	_guard_ticks = 0
	_guard_accum = 0.0
	_break_left = 0.0
	_since_release = 99.0
	_guard_held = false
	_en_drained = 0.0
	parries = 0
	blocked_damage = 0.0
	if field != null:
		field.clear()
	if shield != null:
		shield.clear()
	if dome != null:
		dome.clear()
