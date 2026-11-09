extends Node3D
## The boss unit's capture scene (boss unit). Builds the Crown arena, the real PlayerMech and camera
## rig and the Brood Titan, then runs a scripted fight that puts every attack, every phase and the
## death beat on screen inside ~2.5 minutes.
##
##   tools/godot.sh movie --movie=$HOME/m/mecha-city/captures/boss_fight.avi \
##       --scene=res://enemies/boss/tests/boss_showcase.tscn \
##       --timeline=res://enemies/boss/tests/boss_showcase_timeline.json --god
##
##   tools/godot.sh shot --scene=res://enemies/boss/tests/boss_showcase.tscn --out=boss \
##       --boss-beats=intro,stomp,beam,core,storm,death
##
## The titan runs its REAL brain, telegraphs, hazards and phase logic. Only the hero's damage is
## scripted (there is no player at the pad), and every scripted hit goes through the same
## `take_hit` path a rifle shot uses, so nothing on screen is a mock-up.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const CITY := "res://world/city.tscn"
const PLAYER := "res://player/player_mech.tscn"
const CAMERA := "res://player/camera/camera_rig.tscn"
## The feel director is another unit's scene, but a capture without it films a boss fight with no
## VFX and no shake — the two things the review is judging. The HUD is deliberately NOT instanced:
## it opens on the title screen without the flow unit to dismiss it, and dims the whole capture.
const FEEL := "res://fx/feel_director.tscn"
## Where the Crown deck goes: the Spire's crown from the layout (the sandbox has no Spire, so it
## gets a plateau instead). `--boss-at=x,y,z` overrides either.
const CROWN_CITY := BossTuning.CROWN_CENTRE
const CROWN_SANDBOX := Vector3(0.0, 140.0, 0.0)
## Seconds between scripted beats; long enough for a full telegraph → active → recover cycle.
const BEAT := 4.0
const SETTLE := 1.2
## How far round the deck the hero stands from the titan, in turns (see `_face_the_titan`).
const KITE_TURN := 0.16

var arena: BossArena
var director: BossDirector
var titan: BroodTitan
var player: Node3D

var _beats: PackedStringArray = PackedStringArray()
var _only: PackedStringArray = PackedStringArray()
var _attacks: PackedStringArray = PackedStringArray()
var _elapsed: float = 0.0


func _ready() -> void:
	var spec := Game.flag("boss-beats")
	_only = PackedStringArray(spec.split(",", false)) if spec != "" else PackedStringArray()
	_boot.call_deferred()


func _boot() -> void:
	var world := _instance_world()
	_instance_part(FEEL, "FeelDirector")
	while not Game.world_built():
		await get_tree().physics_frame
	arena = BossArena.new()
	arena.name = "BossArena"
	arena.position = _crown_at(world)
	# The arena only stands down when the world already built the Crown and exported its rim
	# (CONTRACTS §6); on the city that has not landed yet, so the arena IS the deck there too.
	arena.build_geometry = not BossArena.world_has_crown(get_tree())
	add_child(arena)
	_spawn_player()
	director = BossDirector.new()
	director.name = "BossDirector"
	director.arena = arena
	add_child(director)
	director.start_fight()
	await get_tree().physics_frame
	titan = director.titan
	if titan == null:
		push_error("boss_showcase: the director did not spawn a titan")
		return
	titan.telegraph_started.connect(_on_telegraph)
	# A player hard-locks the boss; without it the rig keeps the hero centred and the titan spends the
	# whole capture circling behind the Ø80 core, which is exactly what the cover is for and exactly
	# what makes a still unreadable.
	var rig := Game.camera_rig
	if rig != null and is_instance_valid(rig) and rig.has_method(&"lock_to"):
		rig.call(&"lock_to", titan)
	_run.call_deferred()


## Every attack the titan actually telegraphs, so the capture log proves the hazards on screen are
## the ones the brief asked for (EnemyBase emits this at the start of the windup).
func _on_telegraph(_enemy: EnemyBase, attack: StringName, kind: StringName) -> void:
	_attacks.append(String(attack))
	print("SHOWCASE attack %s (%s) at %.1f s" % [attack, kind, _elapsed])


## The city when it is there, the sandbox otherwise; `--boss-world=sandbox|city` forces one. The
## city's Crown is city-blockout's work and moves under us, while the sandbox plateau is the stable
## stage the brief's §7 asks the fight to work on.
func _instance_world() -> String:
	var want := Game.flag("boss-world")
	var use_city := want != "sandbox" and ResourceLoader.exists(CITY)
	add_child((load(CITY if use_city else SANDBOX) as PackedScene).instantiate())
	return "city" if use_city else "sandbox"


## One of the other units' optional scenes, the way `main.gd` instances its parts: missing is a no-op.
func _instance_part(path: String, node_name: String) -> void:
	if not ResourceLoader.exists(path):
		push_warning("boss_showcase: no " + node_name + " scene at " + path)
		return
	var node := (load(path) as PackedScene).instantiate()
	node.name = node_name
	add_child(node)


func _crown_at(world: String) -> Vector3:
	var spec := Game.flag("boss-at")
	if spec != "":
		var v := spec.split(",")
		if v.size() >= 3:
			return Vector3(float(v[0]), float(v[1]), float(v[2]))
		push_error("boss_showcase: --boss-at needs x,y,z, got '" + spec + "'")
	return CROWN_CITY if world == "city" else CROWN_SANDBOX


## The real 16 m hero and the real third-person rig: the whole point of the capture is the scale
## difference, so a stand-in box would not answer the brief's question.
func _spawn_player() -> void:
	if not ResourceLoader.exists(PLAYER):
		push_warning("boss_showcase: no player_mech.tscn — the capture will have no hero")
		return
	player = (load(PLAYER) as PackedScene).instantiate() as Node3D
	player.name = "PlayerMech"
	add_child(player)
	player.global_position = arena.ring_point(0.25, 0.72, 2.0)
	player.look_at_from_position(player.global_position, arena.global_position, Vector3.UP)
	if ResourceLoader.exists(CAMERA):
		var rig := (load(CAMERA) as PackedScene).instantiate() as Node3D
		rig.name = "CameraRig"
		add_child(rig)
	if Game.has_flag("god") and player.has_method(&"set"):
		player.set(&"god_mode", true)


# --- the scripted fight -------------------------------------------------------------------------

func _run() -> void:
	print("SHOWCASE arena at %s" % arena.global_position)
	# The intro cinematic owns the camera for its whole length and the rig then needs a second to
	# travel back to the hero: attacking inside that window films the fight from 300 m away.
	await _beat("intro", BossTuning.INTRO_CINEMATIC + SETTLE)
	await _beat("stomp", BEAT)
	await _beat("swipe", BEAT)
	# The summon has to come before the R shoulder core breaks, or the core has already taken it away.
	await _beat("summon", BEAT)
	await _damage(BossTuning.HP_MAX * 0.30)
	await _beat("core", BEAT)
	await _phase(2)
	await _beat("beam", BEAT + 2.0)
	await _beat("tail", BEAT)
	await _phase(3)
	await _beat("storm", BEAT)
	await _beat("core", BEAT)
	await _beat("death", 0.0)
	print("SHOWCASE done after %.1f s, attacks: %s" % [_elapsed, ", ".join(_attacks)])


## True unless `--boss-beats` filtered this beat out. The damage and phase steps go through it too, so
## a capture that asks for one beat gets that beat at a predictable time and nothing else.
func _wanted(id: String) -> bool:
	return _only.is_empty() or _only.has(id)


## Runs `id` unless `--boss-beats` filtered it out, then waits `after` seconds of fight.
func _beat(id: String, after: float) -> void:
	if not _wanted(id):
		return
	_beats.append(id)
	print("SHOWCASE beat %s at %.1f s (titan %.0f m away, %.0f m up)"
			% [id, _elapsed, _titan_range(), titan.global_position.y - arena.global_position.y])
	_face_the_titan()
	match id:
		"stomp": titan.demand(&"titan_stomp")
		"swipe": titan.demand(&"titan_swipe")
		"tail": titan.demand(&"titan_tail")
		"beam": titan.demand(&"titan_beam")
		"summon": titan.demand(&"titan_summon")
		"storm": titan.demand(&"titan_lightning")
		"core": _break_core()
		"death": _kill()
		_: pass
	await _kite(after)


## Holds the hero at KITE range on the far side of the deck for `seconds` instead of standing still.
## A real player kites a 60 m boss, and a hero who lets the titan walk into the lens gives the
## capture nothing but shins — this is the difference between a still that reads and one that does
## not (lead review r2 item 3).
func _kite(seconds: float) -> void:
	var left := seconds
	var step := 0.25
	while left > 0.0:
		_face_the_titan()
		var wait: float = minf(step, left)
		await _wait(wait)
		left -= wait


func _titan_range() -> float:
	if player == null or not is_instance_valid(player) or titan == null:
		return -1.0
	return player.global_position.distance_to(titan.global_position)


## Chews the pool down in visible chunks through the real damage path, so the cores light up, the
## hit flash fires and the HUD plate moves exactly as it would under a rifle.
## Stands the hero on the far side of the deck from the titan, at a range inside every attack's band.
## Without this the Ø80 core sits between them for most of the fight — which is what the cover is FOR,
## and also what makes a still photograph of the fight unreadable. The radius also has to clear the
## camera arm (42 m, 64 m on a large target) plus the core (40 m), or the third-person camera ends up
## inside the core.
func _face_the_titan() -> void:
	if player == null or not is_instance_valid(player) or titan == null:
		return
	var to := titan.global_position - arena.global_position
	var bearing := atan2(to.z, to.x) / TAU
	# A sixth of a turn round the deck from the titan: ~100 m of chord between them, which is inside
	# every attack's `range_max` (the stomp's 110 m is the tightest) and still off the Ø80 core's
	# shadow, so a 60 m body and a 16 m hero both fit the frame at the rig's large-target arm.
	var at := arena.ring_point(bearing + KITE_TURN, 0.62, 2.0)
	player.global_position = at
	player.look_at_from_position(at, titan.global_position, Vector3.UP)
	var rig := Game.camera_rig
	if rig != null and is_instance_valid(rig) and rig.has_method(&"lock_to"):
		rig.call(&"lock_to", titan)
	_aim_the_camera(rig)


## Points the rig at the titan's chest as well as locking it. The lock alone drops while the titan is
## still climbing over the rim, and the capture then spends the intro looking at the hero's feet.
func _aim_the_camera(rig: Node) -> void:
	if rig == null or not is_instance_valid(rig) or not rig.has_method(&"set_look"):
		return
	var from: Vector3 = rig.call(&"camera").global_position
	var to := titan.centre() - from
	var flat := Vector2(to.x, to.z).length()
	if flat < 1.0:
		return
	rig.call(&"set_look", rad_to_deg(atan2(-to.x, -to.z)), rad_to_deg(atan2(to.y, flat)))


func _damage(amount: float) -> void:
	if not _wanted("damage"):
		return
	var chunk := 4000.0
	var left := amount
	while left > 0.0 and titan.is_alive():
		var step: float = minf(chunk, left)
		var hit := HitInfo.make(step, HitInfo.BEAM, player, &"beam_rifle")
		hit.hurtbox_part = &"body"
		hit.position = titan.centre()
		titan.take_hit(hit)
		left -= step
		await _wait(0.12)


func _phase(to: int) -> void:
	if not _wanted("phase%d" % to):
		return
	print("SHOWCASE phase %d at %.1f s" % [to, _elapsed])
	titan.restore_for_checkpoint(to)
	# A checkpoint skips the transition the player would see; run the real one instead.
	titan.hp = BossTuning.phase_start_hp(to) + 100.0
	var hit := HitInfo.make(2000.0, HitInfo.BEAM, player, &"beam_rifle")
	hit.hurtbox_part = &"body"
	titan.take_hit(hit)
	await _wait(BossTuning.PHASE_CINEMATIC + SETTLE)


## Breaks the next whole core, through the core's own hurtbox.
func _break_core() -> void:
	for core: BossCore in titan.cores:
		if core.broken:
			continue
		var left := core.hp / BossTuning.CORE_POOL_MULT
		var hit := HitInfo.make(left, HitInfo.BEAM, player, &"beam_rifle")
		hit.hurtbox_part = core.part
		hit.weak_point = true
		hit.position = core.global_position
		core.take_hit(hit)
		return
	push_warning("boss_showcase: every core is already broken")


func _kill() -> void:
	titan.hp = 1200.0
	var hit := HitInfo.make(4000.0, HitInfo.BEAM, player, &"rifle_stage2")
	hit.hurtbox_part = &"body"
	hit.position = titan.centre()
	titan.take_hit(hit)


func _wait(seconds: float) -> void:
	var dt := get_physics_process_delta_time()
	for i in int(seconds / dt):
		await get_tree().physics_frame
	_elapsed += float(int(seconds / dt)) * dt
