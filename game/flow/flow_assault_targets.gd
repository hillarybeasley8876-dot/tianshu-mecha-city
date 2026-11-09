class_name FlowAssaultTargets
extends RefCounted
## The E2E bot's eyes and its map of the ground (split out of `FlowDebugAssault`): which lock points
## belong to the beat it is on, which of them it can actually see, and where it could stand to see
## one. It owns the beat (`spire` / `arena_id`) because every question it answers is asked relative
## to it. It never touches the camera or the trigger — that is `FlowAssaultAim`.
##
## The four pods of a spire sit on four bearings, so a player standing still can only ever shoot two
## of them: `firing_spot()` searches a ring of stands round the trunk and tests each one with the
## same ray the gun will use.

## Candidate firing positions round a spire: bearings × ranges × heights above the pod being shot.
## The ring reaches IN to 40 m and UP to 55 m as well (r5 brief item 7): at A2 the Interchange Knot's
## own structure blocks every line from the old 70/100/140 m ring, so a stand that frames the hive has
## to be able to get closer or higher.
const ORBIT_BEARINGS := 8
const ORBIT_RANGES: Array[float] = [40.0, 70.0, 100.0, 140.0]
const ORBIT_LIFTS: Array[float] = [8.0, 30.0, 55.0]
const LOS_RANGE := 420.0
## What the gun asks: `ShotQuery.ray_hits` from the muzzle, MASK_PLAYER_ATTACK, areas on, and the
## TAP's real `max_hits` (`rifle.gd` uses `pierce + 1`, and a tap has pierce 0). The tap is the strict
## test on purpose — if a tap cannot reach a pod, neither can the player's.
const SHOT_MASK := Layers.MASK_PLAYER_ATTACK
const TAP_HITS := 1
## m of slack past the target, so a ray that ends exactly on the hurtbox still registers it.
const SHOT_PAST := 8.0
## m above the mech's feet the muzzle sits, for a candidate stand where there is no model to ask. The
## Pierce-Light's `muzzle_r` socket is on the right shoulder of a 16 m mech.
const MUZZLE_HEIGHT := 10.0
## m a firing position's floor may sit above or below the weak point it is shooting at. Past this the
## bot is on another level of the city and the aim never closes (see `firing_spot`).
const LEVEL_BAND := 30.0
## m above the floor the mech is placed. Its ORIGIN is the capsule CENTRE, so "2 m above the floor"
## buried it 5.5 m in the ground: the solver pushed it out downward, it slid to whatever was below,
## and the A2 beat spent its whole window on a stand 24 m under the hive with the aim 28° off (r5).
const STAND_LIFT := 9.5
## How far below a candidate firing position the bot looks for something to stand on.
const FLOOR_REACH := 140.0
## A weak point counts as this much closer than it is, so the bot shoots the pods and the cores
## rather than the nearest armoured body.
const WEAK_POINT_PULL := 0.5
## Firing positions that have already been proved blind: how near (horizontally) counts as the same
## spot, and how many the bot remembers.
const BAD_NEAR := 45.0
const BAD_SPOTS := 24

## The Hive Spire this beat takes apart, or null when the beat is an arena (or the boss).
var spire: FlowHiveSpire = null
## The arena whose waves this beat clears; `&"boss"` for the Brood Titan.
var arena_id: StringName = &""

var _bearing: int = 0
var _bad_spots: Array[Vector3] = []
var _query: ShotQuery = null


func setup(target: FlowHiveSpire, arena: StringName) -> void:
	spire = target
	arena_id = arena
	_bearing = 0


## Stick with the target the bot is already aiming at for as long as it is legal, visible and in
## range, and only go looking for another one when it is not. Without this the two nearest pods trade
## places every pass — 16° apart at 70 m — and the camera oscillates between them for ever.
func keep_or_pick(player: Node3D, held: Targetable) -> Targetable:
	# `is_valid_target()` alone is not enough: a burst pod keeps its lock point and its position, and
	# only leaves the `targetable` group, so a bot holding it by object reference shoots a corpse for
	# the rest of the beat.
	if held != null and is_instance_valid(held) and held.is_in_group(&"targetable") \
			and held.is_valid_target() and wants(held):
		var from := FlowDebugView.eye()
		if from.distance_to(held.global_position) <= LOS_RANGE \
				and stand_lands_on(muzzle(), held):
			return held
	return best_target(player)


## The nearest legal target the bot's own shot lands on: a weak point of this spire, or any living
## enemy's lock point.
func best_target(player: Node3D) -> Targetable:
	var from := FlowDebugView.eye()
	var from_shot := muzzle()
	var best: Targetable = null
	var best_d := INF
	for node in player.get_tree().get_nodes_in_group(&"targetable"):
		var t := node as Targetable
		if t == null or not t.is_valid_target() or not wants(t):
			continue
		var d := from.distance_to(t.global_position)
		# A weak point is worth walking past a nearer body for: the pods and the titan's cores are
		# where the damage actually is, and a bot that shoots armour proves nothing.
		if t.is_weak_point:
			d *= WEAK_POINT_PULL
		if d > LOS_RANGE or d >= best_d or not stand_lands_on(from_shot, t):
			continue
		best = t
		best_d = d
	return best


## The nearest lock point of this beat, line of sight or not.
func nearest(player: Node3D) -> Targetable:
	var best: Targetable = null
	var best_d := INF
	for node in player.get_tree().get_nodes_in_group(&"targetable"):
		var t := node as Targetable
		if t == null or not wants(t):
			continue
		var d := player.global_position.distance_to(t.global_position)
		if d < best_d:
			best = t
			best_d = d
	return best


## Is this lock point part of the beat the bot is on?
func wants(t: Targetable) -> bool:
	if spire != null:
		return spire.is_ancestor_of(t)
	if arena_id == &"boss":
		return boss_of(t) != null
	return enemy_of(t) != null


## The living Brood Titan this lock point belongs to (its cores are children of it), or null.
func boss_of(t: Targetable) -> Node3D:
	var actor := t.get_parent()
	while actor != null:
		if actor.is_in_group(&"boss"):
			return actor if actor.has_method(&"is_alive") and bool(actor.call(&"is_alive")) else null
		actor = actor.get_parent()
	return null


## The living enemy that owns this lock point, or null.
func enemy_of(t: Targetable) -> Node3D:
	var actor := t.get_parent()
	while actor != null:
		if actor.is_in_group(&"enemy"):
			return actor if actor.has_method(&"is_alive") and bool(actor.call(&"is_alive")) else null
		actor = actor.get_parent()
	return null


## Does the shot the bot is about to fire land on this target? This is the whole of r5 brief item 7's
## second half. The old test was a MASK_SIGHT ray to the target's CENTRE, which the target's own body
## always blocks: the spire collides with its hull and the pods are solved 1 m inside the visible
## skin, so `sees()` passed on 0 of 576 of the bot's own ring lines, it never picked a target and it
## never fired at a hive. The honest question is the gun's: `ShotQuery.ray_hits` from the muzzle, with
## the mask, the areas and the pierce the weapon really uses, and success is this target's own Hurtbox
## among the hits.
## Where the shot really starts: the rifle's own `muzzle_r` socket, NOT the lens. `rifle.gd:_shoot`
## casts from `ctx.socket("muzzle_r")`, so a lens ray can be clear while the muzzle ray is not — which
## is how a whole A6 beat ran at `firing=true` with the hive's HP frozen at 4,550 while every round
## stopped on the Sky Garden deck. Falls back to the lens when the model has no socket (a stub).
static func muzzle() -> Vector3:
	var player := Game.player
	if player != null and player.has_method(&"model"):
		var model := player.call(&"model") as Node3D
		if model != null and model.has_method(&"socket"):
			var n := model.call(&"socket", &"muzzle_r") as Node3D
			if n != null:
				return n.global_position
	return FlowDebugView.eye()


## The trigger gate: does the shot the bot is about to fire RIGHT NOW land on this target? It fires
## from the muzzle along `shot_dir` — the direction the rifle itself will use, which points at the
## CROSSHAIR and not at the target's centre. That distinction is the whole of the A2/A6 plateau: a ray
## aimed at the centre was clear while the real shot, 6 m off at 90 m, grazed past a 6.07 m pod
## hurtbox, so the bot sat at `firing=true` with the hive's HP frozen.
func lands_on(from: Vector3, target: Targetable, max_hits: int = TAP_HITS) -> bool:
	return _hits_box(from, shot_dir(from, target), LOS_RANGE, hurtbox_of(target), max_hits)


## The stand gate: from a candidate position there is no camera yet, so the bot aims straight at the
## target — which is exactly what it is about to do when it gets there.
func stand_lands_on(from: Vector3, target: Targetable, max_hits: int = TAP_HITS) -> bool:
	var box := hurtbox_of(target)
	var to := target.global_position - from
	if box == null or to.length_squared() < 1.0:
		return false
	return _hits_box(from, to.normalized(), minf(to.length() + SHOT_PAST, LOS_RANGE), box, max_hits)


func _hits_box(from: Vector3, dir: Vector3, reach: float, box: Hurtbox,
		max_hits: int) -> bool:
	if box == null or dir.length_squared() < 0.0001:
		return false
	for h: Dictionary in query().ray_hits(from, dir, reach, SHOT_MASK, max_hits):
		if h["collider"] == box:
			return true
	return false


## The direction the rifle will really fire in: `WeaponContext.aim_dir_from(muzzle)`. Reached through
## the player's weapon system because that is where the shot is cast from; falls back to "straight at
## the target" when the mech has no weapon context (a stub, a candidate stand).
static func shot_dir(from: Vector3, target: Targetable) -> Vector3:
	var player := Game.player
	if player != null:
		var weapons: Variant = player.get(&"_weapons")
		var ctx: Variant = weapons.get(&"ctx") if weapons != null else null
		if ctx != null and ctx.has_method(&"aim_dir_from"):
			var d: Vector3 = ctx.call(&"aim_dir_from", from)
			if d.length_squared() > 0.0001:
				return d.normalized()
	var to := target.global_position - from
	return to.normalized() if to.length_squared() > 0.0001 else Vector3.FORWARD


## The shared `ShotQuery` the weapons use, carrying the mech as the shooter so the shots skip it.
func query() -> ShotQuery:
	if _query != null and _query.source == Game.player:
		return _query
	_query = ShotQuery.new(Game.player)
	var skip: Array[RID] = []
	var player := Game.player as CollisionObject3D
	if player != null:
		skip.append(player.get_rid())
	_query.exclude = skip
	return _query


## The Hurtbox that belongs to a lock point: `Targetable` and `Hurtbox` are siblings under the weak
## point's node (flow's spire) or under the enemy's body part.
static func hurtbox_of(t: Targetable) -> Hurtbox:
	if t == null or not is_instance_valid(t):
		return null
	var node := t.get_parent()
	if node == null:
		return null
	for child in node.get_children():
		var box := child as Hurtbox
		if box != null:
			return box
	return null


## What is in the way (diagnostic for the E2E log): the first collider the SHOT meets, not the first
## collider a sight ray meets — those stopped being the same thing when the trunk became a body of its
## own.
func blocker(from: Vector3, to: Vector3) -> String:
	var dir := to - from
	if dir.length_squared() < 0.0001:
		return "clear"
	var hits := query().ray_hits(from, dir.normalized(), minf(dir.length() + SHOT_PAST, LOS_RANGE),
			SHOT_MASK, 3)
	if hits.is_empty():
		return "clear"
	var first: Dictionary = hits[0]
	var at: Vector3 = first["position"]
	return "%s at %.0f of %.0f m" % [(first["collider"] as Node).name, from.distance_to(at),
			from.distance_to(to)]


## Find somewhere the shot actually lands: eight bearings round the trunk, three distances and two
## heights, each tested with the same ray the gun will use. The pods sit on four sides and the
## Interchange Knot's flyovers block most of the rest, so walking blindly round the trunk spends the
## whole beat falling off flyovers. A candidate with ground under it wins; a candidate that only works
## in mid-air is remembered and used last (the mech falls while it shoots, which is better than a beat
## that never fires).
func firing_spot(target: Targetable) -> Vector3:
	var focus := target.global_position if target != null else spire.global_position
	var space := Game.player.get_world_3d().direct_space_state
	var hover := Vector3.INF
	for i in ORBIT_BEARINGS:
		_bearing = (_bearing + 1) % ORBIT_BEARINGS
		var a := TAU * float(_bearing) / float(ORBIT_BEARINGS)
		var out := Vector3(cos(a), 0.0, sin(a))
		for distance in ORBIT_RANGES:
			for lift in ORBIT_LIFTS:
				var at := spire.global_position + out * distance
				at.y = focus.y + lift
				if bad_spot(at) or not lens_lands(at, target):
					continue
				var floor_at := floor_under(space, at)
				if floor_at != Vector3.INF and not bad_spot(floor_at):
					# A floor far below the pod is a different LEVEL of the city. The line can be clear
					# from there and the shot can still never land, because the bot aims the rig by
					# hand and the pitch it needs is outside what it will accept: the r5 A2 livelock was
					# a stand 140 m out and 24 m under the hive, with `view_off` stuck at 28°.
					if absf(floor_at.y - focus.y) <= LEVEL_BAND \
							and lens_lands(floor_at, target) \
							and FlowDebugView.standable(floor_at):
						return floor_at + Vector3.UP * STAND_LIFT
				if hover == Vector3.INF:
					hover = at
	return hover


## This position has just been proved useless (the camera cannot see the target from here): strike
## it off, or the search hands back the same spot every 1.2 s for the whole beat.
func mark_bad(at: Vector3) -> void:
	_bad_spots.append(at)
	if _bad_spots.size() > BAD_SPOTS:
		_bad_spots.pop_front()


## The whole ring has been struck off. A spot that was blind ten seconds ago is not necessarily blind
## now (the pods burst, the trunk's own weak points move), so start the search again rather than
## stand in the open for the rest of the beat.
func clear_bad() -> void:
	_bad_spots.clear()


func bad_count() -> int:
	return _bad_spots.size()


func ring_size() -> int:
	return ORBIT_BEARINGS * ORBIT_RANGES.size() * ORBIT_LIFTS.size()


func bad_spot(at: Vector3) -> bool:
	for bad: Vector3 in _bad_spots:
		# Flat distance: the mech falls off a bad stand, so the spot it was placed on and the spot it
		# ended up on are the same mistake.
		if Vector2(at.x - bad.x, at.z - bad.z).length() < BAD_NEAR:
			return true
	return false


## Would the shot land from this candidate stand? The ray starts at the mech's shoulder there
## (`MUZZLE_HEIGHT`), because that is where the rifle casts from — the r3 code tested the LENS instead,
## which is 42 m behind the mech and behind a different set of walls.
func lens_lands(at: Vector3, target: Targetable) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return stand_lands_on(at + Vector3.UP * MUZZLE_HEIGHT, target)


## The first solid surface under a point, or `Vector3.INF` when there is none within reach.
func floor_under(space: PhysicsDirectSpaceState3D, at: Vector3) -> Vector3:
	var params := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * FLOOR_REACH,
			Layers.MASK_SIGHT)
	params.collide_with_areas = false
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"] as Vector3
