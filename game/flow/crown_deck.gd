class_name FlowCrownDeck
extends RefCounted
## Where the Crown's fighting floor is, and whether the mech is really standing on it (r5 brief
## item 2). The Ascension Catapult's arc crosses deck tiles, and `is_on_floor()` goes true while the
## capsule overlaps one — so "the player has landed" cannot be `is_grounded()`. This file is the
## probed answer: a standable point on the top disc, and a touchdown test that a kinematic flight can
## never pass.
##
## Everything is duck-typed and probed, because the deck belongs to the city (or to `BossArena` in the
## sandbox) and either can be stubbed out.

## `BossTuning.CROWN_CENTRE` — the layout's `B1_crown`, used when no arena node has been built yet.
const CENTRE := Vector3(0.0, 224.0, -120.0)
## `BossTuning.DECK_RADIUS`, which `BossArena.ring_point` takes its radius fraction against.
const DECK_RADIUS := 150.0
## The top disc is `RIM_STEPS[2]`: r 104 at +16 m over the deck origin, so the fighting floor is the
## ring between the Ø80 core and r 104. The landing and the boss checkpoints stand inside it.
const FIGHT_RADIUS := 104.0
## The S4 side of the deck (t = 0.75 is due south of the Crown centre, which is where the catapult
## pad is) and how far out on it: the lead's r 50-80 m, clear of the core and of the rim step.
const S4_BEARING := 0.75
const S4_RADIUS := 65.0
const PROBE_UP := 160.0        ## m above the deck origin the floor probe starts
const PROBE_DOWN := 220.0      ## m it reaches down
## How close under the feet the deck has to be for a touchdown, and how wide the chest probe is.
const FOOT_REACH := 3.0
const CHEST_RADIUS := 3.0


## The arena node's origin when the fight has one, else the layout's own Crown centre.
static func centre(tree: SceneTree) -> Vector3:
	var arena := tree.get_first_node_in_group(&"boss_arena") as Node3D
	if arena != null and is_instance_valid(arena):
		return arena.global_position
	return CENTRE


## A standable point on the fighting floor, on bearing `t` (0-1) at `radius` metres from the centre.
## The arena's own `ring_point` answers when it is there — it knows whether the deck is its own
## geometry or the city's — and a ray onto `Layers.WORLD` answers when it is not. Never mid-air: a
## probe that finds no floor keeps the deck origin's own height and says so.
static func fight_point(tree: SceneTree, t: float = S4_BEARING, radius: float = S4_RADIUS) -> Vector3:
	var arena := tree.get_first_node_in_group(&"boss_arena") as Node3D
	if arena != null and is_instance_valid(arena) and arena.has_method(&"ring_point"):
		return arena.call(&"ring_point", t, radius / DECK_RADIUS) as Vector3
	var at := centre(tree)
	var angle := TAU * fposmod(t, 1.0)
	var want := at + Vector3(cos(angle), 0.0, sin(angle)) * radius
	var floor_y := floor_under(tree, want, at.y)
	if is_nan(floor_y):
		push_warning("FlowCrownDeck: no floor under %.0f,%.0f — this world has no Crown deck"
				% [want.x, want.z])
		return want
	return Vector3(want.x, floor_y, want.z)


## The world height of the deck under `at`, or NAN when there is nothing there.
static func floor_under(tree: SceneTree, at: Vector3, deck_y: float) -> float:
	var space := _space(tree)
	if space == null:
		return NAN
	var from := Vector3(at.x, deck_y + PROBE_UP, at.z)
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * PROBE_DOWN,
			Layers.WORLD)
	var hit := space.intersect_ray(query)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y


## A real touchdown on the Crown: the mech is not in the catapult's kinematic flight, its feet are on
## the deck (a short ray down hits WORLD within `FOOT_REACH`) and nothing overlaps its chest. The old
## test — `y >= 224 and is_grounded()` — fires 45 times during the arc, because the capsule overlaps a
## deck tile on the way through (r5 brief item 2).
static func touched_down(tree: SceneTree, player: Node3D) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if is_locked(player):
		return false
	var feet := player.global_position.y - FlowBounds.half_height(player)
	if not _feet_on(tree, player.global_position, feet):
		return false
	return not buried(tree, player)


## The catapult's kinematic flight and the Rift Step lunge both hold the mech in `LOCKED`; either one
## means the transform is being written by something other than the player.
static func is_locked(player: Node3D) -> bool:
	if not player.has_method(&"move_state"):
		return false
	return StringName(player.call(&"move_state")) == &"locked"


## Nothing solid where the mech is: a capsule cast is the honest test, a point test would miss a rib
## the mech is standing inside. Public because a checkpoint probe wants the same answer.
static func buried(tree: SceneTree, player: Node3D) -> bool:
	var space := _space(tree)
	if space == null:
		return false
	var half := FlowBounds.half_height(player)
	var shape := CapsuleShape3D.new()
	shape.radius = CHEST_RADIUS
	shape.height = maxf(half * 1.6, CHEST_RADIUS * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, player.global_position)
	query.collision_mask = Layers.WORLD
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return not space.intersect_shape(query, 1).is_empty()


static func _feet_on(tree: SceneTree, at: Vector3, feet: float) -> bool:
	var space := _space(tree)
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, feet + FOOT_REACH, at.z),
			Vector3(at.x, feet - FOOT_REACH, at.z), Layers.WORLD)
	return not space.intersect_ray(query).is_empty()


## The physics world, taken from the root viewport: a test host's "current scene" is the test script
## itself, and a headless fixture has no Node3D to ask, so this is the one lookup that always answers.
static func _space(tree: SceneTree) -> PhysicsDirectSpaceState3D:
	var root := tree.root as Viewport
	if root == null:
		return null
	var world := root.find_world_3d()
	return null if world == null else world.direct_space_state
