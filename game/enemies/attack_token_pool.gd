class_name AttackTokenPool
extends RefCounted
## Crowd-pressure budget (enemies-owned). juice §11.3 / Doom: cap the number of enemies allowed to
## commit at once so the player can read the fight; the brief's numbers are 3 melee attackers and 2
## ranged volleys. A freed token is re-granted only after a short delay, so attacks come in waves.
## Static state is process-wide (one player to pressure).

const MELEE := &"melee"
const RANGED := &"ranged"

const LIMIT_MELEE := 3
const LIMIT_RANGED := 2
const REGRANT_DELAY := 0.8   ## juice §11.3: 0.6–1.0 s before the slot opens again
## The four states a kind can be in, in the order `slot_state` reports them (test_ai prints the share
## of the window each one gets, so a low pressure reading shows whether the pool or the pack is short).
const AT_LIMIT := 0          ## every slot held
const DELAY_SHUT := 1        ## below the limit, but the re-grant delay is holding the rest shut
const FREE_ASKING := 2       ## a slot is free and a monster is asking for it
const FREE_IDLE := 3         ## a slot is free and nobody wants it

static var _holders: Dictionary = {}   ## kind -> Array[Node]
static var _cooldown: Dictionary = {}  ## kind -> seconds left before a freed slot reopens
static var _asked: Dictionary = {}     ## kind -> Array[Node] that called request since the last tick


## True when `who` now holds a token of `kind` (already holding one always succeeds).
static func request(kind: StringName, who: Node) -> bool:
	_prune(kind)
	var askers: Array = _asked.get(kind, [])
	if who not in askers:
		askers.append(who)
		_asked[kind] = askers
	var list: Array = _holders.get(kind, [])
	if list.has(who):
		return true
	if not list.is_empty() and float(_cooldown.get(kind, 0.0)) > 0.0:
		return false
	if list.size() >= _limit(kind):
		return false
	list.append(who)
	_holders[kind] = list
	return true


static func release(kind: StringName, who: Node) -> void:
	var list: Array = _holders.get(kind, [])
	if who in list:
		list.erase(who)
		_holders[kind] = list
		_cooldown[kind] = REGRANT_DELAY


## Called once per frame by the spawner so the re-grant timers run even with no live requester.
static func tick(delta: float) -> void:
	_asked.clear()
	for kind: StringName in _cooldown.keys():
		var left := float(_cooldown[kind]) - delta
		_cooldown[kind] = maxf(left, 0.0)
	_prune(MELEE)
	_prune(RANGED)


static func holders(kind: StringName) -> int:
	_prune(kind)
	return (_holders.get(kind, []) as Array).size()


static func holds(kind: StringName, who: Node) -> bool:
	return (_holders.get(kind, []) as Array).has(who)


## Seconds before a freed slot of `kind` can be handed out again (0 when it is free now).
static func cooldown_left(kind: StringName) -> float:
	return float(_cooldown.get(kind, 0.0))


## Monsters of `kind` that asked for a token since the last `tick` and did not get one.
static func askers(kind: StringName) -> int:
	var list: Array = _asked.get(kind, [])
	var holders_of: Array = _holders.get(kind, [])
	var n := 0
	for who: Node in list:
		if is_instance_valid(who) and not holders_of.has(who):
			n += 1
	return n


## True when `who` asked for a token of `kind` since the last `tick` and is not holding one.
static func asking(kind: StringName, who: Node) -> bool:
	return who in (_asked.get(kind, []) as Array) \
			and not (_holders.get(kind, []) as Array).has(who)


## SPEC §7.1 "full attack tokens" for one kind (lead decision, r16 Round 2): every slot is held, or
## shut by the re-grant delay, while another monster of that kind is still asking for one. This is
## the pressure the SPEC's time-to-death is measured under; the earlier reading ("all 3 + 2 held at
## the same instant") could only ever be a peak, because `release` shuts the whole kind for
## REGRANT_DELAY and `request` refuses while anyone still holds one.
static func at_capacity(kind: StringName) -> bool:
	if askers(kind) <= 0:
		return false
	return slot_state(kind) <= DELAY_SHUT


## Which of the four states `kind` is in right now (AT_LIMIT / DELAY_SHUT / FREE_ASKING / FREE_IDLE).
static func slot_state(kind: StringName) -> int:
	var held := holders(kind)
	if held >= _limit(kind):
		return AT_LIMIT
	if held > 0 and cooldown_left(kind) > 0.0:
		return DELAY_SHUT
	return FREE_ASKING if askers(kind) > 0 else FREE_IDLE


static func reset() -> void:
	_holders.clear()
	_cooldown.clear()
	_asked.clear()


static func _limit(kind: StringName) -> int:
	return LIMIT_MELEE if kind == MELEE else LIMIT_RANGED


static func _prune(kind: StringName) -> void:
	var list: Array = _holders.get(kind, [])
	var changed := false
	for i in range(list.size() - 1, -1, -1):
		if not is_instance_valid(list[i]):
			list.remove_at(i)
			changed = true
	if changed:
		_holders[kind] = list
