class_name HudDeathHold
extends RefCounted
## The GAME_OVER page's death clock (hud r7).
##
## `menu_root.gd` used to call `get_tree().paused = true` in the SAME frame `Events.player_died` fired.
## The hero's `death` clip (`Hero3Model`, advanced in `_physics_process`, blended in over 0.08 s from
## weight 0) froze at weight 0: the mech stood upright under MECH DESTROYED, and every scripted run
## stalled at the death beat because the flow's own beat runner is pausable.
##
## This holds the clock instead. The page goes up at once and the tree only freezes once the flow is
## in `game_over` AND the death has settled — the held `death` clip at full weight with the wreck on
## the floor, `SETTLE` real seconds at the earliest (a hit-stop runs the clip on the slower player
## clock) and `CAP` at the latest, so a corpse that never lands still freezes the run.

## Real seconds the death gets before the tree may freeze, and the backstop after which it freezes
## whatever the corpse is doing. `SETTLE` alone is not enough for a mech killed in the air: the wreck
## has to reach the floor first (the flight death in `death_probe.gd` falls 40 m, ~3 s), and freezing
## it up there would be the same bug in a new place. `CAP` only ever fires for a corpse that never
## lands at all.
const SETTLE := 1.5
const CAP := 8.0
## The clip the hero holds while it is dead (`hero3_clips_react.gd` DEATH).
const DEATH_CLIP := &"death"

## `Feel.real_now()` when the death was announced, or -1.0 when no death is settling.
var at: float = -1.0
## True once the tree has been frozen for this death, so `_process` only does it once.
var frozen: bool = false

var _tree: SceneTree = null
var _flow_node: Node = null
var _flow_searched: bool = false


func setup(tree: SceneTree) -> void:
	_tree = tree


## A death was announced: start the clock.
func arm(now: float) -> void:
	at = now
	frozen = false


## No death is settling any more (the page closed, a RETRY is on its way, the run went back to the
## title).
func clear() -> void:
	at = -1.0
	frozen = false


## True while a death is settling and the tree has not frozen yet: the mech is still collapsing, so a
## RETRY pressed now would cut the death short. A scripted run never freezes, so it never settles.
func settling() -> bool:
	return at >= 0.0 and not frozen and not scripted()


## The death has played out. `CAP` is the backstop for a corpse that never reaches the floor.
func settled(now: float) -> bool:
	var elapsed := now - at
	return elapsed >= CAP or (elapsed >= SETTLE and clip_held() and corpse_down())


## `--flow-script` (CONTRACTS §2) is a scripted capture or debug run: `FlowDebug` drives its own beats
## on the physics tick and revives the mech itself with `respawn`, and it is PAUSABLE — a frozen tree
## would stall the script at the death beat and leave the page up over every capture after it. A
## scripted run has no player to press RETRY, so the page is shown and the tree keeps running.
static func scripted() -> bool:
	return Game.flag("flow-script") != ""


## The flow's own state, duck-typed so the hud still runs with `--stub=flow` (CONTRACTS §1). No flow
## node in the tree means nothing else will ever announce `game_over`, so the pause does not wait.
func flow_in_game_over() -> bool:
	var flow := _flow()
	return flow == null or StringName(flow.call(&"state_name")) == &"game_over"


## True when the hero's held `death` clip is at full weight, read through the same model API the
## mech-move death probe uses (`Hero3Model.clips.current()` / `.weight()`). A build with no hero model
## — a stubbed player, the pure-hud suite's fake actor — has nothing to wait for.
func clip_held() -> bool:
	var m := _model()
	if m == null:
		return true
	var clips := m.get(&"clips") as Object
	if clips == null or not clips.has_method(&"weight"):
		return true
	return StringName(clips.call(&"current")) == DEATH_CLIP and float(clips.call(&"weight")) >= 1.0


## The wreck is down: a corpse still falling has not finished dying. A player with no floor query
## counts as down.
func corpse_down() -> bool:
	var p := _player()
	if p == null or not p.has_method(&"is_on_floor"):
		return true
	return bool(p.call(&"is_on_floor"))


## The flow node, found ONCE by the one method every flow exposes (`FlowGameFlow.state_name`). The hud
## must not name the class: `--stub=flow` has to keep working. The city tree is thousands of nodes, so
## the search runs at most once per `HudDeathHold`.
func _flow() -> Node:
	if is_instance_valid(_flow_node):
		return _flow_node
	if _flow_searched or _tree == null:
		return null
	_flow_searched = true
	_flow_node = _find_flow(_tree.root)
	return _flow_node


func _find_flow(node: Node) -> Node:
	if node.has_method(&"state_name"):
		return node
	for child in node.get_children():
		var found := _find_flow(child)
		if found != null:
			return found
	return null


func _player() -> Node:
	var p := Game.player
	return p if p != null and is_instance_valid(p) else null


func _model() -> Node3D:
	var p := _player()
	if p == null or not p.has_method(&"model"):
		return null
	return p.call(&"model") as Node3D
