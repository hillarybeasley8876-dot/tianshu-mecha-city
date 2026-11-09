class_name BossDirector
extends Node3D
## Owns the Brood Titan fight end to end (boss unit): the skyline walker from the first frame, the
## arena, the intro climb, the phase roars, the death beat and the phase checkpoints.
##
## Instanced by `main.tscn` alongside the other optional parts (see status/boss.md request 1) and by
## the showcase scene. Launch flags it honours: `--boss-test` builds the Crown arena and drops
## straight into the fight in the sandbox, which is how every unit's balance work runs before the
## city exists.

## Shot `t` is the START time in the cinematic, not its length (CONTRACTS §5 / camera_cinematic.gd),
## and the rig captures its hard target when the request goes in — so the boss locks the camera on
## itself before asking for a cut, or the duel frame collapses to 10 m in front of the hero.
const PHASE_SHOTS: Array[Dictionary] = [
	{"offset": Vector3(58.0, 26.0, 46.0), "fov": 46.0, "t": 0.0},
]
## The death beat in two shots: tight while the blast chain walks up the body, then wide for the
## topple over the rim and the storm breaking.
const DEATH_SHOTS: Array[Dictionary] = [
	{"offset": Vector3(58.0, 26.0, 42.0), "fov": 55.0, "t": 0.0},
	{"offset": Vector3(0.0, 80.0, 170.0), "fov": 42.0, "t": 1.6},
]

var titan: BroodTitan = null
var walker: SkylineWalker = null
var arena: BossArena = null
var fight_started: bool = false

var _warned_arena: bool = false
var _death_left: float = 0.0
var _won: bool = false
var _check_left: float = 0.0


func _ready() -> void:
	add_to_group(&"boss_director")
	Events.game_won.connect(_on_game_won)
	Events.spire_destroyed.connect(_on_spire_destroyed)
	_boot.call_deferred()


func _boot() -> void:
	while not Game.world_built():
		await get_tree().physics_frame
	var parent := Game.world if Game.world != null and is_instance_valid(Game.world) else self
	if _wants_walker():
		walker = SkylineWalker.spawn(parent, Vector3.ZERO, 0.12)
	# One line, because "is the titan on the horizon in this run?" is the first question every
	# capture and every free-play smoke test asks (CONTRACTS §2).
	print("BOSS skyline walker: %s" % ("on the ring" if walker != null else "off (free play)"))
	if Game.has_flag("boss-test"):
		_build_test_arena()


## CONTRACTS §2: `--sandbox` is FREE PLAY — a unit test walking the grey box must not have a titan
## on the horizon. `--flow` (flow's own scripted runs) and `--boss-test` ask for it explicitly, and
## the real map always has it from the first frame.
func _wants_walker() -> bool:
	return walker_wanted(Game.has_flag("sandbox"), Game.has_flag("flow"), Game.has_flag("boss-test"))


## The same rule without the command line, so the suite can check it (CONTRACTS §2).
static func walker_wanted(sandbox: bool, flow: bool, boss_test: bool) -> bool:
	return not sandbox or flow or boss_test


## SPEC §8.3: the beast on the horizon answers every fallen spire itself. Flow also calls `roar()` on
## group `&"boss"` for the fight itself, so this only has to cover the pre-fight walker.
func _on_spire_destroyed(_spire: Node3D, _down: int, _total: int) -> void:
	if walker != null and is_instance_valid(walker):
		walker.roar()


## `--boss-test`: the real Crown geometry on the sandbox plateau, so the fight can be balanced and
## captured before the city lands (brief §7).
func _build_test_arena() -> void:
	if arena != null:
		return
	arena = BossArena.new()
	arena.name = "BossArena"
	var at := _test_spawn()
	arena.position = at
	var parent := Game.world if Game.world != null and is_instance_valid(Game.world) else self
	parent.add_child(arena)
	start_fight()


## A flat spot for the test arena: the `--boss-at=x,y,z` flag if given, else above the player spawn.
func _test_spawn() -> Vector3:
	var spec := Game.flag("boss-at")
	if spec != "":
		var v := spec.split(",")
		if v.size() >= 3:
			return Vector3(float(v[0]), float(v[1]), float(v[2]))
		push_error("BossDirector: --boss-at needs x,y,z, got '" + spec + "'")
	if Game.player != null and is_instance_valid(Game.player):
		return Vector3(Game.player.global_position.x, Game.player.global_position.y + 40.0,
				Game.player.global_position.z)
	return Vector3(0.0, 120.0, 0.0)


# --- fight lifecycle --------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _death_left > 0.0:
		_tick_death(delta)
		return
	if _check_left > 0.0:
		_check_left -= delta
		return
	if not fight_started:
		_check_left = 0.5
		_try_start()


## The fight starts when the player is on the Crown: the catapult lands them there, and the flow unit
## has already opened the gate. Height and radius, not a trigger volume, so it works with the city's
## geometry and with the sandbox arena alike.
func _try_start() -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	# Only a player who has climbed the Spire is anywhere near the fight: below this the director
	# stays completely quiet, so a free-play run on the sandbox never looks for a Crown.
	if player.global_position.y < BossTuning.CROWN_SEARCH_Y:
		return
	if arena == null:
		arena = _ensure_arena()
	if arena == null:
		if not _warned_arena:
			_warned_arena = true
			push_warning("BossDirector: the player is above %.0f m but this world has no Crown deck"
					% BossTuning.CROWN_SEARCH_Y)
		return
	var to := player.global_position - arena.global_position
	var flat := Vector2(to.x, to.z).length()
	if to.y < -30.0 or to.y > 160.0 or flat > BossTuning.DECK_RADIUS * 1.8:
		return
	start_fight()


## The city's Crown is built by city-blockout from the layout, so no `&"boss_arena"` node comes with
## it — but the director still owns the breakable rim and the catapult up there. Finds the deck and
## attaches a geometry-less arena to it. Returns null while the world has not built its Spire yet.
func _ensure_arena() -> BossArena:
	var found := get_tree().get_first_node_in_group(&"boss_arena") as BossArena
	if found != null:
		return found
	var at := _crown_centre()
	if at == Vector3.INF:
		return null
	var node := BossArena.new()
	node.name = "BossArena"
	node.build_geometry = not BossArena.world_has_crown(get_tree())
	node.position = at
	var parent := Game.world if Game.world != null and is_instance_valid(Game.world) else self
	parent.add_child(node)
	return node


## Where the Crown deck is, in order of how much the world can be trusted: the `spire` landmark
## marker the city builds from the layout, then the layout constant for the deck height.
## `Vector3.INF` = this world has no Spire (the sandbox), so there is no Crown to attach to.
func _crown_centre() -> Vector3:
	for node in get_tree().get_nodes_in_group(&"landmark"):
		var mark := node as Node3D
		if mark == null or StringName(mark.get_meta(&"landmark_id", &"")) != &"spire":
			continue
		var deck := float(mark.get_meta(&"crown_deck_z", BossTuning.DECK_Y))
		return Vector3(mark.global_position.x, deck, mark.global_position.z)
	return Vector3.INF


## Intro (brief §5): the titan climbs over the deck edge, roars, and the title card goes up as the
## HUD boss bar appears. The player is invulnerable for the whole beat.
func start_fight() -> void:
	if fight_started or arena == null:
		return
	fight_started = true
	arena.armed = true
	if walker != null and is_instance_valid(walker):
		walker.despawn()
		walker = null
	titan = _spawn_titan()
	if titan == null:
		fight_started = false
		return
	titan.core_broken.connect(_on_core_broken)
	titan.phase_changed.connect(_on_phase_changed)
	titan.death_started.connect(_on_death_started)
	Events.objective_changed.emit("巢母 BROOD TITAN")
	_lock_the_camera()
	get_tree().call_group(&"time_of_day", &"set_storm", 0.55, 4.0)
	Audio.music_intensity(1.0)
	_run_intro()


## The titan comes over the rim from below: spawned under the deck edge, then walked up onto it over
## the length of the `climb_over` clip (4.125 s in the rig data).
func _spawn_titan() -> BroodTitan:
	var scene := "res://enemies/boss/brood_titan.tscn"
	if not ResourceLoader.exists(scene):
		push_error("BossDirector: no boss scene at " + scene)
		return null
	var packed := load(scene) as PackedScene
	if packed == null:
		push_error("BossDirector: cannot load " + scene)
		return null
	var boss := packed.instantiate() as BroodTitan
	if boss == null:
		push_error("BossDirector: " + scene + " is not a BroodTitan")
		return null
	boss.name = "BroodTitan"
	var parent := Game.world if Game.world != null and is_instance_valid(Game.world) else self
	parent.add_child(boss)
	var rim := arena.ring_point(0.62, 0.92, 0.0)
	boss.global_position = rim + Vector3.DOWN * BossTuning.HEIGHT * 0.9
	boss.look_at_from_position(boss.global_position, arena.global_position, Vector3.UP)
	boss.set_ai_enabled(false)
	return boss


## The intro shots, built from the live gap between the hero and the climbing titan. Two traps the
## capture log caught: the duel frame's origin is the MIDPOINT (so a fixed offset aims at empty deck
## once the two are 150 m apart), and the titan spends the climb UNDER the deck rim — a camera on the
## deck cannot see it at all. Both shots that matter are therefore outside the rim (`-half` runs from
## the midpoint toward the titan, so a larger multiple is past it) looking back at the Spire.
func _intro_shots() -> Array[Dictionary]:
	var half := 80.0
	var player := Game.player
	if player != null and is_instance_valid(player) and titan != null:
		half = maxf(player.global_position.distance_to(titan.global_position) * 0.5, 45.0)
	var at_titan := Vector3(0.0, 10.0, -half)
	return [
		{"offset": Vector3(0.0, 46.0, -half * 1.55), "look": at_titan, "fov": 55.0, "t": 0.0},
		{"offset": Vector3(14.0, 30.0, -half * 1.12), "look": at_titan + Vector3.UP * 22.0,
			"fov": 42.0, "t": 2.6},
		{"offset": Vector3(-60.0, 26.0, -half * 1.35), "look": at_titan, "fov": 46.0, "t": 5.0},
	]


func _run_intro() -> void:
	_invulnerable(BossTuning.INTRO_CINEMATIC)
	_cinematic(_intro_shots(), BossTuning.INTRO_CINEMATIC)
	var climb: float = titan.play_action(&"climb_over")
	var from := titan.global_position
	var to := arena.ring_point(0.62, 0.80, 1.0)
	var t := 0.0
	while t < climb and is_instance_valid(titan):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		titan.global_position = from.lerp(to, clampf(t / maxf(climb, 0.01), 0.0, 1.0))
	if not is_instance_valid(titan):
		return
	titan.global_position = to
	titan.roar()
	announce()
	# The intro is the hand-off: the beast that just climbed onto the deck has seen the player.
	if Game.player != null and is_instance_valid(Game.player):
		titan.perception.acquire(Game.player, false)
	titan.set_ai_enabled(true)


# --- beats ------------------------------------------------------------------------------------------

## The title card at the intro roar (CONTRACTS §6): the HUD draws it, audio plays a stinger — the
## director only says when and what.
func announce() -> void:
	Events.boss_intro.emit(BossTuning.DISPLAY_NAME, BossTuning.INTRO_SUBTITLE)

## A broken core is the biggest non-phase moment of the fight: the boss staggers, so the camera
## pushes in and the player gets the Core Rend window for free.
func _on_core_broken(_core: BossCore) -> void:
	Events.objective_changed.emit("核心已破 — CORE BREACHED")


## 2–3 s cinematic roar, player invulnerable, the storm rises (brief §4).
func _on_phase_changed(phase: int) -> void:
	_invulnerable(BossTuning.PHASE_CINEMATIC)
	_cinematic(PHASE_SHOTS, BossTuning.PHASE_CINEMATIC)
	if phase == 2 and arena != null:
		arena.break_segments()
	Events.objective_changed.emit("巢母 BROOD TITAN — PHASE %d" % phase)


## The killing blow: slow-mo and the collapse are the titan's, the victory beat is ours.
func _on_death_started() -> void:
	_death_left = BossTuning.DEATH_CINEMATIC
	_invulnerable(BossTuning.DEATH_CINEMATIC + 1.0)
	_cinematic(DEATH_SHOTS, BossTuning.DEATH_CINEMATIC)
	# Storm clears to dusk gold (brief §5, the city-art TimeOfDay hook).
	get_tree().call_group(&"time_of_day", &"set_storm", 0.0, 4.0)
	get_tree().call_group(&"time_of_day", &"set_progress", 1.0)
	Audio.music_intensity(0.3)


## The victory beat runs on the REAL clock (CONTRACTS §3): the killing blow puts the world in 0.2×
## slow-mo, and a timer on the scaled clock would stretch the 4 s wait by five.
func _tick_death(delta: float) -> void:
	_death_left -= Feel.real_delta(delta)
	if _death_left > 0.0 or _won:
		return
	_won = true
	Events.game_won.emit()


func _on_game_won() -> void:
	Audio.music_intensity(0.2)


# --- checkpoints (SPEC §7.1) -------------------------------------------------------------------------

## Flow asks for this when the player aborts the mission from the pause page (flow r5 item 5): the
## titan and its adds go away, the deck disarms and the director is quiet again, so a fresh run starts
## at the title with no fight left over. A no-op when no fight is on.
func abort_fight() -> void:
	if not fight_started:
		return
	fight_started = false
	_won = false
	_death_left = 0.0
	_check_left = 0.0
	if titan != null and is_instance_valid(titan):
		var adds := titan.spawner()
		if adds != null:
			adds.clear()
		titan.queue_free()
	titan = null
	if arena != null and is_instance_valid(arena):
		arena.armed = false
		arena.restore_segments()
	var rig := Game.camera_rig
	if rig != null and is_instance_valid(rig) and rig.has_method(&"end_cinematic"):
		rig.call(&"end_cinematic")
	if _wants_walker() and (walker == null or not is_instance_valid(walker)):
		var parent := Game.world if Game.world != null and is_instance_valid(Game.world) else self
		walker = SkylineWalker.spawn(parent, Vector3.ZERO, 0.12)


## A boss-phase death gets exactly ONE respawn: flow's RETRY (r5 brief item 4). The director used to
## listen to `Events.player_died` and teleport the hero 127-179 m to its own ring point, heal it to
## full and re-enable the fight under the MECH DESTROYED page — so the mech fought on behind the page
## and RETRY then moved it a second time. It also restored the titan at death time, with its AI back
## on. There is no handler now; `restore_for_phase()` below is what flow's respawn calls.
##
## The hook `FlowProgress.respawn` calls (duck-typed like `roar`; a new Events signal would be the
## lead's, lead r16 decision 4). It restores the fight to the START of `phase`: the titan at
## `phase_start_hp(phase)`, its cores whole, no adds, on a deck ring point, and the deck itself with
## the rim that phase runs on — phases 2 and 3 fight on a broken rim, and the old restore mended it
## every time, so the holes were gone for the rest of the fight.
func restore_for_phase(phase: int) -> void:
	if not fight_started or titan == null or not is_instance_valid(titan):
		return
	var to := clampi(phase, 1, BossTuning.PHASE_COUNT)
	titan.restore_for_checkpoint(to)
	if arena != null and is_instance_valid(arena):
		arena.restore_segments()
		if to >= 2:
			arena.break_segments()
	_lock_the_camera()
	Events.objective_changed.emit("巢母 BROOD TITAN — PHASE %d" % to)


# --- helpers -----------------------------------------------------------------------------------------

func _invulnerable(seconds: float) -> void:
	var player := Game.player
	if player != null and is_instance_valid(player) and player.has_method(&"invulnerable_for"):
		player.call(&"invulnerable_for", seconds)


## The rig captures its hard target when a cinematic is requested, so the boss hard-locks the camera
## on itself before its own cutscene — otherwise the duel frame collapses to 10 m in front of the hero
## and the intro films an empty deck.
func _lock_the_camera() -> void:
	var rig := Game.camera_rig
	if rig == null or not is_instance_valid(rig) or not rig.has_method(&"lock_to"):
		return
	if titan != null and is_instance_valid(titan):
		rig.call(&"lock_to", titan)


## CONTRACTS §5: cinematic shots live in the duel frame and the rig resolves them against collision.
func _cinematic(shots: Array, duration: float) -> void:
	var rig := Game.camera_rig
	if rig == null or not is_instance_valid(rig) or not rig.has_method(&"request_cinematic"):
		return
	rig.call(&"request_cinematic", shots, duration)
