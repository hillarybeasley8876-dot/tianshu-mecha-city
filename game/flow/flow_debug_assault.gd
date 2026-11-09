class_name FlowDebugAssault
extends RefCounted
## The E2E bot (r3 brief item 1): fights with the player's REAL weapons — aimed beam rifle, an
## occasional skill — instead of a debug `take_hit`. It exists so a scripted run proves the whole
## damage path (aim ray → muzzle → Hurtbox → pod burst) rather than the objective bookkeeping alone.
##
## This file is the beat: what the bot is here to kill, when it looks up, and when it lets go. The
## work itself is split three ways —
##   `FlowAssaultTargets` — what it can see and where it could stand to see it,
##   `FlowAssaultMove`    — the three moves it makes when it cannot shoot,
##   `FlowAssaultAim`     — pointing the rig by hand, the trigger, the reload and the skills,
## plus `FlowAssaultLog` for the two lines a scripted run is read from.
##
## It aims the rig by hand rather than through the hard lock: `CameraLock` adds the CONTRACTS §5
## large-target pitch offset, which frames a 60 m spire and misses a 6 m pod by 1,400 m.
##
## Two modes: `start_spire` takes a Hive Spire apart (orbiting the trunk when no pod is in line of
## sight — the four pods sit on four bearings, so a player standing still can only ever shoot two of
## them), and `start_arena` clears an arena's waves. `start_boss` fights the Brood Titan.
##
## Only `FlowDebug` creates one, and only when a `--flow-script` asks for it, so nothing here runs in
## a normal session.

signal finished_beat(what: StringName)

## m: how far the lens may be from the mech before the bot stops judging line of sight (the rig's own
## arm is 42 m, so anything under this means the spring has arrived).
const CAM_SETTLED := 60.0
## How many passes (0.35 s each) the camera gets to swing onto a locked target before the bot decides
## the position is blind and moves.
const AIM_TRIES := 4
const REAIM_EVERY := 0.35
## s between the "what is the bot doing" lines in the E2E log.
const BEAT_LOG := 5.0

var _eyes: FlowAssaultTargets = null
var _hands: FlowAssaultAim = null
var _move: FlowAssaultMove = null
var _log: FlowAssaultLog = null

var _reaim_t: float = 0.0
var _had_target: bool = false
var _aimed_at: Targetable = null
var _aim_tries: int = 0
var _beat_t: float = 0.0


func _init() -> void:
	_eyes = FlowAssaultTargets.new()
	_hands = FlowAssaultAim.new()
	_move = FlowAssaultMove.new()
	_move.setup(_eyes)
	_log = FlowAssaultLog.new()
	_log.setup(_eyes, _hands)


## Take one Hive Spire apart; the beat ends when it falls.
func start_spire(target: FlowHiveSpire) -> void:
	_begin(target, &"")
	if target != null and not target.destroyed.is_connected(_on_spire_down):
		target.destroyed.connect(_on_spire_down, CONNECT_ONE_SHOT)


## Clear an arena's waves with the real rifle; the beat ends when the director calls the arena clear.
func start_arena(id: StringName) -> void:
	_begin(null, id)
	if not Events.encounter_cleared.is_connected(_on_arena_cleared):
		Events.encounter_cleared.connect(_on_arena_cleared)


## Fight the Brood Titan with the real weapons (r4 brief item 3): the cores first — they are weak
## points, so the lock and the rifle go there — then the body until the death beat ends the run. The
## beat ends when `Events.game_won` arrives, four seconds after the killing blow.
func start_boss() -> void:
	_begin(null, &"boss")
	if not Events.game_won.is_connected(_on_game_won):
		Events.game_won.connect(_on_game_won)


func _begin(target: FlowHiveSpire, arena: StringName) -> void:
	_eyes.setup(target, arena)
	_hands.reset()
	_reaim_t = 0.0


func _on_game_won() -> void:
	stop()
	finished_beat.emit(&"boss")


func _on_spire_down(_s: FlowHiveSpire) -> void:
	stop()
	finished_beat.emit(&"spire")


func _on_arena_cleared(id: StringName) -> void:
	if id != _eyes.arena_id:
		return
	stop()
	finished_beat.emit(&"arena")


## One step of the attack. Returns true when the beat is over and the bot has let go.
func tick(delta: float) -> bool:
	var spire := _eyes.spire
	if spire != null and (not is_instance_valid(spire) or not spire.alive):
		stop()
		return true
	var player := Game.player as Node3D
	if player == null:
		return false
	_reaim_t -= delta
	_move.cool(delta)
	_beat_t -= delta
	if _beat_t <= 0.0:
		_beat_t = BEAT_LOG
		_log.beat(player, _aimed_at, _hands.firing, _aim_tries)
	_hands.tick_reload(delta)
	if _reaim_t <= 0.0:
		_reaim_t = REAIM_EVERY
		_acquire(player)
	_hands.tick_skill(delta, spire != null or _eyes.arena_id == &"boss")
	return false


## The trigger pulse runs on the idle frame (see `FlowAssaultAim.tick_trigger`).
func tick_trigger(delta: float) -> void:
	_hands.tick_trigger(delta)


## Hold the lock on a live target, or close the distance until one comes into view. Enemy knockback
## walks an idle mech right out of its own arena (the rippers shove it hundreds of metres), so "no
## target in sight" has to mean "go there", not "stand here".
func _acquire(player: Node3D) -> void:
	# After a move the rig's follow spring is still crossing the map: every ray would be cast from
	# where the camera used to be, so the bot would "discover" a blocker, move again, and teleport
	# for ever without ever firing a shot.
	if FlowDebugView.eye().distance_to(player.global_position) > CAM_SETTLED:
		return
	var want := _eyes.keep_or_pick(player, _aimed_at)
	_had_target = _log.aim_change(player, want, _had_target)
	if want == null:
		_hands.release()
		_reposition(player)
		return
	# Aim by hand, every pass — see the class note. Measure FIRST, correct second: `set_look` writes
	# the rig's yaw/pitch, but the rig applies them in its own `_physics_process`, so the frame this
	# runs in still reports the old view. The counter is per POSITION, not per target: two pods
	# trading places every pass used to reset it, and a bot that never reaches four can never conclude
	# that the place it is standing in is blind.
	if _hands.view_off(want) > FlowAssaultAim.AIM_CONE_DEG:
		_hands.point_at(player, want.global_position)
	if _hands.view_off(want) > FlowAssaultAim.AIM_CONE_DEG \
			or _hands.crosshair_off(want) > FlowAssaultAim.AIM_TOLERANCE:
		_aim_tries += 1
		_aimed_at = want
		if _aim_tries >= AIM_TRIES:
			_hands.release()
			_reposition(player)
		return
	_aimed_at = want
	# The trigger gate is the SHOT, not the aim (r5 brief item 7). The bot used to fire whenever the
	# view cone was tight and the crosshair was within 30 m of the target, which is also true from
	# behind a flyover: a whole A6 beat ran at `firing=true` with three pods burst and the hive's HP
	# frozen at 475, because every round stopped on the Sky Garden deck. `lands_on` asks the gun's
	# question — does a tap from the lens reach this target's Hurtbox — and a "no" moves the bot.
	_hands.firing = _eyes.lands_on(FlowAssaultTargets.muzzle(), want)
	if _hands.firing:
		_aim_tries = 0
		return
	_aim_tries += 1
	if _aim_tries >= AIM_TRIES:
		_hands.release()
		_reposition(player)


func _reposition(player: Node3D) -> void:
	if _move.reposition(player):
		_aim_tries = 0


## Let go of the trigger and the lock — the bot never leaves the player holding fire.
func stop() -> void:
	_hands.release()
	if Events.encounter_cleared.is_connected(_on_arena_cleared):
		Events.encounter_cleared.disconnect(_on_arena_cleared)
	if Events.game_won.is_connected(_on_game_won):
		Events.game_won.disconnect(_on_game_won)
	var player := Game.player
	if player != null and player.has_method(&"aim"):
		var aim := player.call(&"aim") as Node
		if aim != null and aim.has_method(&"lock_to"):
			aim.call(&"lock_to", null)
