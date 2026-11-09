class_name FlowDebug
extends Node
## Scripted commands for tools and tests (brief "Done when": a scripted run reaches `boss_gate`
## without the player having to shoot 20,000 points of weak point by hand). Enabled only by
## `--flow-script=res://…json`; without the flag the node does nothing at all.
##
## ```json
## [{"t": 2.0, "cmd": "teleport", "args": [-220, 40, 40, 0]},
##  {"t": 4.0, "cmd": "hurt_spire", "args": [0, 4000]},
##  {"t": 6.0, "cmd": "kill_spire", "args": [0]},
##  {"t": 8.0, "cmd": "state"}]
## ```
## `t` is seconds on the world clock after `Events.world_ready`. The `wait_*` commands take their
## give-up time as their LAST argument (`wait_won` takes only that); `shot` files the camera verdict
## of the frame it saved, and `report` prints the tally.
## Two debug scalings, both printed when they are applied and absent from every other run:
## `--boss-hp-scale=0.02` shortens the titan fight so a scripted run reaches VICTORY, and
## `--spire-hp-scale=0.35` shortens the hives so the bot can destroy every pod and core with the real
## rifle inside one recording slot.

const FLAG := "flow-script"
const ARM_DELAY := 0.5         ## s after the world is built, so GameFlow._start() has placed the spires
## s a `shot` may take before the script gives up on it: the settle, up to three buried-lens repairs
## and the save itself. A capture that blows this is reported, not silently skipped.
const SHOT_LIMIT := 12.0
## `--boss-hp-scale=0.02`: the E2E has to reach VICTORY with real weapons inside a scripted run, and
## 150,000 points of titan is a 5-minute fight. The scale is applied to the titan and its cores when
## it spawns, printed when it happens, and absent from every other run.
const HP_SCALE_FLAG := "boss-hp-scale"
## `--spire-hp-scale=0.35`: the same idea for the hives. 20,000 HP a spire is two and a half minutes
## of trigger time for the bot at the city's frame rate, three times over, and the recording slot is
## 30 minutes; at 0.35 every pod and every core is still destroyed by the real rifle, through the real
## damage path, in a run that finishes. Printed when it is applied, absent from every other run.
const SPIRE_SCALE_FLAG := "spire-hp-scale"
const COMMANDS: Array[StringName] = [&"teleport", &"goto", &"approach_spire", &"core_stand", &"look_at",
		&"shot",
		&"hurt_spire", &"kill_spire", &"assault_spire", &"finish_spire", &"assault_arena",
		&"assault_boss", &"cease", &"wait_state", &"wait_won",
		&"wait_down", &"wait_beat", &"wait_arena", &"heal", &"god", &"die", &"respawn", &"state",
		&"clear_arena", &"mark", &"report", &"dump", &"lethal", &"probe", &"boss_phase",
		&"retry", &"film_collapse"]

var _flow: Node = null
var _events: Array = []
var _next: int = 0
var _t: float = 0.0
var _wait: float = 0.0
var _armed: bool = false
var _assault: FlowDebugAssault = null
var _view: FlowDebugView = FlowDebugView.new()
var _block: StringName = &""      ## the wait_* command holding the script right now
var _block_arg: Variant = null
var _block_t: float = 0.0
var _block_limit: float = 0.0
## The run's evidence — marks, capture verdicts, fallbacks and the report (`flow_debug_report.gd`).
var _log: FlowDebugReport = FlowDebugReport.new()
var _hp_scaled: bool = false
## `film_collapse` state: how many frames are left, which one is next, and how long until it.
var _film_left: int = 0
var _film_step: int = 0
var _film_t: float = 0.0
var _film_gap: float = 0.25
var _film_tag: String = "collapse"


func setup(flow: Node) -> void:
	_flow = flow
	_view.setup(self)
	var path := Game.flag(FLAG)
	if path == "":
		set_physics_process(false)
		return
	Events.game_won.connect(func() -> void: _log.note_won())
	_events = _load(path)
	set_physics_process(not _events.is_empty())


func _load(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("FlowDebug: no script at " + path)
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Array):
		push_error("FlowDebug: %s is not a JSON array" % path)
		return []
	var rows: Array = parsed as Array
	# `sort_custom` is NOT stable, and a script leans on the file order for two rows at the same `t`
	# (`retry` then `wait_state`). Without the index tie-break those two swap at random and the RETRY
	# lands after the wait it was supposed to satisfy — which is how the whole checkpoint matrix
	# pressed RETRY 12 s late. (r5.)
	for i in rows.size():
		(rows[i] as Dictionary)["_i"] = i
	rows.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ta := float((a as Dictionary).get("t", 0.0))
		var tb := float((b as Dictionary).get("t", 0.0))
		if is_equal_approx(ta, tb):
			return int((a as Dictionary)["_i"]) < int((b as Dictionary)["_i"])
		return ta < tb)
	return rows


func _arm() -> void:
	_armed = true
	_t = 0.0
	_scale_spire_hp()
	print("FLOWDBG %d commands armed" % _events.size())


## `--spire-hp-scale` on every spire the flow built (see the constant).
func _scale_spire_hp() -> void:
	var spec := Game.flag(SPIRE_SCALE_FLAG)
	if spec == "":
		return
	var factor := float(spec)
	if factor <= 0.0 or factor > 1.0:
		push_error("FlowDebug: --%s must be in (0, 1], got '%s'" % [SPIRE_SCALE_FLAG, spec])
		return
	var spires := _flow.call(&"spires") as Array
	for node in spires:
		(node as FlowHiveSpire).scale_hp(factor)
	print("FLOWDBG --%s=%.2f applied: %d spires, %.0f -> %.0f HP each"
			% [SPIRE_SCALE_FLAG, factor, spires.size(),
			FlowHiveSpire.PODS * FlowHiveSpire.POD_HP + FlowHiveSpire.CORE_HP,
			(FlowHiveSpire.PODS * FlowHiveSpire.POD_HP + FlowHiveSpire.CORE_HP) * factor])


## The trigger pulse runs on the idle frame (see `FlowDebugAssault.tick_trigger`).
func _process(delta: float) -> void:
	if _assault != null:
		_assault.tick_trigger(delta)


func _physics_process(delta: float) -> void:
	if not _armed:
		_wait += delta
		if Game.world_built() and _wait >= ARM_DELAY:
			_arm()
		return
	_t += delta
	_scale_boss_hp()
	if _assault != null and _assault.tick(delta):
		_assault = null
	if _block != &"" and not _unblocked(delta):
		return
	while _next < _events.size() and _t >= float((_events[_next] as Dictionary).get("t", 0.0)):
		_run(_events[_next] as Dictionary)
		_next += 1
		# One command per frame while a block is open: a `shot` and a `wait_*` both hold the script
		# until their own condition is met.
		if _block != &"":
			break
	if _next >= _events.size() and _block == &"" and _assault == null:
		set_physics_process(false)


## A `wait_*` command holds the script until its condition is met (or its timeout runs out), so the
## E2E is a sequence of beats and not a table of absolute times that drifts with load.
func _unblocked(delta: float) -> bool:
	_block_t -= delta
	var done := false
	match _block:
		&"state":
			done = String(_flow.call(&"state_name")) == String(_block_arg)
		&"down":
			done = (_flow.call(&"spires_down") as Array).size() >= int(_block_arg)
		&"beat":
			done = _assault == null
		&"won":
			done = _log.won()
		&"arena":
			done = bool(_director().arena_state(StringName(_block_arg)).get("active", false))
		&"lethal":
			done = _lethal_tick()
		&"shot":
			done = not _view.saving
		&"film":
			done = _film_tick(delta)
		_:
			done = true
	if not done and _block_t > 0.0:
		return false
	if not done:
		push_warning("FlowDebug: %s wait timed out (%.0f s)" % [_block, _block_limit])
	print("FLOWDBG unblock %s after %.1f s" % [_block, _block_limit - maxf(_block_t, 0.0)])
	_block = &""
	return true


func _run(row: Dictionary) -> void:
	var cmd := StringName(row.get("cmd", ""))
	var args: Array = row.get("args", [])
	if cmd not in COMMANDS:
		push_error("FlowDebug: unknown command '%s'" % cmd)
		return
	print("FLOWDBG t=%.1f %s %s" % [_t, cmd, str(args)])
	match cmd:
		&"teleport":
			_teleport(args)
		&"goto":
			_view.goto_place(StringName(args[0]) if not args.is_empty() else &"",
					float(args[1]) if args.size() > 1 else 12.0)
		&"approach_spire":
			_view.approach_spire(_spire(int(args[0]) if not args.is_empty() else 0),
					float(args[1]) if args.size() > 1 else 110.0,
					float(args[2]) if args.size() > 2 else 20.0)
		&"core_stand":
			_view.core_stand(_spire(int(args[0]) if not args.is_empty() else 0),
					float(args[1]) if args.size() > 1 else 70.0)
		&"shot":
			# A BLOCK, not a fixed hold (r5 brief item 8): the script waits until the .jpg is on disk,
			# so the next beat cannot run in the same tick and two beats cannot save the same picture.
			_view.shot(String(args[0]) if not args.is_empty() else "shot")
			_block = &"shot"
			_block_arg = null
			_block_limit = SHOT_LIMIT
			_block_t = SHOT_LIMIT
		&"look_at":
			if args.size() >= 3:
				_view.look_at(Vector3(float(args[0]), float(args[1]), float(args[2])))
			else:
				push_error("FlowDebug: look_at needs [x, y, z]")
		&"hurt_spire":
			_hurt(args)
		&"kill_spire":
			var target := _spire(int(args[0]) if not args.is_empty() else 0)
			if target != null:
				# The script, not the bot: the tally must never read this spire as a weapon kill
				# (r5 brief item 7).
				_log.note_fallback(target.spire_id)
				target.collapse()
		&"assault_spire":
			_assault_spire(int(args[0]) if not args.is_empty() else 0)
		&"finish_spire":
			_finish_spire(int(args[0]) if not args.is_empty() else 0)
		&"assault_arena":
			_assault_arena(args)
		&"assault_boss":
			_start_assault()
			_assault.start_boss()
		&"wait_state":
			_block = &"state"
			_block_arg = String(args[0]) if not args.is_empty() else ""
			_block_for(args)
		&"wait_won":
			_block = &"won"
			_block_arg = null
			_block_for(args, 0)
		&"wait_down":
			_block = &"down"
			_block_arg = int(args[0]) if not args.is_empty() else 1
			_block_for(args)
		&"wait_beat":
			_block = &"beat"
			_block_arg = null
			_block_for(args)
		&"wait_arena":
			_block = &"arena"
			_block_arg = String(args[0]) if not args.is_empty() else &""
			_block_for(args, 1)
		&"cease":
			if _assault != null:
				_assault.stop()
				_assault = null
			Input.action_release(&"fire")
		&"heal":
			_heal()
		&"god":
			Game.player.call(&"invulnerable_for", 9999.0)
		&"die":
			# --god zeroes the damage in PlayerMech, so the debug death writes the HP itself. The
			# ANNOUNCEMENT is not flow's: `MechDamage.sync()` runs at the top of every physics tick,
			# sees hp reach 0 and emits `player_died` exactly once (mech-move r7b item 8). Emitting
			# here as well made one `die` announce twice — two GAME_OVER pages, two stingers, two
			# respawns (r5b item 3). A repro only: `lethal` is the real path (r5 rules).
			Game.player.set(&"hp", 0.0)
		&"lethal":
			_block = &"lethal"
			_block_arg = null
			_block_for(args, 0)
		&"probe":
			_probe()
		&"boss_phase":
			_boss_phase(args)
		&"retry":
			_accept()
		&"film_collapse":
			_film_collapse(args)
		&"respawn":
			_flow.call(&"respawn")
		&"state":
			var tut := _flow.get(&"tutorial") as FlowTutorialDirector
			var at := Game.player.global_position if Game.player != null else Vector3.ZERO
			print("FLOWDBG state=%s hint=%s tutorial=%s at=%.0f,%.0f,%.0f down=%d hp=%.0f en=%.0f"
					% [_flow.call(&"state_name"), tut.hint_text() if tut != null else "-",
					str(tut.active) if tut != null else "-", at.x, at.y, at.z,
					(_flow.call(&"spires_down") as Array).size(),
					float(Game.player.get(&"hp")) if Game.player != null else 0.0,
					float(Game.player.get(&"energy")) if Game.player != null else 0.0])
		&"clear_arena":
			var arena := StringName(args[0]) if not args.is_empty() else &"sandbox"
			_log.note_scripted_clear(arena)
			_director().force_clear(arena)
		&"mark":
			_mark(args)
		&"report":
			_report()
		&"dump":
			_dump()


func _director() -> FlowEncounterDirector:
	return _flow.get(&"director") as FlowEncounterDirector


## What the run is standing on: the boss arena, the spires and the catapult, with positions. The E2E
## uses it to prove a beat happened where the map says it should.
func _dump() -> void:
	for node in get_tree().get_nodes_in_group(&"boss_arena"):
		var n := node as Node3D
		print("FLOWDBG dump boss_arena %s at %.0f,%.0f,%.0f" % [n.name, n.global_position.x,
				n.global_position.y, n.global_position.z])
	for s in _flow.call(&"spires") as Array:
		var spire := s as FlowHiveSpire
		print("FLOWDBG dump spire %s arena=%s at %.0f,%.0f,%.0f alive=%s hp=%.0f"
				% [spire.spire_id, spire.arena_id, spire.global_position.x, spire.global_position.y,
				spire.global_position.z, str(spire.alive), spire.total_hp()])
	for id: StringName in _director().arena_ids():
		var a := _director().arena_state(id) as Dictionary
		print("FLOWDBG dump arena %s active=%s done=%s wave=%d live=%d"
				% [id, str(a.get("active", false)), str(a.get("done", false)),
				int(a.get("index", 0)), (a.get("live", []) as Array).size()])
	var targets := get_tree().get_nodes_in_group(&"targetable")
	print("FLOWDBG dump targetable=%d enemies=%d" % [targets.size(),
			get_tree().get_nodes_in_group(&"enemy").size()])
	for node in targets:
		var t := node as Targetable
		if t != null:
			print("FLOWDBG dump target %s valid=%s at %.0f,%.0f,%.0f" % [t.name,
					str(t.is_valid_target()), t.global_position.x, t.global_position.y,
					t.global_position.z])


func _teleport(args: Array) -> void:
	if Game.player == null or args.size() < 3:
		push_error("FlowDebug: teleport needs a player and [x, y, z]")
		return
	var yaw := float(args[3]) if args.size() > 3 else 0.0
	Game.player.call(&"debug_teleport", [float(args[0]), float(args[1]), float(args[2])], yaw)


## Hand a spire to the E2E bot, which shoots its pods and core with the real weapons (r3 brief 1).
func _assault_spire(index: int) -> void:
	var target := _spire(index)
	if target == null:
		return
	_start_assault()
	_assault.start_spire(target)


## The scripted fallback for a spire the bot could not find a firing position on (a hive whose pods
## are inside the Interchange Knot's flyovers — city-layout r6 moves them). The same `take_hit` path a
## shot takes, with the authored weak-point damage, so the objective still counts, the pods still
## burst one by one and the collapse still plays. Announced, counted, and listed by `report`: an E2E
## pass that used this is NOT a pass with real weapons (lead r4 item 2).
func _finish_spire(index: int) -> void:
	var target := _spire(index)
	if target == null or not target.alive:
		return
	_log.note_fallback(target.spire_id)
	push_warning("FLOWDBG DEBUG FALLBACK: finishing spire %s through take_hit (%.0f HP left) — the bot could not shoot it"
			% [target.spire_id, target.total_hp()])
	for i in FlowHiveSpire.PODS:
		_hurt([index, FlowHiveSpire.POD_HP, "pod_%d" % i])
	_hurt([index, FlowHiveSpire.CORE_HP, "core"])


## The same bot on an arena's waves: real rippers, real rifle, until the director clears the arena.
func _assault_arena(args: Array) -> void:
	if args.is_empty():
		push_error("FlowDebug: assault_arena needs an arena id")
		return
	_start_assault()
	_assault.start_arena(StringName(args[0]))


func _start_assault() -> void:
	if _assault != null:
		_assault.stop()
	_assault = FlowDebugAssault.new()


## `args = [value, seconds]` — the timeout is always the entry after the value, so a broken beat ends
## the run with a warning instead of hanging it.
func _block_for(args: Array, value_index: int = 1) -> void:
	_block_limit = float(args[value_index]) if args.size() > value_index else 60.0
	_block_t = _block_limit


## A phase boundary for the pacing report: `args = ["name"]`.
func _mark(args: Array) -> void:
	var phase := String(args[0]) if not args.is_empty() else "mark"
	_log.mark(phase, _t, StringName(_flow.call(&"state_name")))


## `--boss-hp-scale=` (r4 brief item 3): the titan spawns when the fight starts, so the scale waits for
## it and applies once — main pool and every core, printed, so a shortened fight is never silent.
func _scale_boss_hp() -> void:
	if _hp_scaled or Game.flag(HP_SCALE_FLAG) == "":
		return
	var boss := get_tree().get_first_node_in_group(&"boss") as Node3D
	if boss == null or not ("hp_max" in boss and "hp" in boss):
		return
	var scale := float(Game.flag(HP_SCALE_FLAG))
	if scale <= 0.0 or scale > 1.0:
		push_error("FlowDebug: --%s must be in (0, 1], got '%s'" % [HP_SCALE_FLAG,
				Game.flag(HP_SCALE_FLAG)])
		_hp_scaled = true
		return
	_hp_scaled = true
	var was := float(boss.get(&"hp_max"))
	boss.set(&"hp_max", was * scale)
	boss.set(&"hp", float(boss.get(&"hp")) * scale)
	var cores := 0
	for core in boss.get_tree().get_nodes_in_group(&"boss_core"):
		if not is_instance_valid(core) or not ("hp_max" in core):
			continue
		core.set(&"hp_max", float(core.get(&"hp_max")) * scale)
		core.set(&"hp", float(core.get(&"hp")) * scale)
		cores += 1
	print("FLOWDBG --%s=%.3f applied to the titan: %.0f -> %.0f HP, %d cores"
			% [HP_SCALE_FLAG, scale, was, was * scale, cores])


## A capture's camera verdict, from `FlowDebugView._save` (r4 brief item 4) — the report owns the list.
func note_camera(shot_name: String, verdict: String, at: Vector3, open: float, who: String,
		md5: String, subject: String) -> void:
	_log.note_camera(shot_name, verdict, at, open, who, md5, subject)


## The pacing table, the camera verdicts and the weapon tally (`flow_debug_report.gd`).
func _report() -> void:
	_log.report((_flow.call(&"spires_down") as Array).size(), _t)


func _hurt(args: Array) -> void:
	if args.size() < 2:
		push_error("FlowDebug: hurt_spire needs [index, amount]")
		return
	var spire := _spire(int(args[0]))
	var hit := HitInfo.make(float(args[1]), HitInfo.BALLISTIC, Game.player, &"debug")
	hit.hurtbox_part = StringName(args[2]) if args.size() > 2 else &"pod_0"
	spire.take_hit(hit)


## The REAL death path: one `HitInfo` through `PlayerMech.take_hit` per tick until the mech is down, so
## `_apply_damage` runs, the death clip plays and the game emits `Events.player_died` itself. It is a
## BLOCK (`args = [give_up_s]`, default 10) rather than one shot because the real path can legitimately
## refuse a hit — the drop-in landing and every respawn grant i-frames, and `take_hit` returns early
## inside them. That is exactly what a ripper has to wait out too. `die` writes hp directly and is a
## repro only; without `--god` this is indistinguishable from an enemy landing the killing blow.
func _lethal_tick() -> bool:
	var player := Game.player
	if player == null or not player.has_method(&"take_hit"):
		push_error("FlowDebug: lethal needs a PlayerMech")
		return true
	if float(player.get(&"hp")) <= 0.0:
		return true
	var hit := HitInfo.make(float(player.get(&"hp_max")) * 10.0, HitInfo.EXPLOSIVE, null,
			&"debug_lethal")
	hit.position = player.global_position
	player.call(&"take_hit", hit)
	return float(player.get(&"hp")) <= 0.0


## Film a hive's collapse for the trailer (r5 brief item 8). `kill_spire` and a real kill run the same
## `FlowHiveCollapse`, and this takes `frames` shots `gap` seconds apart through it, so the contact
## sheet in the status is the whole beat and not one lucky frame. It is a BLOCK: the script waits for
## every frame to reach the disk. `args = [spire, frames, gap]`, default `[0, 8, 0.25]`.
func _film_collapse(args: Array) -> void:
	var spire := _spire(int(args[0]) if not args.is_empty() else 0)
	if spire == null:
		return
	_film_left = maxi(int(args[1]) if args.size() > 1 else 8, 1)
	_film_gap = float(args[2]) if args.size() > 2 else 0.25
	_film_step = 0
	_film_t = 0.0
	_film_tag = String(spire.spire_id)
	# The script destroys this spire, so the tally must not read it as a weapon kill — the same rule
	# `kill_spire` follows (r5 brief item 7).
	_log.note_fallback(spire.spire_id)
	spire.collapse()
	_block = &"film"
	_block_arg = null
	_block_limit = float(_film_left) * (_film_gap + SHOT_LIMIT)
	_block_t = _block_limit


## One frame of the film: wait out the gap, ask for the shot, and hold until it is on disk.
func _film_tick(delta: float) -> bool:
	if _view.saving:
		return false
	if _film_left <= 0:
		return true
	_film_t -= delta
	if _film_t > 0.0:
		return false
	_film_t = _film_gap
	_film_left -= 1
	_view.shot("%s_collapse_%02d" % [_film_tag, _film_step])
	_film_step += 1
	return false


## A REAL `ui_accept` on the menus page. `Input.action_press` only sets the action state, and the
## menus read the EVENT in `Node._input`, so the run has to parse one the way the OS would — this is
## the RETRY the checkpoint matrix presses, not a call into flow's own `respawn()` (r5 rules).
func _accept() -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = &"ui_accept"
		ev.pressed = pressed
		Input.parse_input_event(ev)


## Push the titan into phase `n` through its OWN damage pipeline: the pool is set just above the
## threshold and one real `take_hit` lands, so `Events.boss_phase` is emitted by the boss itself and
## the flow writes the `boss_p<n>` checkpoint the same way a player's damage would.
func _boss_phase(args: Array) -> void:
	var boss := get_tree().get_first_node_in_group(&"boss") as Node
	if boss == null or not ("hp" in boss and "hp_max" in boss):
		push_error("FlowDebug: boss_phase needs a titan in the tree")
		return
	var want := clampi(int(args[0]) if not args.is_empty() else 2, 2, BossTuning.PHASE_COUNT)
	boss.set(&"hp", float(boss.get(&"hp_max")) * BossTuning.phase_fraction(want) + 1.0)
	var hit := HitInfo.make(10.0, HitInfo.EXPLOSIVE, Game.player, &"debug_phase")
	hit.position = (boss as Node3D).global_position
	boss.call(&"take_hit", hit)


## One line of everything the checkpoint matrix has to prove, so a run's log is the evidence: the
## state, HP/EN, how far the lens is from the hero, the objective line, the menus page and whether the
## HUD still thinks the mech is alive.
func _probe() -> void:
	var player := Game.player
	var eye := FlowDebugView.eye()
	var menus := Game.hud.get(&"menus") as Node if Game.hud != null else null
	var hud := player.call(&"hud_state") as Dictionary if player != null \
			and player.has_method(&"hud_state") else {}
	print("FLOWPROBE state=%s hp=%.0f/%.0f en=%.0f cam=%.0fm page=%s alive=%s at=%.0f,%.0f,%.0f"
			% [_flow.call(&"state_name"),
			float(player.get(&"hp")) if player != null else 0.0,
			float(player.get(&"hp_max")) if player != null else 0.0,
			float(player.get(&"energy")) if player != null else 0.0,
			eye.distance_to(player.global_position) if player != null else -1.0,
			str(int(menus.get(&"page"))) if menus != null else "-",
			str(bool(hud.get("alive", false))),
			player.global_position.x if player != null else 0.0,
			player.global_position.y if player != null else 0.0,
			player.global_position.z if player != null else 0.0])


func _heal() -> void:
	var player := Game.player
	if player == null:
		return
	player.call(&"heal", float(player.get(&"hp_max")))
	player.call(&"add_energy", float(player.get(&"energy_max")))


func _spire(index: int) -> FlowHiveSpire:
	var list := _flow.call(&"spires") as Array
	if index < 0 or index >= list.size():
		push_error("FlowDebug: no spire %d of %d" % [index, list.size()])
		return null
	return list[index] as FlowHiveSpire
