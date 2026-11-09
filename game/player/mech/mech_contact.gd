class_name MechContact
extends RefCounted
## Floor contact, footsteps and the model feed of `MechLocomotion` (SPEC §4). Split out of the state
## machine so `mech_locomotion.gd` stays a state machine: these all run after `move_and_slide()`, the
## only point where floor contact (and therefore landing) can be read.

## SPEC §4 landing tiers, keyed on the downward speed the move just cancelled:
## under `land_min_impact` it is a kerb, under `soft_speed` a soft landing (0.20 s), above it a hard
## one (0.38 s); `land_heavy` feel/shake only from `heavy_feel_speed` up, so a plain hop stays light.
static func touchdown(l: MechLocomotion) -> void:
	# Downward speed the move just cancelled. Never absf(): a boost vault touches down still rising,
	# and its upward speed is not an impact.
	var impact := maxf(-l._pre_vy, 0.0)
	l.body.velocity.y = 0.0
	l._gliding = false
	if _is_vault(l):
		l.land_kind = &"none"  # the jets carried it over: the boost goes on, there was no landing
		return
	l.assault_on = false  # touching down always drops the assault toggle
	l.set_flying(false)
	if impact < l.tuning.land_min_impact:
		l.land_kind = &"none"
		if l.state != MechLocomotion.S.GROUND and l.state != MechLocomotion.S.LOCKED \
				and l.state != MechLocomotion.S.LUNGE:
			l._set_state(MechLocomotion.S.GROUND)
		return
	Events.landed.emit(impact)
	var empty := l.energy.is_outage()
	var hard := impact >= l.tuning.soft_speed or empty
	l.land_kind = &"outage" if empty else (&"hard" if hard else &"soft")
	var heavy_feel := empty or impact >= l.tuning.heavy_feel_speed
	Feel.play(&"land_heavy" if heavy_feel else &"land_light", l.body.global_position)
	if l.state == MechLocomotion.S.LOCKED or l.state == MechLocomotion.S.LUNGE:
		return
	if not hard:
		l._land_lock = l.tuning.soft_cancel_from
		l._land_t = l.tuning.soft_recovery
		l.move_state = &"land_light"
	else:
		l._land_lock = 0.0 if empty else l.tuning.hard_cancel_from
		l._land_t = l.tuning.outage_recovery if empty else l.tuning.hard_recovery
		l.move_state = &"land_heavy"
	l._land_pose = l.tuning.land_pose_time
	l._set_state(MechLocomotion.S.LAND)


## A boost hop (mech_stepping.gd) is mid-flight while `_hop_cd` runs: its arc was solved for the
## boost's gravity and speed, so the touchdown on top of the obstacle is a vault, not a landing.
static func _is_vault(l: MechLocomotion) -> bool:
	return l._hop_cd > 0.0 \
			and (l.state == MechLocomotion.S.ASSAULT or l.state == MechLocomotion.S.SLIDE)


static func footsteps(l: MechLocomotion, delta: float) -> void:
	if l.state != MechLocomotion.S.GROUND or not l.body.is_on_floor():
		return
	if _model_owns_footsteps(l):
		l._footstep_t = 0.0
		return
	var s := l.flat_speed()
	if s < 1.0:
		l._footstep_t = 0.0
		return
	l._footstep_t -= delta * s / l.tuning.run_speed
	if l._footstep_t > 0.0:
		return
	l._footstep_t = l.tuning.footstep_interval(s)
	Events.footstep.emit(l.body.global_position, true)
	Feel.play(&"footstep_heavy", l.body.global_position)


## hero-v3 r5 item 7: a model with a gait reports its own touchdowns (`Hero3Gait.footstep`), so the
## timer here is only the fallback for the placeholder.
static func _model_owns_footsteps(l: MechLocomotion) -> bool:
	return l.model != null and is_instance_valid(l.model) \
			and l.model.has_method(&"owns_footsteps")


static func update_model(l: MechLocomotion) -> void:
	if l.model == null or not is_instance_valid(l.model):
		return
	var local := l.body.global_basis.inverse() * l.wish_dir()
	if l.model.has_method(&"set_locomotion"):
		# `input_local` is the stick in the MODEL's own frame, so -y is forward (CONTRACTS §5's model
		# faces -Z) -- the same convention every hero3 filmstrip and gate uses. Negating z here made
		# the gait read every walk, run, strafe and backpedal as its own mirror image: the plants
		# were laid BEHIND the mech, the heel-to-toe roll ran backwards and the lower body yawed the
		# wrong way, and at 9 m/s the planted foot ended 9.7 m behind its hip -- past the end of a
		# 6.16 m leg -- so the pelvis solve saturated at MAX_DROP and the mech skated on one foot
		# (measured: `probe_float.gd`, walk_flat sole gap p50 +0.81 m before this line).
		l.model.call(&"set_locomotion", l.move_state, l.flat_speed(), Vector2(local.x, local.z))
	if l.model.has_method(&"set_thrusters"):
		l.model.call(&"set_thrusters", thruster_level(l))
	if l.model.has_method(&"set_wings"):
		l.model.call(&"set_wings", wing_open(l))


## Thruster plume 0..1: what the legs are doing, read straight off the state.
static func thruster_level(l: MechLocomotion) -> float:
	match l.state:
		MechLocomotion.S.ASSAULT: return 1.0
		MechLocomotion.S.FLIGHT: return 0.85
		MechLocomotion.S.DASH: return 0.8
		MechLocomotion.S.SLIDE: return 0.55
		MechLocomotion.S.AIR: return 0.45 if l.move_state == &"hover" else 0.25
		MechLocomotion.S.LUNGE: return 0.6
		_: return 0.0


static func wing_open(l: MechLocomotion) -> float:
	match l.state:
		MechLocomotion.S.ASSAULT, MechLocomotion.S.FLIGHT: return 1.0
		MechLocomotion.S.SLIDE: return 0.55
		MechLocomotion.S.DASH: return 0.35
		MechLocomotion.S.AIR: return 0.45 if l._gliding else 0.2
		_: return 0.0
