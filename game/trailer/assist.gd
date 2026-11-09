class_name TrailerAssist
extends Node
## Capture-side autopilot for the showcase reel (trailer unit, lead brief trailer-r3).
##
## Some of the verbs the reel has to show are not reachable by pressing a key at a time on a timeline:
## a perfect parry is a 167 ms window that only opens when a monster decides to swing, a Core Rend
## execution needs its victim staggered, and the gatling's perfect vent is a needle the player has to
## hit while it sweeps. This node presses the REAL actions at the REAL moment — it is the player's
## reaction, scripted — so what the camera films is the game's own parry, execution and vent, not a
## replay of an animation.
##
##   tools/godot.sh movie … --trailer-assist=res://trailer/assist/<name>.json
##
## Rules (a JSON object with `rules`, all optional):
##   {"on":"telegraph","kind":"parryable","after":0.20,"press":"guard","hold":0.05,"max":4}
##       react to Events.enemy_telegraph; `kind` filters (parryable / unblockable / ranged / any).
##   {"on":"poise","type":"juggernaut","at":3.0,"amount":3000,"every":0.5,"max":6}
##       feed a live monster real poise damage through take_hit() until it staggers, so the reel can
##       reach an execution inside one take. Damage is 0: this moves the stagger bar, nothing else.
##   {"on":"stagger","press":"melee","hold":0.05,"max":2}
##       press `press` the moment a staggered monster is executable.
##   {"on":"vent","press":"fire","hold":0.05,"max":2,"window":0.06}
##       tap fire as the gatling's vent needle crosses its mark (the perfect vent).
##
## Every rule prints what it did ("ASSIST …"), so a take's log says which beats were assisted.

const PRESS_FRAMES := 3

var rules: Array[Dictionary] = []

var _t: float = 0.0
var _pending: Array[Dictionary] = []      ## [{due, action, hold, rule}]
var _close_on: Array[Dictionary] = []     ## [{rule, enemy}] — staggered, walking in
var _counts: Dictionary = {}              ## rule index -> how many times it has fired
var _done: Dictionary = {}                ## rule index -> true once it can never fire again
var _weapons: Node = null


func setup(spec: Dictionary) -> void:
	for r: Variant in (spec.get("rules", []) as Array):
		rules.append(r as Dictionary)
	if rules.is_empty():
		push_warning("TrailerAssist: no rules in the spec")
		return
	if _has(&"telegraph"):
		Events.enemy_telegraph.connect(_on_telegraph)
	if _has(&"stagger"):
		Events.enemy_staggered.connect(_on_staggered)


## Append a rule the shot declared by flag rather than by file — the arena mark is the same four
## numbers on every take, so it does not deserve a JSON file per segment.
func add_rule(rule: Dictionary) -> void:
	rules.append(rule)


func _has(kind: String) -> bool:
	for r in rules:
		if String(r.get("on", "")) == kind:
			return true
	return false


func _process(delta: float) -> void:
	if rules.is_empty():
		return
	_t += delta
	_due_presses()
	for i in rules.size():
		match String(rules[i].get("on", "")):
			"t":
				_timed(i)
			"poise":
				_poise(i)
			"vent":
				_vent(i)
			_:
				pass


## The mark runs on the physics tick, after the player's own, so the clamp is the last write.
func _physics_process(_delta: float) -> void:
	if Game.player == null:
		return
	for i in rules.size():
		# The wall stands down while a close-in is walking the mech somewhere on purpose: the mark
		# clamps to an 8 m disc and the close-in needs to cross it, so with both live they fight and
		# the mech never reaches the staggered target (m5_juggernaut: the execution never fired).
		if String(rules[i].get("on", "")) == "mark" and _close_on.is_empty():
			_mark(i)
	var j := 0
	while j < _close_on.size():
		var n := _close_on.size()
		_close(j, _close_on[j])
		j += 1 if _close_on.size() == n else 0


## A capture-side arena wall. A 16 m mech under a pack of 14 m mantises is batted 100 m across the
## district in twelve seconds (measured: m2_mantis, the framing log's camera went from (-88,440) to
## (24,542)), and every camera that follows it ends up inside a building. This holds the hero inside a
## disc around the mark: past `radius` the position is projected back onto the rim and the outward
## velocity is removed, so it reads as the mech being stopped rather than teleported — and a fall off
## the deck (more than `drop` below the mark) puts it back on its feet.
func _mark(index: int) -> void:
	var r := rules[index]
	var p: Vector3 = Game.player.global_position
	var mark := _vec(r.get("pos", [0.0, 0.0, 0.0]))
	var radius := float(r.get("radius", 26.0))
	var drop := float(r.get("drop", 22.0))
	if p.y < mark.y - drop:
		Game.player.call(&"debug_teleport", [mark.x, mark.y, mark.z], float(r.get("yaw", 0.0)))
		print("ASSIST t=%.2f mark: recovered from a fall to y=%.0f" % [_t, p.y])
		return
	var flat := Vector3(p.x - mark.x, 0.0, p.z - mark.z)
	if flat.length() <= radius:
		return
	var out := flat.normalized()
	Game.player.global_position = Vector3(mark.x + out.x * radius, p.y, mark.z + out.z * radius)
	var v: Vector3 = Game.player.velocity
	var along := v.dot(out)
	if along > 0.0:
		v -= out * along
		Game.player.velocity = v


## A press that a rule scheduled: hold it for `hold` seconds (a tap is PRESS_FRAMES of real time).
func _due_presses() -> void:
	var i := 0
	while i < _pending.size():
		var p := _pending[i]
		if _t < float(p["due"]):
			i += 1
			continue
		if not bool(p["down"]):
			Input.action_press(StringName(p["action"]))
			p["down"] = true
			p["due"] = _t + maxf(float(p["hold"]), 0.0)
			print("ASSIST t=%.2f press %s (%s)" % [_t, p["action"], p["rule"]])
		else:
			Input.action_release(StringName(p["action"]))
			_pending.remove_at(i)
			continue
		i += 1


func _schedule(rule: Dictionary, index: int, action: String, delay: float, tag: String) -> bool:
	if _spent(index, rule):
		return false
	_counts[index] = int(_counts.get(index, 0)) + 1
	_pending.append({"due": _t + delay, "action": action, "hold": float(rule.get("hold", 0.05)),
			"rule": tag, "down": false})
	return true


## True once a rule has fired `max` times (default 1 for one-shot rules, 99 for the reactive ones).
func _spent(index: int, rule: Dictionary) -> bool:
	if bool(_done.get(index, false)):
		return true
	return int(_counts.get(index, 0)) >= int(rule.get("max", 1))


# --- rules ---------------------------------------------------------------------------------------

## A press at a fixed time, held for `hold` seconds. It lives here rather than on the timeline because
## a take whose guard is entirely assist-driven cannot have autoplay and the assist fight over the
## same action — the parry rules below need the button to themselves between the blocks.
func _timed(index: int) -> void:
	var r := rules[index]
	if _spent(index, r) or _t < float(r.get("at", 0.0)):
		return
	_schedule(r, index, String(r.get("press", "guard")), 0.0, "at %.1f" % float(r.get("at", 0.0)))


func _on_telegraph(enemy: Node, attack: StringName, kind: StringName) -> void:
	for i in rules.size():
		var r := rules[i]
		if String(r.get("on", "")) != "telegraph":
			continue
		var want := String(r.get("kind", "any"))
		if want != "any" and want != String(kind):
			continue
		if r.has("type") and not _is_type(enemy, StringName(r["type"])):
			continue
		_schedule(r, i, String(r.get("press", "guard")), float(r.get("after", 0.2)),
				"telegraph %s/%s" % [kind, attack])


func _on_staggered(enemy: Node, _by: Node) -> void:
	for i in rules.size():
		var r := rules[i]
		if String(r.get("on", "")) != "stagger" or _spent(i, r):
			continue
		if r.has("type") and not _is_type(enemy, StringName(r["type"])):
			continue
		_close_on.append({"rule": i, "enemy": enemy})


## A staggered monster has to be INSIDE the Core Rend window (14 m, SPEC §4.6) for the execution to
## fire, and the mech is usually still standing where the fight was. With `close` set, the assist walks
## it in — the same scripted-reaction idea as the parry: the player's approach, on rails — and presses
## the button when the window actually opens.
func _close(i: int, step: Dictionary) -> void:
	var e := step["enemy"] as Node3D
	if e == null or not is_instance_valid(e) or Game.player == null:
		_close_on.remove_at(i)
		return
	var index := int(step["rule"])
	var r: Dictionary = rules[index]
	if _spent(index, r):
		_close_on.remove_at(i)
		return
	var want := float(r.get("close", 11.0))
	var to := e.global_position - Game.player.global_position
	to.y = 0.0
	var executable := e.has_method(&"is_executable") and bool(e.call(&"is_executable", Game.player))
	if executable or to.length() <= want:
		_schedule(r, index, String(r.get("press", "melee")), float(r.get("after", 0.2)),
				"stagger %s at %.0f m" % [e.name, to.length()])
		_close_on.remove_at(i)
		return
	Game.player.velocity = to.normalized() * float(r.get("speed", 34.0))
	Game.player.look_at(Vector3(e.global_position.x, Game.player.global_position.y,
			e.global_position.z), Vector3.UP)


## Poise: a real take_hit carrying only stagger, repeated until the monster's bar breaks. Nothing else
## about the fight changes — the HP pool, the AI and the hit reactions are the game's own.
func _poise(index: int) -> void:
	var r := rules[index]
	if _spent(index, r) or _t < float(r.get("at", 0.0)):
		return
	if _t < float(r.get("_next", -1.0)):
		return
	var e := _nearest(StringName(r.get("type", "")))
	if e == null:
		return
	var status: Variant = e.get(&"status")
	if status != null and bool(status.call(&"is_staggered")):
		_done[index] = true
		return
	r["_next"] = _t + float(r.get("every", 0.5))
	var hit := HitInfo.make(0.0, HitInfo.MELEE, Game.player, &"trailer_poise")
	hit.stagger = float(r.get("amount", 2000.0))
	hit.position = (e as Node3D).global_position
	e.call(&"take_hit", hit)
	_counts[index] = int(_counts.get(index, 0)) + 1
	print("ASSIST t=%.2f poise %.0f -> %s (%d/%d)" % [_t, hit.stagger, e.name,
			int(_counts[index]), int(r.get("max", 1))])


## The gatling's active vent: tap fire while the needle is inside `window` of the mark.
func _vent(index: int) -> void:
	var r := rules[index]
	if _spent(index, r) or _weapons == null:
		return
	var st: Variant = _weapons.call(&"hud_state")
	if not st is Dictionary:
		return
	var d := st as Dictionary
	if not bool(d.get("overheated", false)):
		return
	var off := absf(float(d.get("vent_needle", 0.0)) - float(d.get("vent_mark", 0.5)))
	if off > float(r.get("window", 0.06)):
		return
	_schedule(r, index, String(r.get("press", "fire")), 0.0, "vent off=%.3f" % off)


# --- helpers -------------------------------------------------------------------------------------

func _weapon_system() -> Node:
	if _weapons == null and Game.player != null:
		_weapons = Game.player.find_child("WeaponSystem", true, false)
	return _weapons


func _is_type(enemy: Node, want: StringName) -> bool:
	return want == &"" or (enemy != null and StringName(enemy.get(&"enemy_type")) == want)


func _vec(v: Variant) -> Vector3:
	var a := v as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## The nearest live monster of `want` (any type when it is empty), measured from the mech.
func _nearest(want: StringName) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n: Node in get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e == null or not _is_type(e, want):
			continue
		if e.has_method(&"is_alive") and not bool(e.call(&"is_alive")):
			continue
		var d := e.global_position.distance_to(Game.player.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _ready() -> void:
	set_process(false)


## Called by trailer_shot.gd once the world is up, so a rule never fires against a half-built scene.
func arm() -> void:
	_weapon_system()
	set_process(true)
	print("ASSIST armed with %d rules" % rules.size())
