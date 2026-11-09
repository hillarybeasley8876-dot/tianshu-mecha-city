class_name Hero3Ground
extends RefCounted
## The floor under each FOOT, as opposed to the floor under the mech (hero-v3 r9 item 1).
##
## `Hero3Frame.ground()` is the model node's own world y, which is the plane the whole gait plans on.
## That is right on a flat street and on a ramp -- the body follows the surface, so the plane does too
## -- and wrong the moment the two feet are on different surfaces: stepping onto a kerb, the capsule
## has already climbed while the trailing foot is still on the road, so the plane rises 2 m and drags
## the trailing foot up with it while the leading foot is buried in the step. Measured on the sandbox
## kerb: a planted sole 0.92 m above the surface under it and another 1.10 m inside it.
##
## One ray per foot per tick, straight down from just above the plant, masked to `Layers.WORLD`. With
## no world under the model -- every filmstrip and unit gate runs the mech in an empty scene -- the
## ray finds nothing and the flat plane is used unchanged, so this cannot change a single number that
## is not measured against real geometry.

## How far above the planned plane the ray starts, and how far below it still counts. The band has to
## cover a 2 m kerb from either side and must not reach the floor of a storey below.
const UP := 4.0
const DOWN := 12.0
## How fast a foot's floor height may follow a surface it has just stepped onto, in m/s. Without it a
## plant that lands on a kerb edge pops the whole leg up in one tick.
const FOLLOW := 26.0

var _world: World3D = null
var _query: PhysicsRayQueryParameters3D = null
## Per-foot smoothed height, and the XZ it was last solved for, so a plant that has not moved is not
## re-rayed every tick.
var _height: Array[float] = [0.0, 0.0]
var _solved: Array[bool] = [false, false]


func setup(skeleton: Skeleton3D) -> void:
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN)
	_query.collision_mask = Layers.WORLD
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_world = skeleton.get_world_3d()


## The floor under `at`, or `plane` when there is no world there. `plane` is the flat plane the gait
## planned on, and it is also what the ray starts from.
func under(index: int, at: Vector3, plane: float, delta: float) -> float:
	if _query == null or _world == null:
		return plane
	var want := _ray(at, plane)
	if not _solved[index]:
		_height[index] = want
		_solved[index] = true
		return want
	_height[index] = move_toward(_height[index], want, FOLLOW * maxf(delta, 0.0))
	return _height[index]


## Forget the smoothed heights: a teleport, a respawn or a gait reset puts the feet somewhere the
## smoothing has no business interpolating from.
func reset() -> void:
	_solved = [false, false]


func _ray(at: Vector3, plane: float) -> float:
	_query.from = Vector3(at.x, plane + UP, at.z)
	_query.to = Vector3(at.x, plane - DOWN, at.z)
	var hit := _world.direct_space_state.intersect_ray(_query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else plane
