class_name FlowProgress
extends Node
## Objectives, checkpoints and respawn — the bookkeeping half of the flow, split out of `game_flow.gd`
## so the state machine stays readable. It owns the hive spires, the destroyed set, the objective line
## and the run clock, and tells `GameFlow` what happened through signals; GameFlow owns what each
## state MEANS and is the only thing that changes `state`.

signal spire_destroyed(id: StringName, count: int)
signal all_spires_down()
signal objective_changed(text: String)
signal respawned(state: StringName)

const SPIRE_SCENE := "res://flow/hive_spire.tscn"
const SPIRE_TOTAL := 3
const RESPAWN_GRACE := 2.0        ## s of i-frames after a respawn
## The cockpit lines for spire 1, 2 and 3 (audio unit, SPEC §8: 「蚀巢已摧毁 n/3」).
const SPIRE_VOICE: Array[StringName] = [&"ai_spire_down_1", &"ai_spire_down_2", &"ai_spire_down_3"]

var director: FlowEncounterDirector = null

var _spires: Array[FlowHiveSpire] = []
var _spire_arenas: Array[StringName] = []
var _down: Array[StringName] = []
var _checkpoint: FlowCheckpoint = null
var _objective: String = ""
var _hint: String = ""
var _run_time: float = 0.0
var _published: int = -1


## Instances the world's hive spires (or the sandbox three) and wires their `destroyed` signal.
## Returns the arena ids that hold a spire, so the encounter director can make those fights louder.
func build_spires() -> Array[StringName]:
	var packed := load(SPIRE_SCENE) as PackedScene
	if packed == null:
		push_error("FlowProgress: cannot load " + SPIRE_SCENE)
		return _spire_arenas
	for row in FlowWorld.hives():
		var spire := packed.instantiate() as FlowHiveSpire
		if spire == null:
			push_error("FlowProgress: the hive spire scene root is not a FlowHiveSpire")
			return _spire_arenas
		spire.height = float(row["height"])
		spire.setup(row["id"], row["arena"])
		spire.position = row["pos"]
		add_child(spire)
		adopt(spire)
	return _spire_arenas


## Takes ownership of a spire: it counts towards the objective and its fall writes the checkpoint and
## the contract signal. `build_spires` places the map's three; a scripted sequence (or a test) can
## hand over one of its own.
func adopt(spire: FlowHiveSpire) -> void:
	if spire == null or spire in _spires:
		return
	spire.destroyed.connect(_on_spire_destroyed)
	_spires.append(spire)
	if not spire.arena_id in _spire_arenas:
		_spire_arenas.append(spire.arena_id)


func spires() -> Array[FlowHiveSpire]:
	return _spires.duplicate()


func spires_down() -> Array[StringName]:
	return _down.duplicate()


func checkpoint() -> FlowCheckpoint:
	return _checkpoint


func run_time() -> float:
	return _run_time


func tick(delta: float) -> void:
	_run_time += delta
	if int(_run_time) != _published:
		_published = int(_run_time)
		_publish_time()


## The victory page is built by the menus on `Events.game_won`, which the HUD hears before flow does, so
## the clock is kept in their stats as the run goes: it is then never more than a second stale and it is
## the unscaled number, not the menus' own scaled accumulation (audit #4).
func _publish_time() -> void:
	if Game.hud == null:
		return
	var menus := Game.hud.get(&"menus") as Node
	if menus == null:
		return
	var stats := menus.get(&"stats") as Dictionary
	if stats != null:
		stats["time"] = _run_time


# --- spires ---------------------------------------------------------------------------------------

func _on_spire_destroyed(spire: FlowHiveSpire) -> void:
	if spire.spire_id in _down:
		return
	_down.append(spire.spire_id)
	var n := _down.size()
	if director != null:
		director.set_spires_down(n)
	_hud_spires(n)
	Audio.voice(SPIRE_VOICE[mini(n, SPIRE_TOTAL) - 1], 88.0, 2.4)
	_titan_roar(spire.global_position)
	_time_of_day(n)
	# CONTRACTS §6: the contract signal the boss's skyline walker roars on. Flow's own signal carries
	# the same beat for the objective line and the checkpoint.
	Events.spire_destroyed.emit(spire, n, SPIRE_TOTAL)
	spire_destroyed.emit(spire.spire_id, n)
	if n >= SPIRE_TOTAL:
		all_spires_down.emit()


## The Titan answers every fallen spire (SPEC §8): the boss unit owns the beast, so flow only asks it
## to roar when it is there and plays the sound either way.
func _titan_roar(from: Vector3) -> void:
	for node in get_tree().get_nodes_in_group(&"boss"):
		if node.has_method(&"roar"):
			node.call(&"roar")
	Feel.play(&"boss_roar", from)
	Audio.voice(&"ai_titan_roar", 60.0, 2.0)


## city-art's TimeOfDay hook (brief §3): each spire pushes the district a third of the way to the
## storm light the boss fight is lit by.
func _time_of_day(count: int) -> void:
	for node in get_tree().get_nodes_in_group(&"time_of_day"):
		if node.has_method(&"set_progress"):
			node.call(&"set_progress", float(count) / float(SPIRE_TOTAL))


func _hud_spires(done: int) -> void:
	if Game.hud == null:
		return
	var data := Game.hud.get(&"data") as Object
	if data != null and data.has_method(&"set_spires"):
		data.call(&"set_spires", done, SPIRE_TOTAL)


# --- objective line -------------------------------------------------------------------------------

func set_hint(text: String) -> void:
	_hint = text
	_emit()


func hint() -> String:
	return _hint


## `line` is the state's own objective ("" when the state has none); the district line is generated
## here because it is the only one that counts.
func refresh_objective(state: StringName, line: String) -> void:
	_objective = ("摧毁蚀巢 %d/%d  DESTROY THE HIVE SPIRES" % [_down.size(), SPIRE_TOTAL]) \
			if state == &"district" else line
	_emit()


func _emit() -> void:
	objective_changed.emit(_objective if _hint == "" else "%s   ·   %s" % [_objective, _hint])


# --- checkpoints and respawn ----------------------------------------------------------------------

func save(id: StringName, resume_state: StringName, phase: int) -> void:
	var at := Game.player.global_transform if Game.player != null else Transform3D.IDENTITY
	_write(FlowCheckpoint.make(id, at, resume_state, _down, _run_time, phase, {}, _done_arenas()))


## A checkpoint at a PROBED point rather than wherever the hero happens to be (r5 brief item 2). The
## boss's three phases all save the fighting-floor point: the live transform when a phase changes can
## be mid-air on the catapult arc, or wedged between two deck rings, and RETRY then strands the hero.
## `floor_at` is a point ON the floor; the capsule's half height is added here, and the facing is
## turned towards `look` so the camera snaps behind a mech that is already looking at the fight.
func save_at(id: StringName, resume_state: StringName, phase: int, floor_at: Vector3,
		look: Vector3) -> void:
	var lift := FlowBounds.half_height(Game.player) if Game.player != null else FlowBounds.HALF_HEIGHT
	var at := floor_at + Vector3.UP * lift
	var to := look - at
	to.y = 0.0
	var basis := Basis.IDENTITY
	if to.length() > 0.01:
		basis = Basis(Vector3.UP, atan2(-to.x, -to.z))
	_write(FlowCheckpoint.make(id, Transform3D(basis, at), resume_state, _down, _run_time, phase,
			{}, _done_arenas()))


func _done_arenas() -> Array[StringName]:
	return director.arenas_done() if director != null else [] as Array[StringName]


func _write(cp: FlowCheckpoint) -> void:
	_checkpoint = cp


## SPEC §7.1 / brief §1: respawn at the last checkpoint with full HP and EN, the spires that were
## down stay down and the ones that were standing come back whole. An arena the player had already
## finished stays finished and empty — only the unfinished ones rewind, so RETRY never re-arms a
## cleared yard or a fallen hive's arena (r5 brief item 6). Returns the state to resume in.
##
## `fallback_at` / `fallback_state` are the answer to "what if there is no checkpoint yet": a death
## before the district opens used to be a soft-lock, so the caller always hands over the drop-in
## landing and the tutorial. An empty return therefore means the caller passed nothing — never that a
## respawn was refused.
func respawn(fallback_at: Transform3D = Transform3D.IDENTITY,
		fallback_state: StringName = &"") -> StringName:
	var cp := _checkpoint
	if cp == null:
		if fallback_state == &"":
			push_warning("FlowProgress: no checkpoint and no fallback, respawn ignored")
			return &""
		push_error("FlowProgress: no checkpoint yet — respawning at the drop-in landing")
		cp = FlowCheckpoint.make(&"start", fallback_at, fallback_state, _down, _run_time, 0)
		_checkpoint = cp
	_down = cp.spires_down.duplicate()
	_run_time = cp.elapsed
	for spire in _spires:
		if not spire.spire_id in _down:
			spire.reset_full()
	if director != null:
		director.set_spires_down(_down.size())
		var keep := _kept_arenas(cp)
		for arena: StringName in director.arena_ids():
			if arena in keep:
				director.keep_arena_done(arena)
			else:
				director.reset_arena(arena)
	_hud_spires(_down.size())
	_restore_player(cp.at)
	_restore_boss(cp.boss_phase)
	respawned.emit(cp.flow_state)
	return cp.flow_state


## SPEC §7.1: a boss-phase checkpoint resumes that phase, not the one the death happened in. The boss
## owns the fight, so flow hands it the phase and lets it do the work — duck-typed like `roar`, because
## a new `Events` signal would be the lead's (lead r16 decision 4). The restore used to run on
## `Events.player_died` inside the boss unit, which put the hero back on its feet under the MECH
## DESTROYED page (r5 brief item 4).
func _restore_boss(phase: int) -> void:
	if phase <= 0:
		return
	for node in get_tree().get_nodes_in_group(&"boss_director"):
		if node.has_method(&"restore_for_phase"):
			node.call(&"restore_for_phase", phase)


## The arenas a respawn must not re-arm: the ones finished when the checkpoint was written, plus the
## arena of every hive that is down (its fight is over whatever the wave machine recorded).
func _kept_arenas(cp: FlowCheckpoint) -> Array[StringName]:
	var keep := cp.arenas_done.duplicate()
	for spire in _spires:
		if spire.spire_id in cp.spires_down and not spire.arena_id in keep:
			keep.append(spire.arena_id)
	return keep


## PAUSE → ABORT (r5 brief item 5): the mission is over. Every spire stands again, the counter reads
## 0/3, the arenas re-arm and the checkpoint is gone, so START from the title is a fresh run.
func reset_run() -> void:
	_down.clear()
	_checkpoint = null
	_run_time = 0.0
	_published = -1
	for spire in _spires:
		spire.reset_full()
	if director != null:
		director.set_spires_down(0)
		for arena: StringName in director.arena_ids():
			director.reset_arena(arena)
	_hud_spires(0)
	set_hint("")


## The checkpoint's transform is the whole answer, not just its origin: the rig takes the hero's yaw
## when it snaps (`camera_rig.gd` `snap_to_player`), so a respawn that only moved the mech left the
## view easing across the city from wherever the player died (r5 brief item 1).
func _restore_player(at: Transform3D) -> void:
	var player := Game.player
	if player == null:
		return
	player.set(&"velocity", Vector3.ZERO)
	player.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)
	player.set(&"hp", player.get(&"hp_max"))
	player.call(&"heal", float(player.get(&"hp_max")))
	player.call(&"add_energy", float(player.get(&"energy_max")))
	player.call(&"invulnerable_for", RESPAWN_GRACE)
	var rig := Game.camera_rig
	if rig != null and is_instance_valid(rig) and rig.has_method(&"snap_to_player"):
		rig.call(&"snap_to_player")
