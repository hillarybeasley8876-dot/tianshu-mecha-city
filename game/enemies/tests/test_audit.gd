extends Node
## Regression suite for the numeric/clock audit (reviews/enemies-audit.md, 2026-11-02).
## Run: tools/godot.sh test res://enemies/tests/test_audit.gd -- --timeout=300
##
## One check per HIGH finding, plus the cheap mediums that are testable headless:
##   #1  knockback is a one-tick offset, not a per-tick re-injection into `velocity`
##   #2/#3 the dissolve fires once; a pooled ripper never returns to the pool twice or alive
##   #4  steer_dir normalises its own input, so a far nav corner is not a speed multiplier
##   #5  the leash measures against the ground under the player, so hovering strands nobody
##   #6/#8 the Undertow pull survives status.tick() and actually displaces the body
##   #7  starting an attack does not snap-turn a whole second of turn_rate in one tick
##   #9  a pull never inherits an old slow factor
##   #12 target_centre() never falls back to the shooter's own origin
##   #13 the hit-stop vibration alternates per rendered frame, not per physics tick

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const DT := 1.0 / 120.0
const BAKE_FRAMES_MAX := 60000
const GROUND := Vector3(0.0, 2.0, 0.0)

var _fails: int = 0
var _checks: int = 0
var _pull_consumed: bool = true
var _spawner: EnemySpawner


func _ready() -> void:
	await _build_world()
	_spawner = EnemySpawner.new()
	_spawner.auto_spawn = false
	_spawner.leash = false
	add_child(_spawner)
	await _knockback()
	await _dissolve_latch()
	await _dissolve_never_zero()
	_steer_dir_normalises()
	await _pull_survives_tick()
	_pull_does_not_inherit_slow()
	await _telegraph_does_not_snap_turn()
	await _charge_windup_roars_once()
	await _aim_fallback()
	await _leash_uses_the_ground()
	print("AUDIT TEST %d checks, %d failures" % [_checks, _fails])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)


func _build_world() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	world.name = "World"
	add_child(world)
	Game.world = world
	var waited := 0
	while not Game.world_built() and waited < BAKE_FRAMES_MAX:
		await get_tree().physics_frame
		waited += 1
	print("SANDBOX navmesh ready after %d physics frames" % waited)


func _check(what: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   %s" % what)
	else:
		_fails += 1
		print("FAIL %s — %s" % [what, detail])


## A monster at `at` with its AI off and its own physics stepped by the test.
func _make(type: StringName, at: Vector3, ai: bool = false) -> EnemyBase:
	var packed := load("res://enemies/%s/%s.tscn" % [type, type]) as PackedScene
	var e := packed.instantiate() as EnemyBase
	add_child(e)
	e.global_position = at
	e.set_ai_enabled(ai)
	e.set_physics_process(false)
	return e


func _step(e: EnemyBase, ticks: int) -> void:
	for i in ticks:
		e._physics_process(DT)


## audit #1: one hit of K m/s must move the monster about K²/80 m. The old integrator added the
## whole decaying impulse back into `velocity` every tick (≈100–490 m/s on a ripper, 20–35 m of
## travel, scaling with the tick rate) instead of 4 m.
func _knockback() -> void:
	var e := _make(EnemyTypes.RIPPER, GROUND)
	await get_tree().physics_frame
	var start := e.global_position
	var vmax := 0.0
	var hit := HitInfo.make(1.0, HitInfo.MELEE, null, &"audit")
	hit.knockback = Vector3(18.0, 0.0, 0.0)
	e.take_hit(hit)
	for i in 240:
		e._physics_process(DT)
		vmax = maxf(vmax, e.velocity.length())
	var flat := Vector3(e.global_position.x - start.x, 0.0, e.global_position.z - start.z).length()
	_check("#1 an 18 m/s hit pushes a ripper 0.5–8 m, not 20–35 m", flat > 0.5 and flat < 8.0,
			"travelled %.2f m" % flat)
	_check("#1 steering velocity never leaves the cap", vmax <= e.move_speed * 2.0 + 0.01,
			"peak |v| %.1f m/s" % vmax)
	e.queue_free()


## audit #2/#3: a reclaimed wreck used to re-emit `dissolved` on every physics tick forever, and the
## spawner appended it to the free list each time — so the pool grew without bound and the next
## ring popped the same live ripper over and over.
func _dissolve_latch() -> void:
	var e := _spawner.spawn(EnemyTypes.RIPPER, EnemySpawner.face_towards(GROUND, Vector3.ZERO))
	await get_tree().physics_frame
	var fired := [0]
	e.dissolved.connect(func(_who: EnemyBase) -> void: fired[0] += 1)
	e.wreck_lifetime = 0.05
	var hit := HitInfo.make(e.hp_max * 2.0, HitInfo.BEAM, null, &"audit")
	hit.hurtbox_part = &"body"
	e.take_hit(hit)
	_step(e, 360)
	_check("#2/#3 a pooled wreck dissolves exactly once", fired[0] == 1,
			"dissolved fired %d times in 3 s" % fired[0])
	var ring: Array[EnemyBase] = []
	for i in 4:
		var at := Vector3(60.0 + float(i) * 12.0, 0.0, 60.0)
		ring.append(_spawner.spawn(EnemyTypes.RIPPER, EnemySpawner.face_towards(at, Vector3.ZERO)))
	await get_tree().physics_frame
	var distinct: Dictionary = {}
	for r: EnemyBase in ring:
		if r != null:
			distinct[r.get_instance_id()] = true
	var alive := 0
	for r: EnemyBase in ring:
		if r != null and r.alive:
			alive += 1
	_check("#2/#3 a ring of 4 spawns 4 distinct live rippers", distinct.size() == 4 and alive == 4,
			"%d distinct, %d alive" % [distinct.size(), alive])
	_check("#2/#3 the spawner counts exactly those 4", _spawner.alive_count() == 4,
			"%d alive" % _spawner.alive_count())
	_spawner.clear()


## melee r6: the dissolve shrank the wreck to exactly (0, 0, 0) on its last frame, which is a
## degenerate basis — every renderer and transform that read it reported a NaN, and it was the only
## `--nan-watch` source left in a scripted fight (40 reports per run).
func _dissolve_never_zero() -> void:
	var e := _spawner.spawn(EnemyTypes.RIPPER, EnemySpawner.face_towards(GROUND, Vector3.ZERO))
	await get_tree().physics_frame
	e.wreck_lifetime = 0.05
	var hit := HitInfo.make(e.hp_max * 2.0, HitInfo.BEAM, null, &"audit")
	hit.hurtbox_part = &"body"
	e.take_hit(hit)
	var min_scale := INF
	var worst_det := INF
	var hidden := false
	for i in 360:
		e._physics_process(DT)
		var m := e.model
		if m == null or not is_instance_valid(m):
			continue
		min_scale = minf(min_scale, m.scale.x)
		worst_det = minf(worst_det, absf(m.global_transform.basis.determinant()))
		hidden = not m.visible
	_check("melee r6 the dissolve never reaches a zero scale", min_scale > 0.0,
			"smallest scale seen %.5f" % min_scale)
	_check("melee r6 the wreck's basis is never degenerate", worst_det > 1e-9,
			"smallest |determinant| %.9f" % worst_det)
	_check("melee r6 the wreck is hidden before it leaves", hidden, "model still visible")
	_spawner.clear()


## audit #4: nav_step hands steer_dir the raw offset to the next corner. Unnormalised, a lone ground
## monster targeted |offset| × move_speed and ran at the 60 m/s cap (log: 'ripper:approach v60').
func _steer_dir_normalises() -> void:
	var e := _make(EnemyTypes.RIPPER, GROUND)
	await get_tree().physics_frame
	for i in 240:
		e.loco.steer_dir(Vector3(150.0, 0.0, 0.0), 1.0, DT)
	var speed := Vector3(e.velocity.x, 0.0, e.velocity.z).length()
	_check("#4 a 150 m corner steers at move_speed, not 150 × move_speed",
			speed > e.move_speed * 0.9 and speed < e.move_speed * 1.05,
			"|v| %.1f m/s, move_speed %.1f" % [speed, e.move_speed])
	e.queue_free()


## audit #6/#8: status.tick() used to zero pull_accel before EnemyBase._integrate read it, so the
## Undertow well never moved a real monster. The pull is now consumed by the integrator.
func _pull_survives_tick() -> void:
	var e := _make(EnemyTypes.RIPPER, GROUND)
	await get_tree().physics_frame
	# Two identical runs, one with the field and one without: the sandbox floor lets a body settle
	# a little sideways, so the pull is measured as the DIFFERENCE, not as absolute travel.
	var base := _drift(e, false)
	var dragged := _drift(e, true)
	_check("#6/#8 the integrator consumes pull_accel", _pull_consumed,
			"pull_accel survived the tick")
	_check("#6/#8 a 120 m/s² well drags a ripper 2–40 m in 0.5 s",
			dragged - base > 2.0 and dragged - base < 40.0,
			"dragged %.2f m (%.2f m of it settling)" % [dragged, base])
	e.queue_free()


## 0.5 s of physics with the monster's own velocity zeroed every tick, so only the pull can move it.
func _drift(e: EnemyBase, pull: bool) -> float:
	e.global_position = GROUND
	e.velocity = Vector3.ZERO
	e.status.reset()
	var start := e.global_position
	for i in 60:
		e.velocity = Vector3.ZERO
		if pull:
			e.status.apply_pull(Vector3(1.0, 0.0, 0.0) * 120.0, 0.1)
		e._physics_process(DT)
		_pull_consumed = _pull_consumed and e.status.pull_accel == Vector3.ZERO
	return Vector3(e.global_position.x - start.x, 0.0, e.global_position.z - start.z).length()


## audit #9: apply_pull extended the slow timer without setting _slow_amount, so a ripper that had
## ever been yanked (factor 0.05) crawled at 5 % speed for the whole of its next well.
func _pull_does_not_inherit_slow() -> void:
	var s := StatusComponent.new()
	s.configure(EnemyTypes.STATS[EnemyTypes.RIPPER])
	s.apply_slow(0.0, 0.2)
	var yanked: float = s.slow_factor
	for i in 30:
		s.tick(0.01)
	var expired: float = s.slow_factor
	s.apply_pull(Vector3.RIGHT * 120.0, 0.5)
	s.tick(0.01)
	var after_pull: float = s.slow_factor
	s.apply_slow(0.2, 1.0)
	s.reset()
	var after_reset: float = s.slow_factor
	_check("#9 a yank slows to the 0.05 floor", is_equal_approx(yanked, 0.05), "%.3f" % yanked)
	_check("#9 the slow clears to 1.0 when it expires", is_equal_approx(expired, 1.0),
			"%.3f" % expired)
	_check("#9 a pull does not re-apply the old slow", is_equal_approx(after_pull, 1.0),
			"%.3f" % after_pull)
	_check("#9 reset() restores the slow amount", is_equal_approx(after_reset, 1.0),
			"%.3f" % after_reset)


## audit #7: _begin_attack called face_dir(dir, 1.0), so a flanked juggernaut popped up to a full
## second of turn_rate (150°) in one 8 ms tick and its 160° swipe connected — flanking it has to
## stay the answer. The telegraph now turns at turn_rate per tick, as its own windup intends.
func _telegraph_does_not_snap_turn() -> void:
	var player := DummyPlayer.new()
	add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	Game.register_player(player)
	var e := _make(EnemyTypes.JUGGERNAUT, Vector3(34.0, 2.0, 0.0), true)
	await get_tree().physics_frame
	e.perception.acquire(player, false)
	var brain := e.get(&"_brain") as EnemyBrain
	var prev := e.rotation.y
	var turned := -1.0
	for i in 1200:
		e.perception.tick(DT)
		brain.think(DT)
		if e.state() == EnemyBrain.ATTACK:
			turned = absf(wrapf(e.rotation.y - prev, -PI, PI))
			break
		prev = e.rotation.y
	var budget := deg_to_rad(e.turn_rate) * DT * 1.5
	_check("#7 starting an attack turns at most one tick of turn_rate",
			turned >= 0.0 and turned <= budget,
			"turned %.1f° in the attack-start tick, budget %.2f°"
					% [rad_to_deg(turned), rad_to_deg(budget)])
	e.queue_free()
	player.queue_free()
	Game.register_player(null)


## audit #12: with no live target, target_centre() returned the shooter's own origin, so a shot
## fired from the muzzle flew straight back through the monster.
func _aim_fallback() -> void:
	var player := DummyPlayer.new()
	add_child(player)
	player.global_position = Vector3(0.0, 1.0, 120.0)
	Game.register_player(player)
	var e := _make(EnemyTypes.SPITTER, GROUND)
	await get_tree().physics_frame
	e.perception.heard_shot(player.global_position)
	var seen: Vector3 = e.perception.hunt_point()
	player.free()
	Game.register_player(null)
	await get_tree().physics_frame
	var aim := e.target_centre()
	_check("#12 with no live target the aim point is the remembered position",
			aim.distance_to(seen + Vector3.UP * EnemyBase.HUNT_AIM_HEIGHT) < 0.01,
			"aim %s, remembered %s" % [aim, seen])
	_check("#12 the aim point is never the shooter's own origin",
			aim.distance_to(e.global_position) > 20.0,
			"aim %s, origin %s" % [aim, e.global_position])
	e.queue_free()


## audit #5: the leash measured a 3D distance to the player and trusted is_target_reachable(), whose
## goal sat at the mech's capsule centre. A hovering player therefore marked every ground monster
## lost and teleported it to the player's own altitude, 150 m out, unchecked against the map.
func _leash_uses_the_ground() -> void:
	var player := DummyPlayer.new()
	add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	Game.register_player(player)
	var walker := _spawner.spawn(EnemyTypes.RIPPER,
			EnemySpawner.face_towards(Vector3(70.0, 0.0, 0.0), Vector3.ZERO))
	await get_tree().physics_frame
	# The player's origin is its capsule centre, 8 m up: an unprojected goal read as unreachable.
	walker.loco.nav_step(player.global_position + Vector3.UP * 8.0, 1.0, DT)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("#5 a goal above the navmesh is still reachable once projected",
			walker.loco.agent.is_target_reachable(),
			"goal %s" % str(walker.loco.agent.target_position))
	var leashy := EnemySpawner.new()
	leashy.auto_spawn = false
	add_child(leashy)
	var e := leashy.spawn(EnemyTypes.RIPPER, EnemySpawner.face_towards(
			leashy.place_around(player.global_position, 0.25, EnemyTypes.RIPPER),
			player.global_position))
	e.set_ai_enabled(false)
	await get_tree().physics_frame
	var start := e.global_position
	player.global_position = Vector3(0.0, 240.0, 0.0)
	var top := -INF
	for i in int(16.0 / get_physics_process_delta_time()):
		await get_tree().physics_frame
		top = maxf(top, e.global_position.y)
	var moved := Vector3(e.global_position.x - start.x, 0.0, e.global_position.z - start.z).length()
	_check("#5 the leash actually relocated the stranded ripper", moved > 50.0,
			"moved %.1f m" % moved)
	_check("#5 a hovering player never teleports a monster into the air", top < 40.0,
			"highest y %.1f m (player at 240 m)" % top)
	leashy.queue_free()
	player.queue_free()
	Game.register_player(null)
	await get_tree().physics_frame


## lead r10 #1: the charge windup called `set_locomotion(&"roar")` on every tick. No locomotion row
## answers "roar", so it resolved to idle and the 2.75 s roar clip never played at all — the brute
## announced an unblockable charge in a neutral stance. The roar is now a one-shot at the top of the
## windup, and the dash re-arms the charge clip the brain played before it.
func _charge_windup_roars_once() -> void:
	var e := _make(EnemyTypes.JUGGERNAUT, GROUND)
	await get_tree().physics_frame
	await get_tree().process_frame
	var charge := EnemyAttack.make(Juggernaut.CHARGE)
	var anim := e.model.get(&"animation") as AnimationPlayer
	e.begin_telegraph(charge)
	e.play_action(charge.anim)      ## exactly what EnemyBrain._begin_attack does, in that order
	for i in int(charge.telegraph / DT):
		e.attack_windup(charge, DT)
	var roars := int(e.action_plays.get(&"roar", 0))
	_check("r10 #1 the charge windup plays roar exactly once", roars == 1, "roar played %d×" % roars)
	_check("r10 #1 the model reports the roar clip during the windup",
			anim != null and String(anim.current_animation) == "roar",
			"current_animation=%s" % ("<no AnimationPlayer>" if anim == null
					else anim.current_animation))
	e.attack_started(charge)
	_check("r10 #1 the dash takes the charge clip back",
			anim != null and String(anim.current_animation) == "charge",
			"current_animation=%s" % ("<no AnimationPlayer>" if anim == null
					else anim.current_animation))
	_check("r10 #1 the windup is still 0.7 s (the attack was not retimed)",
			is_equal_approx(charge.telegraph, 0.7), "telegraph %.3f s" % charge.telegraph)
	e.queue_free()
	await get_tree().physics_frame
