class_name RifleTuning
extends Resource
## Pierce-Light rifle numbers (skills-catalog §4.2 P1, distances ×2 for the 16 m hero).
## Times, damage, impact and EN costs are unscaled.

@export_group("Fire")
@export var fire_interval: float = 0.25      ## 240 rpm cap between shots
@export var magazine: int = 9
@export var reload_time: float = 1.6
@export var reload_time_partial: float = 1.2  ## with at least one round still in the cell
@export var auto_reload_delay: float = 0.25  ## idle this long on an empty cell and it reloads itself

@export_group("Damage")
@export var damage: float = 230.0
@export var impact: float = 70.0             ## stagger / poise damage
@export var full_range: float = 200.0        ## full damage up to here (SPEC §6)
@export var falloff_range: float = 350.0     ## damage has fallen to falloff_mult here
@export var falloff_mult: float = 0.6
@export var max_range: float = 500.0         ## hard cut-off: the beam stops here

@export_group("Charge")
@export var stage1_time: float = 0.6
@export var stage1_damage: float = 700.0
@export var stage1_impact: float = 350.0
@export var stage1_rounds: int = 3
@export var stage1_energy: float = 120.0
@export var stage1_pierce: int = 1           ## extra bodies the beam passes through
@export var stage2_time: float = 1.2
@export var stage2_damage: float = 1400.0
@export var stage2_impact: float = 800.0
@export var stage2_rounds: int = 5
@export var stage2_energy: float = 200.0
@export var stage2_blast_radius: float = 8.0  ## 4 m dossier ×2
@export var auto_fire_time: float = 3.0      ## holding this long fires stage 2 by itself

@export_group("Beam")
@export var beam_life: float = 0.14          ## beam stays up this long (fade is the last 0.12 s)
@export var beam_core_radius: float = 0.5    ## plain shot core (review r1: 0.5 / 1.6 m)
@export var beam_glow_radius: float = 1.6
@export var stage1_core_radius: float = 1.0  ## stage 1 core / glow
@export var stage1_glow_radius: float = 3.5
@export var stage2_core_radius: float = 2.2  ## stage 2 core / glow
@export var stage2_glow_radius: float = 7.0
@export var afterglow_time: float = 0.4      ## dim heat-haze trail left along a charged beam
@export var shock_ring_radius: float = 12.0  ## stage-2 muzzle shock ring (0 -> 12 m)
@export var shock_ring_time: float = 0.12
@export var muzzle_ring_radius: float = 3.2
@export var core_color: Color = Color(0.937, 1.0, 1.0)
@export var glow_color: Color = Color(0.212, 0.886, 1.0)


## Core radius for a charge stage (0 plain, 1 / 2 charged).
func core_radius(stage: int) -> float:
	return [beam_core_radius, stage1_core_radius, stage2_core_radius][clampi(stage, 0, 2)]


func glow_radius(stage: int) -> float:
	return [beam_glow_radius, stage1_glow_radius, stage2_glow_radius][clampi(stage, 0, 2)]


## Damage multiplier at `distance` m (1.0 inside full_range, falling to falloff_mult, 0 past cut-off).
func damage_at(distance: float) -> float:
	if distance <= full_range:
		return 1.0
	if distance >= max_range:
		return 0.0
	var t := (distance - full_range) / maxf(falloff_range - full_range, 0.001)
	return lerpf(1.0, falloff_mult, clampf(t, 0.0, 1.0))
