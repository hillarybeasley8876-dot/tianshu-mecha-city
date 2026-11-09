class_name MechDeath
extends RefCounted
## The death gate (mech-move r7). One predicate decides it all: `PlayerMech.is_alive()`, mirrored by
## `MechDamage.dead`. `enter` runs once on the killing blow, `exit` once on the revive, and
## `PlayerMech._physics_process` takes the `tick` branch in between.
##
## While the gate is closed:
##   * no state acts and no movement input is read, but gravity and `move_and_slide` keep running so
##     the wreck settles. Horizontal speed dies, though the killing blow's own knockback still carries
##     it for a moment;
##   * every state that owes an exit event leaves it (flight, boost slide, assault, dash, lunge, lock);
##   * the components PlayerMech instanced stop polling input — their own `_physics_process` is off,
##     so the pools and projectiles UNDER them (children with their own clocks) keep flying;
##   * the model is fed one neutral pose and then nothing, so the held `death` clip stays at weight 1
##     and the gait stops planting feet;
##   * no EN is spent or regenerated.


static func enter(p: PlayerMech) -> void:
	close_states(p.locomotion())
	stop_components(p)
	pose_model_dead(p)


static func exit(p: PlayerMech) -> void:
	open_states(p.locomotion())
	p.locomotion().input.swallow(MechInput.held_actions())
	pose_model_alive(p)
	# The components come back at once and `PlayerMech` mutes only the verbs that were still held
	# (r7b item 3), so a fresh press of anything else acts on the first live tick.
	p.latch_revive(MechInput.held_component_actions())


## Every physics frame the gate is closed: only the body moves.
static func tick(p: PlayerMech, delta: float) -> void:
	tick_body(p.locomotion(), delta)


# --- the body ------------------------------------------------------------------------------------

## Gravity and the brake curve, nothing else. The input is still POLLED (not acted on): the held-key
## edges have to stay current, or the key that pressed RETRY would read as a fresh press on the first
## live tick — `ui_accept` includes Space and the pad's A, which are also `jump`.
static func tick_body(l: MechLocomotion, delta: float) -> void:
	var rd := Feel.locomotion_delta(delta)
	l.rdelta = rd
	l.pdelta = Feel.player_delta(delta)
	l.input.poll(delta)
	l._on_floor = l.body.is_on_floor()
	l._timers(rd, l.pdelta)
	var brake := l.tuning.brake_rate() * rd
	l.body.velocity.x = move_toward(l.body.velocity.x, 0.0, brake)
	l.body.velocity.z = move_toward(l.body.velocity.z, 0.0, brake)
	if l._on_floor:
		l.body.velocity.y = -1.0  # keeps the floor snap alive on the ramps
	else:
		l.apply_gravity(rd)


## Close the gate on the state machine: a corpse is in no state. Every state that owes an exit event
## leaves it here (SPEC §3), so a death in flight, a boost, a dash, a lunge or a combat lock ends it.
static func close_states(l: MechLocomotion) -> void:
	l.set_flying(false)
	# The flight assault jet (SPEC §3) is a toggle on S.FLIGHT, not the S.ASSAULT state, so
	# `_set_state` below owes nothing for it: without this the camera's assault FOV and arm stay wide
	# for the rest of the run (r7b item 6). The S.ASSAULT state emits its own, so it is excluded here
	# and the bus hears exactly one `boost_ended(&"assault")` either way.
	var flight_jet := l.assault_on and l.state != MechLocomotion.S.ASSAULT
	l.assault_on = false
	l._pending_jump = false
	l._jump_buffer = 0.0
	l._jump_charge = 0.0
	l._land_t = 0.0
	l._land_lock = 0.0
	l._land_pose = 0.0
	l._lock_t = 0.0
	l._lunge_t = 0.0
	l._pause_t = 0.0
	l._gliding = false
	l._strafe = false
	# r8 item 1: a step coast that is running when the mech dies owns the body, and the death tick
	# calls `move_and_slide` rather than `coast_move` -- without this it would never expire.
	l.coast.reset()
	l._set_state(MechLocomotion.S.GROUND)  # emits boost_ended for a dash / slide / assault
	if flight_jet:
		Events.boost_ended.emit(&"assault")
	l.reset_dash_chain()
	l.move_state = &"idle"
	# Lead r7: "horizontal speed dies". A 16 m mech that drops mid-stride does not coast 1.3 m on the
	# ground brake curve, so the speed goes at the latch; the killing blow's own knockback is applied
	# after it (`MechDamage._knockback`) and is the only thing that still carries the wreck.
	l.body.velocity.x = 0.0
	l.body.velocity.z = 0.0


static func open_states(l: MechLocomotion) -> void:
	l._on_floor = l.body.is_on_floor()
	l._air_start_y = l.body.global_position.y
	l._coyote = l.tuning.coyote_time
	l._footstep_t = 0.0
	# A corpse shoved into the air (flow's `hive_collapse.gd` `_shove_hero`) revives off the floor.
	# `close_states` left the machine in S.GROUND, where a jump press only buffers and the mech waits
	# out the coyote window before it is allowed to fall (r7b item 7), so the state is read back off
	# the floor contact the revive actually has.
	l._set_state(MechLocomotion.S.AIR if not l._on_floor else MechLocomotion.S.GROUND)
	l.move_state = &"fall" if not l._on_floor else &"idle"


# --- the components ------------------------------------------------------------------------------

## The gate the lead asked for: PlayerMech owns the loader (CONTRACTS §1), so it can stop every
## component it instanced without editing a single one of their files. What it stops is only what was
## RUNNING (`MechTeardown`): ammo, heat, cooldowns, charges and the selected weapon carry over, so a
## death never hands the player a free reload. Rounds and missiles already in flight are children
## with their own clocks, so they keep flying.
static func stop_components(p: PlayerMech) -> void:
	for c in p.components():
		if not is_instance_valid(c):
			continue
		c.set_physics_process(false)
		MechTeardown.quiet(c)


static func start_components(p: PlayerMech) -> void:
	for c in p.components():
		if is_instance_valid(c):
			c.set_physics_process(true)


# --- the model -----------------------------------------------------------------------------------

## One neutral feed, then silence. `set_locomotion` is what drives the gait and the upper-body clip
## map, so without this the legs keep cycling the state the mech died in (and the gait keeps calling
## `Events.footstep`), and a `fly` / `slide` / `land_*` id would swap the held `death` clip out.
## `&"idle"` maps to no clip (hero3_model.gd `LOCO_CLIP`), so `death` is untouched.
static func pose_model_dead(p: PlayerMech) -> void:
	var m := p.model()
	if m == null or not is_instance_valid(m):
		return
	_feed(m, &"idle")
	if m.has_method(&"set_thrusters"):
		m.call(&"set_thrusters", 0.0)
	if m.has_method(&"set_wings"):
		m.call(&"set_wings", 0.0)
	if m.has_method(&"set_saber_drawn"):
		m.call(&"set_saber_drawn", false)
	p.play_model_action(&"death", MechDamage.DEATH_BLEND)


static func pose_model_alive(p: PlayerMech) -> void:
	var m := p.model()
	if m == null or not is_instance_valid(m):
		return
	if m.has_method(&"stop_action"):
		m.call(&"stop_action")
	_feed(m, &"idle")


static func _feed(m: Node3D, state: StringName) -> void:
	if m.has_method(&"set_locomotion"):
		m.call(&"set_locomotion", state, 0.0, Vector2.ZERO)
