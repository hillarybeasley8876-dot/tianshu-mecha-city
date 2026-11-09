class_name GatlingTuning
extends Resource
## Thunder Spindle gatling numbers (skills-catalog §4.2 P2, distances ×2).

@export_group("Fire")
@export var spin_up: float = 0.3             ## audible spin before the first round leaves
@export var spin_down: float = 0.45          ## barrel keeps spinning this long after release
@export var rounds_per_second: float = 15.0  ## 900 rpm
@export var belt: int = 240
@export var reload_time: float = 3.2
@export var muzzle_speed: float = 900.0      ## m/s (450 ×2)
@export var life: float = 1.4                ## bullets die after this, well past the cut-off

@export_group("Damage")
@export var damage: float = 52.0
@export var impact: float = 22.0
@export var full_range: float = 160.0
@export var falloff_range: float = 240.0     ## 50 % damage here
@export var falloff_mult: float = 0.5
@export var max_range: float = 350.0         ## chosen: the city's longest sightline (SPEC §5)

@export_group("Spread")
@export var spread_hip_deg: float = 2.6
@export var spread_ads_deg: float = 1.1
@export var bloom_max_deg: float = 1.2
@export var bloom_gain_deg: float = 0.9      ## per second of firing
@export var bloom_decay_deg: float = 2.4     ## per second once the trigger is off

@export_group("Heat")
@export var heat_per_shot: float = 0.85      ## 100 / 0.85 ≈ 118 rounds ≈ 7.9 s
@export var cool_rate: float = 30.0          ## per second
@export var cool_delay: float = 0.35

@export_group("Active vent")
@export var vent_sweep: float = 0.9          ## needle travel time, 0 → 1
@export var vent_mark: float = 0.72          ## where the marker sits on the sweep
@export var vent_perfect: float = 0.1        ## 6 f window, total width
@export var vent_good: float = 0.2           ## 12 f window, total width
@export var vent_good_delay: float = 0.8     ## "good" clears heat after this
@export var jam_time: float = 3.2
@export var superheated_time: float = 4.0
@export var superheated_damage: float = 1.3  ## +30 %
@export var superheated_impact: float = 1.5  ## +50 %


func damage_at(distance: float) -> float:
	if distance <= full_range:
		return 1.0
	if distance >= max_range:
		return 0.0
	var t := (distance - full_range) / maxf(falloff_range - full_range, 0.001)
	return lerpf(1.0, falloff_mult, clampf(t, 0.0, 1.0))
