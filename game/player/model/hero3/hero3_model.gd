extends Node3D
## HeroModel API (CONTRACTS §5) for the TIANSHU "Tianshu" hero mech: `player/model/hero3/hero3_model.tscn`.
## Origin between the feet at y = 0, 16 m to the crest, facing -Z. PlayerMech places this node 7.5 m
## below its body origin.
##
## The mesh is a set of RIGID armour plates (one bone each) exported by `blender/hero3/build_hero3.py`,
## so nothing here blends weights: `hero3_rig.gd` owns the sockets, the drones and the thrusters,
## `hero3_gait.gd` owns the procedural legs, and `hero3_clip.gd` plays the authored action clips on
## top of both.

const ACTION_BLEND := 0.08
## A local hit-stop freezes this actor's animation. Every call site that reaches the hero model makes
## the player the attacker or the parrier, so the model creeps by default (FEEL.md: 5 %).
const PAUSE_CREEP := 0.05
const PAUSE_SHAKE_HZ := 61.0
const PAUSE_SHAKE_M := 0.09
## Metres of modelled steel on `saber_r`, measured from the socket. Must match
## `blender/hero3/hero3_saber.BLADE_STEEL` and `MeleeTable.MODEL_BLADE_LENGTH`; `tests/test_hero3.gd`
## asserts all three agree, because `SaberVisual` starts its energy extension at exactly this far out.
const BLADE_STEEL := 12.0
## Move state -> the upper-body clip that goes with it. The game never calls `play_action` for any of
## these: they arrive ONLY as `set_locomotion` states, so without this the dash, the slide, the air
## poses and the landings have no upper body at all (lead r4 item 2). The LEGS for the ground states
## are the skate's business (`Hero3Skate`), which is why every one of these clips is upper-body only.
const LOCO_CLIP: Dictionary = {
	&"dash_f": &"dash_f", &"dash_b": &"dash_b", &"dash_l": &"dash_l", &"dash_r": &"dash_r",
	&"slide": &"slide",
	&"hover": &"hover", &"fly": &"fly", &"assault": &"fly", &"glide": &"fly", &"fall": &"fall",
	&"land_light": &"land_light", &"land_heavy": &"land_heavy",
}
const LOCO_BLEND := 0.12
## Clips that mean the mech is WINDING UP: the vents burn while one of these is playing (lead r7
## item 1). `charge_slash` is the melee one, `charge_r` the beam rifle's.
const CHARGE_CLIPS: Array[StringName] = [&"charge_r", &"charge_slash"]
## Where the flight lean and bank pivot, in the model's own space: the hips, 8.6 m up. Rotating about
## the feet instead would swing the head 16 m x sin(25 deg) = 6.8 m forward on every cruise.
const FLIGHT_PIVOT := Vector3(0.0, 8.6, 0.0)

var rig: Hero3Rig
var gait: Hero3Gait
var aim: Hero3Aim
var clips: Hero3ClipPlayer
## The flight pose language (lead r8 item 3): lean with speed, bank into turns, legs trailing.
var flight: Hero3Flight
var model: Node3D
var skeleton: Skeleton3D

var _state: StringName = &"idle"
var _speed: float = 0.0
var _input: Vector2 = Vector2.ZERO
var _action: StringName = &""
var _pause: float = 0.0
var _creep: float = PAUSE_CREEP
var _shake_t: float = 0.0
var _model_rest := Vector3.ZERO
var _loco_clip: StringName = &""
## True from `play_action(&"death")` until `stop_action()`. `PlayerMech` holds the death clip at 0 hp
## and clears it in `heal()`, which is the one place every revive passes through, so this latch is the
## model's own answer to "is this mech dead" -- and it is what powers the mech down and cuts the
## flight pose (lead r8, from the mech-move acceptance).
var _dying: bool = false
## `--hero3-mirror`: the r9 item 1 BEFORE baseline (see `set_locomotion`).
var _mirror: bool = false


func _ready() -> void:
	model = get_node_or_null(^"Model") as Node3D
	if model == null:
		push_error("Hero3Model: no instanced hero3.glb child named Model")
		return
	skeleton = model.get_node_or_null(^"Hero3Rig/Skeleton3D") as Skeleton3D
	if skeleton == null:
		push_error("Hero3Model: hero3.glb is missing its Skeleton3D")
		return
	_mirror = not _flag("hero3-mirror").is_empty()
	_model_rest = model.position
	skeleton.force_update_all_bone_transforms()
	gait = Hero3Gait.new()
	gait.name = "Hero3Gait"
	add_child(gait)
	gait.setup(skeleton)
	gait.footstep.connect(_on_footstep)
	Events.landed.connect(_on_landed)
	clips = Hero3ClipPlayer.new()
	clips.setup(skeleton, gait.ik)
	clips.posture = gait.posture
	clips.clips = Hero3Clips.build()
	# the gait reads the playing clip's root and foot targets, so it has to be able to see the player
	gait.clips = clips
	rig = Hero3Rig.new()
	rig.name = "Hero3Rig"
	add_child(rig)
	rig.setup(model, skeleton)
	# the rifle solver needs the barrel the rig measured off the mesh (lead r4 item 6)
	aim = Hero3Aim.new()
	aim.setup(skeleton, gait.ik)
	aim.barrel_rest = rig.rifle.get("dir", Vector3(0.0, 0.0, -1.0))
	aim.barrel_len = float(rig.rifle.get("len", 4.6))
	gait.posture.aim_solver = aim
	clips.blade_rest = rig.blade_rest
	flight = Hero3Flight.new()
	set_locomotion(&"idle", 0.0, Vector2.ZERO)



## The hero animation runs on the player clock (CONTRACTS §3 "Clocks"): full speed through witch
## time, frozen by a global hit-stop, and frozen again by this actor's own `hit_pause`.
func _physics_process(delta: float) -> void:
	if skeleton == null:
		return
	# The flight pose is measured on the RAW delta and before anything else: it reads the mech's own
	# motion, and a hit-stop must not make a flying mech look like it stopped (lead r8 item 3).
	flight.dead = _dying
	flight.sample(self, delta, _state)
	gait.set_flight(flight.blend, flight.lean)
	rig.set_thrust_dir(flight.thrust)
	rig.set_powered(powered())
	var dt := Feel.player_delta(delta)
	if _pause > 0.0:
		_pause = maxf(_pause - dt, 0.0)
		_shake_t += dt
		if _creep > 0.0:
			_place_model(Vector3.ZERO)
			# the clip clock runs FIRST: `Hero3Gait` solves the legs against the root and the foot
			# targets the clip asks for on this very frame (lead r4 item 3)
			clips.update(dt * _creep)
			gait.update(dt * _creep)
			clips.apply()
		else:
			var amp := PAUSE_SHAKE_M * clampf(_pause / 0.08, 0.0, 1.0)
			_place_model(Vector3(sin(_shake_t * PAUSE_SHAKE_HZ),
					sin(_shake_t * PAUSE_SHAKE_HZ * 1.37), 0.0) * amp)
	else:
		_place_model(Vector3.ZERO)
		clips.update(dt)
		gait.update(dt)
		clips.apply()
	rig.set_charging(CHARGE_CLIPS.has(clips.current()))
	rig.update(dt)


## Is the mech powered? A dead one is a wreck, unless `--hero3-nopower` is holding the lights on for
## the A/B capture.
func powered() -> bool:
	if not _dying:
		return true
	return rig != null and not rig.power_down_enabled()


## Place the visual under the body. The flight lean and bank are applied HERE, on the model node
## rather than on bones, because every bone write in this unit is an ABSOLUTE skeleton-space pose
## (`Hero3LegIk.set_pose`): a rotation written to the pelvis does not carry the chest, the arms or
## the back frame with it. Rotating the node is the one place that leans the whole machine, and the
## rotation is about `FLIGHT_PIVOT` -- the hips -- so a 25 deg lean does not swing the head 7 m.
func _place_model(shake: Vector3) -> void:
	var rot := Basis(Quaternion(Vector3.RIGHT, -flight.lean) * Quaternion(Vector3.BACK, flight.bank))
	model.transform = Transform3D(rot,
			FLIGHT_PIVOT - rot * FLIGHT_PIVOT + _model_rest + shake)


# --- HeroModel API ----------------------------------------------------------------------------------

## hero-v3 r5 item 7: the thud lands when a foot lands, not on a timer. `MechContact.footsteps` keeps
## its timer for a model that has no gait to report with (the placeholder).
func _on_footstep(_side: String, position: Vector3, _speed: float) -> void:
	Events.footstep.emit(position, true)
	Feel.play(&"footstep_heavy", position)


## HeroModel API extension (hero-v3 r5 item 7): the gait knows when a foot lands, so the caller must
## NOT also run a footstep timer or every step thuds twice.
func owns_footsteps() -> bool:
	return true


## Lead r5 "weight": `Events.landed` carries the impact speed, which is what scales the crouch. It
## arrives BEFORE `set_locomotion(&"land_heavy")` (MechContact.touchdown emits, then the state), so
## the profile is already sized when the gait starts the landing.
func _on_landed(impact_speed: float) -> void:
	if gait != null:
		gait.set_impact(impact_speed)


## HeroModel API extension (lead r5): the downward speed the air pose braces against. Optional --
## PlayerMech only calls it when the model offers it.
func set_fall_speed(down_speed: float) -> void:
	if gait != null:
		gait.set_fall_speed(down_speed)


func _flag(name: String) -> String:
	var loop := Engine.get_main_loop() as SceneTree
	var game: Node = loop.root.get_node_or_null("Game") if loop != null else null
	return String(game.call(&"flag", name, "")) if game != null else ""


func set_locomotion(state: StringName, speed: float, input_local: Vector2) -> void:
	_state = state
	_speed = speed
	_input = input_local
	if gait != null:
		# `--hero3-mirror` is the r9 item 1 BEFORE baseline: `mech_contact.gd` used to send the stick's
		# z negated, so the gait read every walk, run and strafe as its own mirror image. The flag
		# reproduces that in the same binary as the fix, the same discipline as `--hero3-plain`.
		gait.set_state(state, speed, Vector2(input_local.x, -input_local.y) if _mirror else input_local)
	_locomotion_clip(state)


## Play (or release) the upper-body clip that belongs to this move state. Called every tick, so it
## only acts on a CHANGE: re-firing a looping clip 60 times a second would restart its entry ramp
## every frame.
func _locomotion_clip(state: StringName) -> void:
	if clips == null:
		return
	var want: StringName = LOCO_CLIP.get(state, &"")
	if want == _loco_clip:
		return
	if _loco_clip != &"" and clips.current() == _loco_clip:
		clips.stop()
	_loco_clip = want
	if want != &"":
		play_action(want, LOCO_BLEND)


## Returns the clip length in seconds, or 0.0 when the id has no clip. The clips are authored data
## (`hero3_clips_*.gd`), not AnimationPlayer tracks: see `Hero3ClipPlayer` for why.
func play_action(id: StringName, blend: float = ACTION_BLEND) -> float:
	_action = id
	if id == &"death":
		_dying = true
	var length := clips.play(id, blend) if clips != null else 0.0
	if length <= 0.0:
		push_warning("Hero3Model: no clip for action %s" % id)
		return 0.0
	return length


func stop_action() -> void:
	_action = &""
	_dying = false
	if clips != null:
		clips.stop()


func current_action() -> StringName:
	return _action


func set_aim(point: Vector3, weight: float) -> void:
	if gait != null:
		gait.set_aim(point, weight)


func socket(socket_name: StringName) -> Node3D:
	return rig.socket(socket_name) if rig != null else null


func set_thrusters(level: float) -> void:
	if rig != null:
		rig.set_thrusters(level)


func set_wings(open: float) -> void:
	if rig != null:
		rig.set_wings(open)


## HeroModel API extension (skills r4, the Corona Fins): hide or show individual blade drones so a
## docked blade disappears while its fin is out. Bit `i` (0-based) set = `Drone_{i+1}` is deployed and
## its copy on the back is hidden; 0 shows all seven. `Drone_1..4` ride `wing_l`, `Drone_5..7` ride
## `wing_r`; `fins_max` is 6, so the lead's mapping is 3 fins a side with `Drone_1` always docked.
## The modelled cyan tip on each blade hides with it.
func set_drones_docked(mask: int) -> void:
	if rig != null:
		rig.set_drones_docked(mask)


## Read-back of the mask, so a caller can assert what the model actually did.
func drones_docked() -> int:
	return rig.drones_docked() if rig != null else 0


## One drone at a time, 0-based. `deployed` true hides its blade.
func set_drone_deployed(index: int, deployed: bool) -> void:
	if rig != null:
		rig.set_drone_deployed(index, deployed)


func drone_deployed(index: int) -> bool:
	return rig.drone_deployed(index) if rig != null else false


## Where drone `index` is mounted, in WORLD space, so a fin leaves its own blade rather than a
## station marker.
func drone_tip(index: int) -> Vector3:
	return rig.drone_tip(index) if rig != null else global_position


func set_overdrive(on: bool) -> void:
	if rig != null:
		rig.set_overdrive(on)


func set_saber_drawn(on: bool) -> void:
	if rig != null:
		rig.set_saber_drawn(on)


## The model carries its own steel on `saber_r`, so `SaberVisual` draws no second blade: it sheathes
## this one and runs an energy extension from the steel tip out to `MeleeTable.BLADE_LENGTH`
## (melee-defense, review r5 item 2). Both numbers are the Blender build's: the blade is modelled from
## the socket outward, so `blade_length()` is exactly what `hero3_saber.BLADE_STEEL` put there.
func has_own_blade() -> bool:
	return true


func blade_length() -> float:
	return BLADE_STEEL


## `creep` is the fraction of the player clock the animation keeps during the stop: the game default
## (5 %) for a landed hit or a parry, 0.0 to hold the pose dead still and vibrate the mesh.
func hit_pause(seconds: float, creep: float = PAUSE_CREEP) -> void:
	_pause = maxf(_pause, seconds)
	_creep = clampf(creep, 0.0, 1.0)


func clear_hit_pause() -> void:
	_pause = 0.0
	_creep = PAUSE_CREEP


func paused() -> bool:
	return _pause > 0.0


func model_state() -> Dictionary:
	return {"state": String(_state), "speed": _speed, "action": String(_action),
			"clips": 0 if clips == null else clips.clips.size(),
			"bones": skeleton.get_bone_count() if skeleton != null else 0,
			"dying": _dying,
			"flight": flight.report() if flight != null else {},
			"gait": gait.report() if gait != null else {},
			"rig": rig.report() if rig != null else {}}
