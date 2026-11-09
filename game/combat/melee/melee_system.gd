class_name MeleeSystem
extends Node3D
## Melee component of the PlayerMech (CONTRACTS §5): the Dawn Edge saber (曦刃). Owns the input
## buffer, the L1→L2→L3 chain with its cancel windows, the homing lunge, the charged slash and its
## crescent wave, the air string, the Return Cut riposte after a perfect parry, the Ram Kick during
## an assault boost, and the Core Rend executions (ExecutionDirector).
##
## Frame numbers live in `MeleeTable` (skills-catalog §4.3, 60 fps frames doubled to 120 Hz ticks),
## hit detection in `BladeSweep`, feel/VFX in `MeleeStrike`, visuals in `SaberVisual`.
##
## hud_state() keys: combo_step, charging, lunge_ready, execution_available, jackpot, move, phase,
## buffered, executing, return_window, last_hit_usec, last_hit_kind.

signal move_started(move: StringName, step: int)

enum Phase { IDLE, STARTUP, ACTIVE, RECOVERY, LUNGING }

var sweep: BladeSweep = null
var saber: SaberVisual = null
var executor: ExecutionDirector = null
var strike: MeleeStrike = null
var lunge: MeleeLunge = null

var move: StringName = &""          ## the move currently running ("" = idle)
var phase: int = Phase.IDLE
var combo_step: int = 0             ## 0 = no chain running, 1..3 = the last ground step
var charge: MeleeCharge = null

var _player: Node = null
var _model: Node = null
var _aim: Node = null
var _tick: int = 0                  ## ticks elapsed in the current move
var _move_ticks: int = 0
var _startup_ticks: int = 0
var _active_ticks: int = 0
var _buffer: StringName = &""       ## buffered next move ("" = nothing buffered)
var _buffer_ticks: int = 0
var _air_step: int = 0
var _combo_idle: float = 0.0
var _air_hang: float = 0.0
var _return_left: float = 0.0       ## Return Cut window after a perfect parry
var _move_accum: float = 0.0        ## player-time owed to the move clock (CONTRACTS §3)
var _blade_left: float = 0.0        ## player-time left before the blade is stowed again


func _ready() -> void:
	sweep = BladeSweep.new()
	sweep.name = "Sweep"
	add_child(sweep)
	saber = SaberVisual.new()
	saber.name = "Saber"
	add_child(saber)
	executor = ExecutionDirector.new()
	executor.name = "Execution"
	add_child(executor)
	sweep.landed.connect(_on_landed)
	Events.parry_success.connect(_on_parry_success)
	set_physics_process(true)


## The mech instances components before its model/aim siblings are guaranteed ready, so the refs are
## refreshed every tick until they resolve (the weapon system's convention).
func _refresh() -> void:
	var p := get_parent()
	if p == null:
		return
	_player = p
	if _model == null and p.has_method(&"model"):
		_model = p.call(&"model")
		if _model != null:
			saber.attach(_model)
		executor.setup(p as Node3D, _model)
	if _aim == null and p.has_method(&"aim"):
		_aim = p.call(&"aim")
	if strike == null:
		sweep.source = p
		sweep.exclude_owner(p)
		strike = MeleeStrike.new(p, _aim, sweep)
		lunge = MeleeLunge.new(p, strike)
		charge = MeleeCharge.new()


## The blade only exists while melee is active (lead note): it ignites on the first melee input and
## is stowed 0.6 s after the last melee action, with the model's own hilt riding the hip until then.
func _blade_life(delta: float) -> void:
	if move != &"" or executor.active or charge.charging:
		_blade_left = MeleeTable.BLADE_STOW
	else:
		_blade_left = maxf(_blade_left - delta, 0.0)
	var drawn := _blade_left > 0.0
	saber.set_lit(drawn)
	if _model != null and is_instance_valid(_model) and _model.has_method(&"set_saber_drawn"):
		_model.call(&"set_saber_drawn", drawn)


func _physics_process(delta: float) -> void:
	_refresh()
	if _player == null:
		return
	if strike.aim == null and _aim != null:
		strike.aim = _aim
	saber.global_transform = Transform3D(strike.facing(), strike.pivot())
	_blade_life(Feel.player_delta(delta))
	var frozen := _frozen()
	if not frozen:
		_timers(Feel.player_delta(delta))
	if executor.active:
		return
	## Input is real time, so a press during the stop still buffers; only the move clock holds.
	_poll_input()
	if not frozen:
		_advance(Feel.player_delta(delta))


## A LOCAL hit-stop on the player (`hit_pause`, CONTRACTS §4) freezes the mech's own motion and its
## AnimationTree, but it is not Feel's global stop, so `Feel.player_delta` still runs at full speed.
## Without this the saber keeps sweeping while the arm creeps at 5 % — the blade leaves the hand.
func _frozen() -> bool:
	return _model != null and is_instance_valid(_model) and _model.has_method(&"paused") \
			and bool(_model.call(&"paused"))


# --- timers -------------------------------------------------------------------------------------

## Every timer here is player-side (CONTRACTS §3 `Feel.player_delta`): the string, the riposte window
## and the air hang all freeze in a global hit-stop — that freeze is the impact — and run at full
## speed through witch time. The 6-frame input buffer is counted in physics ticks, which are already
## real time, so it needs no scaling.
func _timers(delta: float) -> void:
	## The chain expires once, when the idle timer runs out — not on every idle tick, or a press on
	## the same frame would lose the step it just set.
	var was := _combo_idle
	_combo_idle = maxf(_combo_idle - delta, 0.0)
	if was > 0.0 and _combo_idle <= 0.0 and phase == Phase.IDLE:
		combo_step = 0
		_air_step = 0
	_return_left = maxf(_return_left - delta, 0.0)
	_hang(delta)
	if _buffer_ticks > 0:
		_buffer_ticks -= 1
		if _buffer_ticks <= 0:
			_buffer = &""


## skills-catalog §4.3: an air swing buys a 0.3 s hover-hang, so the string does not sink.
func _hang(delta: float) -> void:
	if _air_hang <= 0.0:
		return
	_air_hang = maxf(_air_hang - delta, 0.0)
	if _player is CharacterBody3D and not _airborne():
		return
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity.y = \
				maxf((_player as CharacterBody3D).velocity.y, -1.0)


# --- input --------------------------------------------------------------------------------------

## The melee button: a press picks a move, a hold charges (MeleeCharge owns the hold state).
func _poll_input() -> void:
	match charge.poll(phase == Phase.IDLE or _in_cancel_window()):
		MeleeCharge.Edge.PRESSED:
			_on_press()
		MeleeCharge.Edge.RELEASED_CHARGED:
			_begin(MeleeTable.CHARGE_SLASH)
		_:
			pass


## A press picks, in order: an execution, the Return Cut, the Ram Kick, a lunge, the air/ground
## chain. When a move is already running the press goes into the 6-frame buffer.
func _on_press() -> void:
	if _try_execution():
		return
	var pick := _pick_move()
	if pick == &"":
		return
	if phase == Phase.IDLE or _in_cancel_window():
		_begin(pick)
	else:
		_buffer = pick
		_buffer_ticks = MeleeTable.ticks(MeleeTable.BUFFER_FRAMES)


## Public accessors answer with the idle-mech value until `_refresh()` has built their part: the
## HUD polls from `_process` (CONTRACTS §5) and can reach a component that entered the tree mid-frame,
## before its first physics tick. Same rule as `last_hit_usec` / `reset` below.
func charge_ratio() -> float:
	return charge.ratio() if charge != null else 0.0


# --- move selection -----------------------------------------------------------------------------

## Order of preference (skills-catalog §4.3 / §4.6 / §4.7): Core Rend on a staggered enemy, then the
## Return Cut after a perfect parry, then the Ram Kick during an assault boost, then a lunge on a
## hard-locked target inside 24–80 m, then the ground or air chain.
func _pick_move() -> StringName:
	if _return_left > 0.0:
		return MeleeTable.RETURN_CUT
	if _assaulting():
		return MeleeTable.RAM_KICK
	if lunge_ready():
		return MeleeTable.LUNGE
	if _airborne():
		return MeleeTable.AIR_CHAIN[mini(_air_step, MeleeTable.AIR_CHAIN.size() - 1)]
	return MeleeTable.GROUND_CHAIN[combo_step % MeleeTable.GROUND_CHAIN.size()]


func _try_execution() -> bool:
	var victim := _execution_target()
	if victim == null or not executor.start(victim):
		return false
	_finish_move()
	combo_step = 0
	return true


## The staggered enemy in front that the melee press would execute (`enemy.is_executable` already
## enforces 14 m and ±60°, CONTRACTS §6).
func _execution_target() -> Node:
	if executor == null or executor.active or _aim == null:
		return null
	if _aim.has_method(&"hard_target") and executor.available(_aim.call(&"hard_target")):
		return _aim.call(&"hard_target") as Node
	if _aim.has_method(&"soft_target") and executor.available(_aim.call(&"soft_target")):
		return _aim.call(&"soft_target") as Node
	return null


func execution_available() -> bool:
	return _execution_target() != null


## skills-catalog §4.3: the lunge gate and its homing travel live in MeleeLunge.
func lunge_ready() -> bool:
	return lunge.ready() if lunge != null else false


# --- the move state machine ---------------------------------------------------------------------

func _begin(id: StringName) -> void:
	if not MeleeTable.has_move(id) or _player == null:
		return
	if id == MeleeTable.LUNGE and not _player.call(&"consume_energy", MeleeTable.LUNGE_EN):
		return
	move = id
	phase = Phase.STARTUP
	_tick = 0
	_move_accum = 0.0
	_startup_ticks = MeleeTable.ticks(MeleeTable.field(id, "startup"))
	_active_ticks = maxi(MeleeTable.ticks(MeleeTable.field(id, "active")), 1)
	_move_ticks = maxi(MeleeTable.ticks(MeleeTable.total_frames(id)), 1)
	_buffer = &""
	_buffer_ticks = 0
	_combo_idle = MeleeTable.COMBO_RESET
	_advance_chain(id)
	if _model != null and _model.has_method(&"play_action"):
		_model.call(&"play_action", id, 0.06)
	if id == MeleeTable.LUNGE:
		phase = Phase.LUNGING
		lunge.begin()
	var step_in := MeleeTable.field(id, "step_in")
	if step_in > 0.0:
		lunge.step_in(step_in)
	if _airborne():
		_air_hang = MeleeTable.AIR_HANG
	Events.melee_swing.emit(id, _step_of(id))
	move_started.emit(id, _step_of(id))


## The chain counter advances only through the ground and air strings; one-off moves reset it.
func _advance_chain(id: StringName) -> void:
	if MeleeTable.GROUND_CHAIN.has(id):
		combo_step = MeleeTable.GROUND_CHAIN.find(id) + 1
		_air_step = 0
	elif MeleeTable.AIR_CHAIN.has(id):
		_air_step = (MeleeTable.AIR_CHAIN.find(id) + 1) % MeleeTable.AIR_CHAIN.size()
		combo_step = 0


func _step_of(id: StringName) -> int:
	if MeleeTable.GROUND_CHAIN.has(id):
		return MeleeTable.GROUND_CHAIN.find(id) + 1
	if MeleeTable.AIR_CHAIN.has(id):
		return MeleeTable.AIR_CHAIN.find(id) + 1
	return 1


## The frame data is 120 Hz ticks of PLAYER time: at time scale 1 one tick is owed per physics tick,
## a global hit-stop withholds them (the swing freezes mid-arc) and witch time owes them at full rate.
func _advance(delta: float) -> void:
	if phase == Phase.IDLE:
		_try_buffer()
		return
	_move_accum += delta * MeleeTable.PHYSICS_HZ
	var steps := 0
	while _move_accum >= 1.0 and steps < 8:
		_move_accum -= 1.0
		steps += 1
		_step_move()
		if phase == Phase.IDLE:
			return


func _step_move() -> void:
	_tick += 1
	## A press buffered before the window opens fires the moment it does (SPEC §3 input buffer).
	if _buffer != &"" and _in_cancel_window():
		_try_buffer()
		return
	## The lunge must keep re-issuing `lunge_to` for its whole travel, not just its startup: the
	## mech-move contract restarts the lunge timer on every call, so stopping early leaves the mech
	## coasting for the last `time_left` and falling short of a 70 m target.
	if move == MeleeTable.LUNGE and phase != Phase.RECOVERY:
		lunge.advance(1.0 / MeleeTable.PHYSICS_HZ)
	if _tick == _startup_ticks:
		phase = Phase.ACTIVE
		sweep.begin(strike.damage_scale(move))
		saber.set_swinging(true)
		if MeleeTable.flag(move, "wave"):
			strike.spawn_wave(_wave_host())
	if phase == Phase.ACTIVE:
		strike.sample(move, _tick, _startup_ticks, _active_ticks)
	if _tick == _startup_ticks + _active_ticks:
		phase = Phase.RECOVERY
		sweep.end()
		## The trail stops sampling here and fades out on its own clock; the blade stays in the hand.
		saber.set_swinging(false)
	if _tick >= _move_ticks:
		_finish_move()
		_try_buffer()


func _finish_move() -> void:
	move = &""
	phase = Phase.IDLE
	_tick = 0
	_move_accum = 0.0
	lunge.clear()


## The crescent is parented to the scene so it survives the mech; the component is the fallback.
func _wave_host() -> Node:
	var scene := get_tree().current_scene if is_inside_tree() else null
	return scene if scene != null else self

## A buffered press fires as soon as the running move reaches its cancel window (or ends).
func _try_buffer() -> void:
	if _buffer == &"":
		return
	var pick := _buffer
	_buffer = &""
	_buffer_ticks = 0
	if pick == MeleeTable.LUNGE and not lunge_ready():
		pick = _pick_move()
	_begin(pick)


## skills-catalog §4.3 cancel windows, expressed in 60 fps frames from the start of the move.
func _in_cancel_window() -> bool:
	if move == &"" or not MeleeTable.flag(move, "cancel_move"):
		return false
	var frame := float(_tick) * MeleeTable.REF_FPS / MeleeTable.PHYSICS_HZ + 1.0
	return frame >= MeleeTable.field(move, "cancel_from") \
			and frame <= MeleeTable.field(move, "cancel_to")


func cancel_open() -> bool:
	return _in_cancel_window()


# --- events and state ---------------------------------------------------------------------------

func _on_landed(hit: HitInfo, receiver: Node) -> void:
	strike.on_landed(move, hit, receiver)


## skills-catalog §4.3: a perfect parry opens the Return Cut window (0.8 s).
func _on_parry_success(_hit: HitInfo, _attacker: Node) -> void:
	_return_left = MeleeTable.RETURN_WINDOW


func last_hit_usec() -> int:
	return strike.last_hit_usec if strike != null else 0


func last_hit_kind() -> StringName:
	return strike.last_hit_kind if strike != null else &""


func _energy() -> float:
	var v: Variant = _player.get(&"energy")
	return float(v) if v is float or v is int else 0.0


func _assaulting() -> bool:
	if not _player.has_method(&"move_state"):
		return false
	return String(_player.call(&"move_state")) == "assault"


func _airborne() -> bool:
	if not _player.has_method(&"is_grounded"):
		return false
	return not bool(_player.call(&"is_grounded"))


# --- HUD ----------------------------------------------------------------------------------------

func hud_state() -> Dictionary:
	return {
		"combo_step": combo_step,
		"charging": charge_ratio(),
		"lunge_ready": lunge_ready(),
		"execution_available": execution_available(),
		"jackpot": executor.jackpot if executor != null else false,
		"move": String(move),
		"phase": Phase.keys()[phase],
		"buffered": String(_buffer),
		"executing": executor.active if executor != null else false,
		"return_window": _return_left,
		"last_hit_usec": last_hit_usec(),
		"last_hit_kind": String(last_hit_kind()),
	}


func reset() -> void:
	move = &""
	phase = Phase.IDLE
	combo_step = 0
	_air_step = 0
	if charge != null:
		charge.reset()
	_buffer = &""
	_buffer_ticks = 0
	_combo_idle = 0.0
	_air_hang = 0.0
	_return_left = 0.0
	if lunge != null:
		lunge.clear()
	_tick = 0
	_move_accum = 0.0
	_blade_left = 0.0
	saber.set_lit(false)
	saber.clear_swing()
	if executor != null:
		executor.cancel()
		executor.clear_jackpot()
