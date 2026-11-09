class_name Hero3Skate
extends RefCounted
## The non-stepping ground stances for the Tianshu mech (hero-v3, lead r4 item 2).
##
## The game's move states are not all walks. `mech-move` sends `slide` (a 42 m/s ground boost),
## `dash_*` (0.25 s at 150 -> 42 m/s), `assault` (84 m/s), `lunge`, `locked` and `coast`, and the
## first gait walked every one of them at the reported speed. A step planner cannot serve 150 m/s:
## one step would have to cover more ground than the leg can reach, so the legs scrambled at 4-8
## steps a second with the feet up to 13.75 m from their IK targets. Dash, boost and assault are the
## verbs the player uses most, so that was the user's complaint every few seconds.
##
## Above the gait's own step limit the mech SKATES instead:
##   * no steps at all -- both soles stay on the floor, pinned in the PELVIS frame, so they slide with
##     the body (a skate slides; that is what a skate is);
##   * the feet are staggered fore and aft along the travel, the knees bent, the pelvis 1.0-1.5 m low;
##   * the lower body leans into the travel, and a dash adds a burst on top of that lean.
##
## The lower body is already yawed toward the travel by `Hero3Gait` (up to 80 deg), so in the lower
## body's OWN frame the travel is always straight ahead and the lean is a plain pitch.

## How fast the stance blends in and out. The lead's brief: about 0.12 s.
const BLEND := 0.12
## The dash burst: the lean snaps up inside three frames and eases back out over 0.22 s.
const BURST_RISE := 0.05
const BURST_FALL := 0.22
const BURST_LEAN_DEG := 10.0
const BURST_STAGGER := 0.80
## `{drop, lean, stagger}` per state: the pelvis depth in metres, the lean in degrees, and how far
## the feet are staggered either side of the hips along the travel.
const DEFAULT: Dictionary = {"drop": 1.25, "lean": 10.0, "stagger": 2.0}
const STANCE: Dictionary = {
	&"slide": {"drop": 1.30, "lean": 12.0, "stagger": 3.2},
	&"lunge": {"drop": 1.10, "lean": 14.0, "stagger": 3.0},
	&"locked": {"drop": 0.70, "lean": 4.0, "stagger": 0.6},
	&"dash_f": {"drop": 1.20, "lean": 10.0, "stagger": 2.2},
	&"dash_b": {"drop": 1.20, "lean": 10.0, "stagger": 2.2},
	&"dash_l": {"drop": 1.20, "lean": 10.0, "stagger": 2.2},
	&"dash_r": {"drop": 1.20, "lean": 10.0, "stagger": 2.2},
}
## States that are ALWAYS a skate, whatever the speed.
const STATES: Array[StringName] = [&"slide", &"lunge", &"locked",
		&"dash_f", &"dash_b", &"dash_l", &"dash_r"]
const DASHES: Array[StringName] = [&"dash_f", &"dash_b", &"dash_l", &"dash_r"]
## States that happen both on the ground and in the air. The model cannot see the floor, so these
## inherit it from the state before: if the air pose was up, it stays up and only the burst lean is
## added.
const DUAL: Array[StringName] = [&"dash_f", &"dash_b", &"dash_l", &"dash_r", &"lunge", &"locked"]

## 0 = the gait's own step cycle, 1 = the full skate stance.
var blend: float = 0.0
## 0 = the stance's own lean, 1 = the dash burst on top of it.
var burst: float = 0.0


static func is_skate_state(state: StringName) -> bool:
	return STATES.has(state)


static func is_dash(state: StringName) -> bool:
	return DASHES.has(state)


static func is_dual(state: StringName) -> bool:
	return DUAL.has(state)


func stance(state: StringName) -> Dictionary:
	if not override.is_empty():
		return override
	return STANCE.get(state, DEFAULT)


## A stance set from outside, which wins over the table. Empty by default; the interpenetration sweep
## (`tests/probe_clear.gd`) uses it to measure which drop and stagger keep the plates apart, and it
## is the hook a per-mech tuning pass would use.
var override: Dictionary = {}


func set_override(stance_: Dictionary) -> void:
	override = stance_


## Advance the blend and the burst. `want` is 1 while this state should be skating on the ground.
func update(delta: float, want: float, state: StringName) -> void:
	blend = move_toward(blend, want, delta / BLEND)
	var target := 1.0 if (want > 0.5 and is_dash(state)) else 0.0
	burst = move_toward(burst, target, delta / (BURST_RISE if target > burst else BURST_FALL))


## How deep the pelvis sits, in metres.
func drop(state: StringName) -> float:
	return float(stance(state)["drop"])


## How far the lower body leans into the travel, in radians.
func lean(state: StringName) -> float:
	return deg_to_rad(float(stance(state)["lean"]) + BURST_LEAN_DEG * burst)


## How far the feet are staggered either side of the hips along the travel, in metres. The burst
## extends the trailing leg, which is what a thruster push-off looks like.
func stagger(state: StringName) -> float:
	return float(stance(state)["stagger"]) + BURST_STAGGER * burst
