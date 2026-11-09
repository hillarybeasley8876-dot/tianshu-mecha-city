class_name MechTuning
extends Resource
## Every movement and resource number of the hero mech in one place, so feel can be retuned from
## `player/mech/mech_tuning.tres` without touching the state machine. Source: SPEC §2/§4 (revised
## 2026-11-01 from feel-mech-games §16 and level-design §3) and skills-catalog §4.1.
## Frame data is 60 fps; the game runs at 120 Hz (2 physics ticks per frame).
## Principle (SPEC §4): heavy legs, instant thrusters — mass from legs/landings, response from thrusters.

## One 60 fps frame in seconds — the unit of every frame-data number below.
const FRAME := 1.0 / 60.0

@export_group("Body")
@export var capsule_radius := 3.5
@export var capsule_height := 15.0
@export var floor_max_angle_deg := 40.0
@export var floor_snap := 0.6
@export var rise_gravity := 79.0       ## derived: hop 8 m in 0.45 s => v0 35.6, g = v0 / t
## SPEC §4 (lead, 11-03): it falls as hard as it rises. At 25.5 m/s^2 the hop rose in 0.45 s and
## drifted down for 0.79 s, which the user called "软绵绵" -- a 16 m machine falling like a balloon.
@export var fall_gravity := 80.0
@export var terminal_speed := 80.0
@export var dive_speed := 95.0         ## `descend` held in the air: a slam, faster than free fall
@export var flight_ceiling := 260.0    ## storm shield above the district

@export_group("Ground")
@export var walk_speed := 9.0
@export var run_speed := 16.0
@export var accel_time := 0.35         ## 0 -> walk top speed; run takes 0.62 s at the same rate
@export var decel_time := 0.25         ## run -> 0
@export var turn_walk_deg := 180.0     ## legs turn 180 deg/s walking, 120 deg/s running
@export var turn_run_deg := 120.0
@export var strafe_turn_rate_deg := 180.0  ## tuning choice: aiming mode keeps the legs nimbler
@export var footstep_walk := 0.90
@export var footstep_run := 0.62

@export_group("Dash")
@export var dash_time := 0.25          ## 30 physics ticks
@export var dash_peak := 150.0
@export var dash_exit := 42.0          ## exits at boost speed
@export var dash_ease := 1.0           ## 150 -> 42 over 0.25 s integrates to exactly 24 m
@export var dash_cost := 110.0
@export var dash_air_cost := 130.0
@export var dash_iframes := 6.0 * FRAME  ## 0.10 s = exactly 12 physics ticks
@export var dash_max_chain := 3
@export var dash_lockout := 0.45       ## after the third chained dash
@export var dash_reload := 0.38        ## ground: minimum spacing between chained dashes
@export var dash_chain_window := 0.50  ## tuning choice: chain lapses this long after a dash
@export var vernier_hang := 0.15       ## air dash only: brief float at the end of the jet

@export_group("Boost")
## SPEC §4: the boost is sustained for as long as it is held and never becomes the assault boost.
@export var boost_speed := 42.0        ## ground skate and air cruise
@export var boost_accel_time := 0.18
@export var boost_turn_rate_deg := 160.0
@export var boost_cost := 0.0          ## SPEC §4: free on the ground, EN keeps regenerating
@export var glide_sink := 6.0          ## air boost holds altitude loss to this instead of falling

@export_group("Assault boost")
@export var assault_brake := 0.25     ## SPEC §4: holding the stick against the jet this long cancels it
@export var assault_ignition := 0.30   ## wind-up before the jet bites (FOV +11 deg)
@export var assault_speed := 84.0
@export var assault_yaw_deg := 80.0
@export var assault_pitch_deg := 45.0
@export var assault_cost := 120.0      ## EN/s
@export var assault_accel_time := 0.25 ## tuning choice: 42 -> 84 spin-up

@export_group("Jump")
@export var jump_apex := 8.0
@export var jump_apex_time := 0.45
@export var jump_dip := 4.0 * FRAME    ## SPEC §4 knee-dip; other inputs stay accepted
@export var coyote_time := 0.10        ## tuning choice: forgiving ledge jumps
@export var jump_buffer := 6.0 * FRAME
## Tuning choice: how long an action pressed during a local hit-stop stays buffered (juice §2.2).
@export var input_buffer := 18.0 * FRAME

@export_group("Ascend / hover")
@export var ascend_speed := 18.0
@export var ascend_cost := 100.0       ## EN/s
@export var hover_cost := 40.0         ## EN/s, holds altitude when ascending is not possible
@export var hover_reserve := 60.0      ## tuning choice: below this the mech hovers instead

@export_group("Flight")
@export var flight_double_tap := 0.30  ## tuning choice: second jump press window
@export var flight_speed := 50.0
@export var flight_boost_speed := 84.0 ## = assault boost
@export var flight_vertical := 20.0
@export var flight_cost := 80.0        ## EN/s, and no EN regen while flying
@export var flight_accel_time := 0.30  ## tuning choice
@export var flight_boost_cost := 120.0
@export var glide_fall_scale := 0.35   ## tuning choice: unpowered glide after EN runs out
@export var glide_sink_cap := 12.0

@export_group("Landing")
@export var soft_speed := 46.0         ## impact m/s that splits soft from hard (~13 m fall; a hop lands at 36)
@export var heavy_feel_speed := 52.0  ## `land_heavy` feel/shake only from here (~17 m fall)
@export var soft_recovery := 0.20
@export var soft_cancel_from := 6.0 * FRAME
@export var hard_recovery := 0.38
@export var hard_cancel_from := 14.0 * FRAME
@export var outage_recovery := 0.70    ## landed with an empty gauge: long, no cancel
@export var land_min_impact := 8.0     ## tuning choice: below this (a 0.4 m drop) it is a kerb
@export var land_pose_time := 0.18    ## tuning choice: how long the soft-landing dip is drawn

@export_group("Stepping")
@export var step_height := 2.5         ## SPEC §4: walk straight over a kerb this tall
@export var step_probe := 0.40         ## tuning choice: probe this far past the frame's own motion
## r8 item 1: the step-up COAST. The capsule used to climb a kerb in ONE tick -- 2.01 m up and 4.24 m
## forward, measured tick-by-tick on the sandbox kerb (`probe_float.gd --debug`, hip y 7.71 -> 9.72,
## hip z 9.48 -> 5.24) -- which is right for the physics (no stall, no lost speed) and impossible for
## the legs: the hip cleared the trailing foot's plant by 6.96 m before the gait released it, 10.4 m
## from a hip whose leg reaches 8.5 m, so the IK clamped and the sole floated 0.91 m. The rise and the
## run-up are now walked out over `run-up / speed` seconds, which is EXACTLY the speed the mech was
## already doing: the body still never stalls and never surges, and the hip advances no faster than
## the feet can follow.
@export var step_coast_min := 0.05      ## seconds; a standstill crawl still coasts, never teleports
## r8 item 1: metres of model lag given back per metre travelled. The model holds the LOWER surface
## while the trailing foot is still standing on it (that is the whole point) and climbs once the mech
## is far enough onto the kerb for both feet to be on top. 0.26 gives the 2 m rise back over 8 m of
## travel, inside the 12 m sandbox kerb at every speed the game has.
@export var step_ease_ratio := 0.26
## ... and a time floor under it, so a mech that stops dead on a kerb still puts its feet back under
## it instead of holding the lag for the rest of the round.
@export var step_ease_speed := 1.2
@export var hop_max_height := 7.0      ## SPEC §4: auto-hop anything this tall while boosting
@export var hop_lookahead := 0.20      ## seconds of travel probed ahead of the mech
@export var hop_lookahead_scale := 1.5  ## lead's rule: probe 1.5x the distance it will really cover
@export var hop_clearance := 1.0       ## extra metres of rise so the feet clear the top
@export var hop_min_speed := 12.0      ## below this the step-up alone carries the mech over
@export var hop_max_impulse := 45.0    ## above this it is too late to clear it: take the wall
@export var hop_cooldown := 0.60       ## one hop per obstacle, not one per frame

@export_group("Energy")
@export var energy_max := 1000.0
@export var regen_ground := 500.0      ## EN/s once `regen_delay_ground` passed without spending
@export var regen_delay_ground := 0.6
@export var regen_air := 120.0
@export var regen_delay_air := 0.9
@export var outage_pause := 1.5
@export var outage_grant := 250.0      ## instant top-up when the lockout ends
@export var outage_restart := 300.0    ## dash / ascend need this much EN after an Outage

@export_group("Armour")
@export var hp_max := 10000.0
@export var hurt_heavy_damage := 600.0
@export var knockback_scale := 1.0
@export var invuln_blink := 0.12       ## tuning choice: mercy window after a heavy hit

@export_group("Overdrive")
@export var od_max := 100.0
@export var od_per_hp_percent := 1.0
@export var od_perfect_dodge := 3.0
@export var od_low_hp_bonus := 1.5
@export var od_low_hp := 0.15

@export_group("Lunge")
@export var lunge_arrive := 3.0
@export var lunge_turn_rate_deg := 240.0
## A wall stops the lunge only when it faces the lunge within ~45° (normal · direction below this);
## a grazed facade or a kerb edge is slid along / stepped onto instead of killing a 110 m/s dash.
@export var lunge_block_dot := -0.7


## Thruster hop launch speed: `jump_apex` reached after `jump_apex_time` (SPEC §4).
func jump_speed() -> float:
	return 2.0 * jump_apex / jump_apex_time


## Dash speed at normalised time `u` (0..1): a hard jet that decays to boost speed.
func dash_speed_at(u: float) -> float:
	return dash_exit + (dash_peak - dash_exit) * pow(clampf(1.0 - u, 0.0, 1.0), dash_ease)


## Ground acceleration (0 -> walk top in `accel_time`) and braking (run -> 0 in `decel_time`).
func accel_rate() -> float:
	return walk_speed / accel_time


func brake_rate() -> float:
	return run_speed / decel_time


## Legs turn faster walking than running (SPEC §4).
func turn_rate(speed: float) -> float:
	return lerpf(turn_walk_deg, turn_run_deg, clampf(speed / run_speed, 0.0, 1.0))


func footstep_interval(speed: float) -> float:
	return lerpf(footstep_walk, footstep_run, clampf(speed / run_speed, 0.0, 1.0))
