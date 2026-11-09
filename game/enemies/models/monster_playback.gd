class_name MonsterPlayback
extends RefCounted
## Which clip a HUSK monster is playing, and how fast (monster-assets): the clip table resolved from
## `<type>_rig.json` against the GLB's animation library, the gait ladder that picks a locomotion
## loop by real ground speed, the playback scale that keeps the planted foot from sliding, the
## one-shot action hold, and the local hit-stop.
##
## Split out of `monster_model.gd` (lead split r1). Everything it knows comes from the rig data —
## no clip name, stride or speed is hard-coded here.

## Blend time into a locomotion state, and into a one-shot action (FEEL: answers within 2 frames).
const LOCOMOTION_BLEND := 0.18
const ACTION_BLEND := 0.08
## Fallback clip length when a caller asks for an action this type does not have.
const MISSING_ACTION := 0.5
## A clip whose stride speed is unknown falls back to this before the playback scale is clamped.
const FALLBACK_STRIDE := 8.0
const MIN_SPEED_SCALE := 0.6
const MAX_SPEED_SCALE := 2.2
## The most a clip may ever be sped up, whatever a rig asks for: past this a leg cycle stops
## reading as legs. The build clamps its own per-type ceiling to the same number.
const MAX_SPEED_SCALE_LIMIT := 4.0
## The slowest a clip may be played, whatever a rig asks for. A 60 m titan patrolling at 4.9 m/s
## needs its 17.5 m/s walk at 0.28x; nothing goes slower than this.
const MIN_SPEED_SCALE_LIMIT := 0.25

## Names the enemies unit uses that map onto a different clip id on some types.
const ALIASES: Dictionary = {
	&"attack": &"bite", &"attack_1": &"slash_1", &"attack_2": &"slash_2", &"attack_3": &"slash_3",
	&"lob": &"fire", &"slam": &"ground_slam", &"sidestep": &"sidestep_l", &"chaff": &"fire",
}

## One warning per type and action id: an attack loop asks every swing, and a log flood hides real
## errors.
static var _missing_warned: Dictionary = {}

var clips: Dictionary = {}

var _animation: AnimationPlayer
var _body_type: StringName = &""
var _locomotion: Dictionary = {}
var _gait: Dictionary = {}
var _actions: Dictionary = {}
var _stride: Dictionary = {}
var _state: StringName = &"idle"
var _speed: float = 0.0
var _pause_left: float = 0.0
var _speed_scale: float = 1.0
var _max_scale: float = MAX_SPEED_SCALE
var _min_scale: float = MIN_SPEED_SCALE
## Seconds of one-shot action still owed to the caller. EnemyBase re-asserts a locomotion state
## every physics tick, so without this hold an attack is cross-faded back to idle one tick after
## `play_action` starts it (lead audit 1).
var _action_left: float = 0.0


## Resolve the rig's clip table against the GLB's animation library and set the loop flags.
func setup(animation: AnimationPlayer, rig: Dictionary, body_type: StringName) -> void:
	_animation = animation
	_body_type = body_type
	if animation == null:
		push_warning("MonsterModel(%s): no AnimationPlayer in the GLB — actions will be inert"
				% body_type)
		return
	_locomotion = rig.get("locomotion", {}) as Dictionary
	_gait = rig.get("gait", {}) as Dictionary
	_actions = rig.get("actions", {}) as Dictionary
	_max_scale = clampf(float(rig.get("speed_scale_max", MAX_SPEED_SCALE)), MIN_SPEED_SCALE,
			MAX_SPEED_SCALE_LIMIT)
	_min_scale = clampf(float(rig.get("speed_scale_min", MIN_SPEED_SCALE)),
			MIN_SPEED_SCALE_LIMIT, _max_scale)
	_stride = rig.get("stride_speed", {}) as Dictionary
	var declared := rig.get("clips", {}) as Dictionary
	var library := animation.get_animation_list()
	var resolved := {}
	for clip_id: String in declared:
		var matched := _match_library_name(clip_id, library)
		if matched == &"":
			push_warning("MonsterModel(%s): clip '%s' is in the rig data but not in the GLB"
					% [body_type, clip_id])
			continue
		var loop := bool((declared[clip_id] as Dictionary).get("loop", false))
		resolved[clip_id] = {"name": String(matched), "loop": loop,
				"length": float((declared[clip_id] as Dictionary).get("length", 1.0))}
		if loop:
			var clip := animation.get_animation(matched)
			if clip != null:
				clip.loop_mode = Animation.LOOP_LINEAR
	clips = resolved


## glTF clip names survive the import, but Godot may prefix or sanitise them; match exactly first,
## then on the tail after the last separator.
func _match_library_name(clip_id: String, library: PackedStringArray) -> StringName:
	for entry in library:
		if entry == clip_id or entry.get_file() == clip_id:
			return StringName(entry)
	for entry in library:
		if entry.contains(clip_id):
			return StringName(entry)
	return &""


# --- locomotion ----------------------------------------------------------------------------------

## Drive the locomotion loop. `state` is EnemyBase's move state (idle / walk / run / stagger / ...);
## the rig data maps it onto this type's clip. Playback speed follows the real ground speed so the
## feet do not slide when the AI walks slower than the clip was authored for.
func set_locomotion(state: StringName, speed: float) -> void:
	_state = state
	_speed = speed
	apply_state()


## The gait ladder picks the clip by real ground speed (lead r3): of the rungs that can be played
## without the planted foot sliding, the one whose authored stride is nearest the speed the body is
## really moving — so a ripper at 7 m/s scuttles at 1x instead of trotting at 2.8x, and the same
## ripper chasing at 30 m/s still scuttles, just faster. Without a ladder the old one-clip-per-state
## map applies.
func current_locomotion_clip() -> String:
	# a state the ladder does not cover (the gallery's "attack", anything a caller invents) is not
	# an error: casting that null to Array is, so the type is checked before the cast
	var found: Variant = _gait.get(String(_state))
	var rungs: Array = found as Array if found is Array else []
	if rungs.is_empty():
		var fallback := String(_locomotion.get(String(_state), _locomotion.get("idle", "idle")))
		return fallback if clips.has(fallback) else String(_locomotion.get("idle", ""))
	var best := ""
	var best_score := INF
	for rung: Variant in rungs:
		var entry := rung as Dictionary
		var clip := String(entry["clip"])
		if not clips.has(clip) or _speed > float(entry.get("clean_max", 0.0)):
			continue
		var score := _gait_score(float(entry.get("stride", 0.0)))
		if score < best_score:
			best_score = score
			best = clip
	if best != "":
		return best
	var last := rungs[rungs.size() - 1] as Dictionary
	return String(last["clip"]) if clips.has(String(last["clip"])) else ""


## How far a rung's authored stride is from the speed the body is moving, as |ln(speed / stride)|.
## A clip with no ground contact (a flyer, an idle) can never be scaled to match, so it scores 0 and
## keeps the state it is asked for; standing still, the slowest gait is the right one.
func _gait_score(stride: float) -> float:
	if stride <= 0.1:
		return 0.0
	if _speed <= 0.5:
		return stride
	return absf(log(_speed / stride))


## Re-assert the locomotion state, unless a one-shot action still owns the player.
func apply_state() -> void:
	if _animation == null or clips.is_empty():
		return
	if _action_left > 0.0:
		return
	play_locomotion()


func play_locomotion() -> void:
	var clip_id := current_locomotion_clip()
	if not clips.has(clip_id):
		return
	var looping := bool((clips[clip_id] as Dictionary)["loop"])
	if not looping and _speed < 0.5:
		return
	if _animation.current_animation == String((clips[clip_id] as Dictionary)["name"]) \
			and _animation.is_playing():
		update_speed_scale()
		return
	_animation.play(String((clips[clip_id] as Dictionary)["name"]), LOCOMOTION_BLEND)
	update_speed_scale()


## Playback is scaled so the clip's stride matches the real ground speed. `stride_speed` is the
## stance foot's backward speed in root space (lead r1) — the speed the loop was authored for —
## and playing it at any other rate makes the planted foot slide (brief: "no foot sliding beyond
## ~10 %"). A clip with no ground contact (a harrier in flight) reports no stride and plays at 1x.
func update_speed_scale() -> void:
	var clip_id := current_locomotion_clip()
	var stride := float(_stride.get(clip_id, FALLBACK_STRIDE))
	var scale := 1.0
	if _speed > 0.5 and stride > 0.1:
		scale = clampf(_speed / stride, _min_scale, _max_scale)
	_speed_scale = scale
	if _pause_left <= 0.0 and _animation != null:
		_animation.speed_scale = scale


# --- one-shot actions ----------------------------------------------------------------------------

## Play a one-shot action and return its length in seconds, so callers can time gameplay against it.
## The action owns the player for its whole length: EnemyBase re-asserts `idle` every tick during a
## wind-up, and without the hold the attack is cross-faded away one physics tick after it starts
## (lead audit 1).
func play_action(id: StringName, blend: float = ACTION_BLEND) -> float:
	if _animation == null:
		return MISSING_ACTION
	var clip_id := resolve_action(id)
	if clip_id == "":
		_warn_missing(id)
		return MISSING_ACTION
	var entry := clips[clip_id] as Dictionary
	_animation.play(String(entry["name"]), maxf(blend, 0.0))
	_animation.speed_scale = 1.0 if _pause_left <= 0.0 else 0.0
	_action_left = float(entry["length"])
	return float(entry["length"])


## This type's own clip for a requested id: a clip of the same name, then the rig's per-type action
## table, then the shared aliases. Every step only counts if the clip is really there — an alias to a
## clip this type does not have would index a missing key and abort the call (lead audit 2).
func resolve_action(id: StringName) -> String:
	var clip_id := String(id)
	if clips.has(clip_id):
		return clip_id
	var mapped := String(_actions.get(clip_id, ""))
	if mapped != "" and clips.has(mapped):
		return mapped
	var aliased := String(ALIASES.get(StringName(clip_id), ""))
	if aliased != "" and clips.has(aliased):
		return aliased
	return ""


func _warn_missing(id: StringName) -> void:
	var key := "%s/%s" % [_body_type, id]
	if not _missing_warned.has(key):
		_missing_warned[key] = true
		push_warning("MonsterModel(%s): no action '%s'" % [_body_type, id])


# --- hit-stop and the frame tick -----------------------------------------------------------------

## Local hit-stop: freeze this monster's own animation (Feel owns the global time scale, and
## EnemyVisuals owns the vibration offset, so this only stops playback).
func pause(seconds: float) -> void:
	_pause_left = maxf(_pause_left, seconds)
	if _animation != null:
		_animation.speed_scale = 0.0


## The model's `_process`: run the hit-stop down, then the one-shot hold. Both are wall-clock, not
## physics, so they live here rather than in a physics tick.
func advance(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		if _pause_left <= 0.0 and _animation != null:
			_animation.speed_scale = _speed_scale if _animation.current_animation in loop_names() \
					else 1.0
		return
	if _action_left <= 0.0:
		return
	_action_left -= delta
	if _action_left <= 0.0:
		# the one-shot is spent: hand the player back to whatever locomotion state the brain has
		# been asserting all along, without waiting for its next tick
		play_locomotion()


func loop_names() -> PackedStringArray:
	var out := PackedStringArray()
	for clip_id: String in clips:
		if bool((clips[clip_id] as Dictionary)["loop"]):
			out.append(String((clips[clip_id] as Dictionary)["name"]))
	return out


func clip_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for clip_id: String in clips:
		out.append(clip_id)
	out.sort()
	return out
