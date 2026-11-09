extends Node
## Field-of-view channel (camera-aim). Owns every FOV number the rig needs so the rig itself stays about
## placement: the player's base FOV from Settings, the ADS zoom, the held boost FOV, transient punches
## from `Feel.fov_kick` and scripted overrides (cinematics, overdrive).
## Numbers: SPEC §5 — Godot FOV is VERTICAL: third person 55° (boost 60°, assault 66°, ADS 38°),
## first person 62° (ADS 45°); ADS in 0.25 s, out 0.40 s. FEEL header: 1st person FOV effects ×0.75.
## juice-impact §3.3: clamp the sum of transient effects to ±15°.

const FOV_THIRD := 55.0
const FOV_THIRD_ADS := 38.0
const FOV_FIRST := 62.0
const FOV_FIRST_ADS := 45.0
const FOV_FX_CLAMP := 15.0
const FOV_FX_FIRST := 0.75          ## FEEL header: 1st person FOV effects ×0.75
const ADS_IN := 0.25                ## SPEC §5
const ADS_OUT := 0.40
const BOOST_FOV: Dictionary = {&"quick": 58.0, &"slide": 60.0, &"assault": 66.0}
const BOOST_IN := 0.12              ## FEEL boost_start: 120 ms in, 300 ms back
const BOOST_OUT := 0.30
## The player can slide the base FOV; SPEC's 55/62 are the defaults core/settings.gd ships, and the ADS
## zoom keeps its ratio to whatever the slider says so the magnification feels the same at any FOV.
const ADS_RATIO_THIRD := FOV_THIRD_ADS / FOV_THIRD
const ADS_RATIO_FIRST := FOV_FIRST_ADS / FOV_FIRST
const SETTING_MIN := 40.0
const SETTING_MAX := 110.0

var _cam: Camera3D = null
var _ads_t: float = 0.0
var _ads_target: float = 0.0
var _kick: float = 0.0              ## transient degrees, returns to 0 at a constant rate
var _kick_rate: float = 0.0
var _boost: float = 0.0             ## held boost degrees (absolute target minus the base)
var _boost_target: float = 0.0
var _boost_ref: float = 0.0         ## magnitude the linear in/out rate is derived from
var _override_from: float = 0.0
var _override_to: float = 0.0
var _override_t: float = 1.0
var _override_time: float = 0.25
var _hold: float = 0.0              ## absolute FOV held by a cinematic shot
var _holding: bool = false
var _first_person: bool = false


func setup(cam: Camera3D) -> void:
	_cam = cam
	_cam.fov = base()


## The player's own FOV slider sets the wide FOV in degrees; ADS zooms by the SPEC ratio.
func base() -> float:
	var spec_wide := FOV_FIRST if _first_person else FOV_THIRD
	var ratio := ADS_RATIO_FIRST if _first_person else ADS_RATIO_THIRD
	var boost := _boost * (FOV_FX_FIRST if _first_person else 1.0)
	var wide := setting_fov() + boost
	return lerpf(wide, spec_wide * ratio * (wide / spec_wide), _ads_t)


func current() -> float:
	return _cam.fov if _cam != null else base()


## The slider value alone (no ADS zoom, no boost, no punch): camera framing is solved against it.
func setting_fov() -> float:
	var setting := &"fov_first" if _first_person else &"fov_third"
	return clampf(float(Settings.get_value(setting)), SETTING_MIN, SETTING_MAX)


func is_ads() -> bool:
	return _ads_t > 0.5


## 0 → 1 ramp the ADS zoom runs on. The rig shortens the spring arm with it (SPEC §5: 40 m → 28 m).
func ads_blend() -> float:
	return _ads_t


## Transient punch: snap to the requested degrees, then bleed off over `duration` (juice §3.3).
func kick(degrees: float, duration: float) -> void:
	_kick += degrees
	_kick_rate = maxf(absf(_kick) / maxf(duration, 0.05), 1.0)


## SPEC §5 gives boost/assault absolute third-person FOVs; the channel stores the offset over the base
## (and damps it by ×0.75 in the cockpit, per the FEEL header).
func set_boost(kind: StringName, active: bool) -> void:
	if active:
		_boost_target = float(BOOST_FOV.get(kind, FOV_THIRD)) - FOV_THIRD
	else:
		_boost_target = 0.0
	# The rate comes from the size of the move, so releasing a 11° assault boost takes the full 0.30 s.
	_boost_ref = maxf(absf(_boost_target - _boost), 1.0)


## Blend to an absolute FOV; pass `hold = true` to keep it until `release()` (cinematic shots).
func override(degrees: float, s: float = 0.2, hold: bool = false) -> void:
	if hold:
		# Cinematics stop calling update(), so the held value has to land on the camera now.
		_hold = degrees
		_holding = true
		if _cam != null:
			_cam.fov = degrees
		return
	_override_from = current()
	_override_to = degrees
	_override_time = maxf(s, 0.001)
	_override_t = 0.0


func release(s: float = 0.25) -> void:
	_holding = false
	override(base(), s)


func update(delta: float, first_person: bool, ads_pressed: bool) -> void:
	if _cam == null:
		return
	_first_person = first_person
	if _holding:
		_cam.fov = _hold
		return
	_ads_target = 1.0 if ads_pressed else 0.0
	_ads_t = move_toward(_ads_t, _ads_target, delta / (ADS_IN if _ads_target > _ads_t else ADS_OUT))
	if _kick != 0.0:
		_kick = move_toward(_kick, 0.0, _kick_rate * delta)
	# Linear, not exponential: the rate comes from the requested magnitude, so the move always finishes.
	var span := BOOST_IN if _boost_target > _boost else BOOST_OUT
	_boost = move_toward(_boost, _boost_target, (_boost_ref / span) * delta)
	var fx := clampf(_kick, -FOV_FX_CLAMP, FOV_FX_CLAMP)   # the held boost FOV is already in base()
	if first_person:
		fx *= FOV_FX_FIRST
	_cam.fov = base() + fx
	if _override_t < 1.0:
		_override_t = minf(_override_t + delta / _override_time, 1.0)
		_cam.fov = lerpf(_override_from, _override_to, smoothstep(0.0, 1.0, _override_t))
