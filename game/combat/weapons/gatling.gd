class_name ThunderSpindleGatling
extends Node3D
## P2 Thunder Spindle gatling (雷纺机炮) — 900 rpm ballistic stream with a heat gauge and a
## skill-based active vent. Overheating opens a 0.9 s needle sweep: hit the marker for Superheated
## rounds, miss it for a 3.2 s jam (skills-catalog §4.2 P2, ranges ×2).
##
## Clock (CONTRACTS §3): rate, spin, heat, cooling, Superheated, jam and the vent sweep all take
## `Feel.player_delta`, so the needle keeps real-time speed in witch time (the press window stays the
## 6 frames the HUD promises) and freezes with the player in a global hit-stop — a real-time needle
## would slide out from under the press during the freeze. The rounds in flight are world-clock.

const ID := &"gatling"
const TRACER_EVERY := 3
## Muzzle flash diameter in metres, sized for the 42 m third-person arm. In the cockpit the lens is
## ~6 m from `muzzle_r`, where 2.2 m is a third of the frame — WeaponContext scales it down there.
const FLASH_SIZE := 2.2

enum State { READY, VENT, VENT_GOOD, JAM, RELOAD }

@export var tuning: GatlingTuning

var ctx: WeaponContext = null
var ammo: int = 0
var heat: float = 0.0
var state: State = State.READY
var superheated_left: float = 0.0
var rounds_fired: int = 0

var _spin: float = 0.0
var _shot_accum: float = 0.0
var _bloom: float = 0.0
var _since_shot: float = 99.0
var _vent_t: float = 0.0
var _timer: float = 0.0
var _reloading: bool = false


func _ready() -> void:
	if tuning == null:
		tuning = GatlingTuning.new()
	if ammo <= 0:
		ammo = tuning.belt


func setup(c: WeaponContext) -> void:
	ctx = c


func reset_state() -> void:
	ammo = tuning.belt
	heat = 0.0
	state = State.READY
	superheated_left = 0.0
	rounds_fired = 0
	_spin = 0.0
	_shot_accum = 0.0
	_bloom = 0.0
	_since_shot = 0.0
	_vent_t = 0.0
	_reloading = false


func update(player_dt: float, held: bool, pressed: bool, reload_pressed: bool) -> void:
	_tick(player_dt, held, pressed or reload_pressed, reload_pressed, false)


## Timers only — the gun is holstered (mid-swap, or the rifle is out). Heat keeps cooling and the
## jam / reload / Superheated clocks keep running, so the gauge the reticle draws is never a frozen
## lie; a VENT sweep nobody can answer runs out into a jam. Silent: the mech is not holding the
## gatling, so a Feel row at a stowed muzzle would be a phantom cue.
func tick_holstered(player_dt: float) -> void:
	_tick(player_dt, false, false, false, true)


func _tick(player_dt: float, held: bool, pressed: bool, reload_pressed: bool,
		holstered: bool) -> void:
	superheated_left = maxf(superheated_left - player_dt, 0.0)
	match state:
		State.VENT:
			_update_vent(player_dt, pressed, holstered)
		State.VENT_GOOD:
			_timer -= player_dt
			if _timer <= 0.0:
				heat = 0.0
				state = State.READY
		State.JAM:
			_timer -= player_dt
			if _timer <= 0.0:
				heat = 0.0
				state = State.READY
		State.RELOAD:
			_timer -= player_dt
			if _timer <= 0.0:
				ammo = tuning.belt
				state = State.READY
				_reloading = false
		State.READY:
			if holstered:
				_cool(player_dt)
			else:
				_update_ready(player_dt, held, reload_pressed)


func _update_vent(player_dt: float, pressed: bool, holstered: bool) -> void:
	_vent_t += player_dt
	if pressed and not holstered:
		_resolve_vent()
	elif _vent_t >= tuning.vent_sweep:
		_jam(holstered)


## Window maths in seconds: the perfect window is `vent_perfect` wide around the marker.
func _resolve_vent() -> void:
	var mark := tuning.vent_mark * tuning.vent_sweep
	var off := absf(_vent_t - mark)
	if off <= tuning.vent_perfect * 0.5:
		heat = 0.0
		superheated_left = tuning.superheated_time
		state = State.READY
		# The sound comes from the row and the audio router only (lead r5 item 2): the row layers
		# `gatling_vent_hiss` + `ui_vent_chime` and the router maps the id to `gatling_vent_perfect`.
		# A direct Audio.play here would be a third, duplicate chime.
		Feel.play(&"gatling_vent_perfect", ctx.socket(&"muzzle_r"))
	elif off <= tuning.vent_good * 0.5:
		state = State.VENT_GOOD
		_timer = tuning.vent_good_delay
		Feel.play(&"gatling_vent_good", ctx.socket(&"muzzle_r"))
	else:
		_jam()


func _jam(silent: bool = false) -> void:
	state = State.JAM
	_timer = tuning.jam_time
	_vent_t = 0.0
	_spin = 0.0
	_shot_accum = 0.0
	if not silent:
		Feel.play(&"gatling_jam", ctx.socket(&"muzzle_r"))


func _cool(player_dt: float) -> void:
	_since_shot += player_dt
	if _since_shot >= tuning.cool_delay:
		heat = maxf(heat - tuning.cool_rate * player_dt, 0.0)


func _update_ready(player_dt: float, held: bool, reload_pressed: bool) -> void:
	if reload_pressed:
		reload()
		return
	_cool(player_dt)
	if not held:
		var was := _spin
		_spin = maxf(_spin - player_dt / maxf(tuning.spin_down, 0.001), 0.0)
		# hero-v3 r5 item 3: `gatling_spin` holds until the barrel actually stops.
		if was > 0.0 and _spin <= 0.0:
			ctx.stop_action()
		_shot_accum = 0.0
		_bloom = maxf(_bloom - tuning.bloom_decay_deg * player_dt, 0.0)
		return
	if ammo <= 0:
		reload()
		return
	if _spin <= 0.0:
		ctx.play_action(&"gatling_spin")
		Audio.play(&"gatling_spin", ctx.socket(&"muzzle_r"))
	_spin = minf(_spin + player_dt / maxf(tuning.spin_up, 0.001), 1.0)
	if _spin < 1.0:
		return
	_bloom = minf(_bloom + tuning.bloom_gain_deg * player_dt, tuning.bloom_max_deg)
	_shot_accum += player_dt * tuning.rounds_per_second
	while _shot_accum >= 1.0 and ammo > 0 and state == State.READY:
		_shot_accum -= 1.0
		_shoot()


func _shoot() -> void:
	ammo -= 1
	rounds_fired += 1
	_since_shot = 0.0
	var muzzle := ctx.socket(&"muzzle_r")
	var dir := _spread(ctx.aim_dir_from(muzzle))
	var hot := superheated_left > 0.0
	var dmg := tuning.damage * (tuning.superheated_damage if hot else 1.0)
	var imp := tuning.impact * (tuning.superheated_impact if hot else 1.0)
	var tracer := rounds_fired % TRACER_EVERY == 0
	ctx.bullets.fire(muzzle, dir, dmg, imp, tuning.muzzle_speed, tuning.life, tracer)
	Events.weapon_fired.emit(ID, muzzle, dir)
	heat = minf(heat + tuning.heat_per_shot, 100.0)
	ctx.sparks.muzzle_flash(muzzle, dir, Color(1.0, 0.8, 0.4), ctx.fp_size(FLASH_SIZE), 0.07,
			ctx.fp_alpha())
	ctx.casings.eject(muzzle, (ctx.facing().cross(Vector3.UP)).normalized() + Vector3.UP * 0.8, 14.0)
	if heat >= 100.0:
		state = State.VENT
		_vent_t = 0.0
		_spin = 0.0
		_shot_accum = 0.0
		Feel.play(&"gatling_overheat", muzzle)
		return
	if tracer:
		Feel.play(&"gatling_fire", muzzle)
		Audio.play(&"gatling_fire", muzzle)


## Cone spread: hip or ADS base plus the bloom built up while firing.
func _spread(dir: Vector3) -> Vector3:
	var total := (tuning.spread_ads_deg if ctx.ads else tuning.spread_hip_deg) + _bloom
	if total <= 0.0:
		return dir
	var cone := deg_to_rad(total)
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var side := up.cross(dir).normalized()
	var d := dir.rotated(up, randf_range(-cone, cone))
	return d.rotated(side, randf_range(-cone, cone)).normalized()


func reload() -> bool:
	if _reloading or ammo >= tuning.belt or state == State.JAM or ctx == null:
		return false
	_reloading = true
	state = State.RELOAD
	_timer = tuning.reload_time
	_spin = 0.0
	_shot_accum = 0.0
	ctx.play_action(&"reload")
	return true


func is_firing() -> bool:
	return state == State.READY and _spin >= 1.0


## Spin the barrel down (weapon swap). Heat, jam and Superheated timers keep running:
## WeaponSystem keeps ticking them through `tick_holstered()` while the rifle is out.
func cancel() -> void:
	_spin = 0.0
	_shot_accum = 0.0


func spin() -> float:
	return _spin


func needle() -> float:
	return clampf(_vent_t / maxf(tuning.vent_sweep, 0.001), 0.0, 1.0) if state == State.VENT else 0.0


func overheated() -> bool:
	return state == State.VENT or state == State.VENT_GOOD


func hud_state() -> Dictionary:
	return {
		"ammo": ammo,
		"ammo_max": tuning.belt,
		"reloading": state == State.RELOAD,
		"heat": heat / 100.0,
		"overheated": overheated(),
		"vent_needle": needle(),
		"vent_mark": tuning.vent_mark,
		"superheated": superheated_left > 0.0,
	}
