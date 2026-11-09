extends Node3D
## Camera shake pivot (camera-aim). Owns every ADDITIVE camera effect, so gameplay aim (read from the
## parent Pitch node) never drifts: trauma noise rotation, the directional kick spring and the landing
## dip. Numbers from docs/FEEL.md (trauma², decay 1.2/s, rotational only) and
## ref/research/juice-impact.md §3.2 (Perlin 14 Hz, critically damped kick ω 22/26 rad/s).
## Runs on UNSCALED time so the view keeps shaking through hit-stop and slow motion (juice §3.4): the rig
## passes `Feel.real_delta(delta)` (CONTRACTS §3), never the wall clock — movie capture renders a frame in
## ~70 ms of wall time, and a hitch can too, while the game clock still advances 1/120 s per tick.

const DECAY := 1.2                  ## trauma per second, linear (FEEL header)
const NOISE_HZ := 14.0
const MAX_PITCH_DEG := 3.0
const MAX_YAW_DEG := 3.0
const MAX_ROLL_DEG := 2.0           ## small on purpose: roll makes players dizzy (juice §3.1)
const KICK_OMEGA_TP := 22.0
const KICK_OMEGA_FP := 26.0
const KICK_OMEGA_MIN := 8.0     ## bounds for the settle time requested with Feel.kick
const KICK_OMEGA_MAX := 45.0
const KICK_SETTLE := 5.8        ## time constants a critically damped spring needs to settle
const DIP_OMEGA := 14.0             ## a heavy body sinks at once and comes back up slower
const DIP_MIN := 0.35               ## SPEC §5: landing dip −0.35…−1.2 m, scaled by fall speed
const DIP_MAX := 1.2
const DIP_SOFT_SPEED := 30.0        ## at or under this the dip is the minimum (a hop lands at 36 m/s)
const DIP_TERMINAL_SPEED := 80.0    ## = MechTuning.terminal_speed
const STEP_DEPTH := 0.12            ## SPEC §5: footstep translate −0.12 m, spring k 65 d 15
const STEP_K := 65.0
const STEP_D := 15.0
const MAX_DT := 0.1                 ## s per advance (a stalled frame must not fling the view)
const SUBSTEP := 1.0 / 240.0        ## s; keeps ω·h ≤ 0.19 at ω 45, so the explicit springs stay stable

var trauma: float = 0.0

var _first_person: bool = false
var _noise: Array[FastNoiseLite] = []
var _t: float = 0.0
var _kick: Vector3 = Vector3.ZERO       ## degrees (pitch, yaw, roll)
var _kick_vel: Vector3 = Vector3.ZERO
var _kick_omega: float = 0.0            ## 0 = use the mode default; set by Feel.kick's duration
var _dip: float = 0.0
var _dip_vel: float = 0.0
var _step: float = 0.0                  ## footstep translate, m (SPEC §5: never rotation in 1st person)
var _step_vel: float = 0.0
var _floor: float = 0.0                 ## held minimum trauma (Feel.shake_floor)
var _floor_left: float = 0.0            ## real seconds the floor still holds


func _ready() -> void:
	for seed_value in 3:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.seed = 1000 + seed_value
		n.frequency = 1.0
		_noise.append(n)


## Trauma is ADDED and clamped to 1 (FEEL header). Shake amplitude = trauma².
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Continuous shake (Feel.shake_floor): trauma never drops below `amount` for `seconds` of real time.
## Overlapping floors keep the strongest amount and the longest hold.
func hold_floor(amount: float, seconds: float) -> void:
	if seconds <= 0.0 or amount <= 0.0:
		return
	_floor = maxf(_floor, amount) if _floor_left > 0.0 else amount
	_floor_left = maxf(_floor_left, seconds)


## Directional recoil: shove the view opposite the force (juice §3.1, Vlambeer). Degrees.
## Recoil in the cockpit reads 1.2× stronger (juice §3.2), unlike shake which is damped there.
## `duration` (from Feel.kick) sets how long the spring takes to settle; <= 0 keeps the mode default.
func add_kick(pitch_deg: float, yaw_deg: float, roll_deg: float, duration: float = -1.0) -> void:
	_kick += Vector3(pitch_deg, yaw_deg, roll_deg) * (1.2 if _first_person else 1.0)
	_kick_omega = clampf(KICK_SETTLE / duration, KICK_OMEGA_MIN, KICK_OMEGA_MAX) if duration > 0.0 else 0.0


## Landing dip from Events.landed(impact_speed), scaled by fall speed (SPEC §5: −0.35…−1.2 m).
func land(impact_speed: float) -> void:
	var k := clampf((impact_speed - DIP_SOFT_SPEED) / (DIP_TERMINAL_SPEED - DIP_SOFT_SPEED), 0.0, 1.0)
	_dip = -lerpf(DIP_MIN, DIP_MAX, k)


## Footstep translate: the camera sinks a little with every heavy step (SPEC §5 "mass cues").
func footstep(heavy: bool) -> void:
	_step -= STEP_DEPTH * (1.0 if heavy else 0.5)
	_step_vel = 0.0


func reset() -> void:
	trauma = 0.0
	_kick = Vector3.ZERO
	_kick_vel = Vector3.ZERO
	_kick_omega = 0.0
	_dip = 0.0
	_dip_vel = 0.0
	_step = 0.0
	_step_vel = 0.0
	_floor = 0.0
	_floor_left = 0.0
	rotation = Vector3.ZERO
	position.y = 0.0


## Called once per physics tick by the rig with the REAL delta; writes rotation/position. The springs are
## sub-stepped so any delta up to MAX_DT stays stable (one 70 ms step at ω 45 diverged to NaN).
func advance(first_person: bool, dt: float) -> void:
	dt = clampf(dt, 0.0, MAX_DT)
	_t += dt
	trauma = maxf(trauma - DECAY * dt, 0.0)
	if _floor_left > 0.0:
		_floor_left -= dt
		trauma = maxf(trauma, _floor)
	_first_person = first_person
	var steps := maxi(ceili(dt / SUBSTEP), 1)
	var h := dt / float(steps)
	for i in steps:
		_spring_kick(h)
		_spring_dip(h)
		_spring_step(h)
	var shake := trauma * trauma * (0.6 if first_person else 1.0)
	var t := _t * NOISE_HZ
	rotation = Vector3(
			deg_to_rad(MAX_PITCH_DEG * shake * _noise[0].get_noise_1d(t) + _kick.x),
			deg_to_rad(MAX_YAW_DEG * shake * _noise[1].get_noise_1d(t) + _kick.y),
			deg_to_rad(MAX_ROLL_DEG * shake * _noise[2].get_noise_1d(t) + _kick.z))
	position.y = _dip + _step


## Critically damped: a = -ω²x - 2ωv (settles in ~200 ms at ω 22).
func _spring_kick(dt: float) -> void:
	var omega := _kick_omega
	if omega <= 0.0:
		omega = KICK_OMEGA_FP if _first_person else KICK_OMEGA_TP
	_kick_vel += (-omega * omega * _kick - 2.0 * omega * _kick_vel) * dt
	_kick += _kick_vel * dt
	if _kick.length_squared() < 1e-8 and _kick_vel.length_squared() < 1e-6:
		_kick = Vector3.ZERO
		_kick_vel = Vector3.ZERO


func _spring_dip(dt: float) -> void:
	_dip_vel += (-DIP_OMEGA * DIP_OMEGA * _dip - 2.0 * DIP_OMEGA * _dip_vel) * dt
	_dip += _dip_vel * dt
	if absf(_dip) < 1e-4 and absf(_dip_vel) < 1e-3:
		_dip = 0.0
		_dip_vel = 0.0


## Footstep spring with the SPEC's own constants (k 65, d 15).
func _spring_step(dt: float) -> void:
	_step_vel += (-STEP_K * _step - STEP_D * _step_vel) * dt
	_step += _step_vel * dt
	if absf(_step) < 1e-4 and absf(_step_vel) < 1e-3:
		_step = 0.0
		_step_vel = 0.0
