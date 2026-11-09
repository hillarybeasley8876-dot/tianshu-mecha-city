class_name FlowEncounterDirector
extends Node3D
## Runs the district's fights (brief §2). Every arena of the live world (CONTRACTS §7) gets a trigger
## zone and a wave list from `res://flow/encounters/<arena>.json`; waves start on entering the arena,
## when half the previous wave is dead (dossier rule 6 — the next wave overlaps the current one), when
## it is cleared, or on a timer. Between arenas, roaming packs and the Harrier patrol keep the district
## alive, and everything scales with the number of spires already down.
##
## Hard budget: 40 enemies alive (CONTRACTS §2). A wave that would break it is trimmed, not dropped,
## and the trim is reported once.

signal arena_started(arena_id: StringName)
signal arena_cleared(arena_id: StringName)
signal intensity_changed(level: float)

const BUDGET := 40
const TICK_HZ := 10.0             ## wave-machine rate (lead r3: flow stays under 1 ms of the frame)
const ROAM_ID := &"roam"
## SPEC §8 music curve: nothing happening 0.0, contact 0.5, a spire fight 0.8 (GameFlow owns the rest).
const INTENSITY_IDLE := 0.0
const INTENSITY_CONTACT := 0.5
const INTENSITY_SPIRE := 0.8
## Roaming packs come from behind most of the time (juice §11.2: 75 %).
const BEHIND_BIAS := 0.75
## Half-extent of the city's ground (MAP §1: the terrain tiles stop at ±700 m) and the slack kept
## inside it, so a roaming pack never lands past the edge where there is no navmesh and no floor.
const MAP_HALF := 700.0
const SPAWN_MARGIN := 30.0
const ROAM_FILE := "res://flow/encounters/roam.json"

var spires_down: int = 0
var enabled: bool = true
## Test seam: when set, `_spawn_group` calls this instead of the enemies unit's spawner, so the wave
## machine can be exercised headless. Signature: `func(type, at, count) -> Array[Node3D]`.
var spawn_hook: Callable = Callable()

var _arenas: Dictionary = {}        ## arena_id -> arena state
var _roam: Array[Dictionary] = []
var _roam_t: Dictionary = {}       ## pack id -> seconds until the next one
var _roam_live: Array[Node3D] = []
var _intensity: float = INTENSITY_IDLE
var _tick_t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20261101


## Build the zones from the live world's arenas (CONTRACTS §7). `spire_arenas` are the arena ids that
## hold a hive (their fights are louder).
func build(spire_arenas: Array[StringName]) -> void:
	for row in FlowWorld.arenas():
		# A Dictionary boxes its values, so the typed arrays have to be rebuilt here rather than cast.
		var parts: Array[PackedVector3Array] = []
		for part: PackedVector3Array in row["parts"] as Array:
			parts.append(part)
		var sockets: Array[Dictionary] = []
		for socket: Dictionary in row["sockets"] as Array:
			sockets.append(socket)
		_add_arena(row["id"] as StringName, parts, float(row["lo"]), float(row["hi"]), sockets,
				row["centre"] as Vector3, StringName(row["id"]) in spire_arenas)
	_load_roam()


func _add_arena(id: StringName, parts: Array[PackedVector3Array], lo: float, hi: float,
		sockets: Array[Dictionary], centre: Vector3, hosts_spire: bool) -> void:
	var waves := FlowEncounterWaves.waves(id)
	if waves.is_empty():
		return
	var zone := FlowArenaZone.new()
	add_child(zone)
	zone.build(id, parts, lo, hi)
	zone.entered.connect(_on_arena_entered)
	zone.exited.connect(_on_arena_exited)
	var table: Dictionary = {}
	for s in sockets:
		table[s["id"]] = s["pos"]
	_arenas[id] = {"zone": zone, "sockets": table, "waves": waves, "index": 0, "live": [],
			"active": false, "done": false, "timer": 0.0, "elapsed": 0.0, "spire": hosts_spire,
			"centre": centre, "floor": lo}


## Sandbox: one flat arena around the spawn so the tutorial waves can be exercised before the city
## exists (brief §5).
func build_sandbox(centre: Vector3, radius: float) -> void:
	var waves := FlowEncounterWaves.waves(&"sandbox")
	if waves.is_empty():
		return
	var zone := FlowArenaZone.new()
	add_child(zone)
	zone.build_box(&"sandbox", centre, radius, 120.0)
	_load_roam()
	zone.entered.connect(_on_arena_entered)
	zone.exited.connect(_on_arena_exited)
	_arenas[&"sandbox"] = {"zone": zone, "sockets": {}, "waves": waves, "index": 0, "live": [],
			"active": false, "done": false, "timer": 0.0, "elapsed": 0.0, "spire": true,
			"centre": centre, "floor": centre.y - 40.0}


# --- wave machine ---------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# 10 Hz is plenty for a wave machine (lead r3: flow must stay under 1 ms of the frame): the
	# conditions it tests are "half of that wave is dead" and "this many seconds have passed".
	_tick_t += delta
	if _tick_t < 1.0 / TICK_HZ:
		return
	var step := _tick_t
	_tick_t = 0.0
	tick(step)


## One step of the wave machine. Public so tests can drive it without a running tree.
func tick(delta: float) -> void:
	if not enabled:
		return
	for id: StringName in _arenas:
		_tick_arena(id, delta)
	_tick_roam(delta)
	_update_intensity()


func _tick_arena(id: StringName, delta: float) -> void:
	var a := _arenas[id] as Dictionary
	var live := _prune(a["live"] as Array)
	a["live"] = live
	a["elapsed"] = float(a["elapsed"]) + delta
	if not bool(a["active"]):
		return
	var waves := a["waves"] as Array
	var index := int(a["index"])
	if index < waves.size():
		if _ready_to_start(a, (waves[index] as Dictionary)["start"] as Dictionary, live):
			_start_wave(id, a, waves[index] as Dictionary)
		return
	if live.is_empty() and not bool(a["done"]):
		a["done"] = true
		a["active"] = false
		Events.encounter_cleared.emit(id)
		arena_cleared.emit(id)


## Dossier rule 6: the next wave starts halfway through the current one. A wave that could not spawn
## anything (no spawner, budget spent) never blocks the arena — the next condition is treated as met.
func _ready_to_start(a: Dictionary, start: Dictionary, live: Array) -> bool:
	var spawned := int(a.get("wave_size", 0))
	match StringName(start.get("kind", &"on_enter")):
		&"previous_half":
			if spawned <= 0:
				return int(a["index"]) > 0
			return live.size() <= int(ceil(float(spawned) * 0.5))
		&"previous_cleared":
			if spawned <= 0:
				return int(a["index"]) > 0
			return live.is_empty()
		&"timer":
			return float(a["elapsed"]) >= float(a.get("wave_end", 0.0)) + float(start.get("delay", 0.0))
		_:
			return spawned == 0


func _start_wave(id: StringName, a: Dictionary, wave: Dictionary) -> void:
	var live := a["live"] as Array
	var sockets := a["sockets"] as Dictionary
	var centre := a["centre"] as Vector3
	var total := 0
	for group: Dictionary in wave["groups"] as Array:
		var count := mini(FlowEncounterWaves.group_count(group, spires_down), budget_left())
		if count <= 0:
			continue
		var at: Vector3 = sockets.get(group.get("socket", &""), centre) as Vector3
		at = FlowSpawner.ground_snap(self, at, float(a["floor"]))
		for e in _spawn_group(group["type"], at, count):
			live.append(e)
			total += 1
	a["index"] = int(a["index"]) + 1
	a["wave_size"] = total
	a["wave_end"] = float(a["elapsed"])


func _spawn_group(type: StringName, at: Vector3, count: int) -> Array[Node3D]:
	if spawn_hook.is_valid():
		var made: Array[Node3D] = []
		for e: Variant in spawn_hook.call(type, at, count) as Array:
			made.append(e as Node3D)
		return made
	return FlowSpawner.spawn_ring(FlowSpawner.get_spawner(self), type, at, count,
			FlowEncounterWaves.GROUP_SPREAD, _rng.randf())


## Test and tool hook: run a roaming pack's timer down (all of them when `id` is empty) so the next
## tick sends it.
func arm_roam(id: StringName = &"") -> void:
	if id != &"":
		_roam_t[id] = 0.0
		return
	for key: StringName in _roam_t:
		_roam_t[key] = 0.0


## CONTRACTS §2: never more than 40 enemies with AI. A wave that would break the budget is trimmed.
func budget_left() -> int:
	if spawn_hook.is_valid():
		return maxi(BUDGET - live_count(), 0)
	var spawner := FlowSpawner.get_spawner(self)
	var alive := 0
	if spawner != null and spawner.has_method(&"alive_count"):
		alive = int(spawner.call(&"alive_count"))
	else:
		alive = live_count()
	return maxi(BUDGET - alive, 0)


func _on_arena_entered(id: StringName) -> void:
	var a := _arenas.get(id) as Dictionary
	if a == null or bool(a["done"]):
		return
	if not bool(a["active"]):
		a["active"] = true
		a["elapsed"] = 0.0
		Events.encounter_started.emit(id)
		arena_started.emit(id)


func _on_arena_exited(id: StringName) -> void:
	var a := _arenas.get(id) as Dictionary
	if a != null and int(a["index"]) == 0:
		a["active"] = false


# --- roaming packs -------------------------------------------------------------------------------

func _load_roam() -> void:
	var path := ROAM_FILE
	if not FileAccess.file_exists(path):
		push_warning("FlowEncounterDirector: no roaming table at %s" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("FlowEncounterDirector: %s is not a JSON object" % path)
		return
	for row: Variant in (parsed as Dictionary).get("packs", []):
		var p := row as Dictionary
		if p == null or not EnemyTypes.is_type(StringName(p.get("type", ""))):
			continue
		_roam.append(p)
		_roam_t[StringName(p.get("id", ""))] = float(p.get("first_delay", p.get("interval", 45.0)))


func _tick_roam(delta: float) -> void:
	_prune(_roam_live)
	var player := Game.player
	if player == null or _roam.is_empty() or _any_arena_active():
		return
	for p in _roam:
		var id := StringName(p.get("id", ""))
		_roam_t[id] = float(_roam_t.get(id, 0.0)) - delta
		if float(_roam_t[id]) > 0.0:
			continue
		_roam_t[id] = float(p.get("interval", 45.0))
		if spires_down < int(p.get("min_spires", 0)):
			continue
		if _roam_live.size() >= int(p.get("max_alive", 8)):
			continue
		_spawn_pack(p, player)


## A pack arrives out of sight and mostly from behind (juice §11.2), 160–320 m out — but always on
## ground that exists. The terrain ends at ±`MAP_HALF`, and a monster placed past it has no navmesh and
## no floor: it falls forever, keeps counting against the budget and pins the music at contact
## (audit #3). The point is clamped inside the map, snapped onto the ground, and if even that finds
## nothing the spawner is asked for a navmesh point near the player instead.
func _spawn_pack(p: Dictionary, player: Node3D) -> void:
	var count := mini(int(p.get("count", 4)), budget_left())
	if count <= 0:
		return
	var bearing := _rng.randf() * TAU
	if _rng.randf() < BEHIND_BIAS:
		var back := player.global_basis.z
		bearing = atan2(back.z, back.x) + (_rng.randf() - 0.5) * 1.6
	var dist := lerpf(float(p.get("min_range", 160.0)), float(p.get("max_range", 320.0)), _rng.randf())
	var want := player.global_position + Vector3(cos(bearing), 0.0, sin(bearing)) * dist
	var limit := MAP_HALF - FlowEncounterWaves.GROUP_SPREAD - SPAWN_MARGIN
	var at := Vector3(clampf(want.x, -limit, limit), want.y, clampf(want.z, -limit, limit))
	var snapped := FlowSpawner.snap_to_ground(self, at)
	if snapped == Vector3.INF:
		at = _navmesh_fallback(player, bearing)
	else:
		at = snapped
	_roam_live.append_array(_spawn_group(StringName(p["type"]), at, count))


## Nowhere to stand at the wanted point: let the enemies unit find a reachable one near the player
## (`place_around` path-checks against the navmesh), or stay at the clamped point when there is no
## spawner to ask.
func _navmesh_fallback(player: Node3D, bearing: float) -> Vector3:
	var spawner := FlowSpawner.get_spawner(self)
	if spawner != null and spawner.has_method(&"place_around"):
		return spawner.call(&"place_around", player.global_position, bearing / TAU) as Vector3
	return player.global_position


func _any_arena_active() -> bool:
	for id: StringName in _arenas:
		if bool((_arenas[id] as Dictionary)["active"]):
			return true
	return false


# --- music + housekeeping -------------------------------------------------------------------------

func _update_intensity() -> void:
	var level := INTENSITY_IDLE
	for id: StringName in _arenas:
		var a := _arenas[id] as Dictionary
		if not bool(a["active"]) or (_prune(a["live"] as Array)).is_empty():
			continue
		level = maxf(level, INTENSITY_SPIRE if bool(a["spire"]) else INTENSITY_CONTACT)
	if level == INTENSITY_IDLE and not _roam_live.is_empty():
		level = INTENSITY_CONTACT
	if not is_equal_approx(level, _intensity):
		_intensity = level
		intensity_changed.emit(level)


func intensity() -> float:
	return _intensity


func set_spires_down(count: int) -> void:
	spires_down = clampi(count, 0, 3)


## Test and respawn hook: forget an arena's progress and kill what it still has on the field.
func reset_arena(id: StringName, kill_live: bool = true) -> void:
	var a := _arenas.get(id) as Dictionary
	if a == null:
		return
	if kill_live:
		for e in _prune(a["live"] as Array):
			if is_instance_valid(e):
				e.queue_free()
	a["live"] = []
	a["index"] = 0
	a["wave_size"] = 0
	a["wave_end"] = 0.0
	a["elapsed"] = 0.0
	a["active"] = false
	a["done"] = false


## The arenas the player has finished, so a checkpoint can carry the set (r5 brief item 6).
func arenas_done() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _arenas:
		if bool((_arenas[id] as Dictionary)["done"]):
			out.append(id)
	return out


## Respawn hook for an arena that was already finished: it stays finished and empty. Nothing rewinds
## it and nothing is announced, so re-entering it (or respawning inside it, which both district
## checkpoints do) can never restart its waves (r5 brief item 6).
func keep_arena_done(id: StringName) -> void:
	var a := _arenas.get(id) as Dictionary
	if a == null:
		return
	for e in _prune(a["live"] as Array):
		if is_instance_valid(e):
			e.queue_free()
	a["live"] = []
	a["index"] = (a["waves"] as Array).size()
	a["wave_size"] = 0
	a["wave_end"] = 0.0
	a["elapsed"] = 0.0
	a["active"] = false
	a["done"] = true


func arena_state(id: StringName) -> Dictionary:
	return _arenas.get(id, {}) as Dictionary


## Tool and test hook (`flow_debug clear_arena`): the arena is over now — kill what is on the field,
## stop the waves and announce it, exactly as if the player had finished it.
func force_clear(id: StringName) -> void:
	var a := _arenas.get(id) as Dictionary
	if a == null:
		push_warning("FlowEncounterDirector: no arena '%s' to clear" % id)
		return
	reset_arena(id)
	a["index"] = (a["waves"] as Array).size()
	a["done"] = true
	Events.encounter_cleared.emit(id)
	arena_cleared.emit(id)


func arena_ids() -> Array:
	return _arenas.keys()


func live_count() -> int:
	var total := _roam_live.size()
	for id: StringName in _arenas:
		total += (_arenas[id]["live"] as Array).size()
	return total


func _prune(list: Array) -> Array:
	for i in range(list.size() - 1, -1, -1):
		var e := list[i] as Node3D
		if not is_instance_valid(e) or (e.has_method(&"is_alive") and not bool(e.call(&"is_alive"))):
			list.remove_at(i)
	return list
