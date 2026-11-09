class_name MechDebug
extends RefCounted
## Tool hook of `MechLocomotion` (tests, timelines, debug tools): drop every timer, flag and state so
## a scripted run starts from a known pose. Lives outside the state machine because nothing in the
## game calls it — it is the one place allowed to write the private fields wholesale.

static func reset(l: MechLocomotion) -> void:
	l._set_state(MechLocomotion.S.GROUND)
	l._dash_t = 0.0
	l._dash_iframes_t = 0.0
	l._dash_chain = 0
	l._dash_lockout = 0.0
	l._dash_cooldown = 0.0
	l._chain_idle = 0.0
	l._jump_charge = 0.0
	l._pending_jump = false
	l._jump_buffer = 0.0
	l._land_t = 0.0
	l._land_lock = 0.0
	l._land_pose = 0.0
	l._vernier = 0.0
	l._assault_ignite = 0.0
	l._skid_t = 0.0
	l.assault_on = false
	l._lock_t = 0.0
	l._lunge_t = 0.0
	l._pause_t = 0.0
	l._footstep_t = 0.0
	l._gliding = false
	l._hop_cd = 0.0
	l.coast.reset()
	l._strafe = false
	l.land_kind = &"none"
	l.step_events = 0
	l.hop_events = 0
	l.set_flying(false)
	l.move_state = &"idle"
	l.body.velocity = Vector3.ZERO
	l.energy.debug_reset()
	l.input.reset_taps()
