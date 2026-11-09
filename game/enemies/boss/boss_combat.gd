class_name BossCombat
extends RefCounted
## The Brood Titan's attack resolution (boss unit). One static table per phase, one dispatch point
## per brain hook, so `brood_titan.gd` stays the actor and never grows the per-attack detail.
##
## EnemyBrain runs telegraph → active → recover for every attack. The titan's three "spawned"
## attacks (stomp ring, beam breath, summon, storm) all fire once at the start of the active window
## and then run themselves; the two sweeps (claw, tail) resolve here.

## The attacks this phase may use, minus the ones a broken core has removed.
static func build_table(phase: int, removed: Array) -> Array[EnemyAttack]:
	var rows: Array = []
	for id: StringName in BossTuning.attack_ids(phase):
		if id in removed:
			continue
		var row := BossTuning.scaled_row(id, phase)
		if not row.is_empty():
			rows.append(row)
	if rows.is_empty():
		# Every attack removed would leave the titan defenceless and the fight unwinnable in a
		# confusing way; the stomp is the floor it always keeps.
		push_warning("BossCombat: phase %d has no attacks left, falling back to the stomp" % phase)
		rows.append(BossTuning.scaled_row(&"titan_stomp", phase))
	return EnemyAttack.make_all(rows)


static func pick(table: Array[EnemyAttack], dist: float) -> EnemyAttack:
	var in_range: Array[EnemyAttack] = []
	for a: EnemyAttack in table:
		if dist >= a.range_min and dist <= a.range_max:
			in_range.append(a)
	return EnemyStrike.choose(in_range if not in_range.is_empty() else table)


# --- telegraph / active / recover ------------------------------------------------------------------

## The windup: stop, turn to the player, hold the pose. Nothing here can damage anything.
static func windup(titan: BroodTitan, attack: EnemyAttack, dt: float) -> void:
	titan.loco.decelerate(dt)
	if attack.id != &"titan_tail":
		titan.face_dir(titan.target_centre() - titan.global_position, dt)
	else:
		# The tail is the punish for standing behind: it does NOT turn to face you.
		titan.set_locomotion(&"idle")


## One-shot at the telegraph → active boundary: everything that spawns and then runs itself.
static func started(titan: BroodTitan, attack: EnemyAttack) -> void:
	match attack.id:
		&"titan_beam": fire_beam(titan, attack)
		&"titan_summon": summon(titan)
		&"titan_lightning": storm(titan)
		_: pass


static func active(titan: BroodTitan, attack: EnemyAttack, dt: float) -> void:
	if attack.id == &"titan_tail":
		# The tail carries the body around: the titan keeps turning away through the sweep.
		titan.face_dir(-(titan.target_centre() - titan.global_position), dt * 0.4)
		return
	titan.loco.decelerate(dt)


static func recover(titan: BroodTitan, _attack: EnemyAttack, dt: float) -> void:
	titan.loco.decelerate(dt)
	titan.set_locomotion(&"idle")


## Called once by the brain for the attacks that spawn a hazard instead of sweeping.
static func spawn(titan: BroodTitan, attack: EnemyAttack) -> bool:
	var parent := titan.get_parent()
	if parent == null:
		push_error("BossCombat: the titan has no parent to spawn '%s' into" % attack.id)
		return false
	if attack.id == &"titan_stomp":
		# The ring leaves the foot that came down, on the deck surface under it — not at the titan's
		# body origin, which is mid-air during a hop and would put the ring above the player's feet.
		var foot := titan.global_position + Vector3(0.0, 0.0, -BossTuning.RADIUS)
		var arena := titan.get_tree().get_first_node_in_group(&"boss_arena") as BossArena
		foot.y = (arena.floor_y_at(foot) if arena != null else titan.global_position.y) + 1.0
		TitanRing.spawn(parent, foot, attack, titan)
		return true
	return false


## Melee resolution. The claw sweeps the frontal arc EnemyStrike already knows; the tail sweeps the
## REAR arc, which is why the titan never turns to face you during it.
static func sweep(titan: BroodTitan, attack: EnemyAttack) -> bool:
	if attack.id == &"titan_tail":
		return rear_arc_hit(titan, attack)
	if attack.id == &"titan_beam" or attack.id == &"titan_lightning":
		return true   ## the spawned hazard does the damage over the whole active window
	return EnemyStrike.melee_sweep(titan, attack)


## A 200° arc measured from BEHIND the titan: standing at its back is not safe.
static func rear_arc_hit(titan: BroodTitan, attack: EnemyAttack) -> bool:
	var space := titan.get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(attack.range_max, 1.0)
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, titan.centre())
	params.collision_mask = Layers.MASK_ENEMY_ATTACK
	params.exclude = [titan.get_rid()]
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var back := titan.global_transform.basis.z   ## +Z is behind a -Z-facing actor
	var half := cos(deg_to_rad(attack.arc_deg * 0.5))
	for r: Dictionary in space.intersect_shape(params, 8):
		var col: Object = r.get("collider")
		if not (col is Hurtbox):
			continue
		var box := col as Hurtbox
		var victim := box.actor() as Node3D
		if victim == null or victim == titan:
			continue
		var to := victim.global_position - titan.global_position
		if back.dot(Vector3(to.x, 0.0, to.z).normalized()) < half:
			continue
		var hit := attack.build_hit(titan)
		hit.position = box.global_position
		hit.knockback = to.normalized() * attack.knockback
		if box.apply(hit) == null:
			continue
		titan.attack_landed.emit(titan, attack.id)
		return true
	return false


# --- spawned hazards -------------------------------------------------------------------------------

## The beam leaves the mouth socket and sweeps for the length of the active window.
static func fire_beam(titan: BroodTitan, attack: EnemyAttack) -> void:
	var parent := titan.get_parent()
	if parent == null:
		push_error("BossCombat: the titan has no parent to fire the beam into")
		return
	var mouth := titan.model_socket(&"mouth").global_position
	var beam := TitanBeam.spawn(parent, mouth, titan.rotation.y, titan)
	if beam == null:
		return
	beam.damage = attack.damage
	beam.start()


## 6 rippers + 2 harriers off the deck edge (brief §3). Rippers drop onto the deck and walk in;
## harriers route through the sky graph so they arrive over the crown, not through it.
static func summon(titan: BroodTitan) -> void:
	var spawner := titan.spawner()
	if spawner == null:
		push_warning("BossCombat: no spawner — the summon adds were skipped")
		return
	var wanted := BossTuning.SUMMON_RIPPERS + BossTuning.SUMMON_HARRIERS
	var room: int = BossTuning.SUMMON_CAP - spawner.alive_count()
	if room <= 0:
		push_warning("BossCombat: summon skipped, %d adds are already up" % spawner.alive_count())
		return
	var centre := titan.global_position
	var ripper_row: Array[StringName] = []
	for i in BossTuning.SUMMON_RIPPERS:
		ripper_row.append(EnemyTypes.RIPPER)
	var harrier_row: Array[StringName] = []
	for i in BossTuning.SUMMON_HARRIERS:
		harrier_row.append(EnemyTypes.HARRIER)
	var plan: Array[StringName] = ripper_row + harrier_row
	plan.resize(mini(plan.size(), room))
	for i in plan.size():
		var t := float(i) / float(maxi(plan.size(), 1))
		var type: StringName = plan[i]
		var at := _deck_point(titan, t, type)
		var spawned := spawner.spawn(type, EnemySpawner.face_towards(at, centre))
		if spawned == null:
			continue
		if type == EnemyTypes.HARRIER:
			_route_flyer(titan, spawned, centre)
	Feel.play(&"boss_roar", centre, 0.5)
	Audio.play(&"titan_roar", centre)


## Flyers are handed a sky route (CONTRACTS §7 `world.sky_path`); without a world or a sky graph the
## call returns [from, to] and the harrier steers straight, which is exactly the sandbox behaviour.
static func _route_flyer(titan: BroodTitan, flyer: EnemyBase, goal: Vector3) -> void:
	var world := Game.world
	if world == null or not is_instance_valid(world) or not world.has_method(&"sky_path"):
		return
	var route: PackedVector3Array = world.call(&"sky_path", flyer.global_position, goal)
	if route.size() < 2:
		return
	flyer.set_meta(&"sky_route", route)


## A spawn point for the adds: on the arena's rim when there is an arena (so they land on the deck,
## not in the void), else on a ring around the titan. Harriers come in above it.
##
## Never inside the titan's own 18 m body. The rim fraction 0.88 is r 132, which is exactly where
## `_stay_on_the_deck` clamps the beast, so a point there is under its feet — and an add that spawns
## under the titan is the floor it is standing on (r5 brief item 3). The bearing is stepped round the
## deck until the point is clear.
static func _deck_point(titan: BroodTitan, t: float, type: StringName) -> Vector3:
	var lift := Vector3.UP * 60.0 if type == EnemyTypes.HARRIER else Vector3.ZERO
	var arena := titan.get_tree().get_first_node_in_group(&"boss_arena") as BossArena
	if arena != null:
		return _clear_of_the_titan(titan, arena, t) + lift
	var angle := TAU * fposmod(t + 0.07, 1.0)
	return titan.global_position + Vector3(cos(angle), 0.0, sin(angle)) \
			* BossTuning.SUMMON_RADIUS + lift


## `BossTuning.RADIUS * 2.5` is 45 m: clear of the 18 m body, its hurtboxes and the slide the titan
## makes in the tick the add appears. Eight bearings is a full turn in 45° steps; the last one is
## returned even if the titan is somehow everywhere, because a summon that spawns is better than one
## that silently does not.
static func _clear_of_the_titan(titan: BroodTitan, arena: BossArena, t: float) -> Vector3:
	var want := BossTuning.RADIUS * 2.5
	var at := arena.ring_point(t, 0.88, 4.0)
	for i in 8:
		at = arena.ring_point(t + float(i) * 0.125, 0.88, 4.0)
		var flat := Vector2(at.x - titan.global_position.x, at.z - titan.global_position.z).length()
		if flat >= want:
			break
	return at


## Phase 3: `LIGHTNING_CIRCLES` telegraphed circles around the player, staggered so the deck lights
## up in a rhythm rather than all at once (juice §11.1: each strike is its own read).
static func storm(titan: BroodTitan) -> void:
	var parent := titan.get_parent()
	if parent == null:
		push_error("BossCombat: the titan has no parent to call lightning into")
		return
	var focus := titan.target_centre()
	for i in BossTuning.LIGHTNING_CIRCLES:
		var angle := TAU * (float(i) / float(BossTuning.LIGHTNING_CIRCLES) + randf() * 0.2)
		var spread := BossTuning.LIGHTNING_SPREAD * (0.4 + 0.6 * float(i + 1)
				/ float(BossTuning.LIGHTNING_CIRCLES))
		var at := focus + Vector3(cos(angle), 0.0, sin(angle)) * spread
		TitanLightning.spawn(parent, at, titan, float(i) * 0.22)
