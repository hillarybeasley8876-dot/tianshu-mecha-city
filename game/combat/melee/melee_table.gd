class_name MeleeTable
extends RefCounted
## Dawn Edge saber frame data (skills-catalog §4.3), lead-scaled for our 16 m hero: REACH and RADII
## are ×2 (SPEC scale rule), frames / seconds / damage / EN are unchanged. Frames in the dossier are
## 60 fps; the game runs at 120 Hz, so every window is doubled by `ticks()`.
##
## Frame index convention: frame 1 is the first frame of startup, so the total move length is
## startup + active + recovery and a "cancel from f14" means 13 frames have already elapsed.

const REF_FPS := 60.0
const PHYSICS_HZ := 120.0

## Move ids (also the model's play_action ids, SPEC §10).
const L1 := &"melee_l1"
const L2 := &"melee_l2"
const L3 := &"melee_l3"
const LUNGE := &"lunge"
const CHARGE_SLASH := &"charge_slash"
const AIR_L1 := &"air_l1"
const AIR_L2 := &"air_l2"
const RETURN_CUT := &"return_cut"
const RAM_KICK := &"ram_kick"

## Damage / impact / reach (metres, already ×2) / arc (degrees, half-angle is used by the sweep).
const DATA: Dictionary = {
	L1: {
		"startup": 9.0, "active": 4.0, "recovery": 16.0,
		"damage": 380.0, "impact": 180.0, "reach": 18.0, "arc": 120.0,
		"knockback": 0.0, "hitstop": 5.0, "feel": &"melee_light", "step_in": 6.0,
		"cancel_from": 14.0, "cancel_to": 24.0, "cancel_next": true, "cancel_move": true,
		"detonate": false, "wave": false,
	},
	L2: {
		"startup": 8.0, "active": 4.0, "recovery": 16.0,
		"damage": 380.0, "impact": 180.0, "reach": 18.0, "arc": 120.0,
		"knockback": 0.0, "hitstop": 5.0, "feel": &"melee_light", "step_in": 0.0,
		"cancel_from": 13.0, "cancel_to": 24.0, "cancel_next": true, "cancel_move": true,
		"detonate": false, "wave": false,
	},
	L3: {
		"startup": 14.0, "active": 6.0, "recovery": 28.0,
		"damage": 820.0, "impact": 480.0, "reach": 20.0, "arc": 200.0,
		"knockback": 14.0, "hitstop": 9.0, "feel": &"melee_heavy", "step_in": 0.0,
		"cancel_from": 22.0, "cancel_to": 34.0, "cancel_next": false, "cancel_move": true,
		"detonate": false, "wave": false,
	},
	LUNGE: {
		"startup": 6.0, "active": 42.0, "recovery": 12.0,
		"damage": 950.0, "impact": 520.0, "reach": 18.0, "arc": 140.0,
		"knockback": 4.0, "hitstop": 7.0, "feel": &"lunge_hit", "step_in": 0.0,
		"cancel_from": 48.0, "cancel_to": 60.0, "cancel_next": true, "cancel_move": true,
		"detonate": false, "wave": false,
	},
	CHARGE_SLASH: {
		"startup": 10.0, "active": 8.0, "recovery": 30.0,
		"damage": 1500.0, "impact": 900.0, "reach": 22.0, "arc": 210.0,
		"knockback": 8.0, "hitstop": 10.0, "feel": &"charge_slash", "step_in": 0.0,
		"cancel_from": 48.0, "cancel_to": 48.0, "cancel_next": false, "cancel_move": false,
		"detonate": true, "wave": true,
	},
	AIR_L1: {
		"startup": 8.0, "active": 4.0, "recovery": 14.0,
		"damage": 340.0, "impact": 160.0, "reach": 16.0, "arc": 130.0,
		"knockback": 0.0, "hitstop": 4.0, "feel": &"melee_light", "step_in": 0.0,
		"cancel_from": 26.0, "cancel_to": 26.0, "cancel_next": false, "cancel_move": true,
		"detonate": false, "wave": false,
	},
	AIR_L2: {
		"startup": 8.0, "active": 4.0, "recovery": 14.0,
		"damage": 340.0, "impact": 160.0, "reach": 16.0, "arc": 150.0,
		"knockback": 2.0, "hitstop": 4.0, "feel": &"melee_light", "step_in": 0.0,
		"cancel_from": 26.0, "cancel_to": 26.0, "cancel_next": false, "cancel_move": true,
		"detonate": false, "wave": false,
	},
	RETURN_CUT: {
		"startup": 6.0, "active": 6.0, "recovery": 20.0,
		"damage": 1400.0, "impact": 900.0, "reach": 18.0, "arc": 180.0,
		"knockback": 10.0, "hitstop": 10.0, "feel": &"finisher", "step_in": 0.0,
		"cancel_from": 32.0, "cancel_to": 32.0, "cancel_next": false, "cancel_move": false,
		"detonate": false, "wave": false,
	},
	RAM_KICK: {
		"startup": 6.0, "active": 6.0, "recovery": 20.0,
		"damage": 850.0, "impact": 750.0, "reach": 18.0, "arc": 100.0,
		"knockback": 18.0, "hitstop": 9.0, "feel": &"melee_heavy", "step_in": 0.0,
		"cancel_from": 32.0, "cancel_to": 32.0, "cancel_next": false, "cancel_move": true,
		"detonate": false, "wave": false,
	},
}

## Ground combo order; the air string is shorter (SPEC/skills §4.3).
const GROUND_CHAIN: Array[StringName] = [L1, L2, L3]
const AIR_CHAIN: Array[StringName] = [AIR_L1, AIR_L2]

## Global tuning (SPEC §3 "input buffer 6 f", §4.3 charge / hang, §4.6 execution).
const BUFFER_FRAMES := 6.0
const CHARGE_FRAMES := 30.0        ## hold this long to release a charged slash
const TAP_HOLD_FRAMES := 15.0      ## SPEC §3 tap/hold threshold 0.25 s
const AIR_HANG := 0.3              ## hover-hang after an air swing
const LUNGE_MIN := 24.0            ## skills-catalog §4.3 12–40 m ×2
const LUNGE_MAX := 80.0
const LUNGE_SPEED := 110.0
const LUNGE_TIME := 0.7
const LUNGE_HOMING_DEG := 120.0
const LUNGE_EN := 140.0
const LUNGE_STOP := 10.0           ## metres in front of the target the lunge ends at
const CHARGE_EN := 0.0             ## the charged slash itself is free; the hold time is the cost
const WAVE_LENGTH := 90.0          ## SPEC/skills §4.3: 45 m ×2
const WAVE_SPEED := 140.0          ## 70 m/s ×2
const WAVE_WIDTH := 24.0
const WAVE_HEIGHT := 16.0          ## tall enough to cover a 16 m mech standing on the ground
const WAVE_THICKNESS := 4.0        ## the crescent is ~4 m deep at its centre (review r1)
const WAVE_DROP := 5.0             ## metres below the blade pivot the crescent's base runs at
const WAVE_DAMAGE := 600.0
const WAVE_IMPACT := 300.0
const WAVE_LIFETIME := 2.0
const WAVE_SCOUR_STEP := 7.0       ## metres between ground spark/dust bursts under the wave
const RETURN_WINDOW := 0.8         ## skills-catalog §4.3: Return Cut ≤0.8 s after a perfect parry
const RAM_KICK_STAGGER_MULT := 2.5 ## SPEC §4 assault boost: ×2.5 vs staggered
const COMBO_RESET := 1.5           ## seconds without a swing before the chain restarts at L1
const SWEEP_TILT_DEG := 18.0       ## the blade plane leans this much out of horizontal
const BLADE_LENGTH := 14.0         ## the ONE agreed blade number (review r5 item 2): the visible blade
                                   ## is this long from the `saber_r` socket, and the hit volume's
                                   ## reach is measured so this length covers it (suite_hand's
                                   ## `visible_reach_covers_the_hitbox`). hero-v3 models MODEL_BLADE
                                   ## of steel and the energy extension makes up the rest.
## What a model that carries its own blade should model, in metres of steel: 12 m of it plus a 2 m
## energy tip is the 14 m above, which is what keeps the reach generous AND visible.
const MODEL_BLADE_LENGTH := 12.0
## Half-width at the hilt, and how much wider the additive glow sits around it. The r4 strips showed
## a 5× glow on a 0.8 m core as an 8 m leaf: a saber is long and THIN, so the glow only sheathes it.
const BLADE_HALF := 0.5
const BLADE_GLOW_SCALE := 2.1
const BLADE_HEIGHT := 0.0          ## metres above the body origin the arc pivots at (CONTRACTS §5:
                                   ## the body origin sits 7.5 m above the feet, so this is the waist)
const BLADE_WIDTH := 5.0           ## lateral thickness of the swept box
const BLADE_SPAN := 12.0           ## vertical span of the swept box, so it covers 6–22 m monsters
const TRAIL_FADE := 0.18           ## s the swing ribbon stays visible after the blade leaves a sample
const BLADE_EXTEND := 0.12         ## s the energy blade takes to grow out of the hilt on ignition
const BLADE_STOW := 0.6            ## s after the last melee action before the blade is put away

## Swing-plane tilt per move (degrees out of horizontal; negative = downward chop).
const TILT: Dictionary = {
	L1: -18.0, L2: 18.0, L3: -12.0, LUNGE: -10.0, CHARGE_SLASH: -32.0,
	AIR_L1: -26.0, AIR_L2: 26.0, RETURN_CUT: -20.0, RAM_KICK: 0.0,
}

## Which way the blade travels across the active window (hero-v3 r5 item 6): +1 = it ends on the
## mech's right (a left-to-right cut), -1 = it ends on its left. GENERATED, not typed -- paste the
## `SWEEP` block that `player/model/hero3/tests/test_hero3_reach.gd` prints after a model change.
## Without this the hitbox swept the opposite way to the animated blade on half the moves.
const SWEEP: Dictionary = {
	&"air_l1": -1.0,
	&"air_l2": 1.0,
	&"charge_slash": 1.0,
	&"lunge": -1.0,
	&"melee_l1": -1.0,
	&"melee_l2": 1.0,
	&"melee_l3": 1.0,
	&"ram_kick": -1.0,
	&"return_cut": -1.0,
}


## 60 fps frames → 120 Hz physics ticks.
static func ticks(frames: float) -> int:
	return maxi(int(round(frames * PHYSICS_HZ / REF_FPS)), 0)


static func seconds(frames: float) -> float:
	return frames / REF_FPS


static func has_move(id: StringName) -> bool:
	return DATA.has(id)


static func field(id: StringName, key: String, fallback: float = 0.0) -> float:
	var row: Dictionary = DATA.get(id, {})
	return float(row.get(key, fallback))


static func flag(id: StringName, key: String) -> bool:
	var row: Dictionary = DATA.get(id, {})
	return bool(row.get(key, false))


static func name_of(id: StringName, key: String) -> StringName:
	var row: Dictionary = DATA.get(id, {})
	return row.get(key, &"") as StringName


static func total_frames(id: StringName) -> float:
	return field(id, "startup") + field(id, "active") + field(id, "recovery")


static func tilt_deg(id: StringName) -> float:
	return float(TILT.get(id, SWEEP_TILT_DEG))


## +1 when the blade ends on the mech's right, -1 when it ends on its left (hero-v3 r5 item 6).
static func sweep_sign(id: StringName) -> float:
	return float(SWEEP.get(id, -1.0))


## Where the blade points at `progress` 0..1 through the move's arc, given the swing's facing. The
## hitbox (BladeSweep) and the visual (MeleeStrike → SaberVisual) both use this, so they agree, and
## `SWEEP` makes them agree with the ANIMATED blade as well.
static func blade_dir(id: StringName, facing: Basis, progress: float) -> Vector3:
	var half := deg_to_rad(field(id, "arc", 120.0) * 0.5)
	var angle := lerpf(-half, half, clampf(progress, 0.0, 1.0)) * sweep_sign(id)
	var flat := (-facing.z).rotated(Vector3.UP, angle)
	return flat.rotated(facing.x, deg_to_rad(tilt_deg(id))).normalized()
