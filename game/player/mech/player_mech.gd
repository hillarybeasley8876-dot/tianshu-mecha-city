class_name PlayerMech
extends CharacterBody3D
## The player's 16 m mech: root of every combat component (CONTRACTS §5). Locomotion lives in
## `MechLocomotion`, EN/OD in `MechEnergy`, the damage pipeline and the death latch in `MechDamage`,
## what that latch stops in `MechDeath`, the scene graph in `MechBuild`, and the frame numbers in
## `MechTuning`; this file owns the physics frame and the public API other units call.
##
## Public API (CONTRACTS §5): velocity, is_grounded/is_flying/is_boosting/move_state, move_input,
## facing, energy/energy_max/consume_energy/add_energy, hp/hp_max/heal, lunge_to, apply_impulse,
## lock_movement, set_strafe_aim, invulnerable_for, is_invulnerable, add_damage_filter, can_cancel,
## model, aim, telemetry, debug_teleport, take_hit, is_alive, get_team, hit_pause.
##
## `is_alive()` is the SINGLE "dead" predicate (r16 B3): skills and every other component ask that one
## method, and `MechDamage.dead` is only its cached mirror.
##
## hud_state() keys: hp, hp_max, en, en_max, od, od_max, overdrive_active, outage, state, speed, alive.

## FEEL.md local hit-stop: the victim is still, the attacker keeps creeping at 5 % of its speed.
const FROZEN_CREEP := 0.05
## HeroModel aim feed (hero-v3 r5 item 2): the rifle comes UP fast and comes DOWN slowly, and it stays
## up this long after the last shot so a burst does not make the arm pump.
const AIM_RISE := 0.10
const AIM_FALL := 0.45
const AIM_HOLD := 0.55
## A knockback at least this strong (m/s of impulse) knocks the mech off its feet.
const KNOCKDOWN_IMPULSE := 18.0
## Optional component scenes, instanced in this order (CONTRACTS §5); missing ones are skipped.
const COMPONENTS: PackedStringArray = [
	"res://player/aim/aim_system.tscn",
	"res://combat/weapons/weapon_system.tscn",
	"res://combat/melee/melee_system.tscn",
	"res://combat/defense/defense_system.tscn",
	"res://combat/skills/skill_system.tscn",
]

var tuning: MechTuning
var hp: float = 10000.0
var hp_max: float = 10000.0

var _en: MechEnergy
var _loco: MechLocomotion
var _dmg: MechDamage
var _model: Node3D
var _aim: Node
var _weapons: Node
var _components: Array[Node] = []
var _aim_w: float = 0.0
var _aim_hold: float = 0.0
## r7b item 3: the component-facing actions still held when the death gate re-opened. Each one reads
## as RELEASED to the components, which poll `Input` themselves and cannot be edited from here, and
## `Input.action_release` is the only per-action handle the loader has. Only the verbs that were held
## are muted, so a fresh press of anything else acts on the very first live tick.
var _revive_held: PackedStringArray = []
var _cam_checked: bool = false

## EN gauge (SPEC §4). Proxied to MechEnergy so components can read and write one number.
var energy: float:
	get: return _en.energy if _en != null else 0.0
	set(v): if _en != null: _en.energy = clampf(v, 0.0, _en.energy_max)
var energy_max: float:
	get: return _en.energy_max if _en != null else 0.0
## Overdrive meter 0..100 (skills-catalog §4.1).
var overdrive: float:
	get: return _en.overdrive if _en != null else 0.0


func _ready() -> void:
	add_to_group(&"player")
	tuning = MechBuild.load_tuning()
	_en = MechEnergy.new(tuning)
	hp_max = tuning.hp_max
	hp = hp_max
	MechBuild.build_body(self, tuning)
	global_transform = Game.spawn_transform(MechBuild.spawn_fallback(Game.world, tuning))
	_loco = MechLocomotion.new()
	_loco.name = "Locomotion"
	add_child(_loco)
	_dmg = MechDamage.new()
	_dmg.name = "Damage"
	add_child(_dmg)
	_dmg.setup(self, tuning, _loco)
	_model = MechBuild.instance_model(self)
	_loco.setup(self, tuning, _en, _model)
	Game.register_player(self)
	MechBuild.build_hurtboxes(self, tuning)
	MechBuild.load_components(self, COMPONENTS)
	Events.weapon_fired.connect(_on_weapon_fired)


func _physics_process(delta: float) -> void:
	if not _cam_checked:
		_cam_checked = true
		MechBuild.ensure_debug_camera(self)
	_dmg.sync()  # one predicate: `is_alive()`; this keeps the latch on the same side of it
	var pd := Feel.player_delta(delta)  # CONTRACTS §3: player timers, EN/OD, i-frames
	if _dmg.dead:
		# The death gate: gravity and the body keep running so the wreck settles, and nothing else
		# does. No state acts, no component polls input, no EN moves and the model holds `death`.
		MechDeath.tick(self, delta)
		_move()
		_feed_model(pd)
		return
	_tick_revive_latch()
	_dmg.tick(pd)
	_en.tick(pd, is_on_floor(), _loco.flying)
	_loco.tick(delta)
	if _loco.is_frozen():
		# Local hit-stop (CONTRACTS §4 / FEEL.md): the state handlers are not running, so the body only
		# creeps at 5 % and the velocity waits for them. Contacts are still read in post_move().
		var held := velocity
		velocity = held * Feel.real_delta(1.0) * FROZEN_CREEP
		move_and_slide()
		velocity = held
	elif _loco.coasting():
		_loco.coast_move()  # r8 item 1: the step-up coast owns the body until it is on the kerb
	else:
		_move()
	_loco.post_move(delta)
	_feed_model(pd)


## CONTRACTS §3: move_and_slide integrates with the SCALED delta, so the velocity is scaled by
## 1 / time_scale around it -- witch time and global hit-stops slow the world, never the mech.
func _move() -> void:
	var k := Feel.real_delta(1.0)
	velocity *= k
	move_and_slide()
	velocity /= k


## r16 B8 / r7b item 3: keep the verbs the player never let go of across the death page muted, and let
## go of each one the moment its device does. This runs in the parent's `_physics_process`, so the
## mute lands BEFORE the components (its children) poll in the same tick -- and re-applying it every
## tick is what stops a key repeat from sneaking a held trigger back in on the next event.
func _tick_revive_latch() -> void:
	if _revive_held.is_empty():
		return
	var still: PackedStringArray = []
	for a in _revive_held:
		if not _device_down(a):
			continue
		still.append(a)
		Input.action_release(a)
	_revive_held = still


## True while any device event bound to `action` is still physically down. An action with no InputMap
## event -- the pad-only `lock_prev` / `lock_next`, which `core/pad_input.gd` drives through
## `Input.action_press` -- cannot be asked, and nothing can repeat it either, so it drops out at once:
## the mute applied on the revive tick stands until the pad sends a new press.
func _device_down(action: String) -> bool:
	for ev in InputMap.action_get_events(StringName(action)):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			if k.physical_keycode != KEY_NONE and Input.is_physical_key_pressed(k.physical_keycode):
				return true
			if k.keycode != KEY_NONE and Input.is_key_pressed(k.keycode):
				return true
		elif ev is InputEventMouseButton:
			if Input.is_mouse_button_pressed((ev as InputEventMouseButton).button_index):
				return true
		elif ev is InputEventJoypadButton:
			var j := ev as InputEventJoypadButton
			if Input.is_joy_button_pressed(j.device, j.button_index):
				return true
	return false


## hero-v3 r5 items 2 + "weight": every physics frame the model is told where the crosshair is, how
## much the upper body should follow it, and how fast it is falling. `ctx.ads` is the aim button,
## `weapon_fired` keeps the rifle up for a beat after a burst, and the fall is slow so the arm lowers
## instead of dropping. A corpse is fed weight 0, so the arm comes down and stays down.
func _feed_model(player_dt: float) -> void:
	if _model == null or not is_instance_valid(_model):
		return
	_loco.apply_step_lag()  # r8 item 1: hold the gait's ground plane on the surface the feet are on
	if _model.has_method(&"set_fall_speed"):
		_model.call(&"set_fall_speed", -velocity.y)
	if not _model.has_method(&"set_aim"):
		return
	var ctx: Variant = null if _weapons == null else _weapons.get(&"ctx")
	if ctx == null or _aim == null:
		return
	var held: bool = not _dmg.dead and (bool(ctx.get(&"ads")) or _aim_hold > 0.0)
	_aim_hold = maxf(_aim_hold - player_dt, 0.0)
	var rate := AIM_RISE if held else AIM_FALL
	_aim_w = move_toward(_aim_w, 1.0 if held else 0.0, player_dt / rate)
	_model.call(&"set_aim", ctx.call(&"aim_point"), _aim_w)


func _on_weapon_fired(_id: StringName, _muzzle: Vector3, _dir: Vector3) -> void:
	_aim_hold = AIM_HOLD


# --- handles the other mech modules and the tests use ---------------------------------------------

func locomotion() -> MechLocomotion:
	return _loco


func damage() -> MechDamage:
	return _dmg


## Every component this mech instanced, in CONTRACTS §5 order. The death gate stops them all without
## editing a single one of their files (CONTRACTS §1: the loader is ours).
func components() -> Array[Node]:
	return _components


func play_model_action(id: StringName, blend: float = 0.06) -> void:
	if _model != null and is_instance_valid(_model) and _model.has_method(&"play_action"):
		_model.call(&"play_action", id, blend)


## r16 B8: `MechDeath` hands over whatever was held at the revive. Every component comes back at once
## and the verbs that were held read as released until they really are (see `_tick_revive_latch`).
func latch_revive(held: PackedStringArray) -> void:
	_revive_held = held
	_aim_w = 0.0
	_aim_hold = 0.0
	MechDeath.start_components(self)
	for a in held:
		Input.action_release(a)


# --- contract API (CONTRACTS §5) -----------------------------------------------------------------

func is_grounded() -> bool:
	return is_on_floor()


func is_flying() -> bool:
	return _loco.flying


func is_boosting() -> bool:
	return _loco.is_boosting()


func move_state() -> StringName:
	return _loco.move_state


func move_input() -> Vector2:
	return _loco.input.move


func facing() -> Basis:
	return global_basis


func consume_energy(amount: float) -> bool:
	return _en.consume(amount)


## Per-frame cost for continuous drains (ascend, guard): returns false the moment EN hits 0.
func drain_energy(amount: float, big_move: bool = false) -> bool:
	return _en.drain(amount, big_move)


func add_energy(amount: float) -> void:
	_en.add_energy(amount)


func add_overdrive(pct: float) -> void:
	var bonus := tuning.od_low_hp_bonus if hp < hp_max * tuning.od_low_hp else 1.0
	_en.add_overdrive(pct * bonus)


func set_overdrive_active(on: bool) -> void:
	_en.set_overdrive_active(on)


func heal(amount: float) -> void:
	_dmg.heal(amount)


func lunge_to(point: Vector3, speed: float, max_time: float) -> void:
	_loco.lunge_to(point, speed, max_time)


func apply_impulse(v: Vector3) -> void:
	_loco.apply_impulse(v)


func lock_movement(seconds: float, allow_turn: bool = false) -> void:
	_loco.lock_movement(seconds, allow_turn)


func set_strafe_aim(on: bool) -> void:
	_loco.set_strafe_aim(on)


func invulnerable_for(seconds: float) -> void:
	_dmg.invulnerable_for(seconds)


func is_invulnerable() -> bool:
	return _dmg.is_invulnerable()


## `func(hit: HitInfo) -> bool`; true means the hit was consumed (block, parry, barrier).
func add_damage_filter(f: Callable) -> void:
	_dmg.add_filter(f)


func remove_damage_filter(f: Callable) -> void:
	_dmg.remove_filter(f)


## May the mech start another action now? `&"dash"` asks specifically for the dodge. A corpse can
## cancel nothing (mech-move r7).
func can_cancel(tag: StringName = &"any") -> bool:
	return is_alive() and _loco.can_cancel(tag)


func model() -> Node3D:
	return _model


func aim() -> Node:
	return _aim


## The one "dead" predicate (r16 B3). Everything else mirrors it.
func is_alive() -> bool:
	return hp > 0.0


func get_team() -> int:
	return 0


func take_hit(hit: HitInfo) -> void:
	_dmg.take_hit(hit)


## CONTRACTS §4: a local hit-stop freezes the mech's own motion AND its animation, so the model gets
## it too — its AnimationTree runs in MANUAL mode for exactly this (hero_model.gd).
func hit_pause(seconds: float) -> void:
	_loco.hit_pause(seconds)
	if _model != null and is_instance_valid(_model) and _model.has_method(&"hit_pause"):
		_model.call(&"hit_pause", seconds)


## Rift Step (CONTRACTS §5) spends the dash chain itself; this hands it back.
func reset_dash_chain() -> void:
	_loco.reset_dash_chain()


func telemetry() -> Dictionary:
	return {
		"state": String(_loco.move_state),
		"speed": Vector2(velocity.x, velocity.z).length(),
		"vx": velocity.x, "vy": velocity.y, "vz": velocity.z,
		"x": global_position.x, "y": global_position.y, "z": global_position.z,
		"en": energy, "od": overdrive, "hp": hp,
		"grounded": is_on_floor(), "flying": _loco.flying, "boosting": _loco.is_boosting(),
		"invuln": is_invulnerable(), "dash_chain": _loco.dash_chain(),
		"assault": _loco.assault_on,
		"land_kind": String(_loco.land_kind), "step_events": _loco.step_events,
		"hop_events": _loco.hop_events,
	}


func hud_state() -> Dictionary:
	return {
		"hp": hp, "hp_max": hp_max, "en": energy, "en_max": energy_max,
		"od": overdrive, "od_max": tuning.od_max, "overdrive_active": _en.overdrive_active,
		"outage": _en.is_outage(), "state": String(_loco.move_state),
		"speed": Vector2(velocity.x, velocity.z).length(), "alive": is_alive(),
	}


func debug_teleport(pos: Array, yaw_deg: float = 0.0) -> void:
	if pos.size() < 3:
		push_error("PlayerMech.debug_teleport needs [x, y, z]")
		return
	velocity = Vector3.ZERO
	global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	rotation.y = deg_to_rad(yaw_deg)


## Capture affordance: play a HeroModel action from a drive timeline, which can only call methods on
## the player. `tools/godot.sh drive --timeline=...` uses it to film a clip the game only reaches
## through a window that is 167 ms wide (the perfect parry).
func debug_model_action(id: String) -> void:
	play_model_action(StringName(id), 0.04)


## Capture affordance (trailer unit): fire the perfect-dodge beat through the same function a real
## dodge uses. A scripted take cannot reliably land an enemy attack inside the dash i-frames, and this
## changes no gameplay number: it only supplies the hit that `_perfect_dodge` would have eaten.
func debug_perfect_dodge() -> void:
	_dmg.debug_perfect_dodge()
