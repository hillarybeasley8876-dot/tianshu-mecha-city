class_name SkillTuning
extends Resource
## Every skill number in one place (skills-catalog §4.4/§4.5). SPEC scale rule S = 2: reach, radii and
## projectile speeds are already doubled for our 16 m hero; frame counts, seconds, damage, EN costs,
## cooldowns and percentages are NOT scaled. Seconds are derived from the dossier's 60 fps frames.

const FRAME := 1.0 / 60.0        ## the dossier counts frames at 60 fps
const TICK := 1.0 / 120.0        ## our physics rate (CONTRACTS §2)

@export_group("S1 Rift Step")
@export var rift_cd := 8.0
@export var rift_cost := 110.0            ## [tuning] same band as a dash: the blink replaces one
@export var rift_lock_range := 90.0       ## 45 m at the dossier's 8 m
@export var rift_behind := 14.0           ## 7 m behind the target, facing it
@export var rift_flank := 14.0            ## 7 m to the stick's flank
@export var rift_backoff := 50.0          ## 25 m straight back
@export var rift_free := 44.0             ## 22 m in the stick direction with no lock
@export var rift_transit := 9.0 * FRAME   ## invulnerable, drawn as a streak
@export var rift_recovery := 6.0 * FRAME
@export var rift_ambush := 0.45           ## window after the recovery
@export var rift_ambush_damage := 1.5     ## +50 % damage
@export var rift_ambush_impact := 2.0     ## +100 % impact
@export var rift_decoy := 0.6             ## decoy shell that draws Swarmers

@export_group("S2 Skyhook Anchor")
@export var anchor_charges := 2
@export var anchor_recharge := 5.0
@export var anchor_cost := 60.0           ## [tuning] traversal must stay cheap enough to chain
@export var anchor_speed := 360.0         ## 180 m/s cable shot
@export var anchor_range := 120.0         ## 60 m
@export var anchor_snap_deg := 15.0       ## snaps onto a locked target inside this cone
@export var reel_start := 60.0            ## 30 m/s
@export var reel_top := 92.0              ## 46 m/s
@export var reel_ramp := 0.6              ## seconds to reach the top speed
@export var swing_angle_deg := 25.0       ## aim this far off the cable = swing instead of reel
@export var swing_detach_deg := 90.0      ## auto-detach, momentum kept
@export var release_up := 12.0            ## jump while attached launches you up at 6 m/s
@export var yank_distance := 18.0         ## light enemy stops 9 m in front of you
@export var yank_time := 0.35
@export var yank_stun := 0.6
@export var pull_in_speed := 92.0         ## heavy enemy: you are reeled in instead
@export var hook_kick_damage := 900.0
@export var hook_kick_impact := 700.0
@export var cable_hp := 600.0

@export_group("S4 Corona Fins")
@export var fins_cd := 10.0
@export var fins_cost := 80.0             ## [tuning] the tap is the kit's bread-and-butter primer
@export var fins_base := 2
@export var fins_per_mark := 2            ## 2 + 2 x marks -> 2 / 4 / 6
@export var fins_max := 6
@export var fin_speed := 150.0            ## 75 m/s
@export var fins_range := 180.0           ## 90 m
@export var fin_station := 18.0           ## 9 m sphere around the target
@export var fin_beams := 4
@export var fin_beam_gap := 0.22
@export var fin_damage := 110.0
@export var fin_impact := 45.0
@export var fin_return := 2.4
@export var fin_hp := 400.0
@export var fin_respawn := 6.0
@export var ward_hold := 0.35             ## hold this long and the tap becomes the ward
@export var ward_cd := 20.0
@export var ward_cost := 120.0            ## [tuning] the barrier is the expensive half of the fin kit
@export var ward_fins := 4                ## tetrahedron
@export var ward_absorb := 3000.0
@export var ward_time := 6.0
@export var ward_escort_fins := 2
@export var ward_escort_damage := 60.0
@export var ward_escort_gap := 0.5

@export_group("S6 Shockcore Burst")
@export var burst_cd := 20.0
@export var burst_cost := 150.0           ## [tuning] an AoE panic button priced above a lunge
@export var burst_startup := 18.0 * FRAME
@export var burst_active := 6.0 * FRAME
@export var burst_recovery := 20.0 * FRAME
@export var burst_radius := 32.0          ## 16 m
@export var burst_core := 12.0            ## full damage inside 6 m
@export var burst_damage := 1800.0
@export var burst_edge_damage := 600.0
@export var burst_impact := 1400.0
@export var burst_knock_light := 20.0
@export var burst_knock_heavy := 6.0

@export_group("S7 Undertow Well")
@export var well_cd := 16.0
@export var well_cost := 120.0            ## [tuning] priced with the lunge: it sets up a payoff
@export var well_throw := 90.0            ## 45 m/s arc
@export var well_range := 100.0           ## 50 m
@export var well_arm_time := 1.2          ## arms on impact or after this long in flight
@export var well_field := 3.5
@export var well_radius := 24.0           ## 12 m
@export var well_pull := 18.0             ## 9 m/s cap on Swarmers / Stalkers
@export var well_slow_heavy := 0.6        ## Brutes keep 60 % -> slowed by 40 %
@export var well_slow_boss := 0.85        ## bosses lose 15 %
@export var well_prime := 5.0
@export var collapse_damage := 900.0
@export var collapse_impact := 700.0
@export var collapse_radius := 20.0       ## 10 m
@export var collapse_od := 2.0            ## +2 % OD per COLLAPSE (§4.1)

@export_group("S8 Plunge Breaker")
@export var plunge_cd := 12.0
@export var plunge_cost := 140.0          ## [tuning] exactly the dossier's lunge cost
@export var plunge_hold := 0.25           ## melee held this long in the air
@export var plunge_min_height := 16.0     ## 8 m above the ground
@export var plunge_hang := 10.0 * FRAME
@export var plunge_speed := 190.0         ## 95 m/s
@export var plunge_cone_deg := 30.0       ## dive stays inside this of vertical
@export var plunge_home_range := 120.0    ## 60 m horizontal onto a locked target
@export var plunge_radius := 20.0         ## 10 m
@export var plunge_damage := 1600.0
@export var plunge_edge_damage := 500.0
@export var plunge_impact := 1100.0
@export var plunge_bonus_step := 20.0     ## +10 % per 20 m fallen (10 m at the dossier's scale)
@export var plunge_bonus_rate := 0.10
@export var plunge_bonus_cap := 0.50
@export var plunge_airlock := 0.75        ## non-bosses hang for an air juggle
@export var plunge_recovery := 24.0 * FRAME
@export var plunge_cancel_from := 12.0 * FRAME

@export_group("Zenith Overdrive")
@export var od_required := 100.0
@export var od_hold := 0.25
@export var od_ignite := 0.45
@export var od_duration := 12.0
@export var od_cd_tick := 2.5             ## cooldowns run 2.5x faster
@export var od_regen := 3.0               ## EN regen x3
@export var od_damage := 1.25             ## +25 % dealt
@export var od_taken := 0.70              ## -30 % taken
@export var od_impact := 1.30             ## +30 % impact
@export var od_afterimage_gap := 3.0 * FRAME
@export var od_afterimage_life := 0.25
@export var od_afterimage_speed := 12.0 ## planar m/s below which ghosts stop: at rest they stack
@export var od_lance_at := 1.0            ## auto-lance when this much time is left
@export var aftermath := 3.0
@export var aftermath_regen := 0.5

@export_group("Zenith Lance")
@export var lance_charge := 0.8
@export var lance_beam := 3.0
@export var lance_width := 16.0           ## 8 m
@export var lance_length := 800.0         ## SPEC §6: 800 m, clamped by sightlines
@export var lance_rate := 10.0            ## damage ticks per second
@export var lance_damage := 450.0
@export var lance_impact := 150.0
@export var lance_turn_deg := 40.0        ## rooted, sweeps at most this fast
@export var lance_barrier_time := 1.0     ## boss barriers need this much contact


## Radial damage falloff shared by the burst, the plunge and the COLLAPSE: full inside `core`,
## lerping down to `edge` at `radius`.
func falloff(distance: float, radius: float, core: float, top: float, edge: float) -> float:
	if distance >= radius:
		return 0.0
	if distance <= core:
		return top
	var t := (distance - core) / maxf(radius - core, 0.001)
	return lerpf(top, edge, clampf(t, 0.0, 1.0))
