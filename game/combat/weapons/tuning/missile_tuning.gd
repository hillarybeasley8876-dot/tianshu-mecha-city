class_name MissileTuning
extends Resource
## Hailstorm Volley numbers (skills-catalog §4.4 S3, distances/speeds ×2; times and damage unscaled).

@export_group("Painting")
@export var lock_interval: float = 0.10
@export var lock_max: int = 12
@export var lock_per_target: int = 4
@export var lock_range: float = 300.0        ## SPEC §6
@export var lock_box_h_deg: float = 24.0     ## horizontal half-extent of the paint box
@export var lock_box_v_deg: float = 16.0
@export var paint_auto_fire: float = 3.0     ## holding this long launches the salvo

@export_group("Launch")
@export var salvo_time: float = 0.5          ## 12 missiles leave over this
@export var missiles_locked: int = 12
@export var missiles_free: int = 6           ## no locks: a straight half-salvo at the aim point
@export var cooldown: float = 14.0

@export_group("Flight")
@export var bloom_time: float = 0.2
@export var bloom_speed: float = 44.0        ## 22 ×2
@export var bloom_cone_deg: float = 35.0
@export var ignite_time: float = 0.4         ## speed ramp 120 → 200 m/s
@export var speed_start: float = 120.0       ## 60 ×2
@export var speed_max: float = 200.0         ## 100 ×2
@export var turn_start_deg: float = 300.0
@export var turn_max_deg: float = 600.0
@export var turn_ramp_time: float = 0.6      ## turn rate steps up after this
@export var life: float = 6.0
@export var fuse_radius: float = 5.0         ## 2.5 ×2 proximity fuse

@export_group("Damage")
@export var damage: float = 280.0
@export var impact: float = 140.0
@export var blast_radius: float = 6.0        ## 3 ×2
@export var chaff_group: StringName = &"chaff"
@export var chaff_absorb: int = 4            ## missiles eaten per spore cloud
@export var chaff_radius: float = 14.0


## Launch interval for a full salvo (12 rounds inside salvo_time).
func salvo_interval() -> float:
	return salvo_time / float(maxi(missiles_locked, 1))
