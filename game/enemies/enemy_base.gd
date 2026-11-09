class_name EnemyBase
extends CharacterBody3D
## Monster root (enemies-owned; CONTRACTS §6). Owns HP, per-part armour, the StatusComponent
## (stability/stagger/marks/primed/combo scaling), hit reactions, death + wreck, team 1, perception
## and the movement the brain asks for. Archetype scripts subclass this and supply attacks + a brain.
##
## Damage order in `take_hit`: hurtbox part multiplier (Hurtbox) → armour per part → weak point
## ×2.5 → staggered ×1.8 (melee/charged) or ×1.35 → combo scaling (suspended while staggered).

signal telegraph_started(enemy: EnemyBase, attack: StringName, kind: StringName)
signal attack_landed(enemy: EnemyBase, attack: StringName)
signal died(enemy: EnemyBase)
signal dissolved(enemy: EnemyBase)

const WRECK_TIME := 30.0        ## the wreck stays this long, then dissolves (SPEC/juice §7)
const DISSOLVE_TIME := 1.2
const MIN_DISSOLVE_SCALE := 0.001  ## never a zero scale: that is a degenerate basis (melee r6)
const HIT_PAUSE_MAX := 0.25     ## juice §2.2: local hit-stop caps at 250 ms
const GRAVITY := 56.0           ## SPEC §2 hero gravity; monsters use the same world gravity
const EXECUTE_RANGE := 14.0     ## skills-catalog §4.6 Core Rend 7 m at the dossier's 8 m → ×2
const EXECUTE_ARC_DEG := 60.0
const KNOCKBACK_DECAY := 40.0  ## m/s² the knockback impulse bleeds off
const PULL_DECAY := 60.0      ## m/s² the Undertow pull bleeds off once its field lets go
const PULL_MAX := 20.0        ## m/s ceiling on the pull drift, so a well drags rather than launches
const HUNT_AIM_HEIGHT := 4.0  ## chest height of a remembered target position (audit #12)

@export var enemy_type: StringName = &"ripper"
@export var wreck_lifetime: float = WRECK_TIME
## Radians per second the monster orbits the player while it waits for an attack token.
@export var circle_speed: float = 0.5

var hp: float = 300.0
var hp_max: float = 300.0
var status: StatusComponent
var perception: Perception
var loco: EnemyLocomotion
var visuals: EnemyVisuals
var model: Node3D = null
var body_height: float = 6.0
var mass_kg: float = 1.0
var move_speed: float = 30.0
var turn_rate: float = 540.0
var engage_range: float = 18.0
var is_flyer: bool = false
var alive: bool = true

var _pause_left: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _pull_vel: Vector3 = Vector3.ZERO
var _dead_time: float = 0.0
var _dissolved: bool = false
var _ai_enabled: bool = true
var _hurtboxes: Array[Hurtbox] = []
var _brain: EnemyBrain = null


func _ready() -> void:
	add_to_group(&"enemy")
	collision_layer = Layers.ENEMY
	collision_mask = Layers.MASK_CHARACTER
	floor_max_angle = deg_to_rad(50.0)
	hp_max = EnemyTypes.get_stat(enemy_type, "hp", 300.0)
	hp = hp_max
	body_height = EnemyTypes.get_stat(enemy_type, "height", 6.0)
	mass_kg = maxf(EnemyTypes.get_stat(enemy_type, "mass", 1.0), 0.1)
	move_speed = EnemyTypes.get_stat(enemy_type, "speed", 24.0)
	turn_rate = EnemyTypes.get_stat(enemy_type, "turn", 360.0)
	engage_range = EnemyTypes.get_stat(enemy_type, "engage", 20.0)
	status = StatusComponent.new()
	status.configure(EnemyTypes.STATS.get(enemy_type, {}))
	status.staggered.connect(_on_staggered)
	status.stagger_ended.connect(_on_stagger_ended)
	perception = Perception.new()
	perception.configure(self, EnemyTypes.get_stat(enemy_type, "sight", 320.0),
			EnemyTypes.get_stat(enemy_type, "fov", 75.0))
	perception.target_acquired.connect(_on_target_acquired)
	visuals = EnemyVisuals.new()
	visuals.setup(self)
	_build_body()
	_build_model()
	loco = EnemyLocomotion.new()
	loco.setup(self, not is_flyer)
	Events.weapon_fired.connect(_on_weapon_fired)
	_brain = _make_brain()
	if _brain != null:
		_brain.setup(self)
	on_spawned()


# --- archetype hooks ---------------------------------------------------------------------------

func _make_brain() -> EnemyBrain:
	return EnemyBrain.new()


func attacks() -> Array[EnemyAttack]:
	return []


func on_spawned() -> void:
	pass


func _on_target_acquired(_target: Node3D) -> void:
	pass


## Pack alert from another monster inside Perception.PACK_ALERT_RANGE. The alarm CHAINS: a monster
## that wakes up shouts its own neighbours, so one sighting rouses the whole pack even when the
## player is behind cover from most of them. The `perception.target != null` guard makes the
## recursion terminate — every monster can only wake up once.
func on_pack_alert(target: Node3D) -> void:
	if alive and perception.target == null:
		perception.acquire(target, true)


# --- body, model -------------------------------------------------------------------------------

## Loads the real monster model when monster-assets has shipped it, otherwise the placeholder with
## the identical API (CONTRACTS §6). Both live in EnemyBodyBuilder so this file stays readable.
func _build_body() -> void:
	_hurtboxes = EnemyBodyBuilder.build_body(self)


func _build_model() -> void:
	model = EnemyBodyBuilder.build_model(self)
	if model != null:
		set_hit_flash(0.0)


# --- damage (CONTRACTS §4) ----------------------------------------------------------------------

func take_hit(hit: HitInfo) -> void:
	if not alive:
		return
	var dmg := EnemyDamage.resolve(self, hit)
	status.commit_hit()
	hit.final_amount = dmg
	hp = maxf(0.0, hp - dmg)
	if hit.kind == HitInfo.BEAM or hit.kind == HitInfo.BALLISTIC or hit.kind == HitInfo.EXPLOSIVE:
		status.add_mark_hit()
	if hit.stagger > 0.0:
		status.add_impact(EnemyDamage.impact(self, hit))
	_apply_knockback(hit)
	Events.hit_landed.emit(hit, self)
	set_hit_flash(0.6)
	EnemyDamage.apply_hitstop(self, hit)
	if hp <= 0.0:
		_die(hit)


func _apply_knockback(hit: HitInfo) -> void:
	if hit.knockback == Vector3.ZERO:
		return
	_knockback += hit.knockback / mass_kg


## Contract for anything that shoves a hit receiver (MeleeStrike.shove): EnemyBase already applies
## `hit.knockback` itself, scaled by mass, so a caller must NOT also add it to `velocity` — that is
## the double application audit #1 found. Callers test `handles_own_knockback()`.
func handles_own_knockback() -> bool:
	return true


## Local hit-stop (CONTRACTS §4): freeze own motion + animation, vibrate the visual root only
## (juice §2.3 Sakurai rules — never move the collision shapes).
func hit_pause(seconds: float) -> void:
	var s := clampf(seconds, 0.0, HIT_PAUSE_MAX)
	_pause_left = maxf(_pause_left, s)
	visuals.start_vibration(s)
	if model != null and model.has_method(&"hit_pause"):
		model.call(&"hit_pause", s)


func is_paused() -> bool:
	return _pause_left > 0.0


## Turns the brain off without touching physics (cinematics, perf bisecting, staggered cutscenes).
func set_ai_enabled(on: bool) -> void:
	_ai_enabled = on
	if not on:
		loco.decelerate(1.0)


func is_alive() -> bool:
	return alive


func get_team() -> int:
	return 1


func set_hit_flash(v: float) -> void:
	visuals.set_hit_flash(v)


# --- telegraphs ---------------------------------------------------------------------------------

## Starts the visual tell for an attack: white glint = parryable, red glow + a distinct shape and
## sound = unblockable. SPEC §7.1: the windup is ≥ 400 ms parryable / ≥ 600 ms unblockable, and an
## unblockable is never signalled by colour alone.
func begin_telegraph(attack: EnemyAttack) -> void:
	visuals.begin_telegraph(attack)
	# The per-archetype tell is the audio router's job (Audio.on_enemy_telegraph -> ripper_leap_tell,
	# mantis_glint, ...), driven by the Events signal below. Only the unblockable cue is played here,
	# because it rides the never-ducked UI bus and must not wait for the router.
	if attack.kind == EnemyAttack.UNBLOCKABLE:
		Audio.play(&"telegraph_unblockable", global_position)
	telegraph_started.emit(self, attack.id, attack.kind)
	# The HUD threat arrows and the audio mix read the global bus, not our local signal.
	Events.enemy_telegraph.emit(self, attack.id, attack.kind)


func end_telegraph() -> void:
	visuals.end_telegraph()


# --- stagger / execution -----------------------------------------------------------------------

func _on_staggered(_s: StatusComponent) -> void:
	if _brain != null:
		_brain.interrupt()
	end_telegraph()
	if model != null:
		model.call(&"play_action", &"stagger")
		if model.has_method(&"set_stagger"):
			model.call(&"set_stagger", true)
	Events.enemy_staggered.emit(self, null)
	Feel.play(&"stagger_enemy", global_position, 1.0)


func _on_stagger_ended(_s: StatusComponent) -> void:
	if model != null and model.has_method(&"set_stagger"):
		model.call(&"set_stagger", false)


## Core Rend window (skills-catalog §4.6, ×2 for our 16 m scale = 14 m): staggered, alive, in front.
func is_executable(by: Node3D) -> bool:
	if not alive or not status.is_staggered() or by == null or not is_instance_valid(by):
		return false
	var to := by.global_position - global_position
	if to.length() > EXECUTE_RANGE:
		return false
	var fwd := -global_transform.basis.z
	return fwd.dot(to.normalized()) >= cos(deg_to_rad(EXECUTE_ARC_DEG))


## Called by melee-defense when a Core Rend lands. Big damage, no stagger immunity games: it kills
## or leaves the monster at 1 HP for non-boss archetypes.
func execute_hit(by: Node3D, damage: float = 9999.0) -> void:
	if not is_executable(by):
		return
	var hit := HitInfo.make(damage, HitInfo.MELEE, by, &"core_rend")
	hit.finisher = true
	hit.position = global_position + Vector3.UP * body_height * 0.5
	hit.stagger = 0.0
	take_hit(hit)
	Feel.play(&"finisher", global_position, 1.0)


# --- death --------------------------------------------------------------------------------------

func _die(hit: HitInfo) -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	for hb: Hurtbox in _hurtboxes:
		hb.collision_layer = 0
	remove_from_group(&"enemy")
	if _brain != null:
		_brain.stop()
	end_telegraph()
	if model != null:
		model.call(&"play_action", &"death")
	Events.enemy_killed.emit(self, hit)
	# The victim's own hold rides with the row: gunfire freezes the victim and never the world
	# (FEEL.md:6). FeelDirector runs Feel.local_hit_stop on these actors, and it does so even when the
	# row's cooldown drops the visuals, so a salvo that kills six in one frame still holds all six.
	Feel.play(&"kill_large" if body_height >= 12.0 else &"kill_small", global_position, 1.0, [self])
	died.emit(self)
	_dead_time = 0.0


# --- frame --------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		# A kill's local hit-stop holds the wreck: the collapse and the death action freeze while the
		# vibration keeps ticking, so the victim reads as "frozen + vibrating" (FEEL.md:7) instead of
		# dropping straight through its own impact frame.
		if _pause_left > 0.0:
			_pause_left -= delta
			visuals.tick_vibration(delta)
			return
		_tick_wreck(delta)
		return
	var dt := delta
	if _pause_left > 0.0:
		_pause_left -= delta
		dt = 0.0
	visuals.tick_vibration(delta)
	visuals.tick_flash(delta)
	visuals.tick_telegraph(dt)
	status.tick(dt)
	perception.tick(delta)
	if dt > 0.0 and _brain != null and _ai_enabled:
		_brain.think(dt)
	_integrate(dt)


## Velocity integration shared by ground and flying archetypes.
##
## Knockback and the Undertow pull are OFFSETS, not accelerations added to the persistent velocity:
## adding the whole decaying impulse back every tick compounded it into K²/(2·decay·dt) m/s — a
## ripper was flung 20–35 m instead of 1–4 m, and the distance scaled with the tick rate (audit #1).
## The offset moves the body for this tick only; the brain's steering still owns `velocity`.
func _integrate(dt: float) -> void:
	if dt <= 0.0:
		return
	var v := velocity
	if not is_flyer:
		if not is_on_floor():
			v.y -= GRAVITY * dt
		elif v.y < 0.0:
			v.y = 0.0
	velocity = v.limit_length(maxf(move_speed * 2.0, 60.0))
	_pull_vel = (_pull_vel + status.consume_pull() * dt).limit_length(maxf(move_speed, PULL_MAX))
	var offset := _knockback + _pull_vel
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * dt)
	_pull_vel = _pull_vel.move_toward(Vector3.ZERO, PULL_DECAY * dt)
	if offset == Vector3.ZERO:
		move_and_slide()
		return
	velocity += offset
	move_and_slide()
	velocity -= offset


func _tick_wreck(delta: float) -> void:
	if _dissolved:
		return
	_dead_time += delta
	if model == null:
		if _dead_time > wreck_lifetime:
			_finish_dissolve()
		return
	var collapse: float = clampf(_dead_time / 0.8, 0.0, 1.0)
	model.rotation_degrees.z = collapse * 78.0
	model.position.y = -collapse * body_height * 0.12
	if _dead_time > wreck_lifetime:
		var k: float = clampf((_dead_time - wreck_lifetime) / DISSOLVE_TIME, 0.0, 1.0)
		if k >= 1.0:
			# Hide it before the last frame of the shrink: a scale of exactly zero is a degenerate
			# basis, and every renderer/transform that reads it reports a NaN (melee r6 — 40
			# `--nan-watch` reports per fight, the only source left in a scripted fight).
			model.visible = false
			_finish_dissolve()
			return
		model.scale = Vector3.ONE * maxf(1.0 - k, MIN_DISSOLVE_SCALE)


## Emits `dissolved` exactly once — a reclaimed (pooled) wreck stays in the tree, and without the
## latch it re-emitted 120×/s for as long as it sat in the pool, growing the free list without
## bound (audit #2/#3). Emits `dissolved` and frees itself — unless a listener (the spawner's
## ripper pool) claimed the node with `reclaim()`, in which case it stays in the tree, hidden,
## physics stopped, ready to be recycled.
func _finish_dissolve() -> void:
	if _dissolved:
		return
	_dissolved = true
	dissolved.emit(self)
	if get_meta(&"reclaimed", false):
		set_physics_process(false)
		return
	queue_free()


## Called from a `dissolved` listener to keep this node instead of letting it be freed.
func reclaim() -> void:
	set_meta(&"reclaimed", true)


# --- HUD ----------------------------------------------------------------------------------------

func hud_state() -> Dictionary:
	return {
		"name": EnemyTypes.display_name(enemy_type),
		"type": enemy_type,
		"hp": hp,
		"hp_max": hp_max,
		"stability": status.stability,
		"stability_max": status.stability_max,
		"staggered": status.is_staggered(),
		"marks": status.marks,
		"primed": status.is_primed(),
		"alive": alive,
	}


## Used by EnemySpawner's ripper pool: put the monster back into a fresh, reusable state.
func recycle() -> void:
	remove_meta(&"reclaimed")
	alive = true
	hp = hp_max
	status.reset()
	perception.clear()
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_pull_vel = Vector3.ZERO
	_pause_left = 0.0
	_dead_time = 0.0
	_dissolved = false
	set_physics_process(true)
	visuals.reset()
	collision_layer = Layers.ENEMY
	collision_mask = Layers.MASK_CHARACTER
	for hb: Hurtbox in _hurtboxes:
		hb.collision_layer = Layers.ENEMY_HURTBOX
	if not is_in_group(&"enemy"):
		add_to_group(&"enemy")
	if model != null:
		if model.has_method(&"set_stagger"):
			model.call(&"set_stagger", false)
		model.rotation_degrees = Vector3.ZERO
		model.position = Vector3.ZERO
		model.scale = Vector3.ONE
		model.visible = true
	if _brain != null:
		_brain.restart()
	on_spawned()


func _on_weapon_fired(_weapon: StringName, muzzle: Vector3, _direction: Vector3) -> void:
	if alive:
		perception.heard_shot(muzzle)


# --- brain API: archetype hooks with sensible defaults -------------------------------------------

## Current AI state (EnemyBrain constants) — HUD threat ring and tests read this.
func state() -> StringName:
	return _brain.state if _brain != null else EnemyBrain.IDLE


## The attack being run right now, or null. Tests use it to tell a real volley from a utility move
## (the spitter's chaff puff), which deliberately takes no attack token.
func current_attack() -> EnemyAttack:
	return _brain.current if _brain != null else null


func token_kind() -> StringName:
	return AttackTokenPool.MELEE


## Stand-off point for this archetype: `flank` rotates around the target so packs surround it.
func desired_point(flank: float) -> Vector3:
	var hunt := perception.hunt_point()
	if not perception.has_hunt_point():
		return global_position
	return hunt + Vector3(cos(flank), 0.0, sin(flank)) * engage_range


## Ground types walk the navmesh, flyers steer directly.
func approach(point: Vector3, dt: float) -> void:
	if is_flyer:
		loco.steer_to(point, 1.0, dt)
	else:
		loco.nav_step(point, 1.0, dt)


func choose_attack() -> EnemyAttack:
	return EnemyStrike.choose(attacks())


func attack_windup(_attack: EnemyAttack, dt: float) -> void:
	loco.decelerate(dt)
	face_dir(target_centre() - global_position, dt)
	set_locomotion(&"idle")


func attack_started(_attack: EnemyAttack) -> void:
	pass


func attack_active(attack: EnemyAttack, dt: float, _hit_done: bool) -> void:
	if attack.lunge_speed > 0.0:
		loco.dash_along(-global_transform.basis.z, attack.lunge_speed, dt)
	else:
		loco.decelerate(dt)


func attack_recover(_attack: EnemyAttack, dt: float) -> void:
	loco.decelerate(dt)
	set_locomotion(&"idle")


func melee_sweep(attack: EnemyAttack) -> bool:
	return EnemyStrike.melee_sweep(self, attack)


## Projectiles / shockwaves are spawned once at the start of the active window.
func spawn_attack(attack: EnemyAttack) -> bool:
	return EnemyStrike.spawn(self, attack)


# --- movement helpers used by the brain (see EnemyLocomotion) ------------------------------------

## Centre of mass in world space (lock point, aim point, distance tests).
func centre() -> Vector3:
	return global_position + Vector3.UP * body_height * 0.5


func target() -> Node3D:
	return perception.target


## Aim point on the current target: its centre of mass when it exposes `body_height`, else chest.
## With no live target this falls back to the last place it was seen, NEVER to the shooter's own
## origin — a shot aimed at that fired from the muzzle straight back through the monster (audit #12).
func target_centre() -> Vector3:
	var t := perception.target
	if t == null or not is_instance_valid(t):
		if perception.has_hunt_point():
			return perception.hunt_point() + Vector3.UP * HUNT_AIM_HEIGHT
		return global_position
	var h: float = float(t.get(&"body_height")) if &"body_height" in t else 8.0
	return t.global_position + Vector3.UP * h * 0.5


## Turns toward `dir` at turn_rate deg/s (horizontal only). Returns the remaining angle in radians.
func face_dir(dir: Vector3, dt: float) -> float:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	var want := atan2(-flat.x, -flat.z)
	var cur := rotation.y
	var step := deg_to_rad(turn_rate) * dt
	var diff := wrapf(want - cur, -PI, PI)
	rotation.y = cur + clampf(diff, -step, step)
	return absf(wrapf(want - rotation.y, -PI, PI))


## Flyers roll and pitch into their flight direction; ground types never leave the horizontal plane.
func face_dir_3d(dir: Vector3, dt: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var want := dir.normalized()
	var fwd := -global_transform.basis.z
	var axis := fwd.cross(want)
	if axis.length_squared() < 0.000001:
		return
	var step := minf(fwd.angle_to(want), deg_to_rad(turn_rate) * dt)
	global_transform.basis = global_transform.basis.rotated(axis.normalized(), step).orthonormalized()


func set_locomotion(state: StringName) -> void:
	if model != null and model.has_method(&"set_locomotion"):
		model.call(&"set_locomotion", state, Vector3(velocity.x, 0.0, velocity.z).length())


## One-shot actions this monster has played, by id. Tests and the fight probe read it to prove a
## clip fired exactly once (a windup that re-triggers every tick never advances); actions are rare,
## so the dictionary write costs nothing.
var action_plays: Dictionary[StringName, int] = {}


func play_action(id: StringName) -> float:
	action_plays[id] = int(action_plays.get(id, 0)) + 1
	if model != null and model.has_method(&"play_action"):
		return float(model.call(&"play_action", id))
	return 0.0


func model_socket(name: StringName) -> Node3D:
	if model != null and model.has_method(&"socket"):
		return model.call(&"socket", name) as Node3D
	return self
