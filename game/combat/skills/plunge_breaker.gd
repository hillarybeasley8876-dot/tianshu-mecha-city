class_name PlungeBreaker
extends Node3D
## S8 Plunge Breaker (坠击破) — aerial slam (skills-catalog §4.4 S8, height / speed / radius x2).
##
## Needs the mech airborne at least 16 m above the ground and the melee action held for 0.25 s. 10 f
## of hang, then a 190 m/s dive that stays inside 30 deg of vertical and homes onto a locked target up
## to 120 m away horizontally. The impact clears 20 m for 1,600 damage falling to 500 at the rim,
## +10 % per 20 m fallen up to +50 %, 1,100 impact, and launches every non-boss into a 0.75 s air-lock
## so an air juggle can follow. 24 f of recovery, dash-cancellable from f12.

enum S { IDLE, HANG, DIVE, RECOVERY }

const AIRLOCK_COLOR := Color(1.0, 0.75, 0.35)
const SHEATH_COLOR := Color(0.62, 0.95, 1.0)
const COLUMN_COLOR := Color(0.8, 0.98, 1.0)

var ctx: SkillContext = null
var system: SkillSystem = null

var _state: int = S.IDLE
var _t: float = 0.0
var _dive_dir: Vector3 = Vector3.DOWN
var _fall_start: float = 0.0
var _target: Node3D = null
var _sheath: SkillFxSheath = null
var _landed_at: Vector3 = Vector3.ZERO
var _dealt: float = 0.0
var _launched: int = 0
var _last_bonus: float = 1.0


func setup(ctx_: SkillContext, system_: SkillSystem) -> void:
	ctx = ctx_
	system = system_


func is_diving() -> bool:
	return _state == S.HANG or _state == S.DIVE


func is_busy() -> bool:
	return _state != S.IDLE


## Checked BEFORE the charge is spent, so a hold too close to the ground costs nothing.
func can_begin() -> bool:
	return _state == S.IDLE and ctx.player != null and height_ok()


func last_damage() -> float:
	return _dealt


func last_launch_count() -> int:
	return _launched


func last_height_bonus() -> float:
	return _last_bonus


## Airborne AND at least 16 m above whatever is below. Both halves are re-checked every frame while
## the melee action is held, so a hold that starts too low simply never arms.
## Airborne AND at least 16 m above whatever is below, measured from the FEET: the dossier's "8 m
## above the ground" is a hero height, and the body origin is the capsule centre 7.5 m up (audit #7).
func height_ok() -> bool:
	if ctx.player == null:
		return false
	if ctx.player.has_method(&"is_grounded") and bool(ctx.player.call(&"is_grounded")):
		return false
	var feet := ctx.feet()
	var ground := ctx.ground_y(feet)
	if ground == -INF:
		return true  # nothing under the mech inside 1,200 m: high enough by definition
	return feet.y - ground >= ctx.tuning.plunge_min_height


func begin() -> bool:
	if _state != S.IDLE or ctx.player == null or not height_ok():
		return false
	_state = S.HANG
	_t = 0.0
	_dealt = 0.0
	_launched = 0
	_target = ctx.lock_target()
	# plasma sheath: the tell that the dive is committed, lit from the hang so the 10 f read
	if ctx.vfx != null:
		_sheath = ctx.vfx.sheath()
		_sheath.open(ctx.player as Node3D, 9.0, SHEATH_COLOR)
		_sheath.follow(Vector3.DOWN * 4.0)
	var body := ctx.player as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO
	if ctx.player.has_method(&"lock_movement"):
		ctx.player.call(&"lock_movement", ctx.tuning.plunge_hang, false)
	_play_action(&"plunge_dive")
	Feel.fov_kick(-3.0, 0.2)
	return true


func tick(delta: float) -> void:
	match _state:
		S.HANG:
			_tick_hang(delta)
		S.DIVE:
			_tick_dive(delta)
		S.RECOVERY:
			_tick_recovery(delta)
		_:
			pass


## The 10 f hang is the tell: the mech floats, the plasma sheath ignites, then it drops.
func _tick_hang(delta: float) -> void:
	_t += delta
	var body := ctx.player as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO
	if _sheath != null:
		_sheath.follow(Vector3.DOWN * 6.0)
	if _t < ctx.tuning.plunge_hang:
		return
	_state = S.DIVE
	_t = 0.0
	_fall_start = ctx.origin().y
	_dive_dir = _aim_dive()
	SkillFx.spawn(self, &"thruster_burst", ctx.origin(), Vector3.UP, 1.5)


# --- dive ----------------------------------------------------------------------------------------

## The dive is mostly vertical: a locked target inside 120 m horizontally bends it, but never past
## 30 deg off straight down (skills-catalog §4.4 S8).
func _aim_dive() -> Vector3:
	var down := Vector3.DOWN
	if _target == null or not is_instance_valid(_target) or not ctx.is_alive(_target):
		return down
	var to := ctx.centre_of(_target) - ctx.origin()
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > ctx.tuning.plunge_home_range:
		return down
	var dir := to.normalized()
	var max_tilt := deg_to_rad(ctx.tuning.plunge_cone_deg)
	var angle := down.angle_to(dir)
	if angle <= max_tilt:
		return dir
	# slerp is undefined for a near-zero angle; under the cap the straight-down dive is already right
	if angle < 0.0005:
		return down
	var bent := down.slerp(dir, max_tilt / angle).normalized()
	return bent if bent.is_finite() else down


func _tick_dive(delta: float) -> void:
	_t += delta
	var body := ctx.player as CharacterBody3D
	if body == null:
		_end()
		return
	if _target != null and is_instance_valid(_target) and ctx.is_alive(_target):
		_dive_dir = _aim_dive()
	body.velocity = _dive_dir * ctx.tuning.plunge_speed
	if _sheath != null:
		_sheath.follow(body.velocity)
	var feet := ctx.feet()
	var ground := ctx.ground_y(feet)
	if bool(ctx.player.call(&"is_grounded")) \
			or (ground != -INF and feet.y - ground <= 2.0) or _t > 6.0:
		_impact()


## Damage scales with the height actually fallen: +10 % per 20 m, capped at +50 %.
func height_bonus(fallen: float) -> float:
	var t := ctx.tuning
	return 1.0 + minf(t.plunge_bonus_rate * floorf(fallen / t.plunge_bonus_step),
			t.plunge_bonus_cap)


func _impact() -> void:
	var body := ctx.player as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO
	_landed_at = ctx.origin()
	_fall_start = maxf(_fall_start - _landed_at.y, 0.0)
	_last_bonus = height_bonus(_fall_start)
	if _sheath != null:
		_sheath.stop()
		_sheath = null
	var t := ctx.tuning
	for e in ctx.enemies_in_radius(_landed_at, t.plunge_radius):
		var to := ctx.centre_of(e) - _landed_at
		var dist := to.length()
		var dmg := t.falloff(dist, t.plunge_radius, t.plunge_radius * 0.25,
				t.plunge_damage, t.plunge_edge_damage) * _last_bonus
		if dmg <= 0.0:
			continue
		var dir := to.normalized() if to.length_squared() > 0.001 else Vector3.UP
		_dealt += ctx.damage(e, dmg, HitInfo.CRUSH, &"plunge_breaker",
				t.plunge_impact * _last_bonus, ctx.knockback_for(e, 16.0, 5.0, dir),
				ctx.centre_of(e))
		Feel.local_hit_stop([e], 6.0 / 60.0)
		if not ctx.is_boss(e):
			_airlock(e)
			_launched += 1
	_detonate_primes()
	Feel.play(&"plunge_land", _landed_at)
	Feel.shake(0.40, _landed_at)
	_draw_impact()
	_play_action(&"plunge_land")
	_state = S.RECOVERY
	_t = 0.0


## The Plunge signature (r1 review): a vertical cyan-white light column punching out of the crater, a
## radial debris ring, a dust wave running to 20 m and the crater decal. No orange kill blast.
func _draw_impact() -> void:
	var t := ctx.tuning
	var ground := ctx.ground_point(_landed_at)
	if ctx.vfx != null:
		# the column is the brightest thing in the game at this camera distance: 0.9 of the column's
		# own 1.0 ceiling, so it blooms at the rim instead of clipping the crater to white
		ctx.vfx.column().fire(ground, 110.0, t.plunge_radius * 0.22, 0.9, COLUMN_COLOR, 0.3, 0.9)
		ctx.vfx.shell().fire(ground + Vector3.UP * 3.0, 1.0, t.plunge_radius * 0.5, 0.35,
				SHEATH_COLOR, Color(1.0, 1.0, 1.0), 1.0, 2.6)
		ctx.vfx.ring().fire(ground + Vector3.UP * 0.4, Vector3.UP, 3.0, t.plunge_radius, 0.45,
				COLUMN_COLOR, 0.1, 2.8)
		ctx.vfx.inflow().fire(ground + Vector3.UP * 1.0, t.plunge_radius * 0.9, 0.8,
				Color(0.66, 0.58, 0.46), 110, 16.0, 0.4, 2.2)
	SkillFx.ring(self, ground, Vector3.UP, t.plunge_radius, 0.32, AIRLOCK_COLOR)
	SkillFx.spawn(self, &"dust_ring", ground, Vector3.UP, t.plunge_radius / 5.0)
	SkillFx.spawn_debris(self, ground, 18, 16.0, 1.6)
	SkillFx.decal(self, &"land_crater", ground, Vector3.UP, t.plunge_radius / 8.0)
	SkillFx.flash(self, ground + Vector3.UP * 8.0, COLUMN_COLOR, 4.0, 120.0, 6.0)


## Non-bosses hang in the air for 0.75 s: free air L1-L2 (skills-catalog §4.7 "Plunge -> air juggle").
func _airlock(e: Node3D) -> void:
	var s := ctx.status_of(e)
	if s != null and s.has_method(&"apply_slow"):
		s.call(&"apply_slow", 0.0, ctx.tuning.plunge_airlock)
	SkillFx.spawn(self, &"spark_burst", ctx.centre_of(e), Vector3.UP, 0.8)


func _detonate_primes() -> void:
	if ctx.player == null or not ctx.player.is_inside_tree():
		return
	ctx.player.get_tree().call_group(&"prime_detonators", &"detonate_primes", _landed_at,
			ctx.tuning.plunge_radius, ctx.player)


func _tick_recovery(delta: float) -> void:
	_t += delta
	if _t >= ctx.tuning.plunge_recovery:
		_end()


func _end() -> void:
	_state = S.IDLE
	_t = 0.0
	_target = null
	if _sheath != null:
		_sheath.stop()
		_sheath = null


func _play_action(id: StringName) -> void:
	if ctx.model != null and is_instance_valid(ctx.model) and ctx.model.has_method(&"play_action"):
		ctx.model.call(&"play_action", id)


func reset() -> void:
	_end()
	_dealt = 0.0
	_launched = 0
	_last_bonus = 1.0
