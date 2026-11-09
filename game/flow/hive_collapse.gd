class_name FlowHiveCollapse
extends Node
## The death of a Hive Spire — the reward beat (brief §3, lead r1 must-fix 5). A 2 s cinematic in the
## duel frame (hero → spire, CONTRACTS §5): a wide shot from ~110 m, the spire toppling away from the
## hero, three blasts chaining UP the trunk, the destroyed mesh and a smoke column that stays. Control
## returns when the shot list runs out.
##
## Cinematic timing on the unscaled clock, so the slow-mo the FEEL `kill_large` row fires stretches the
## explosions instead of racing them — but accumulated per frame (`Feel.real_delta`, CONTRACTS §3)
## rather than read from `Feel.real_now()`, which keeps running while the tree is paused and would fire
## the rest of the chain in one frame after a pause (audit #5).

## s, real clock, base → crown. The first one waits for the camera to arrive: a blast that goes off
## while the shot is still blending fills the frame with fire instead of showing the spire.
const BLAST_GAPS: Array[float] = [0.25, 0.62, 1.00]
## Fraction of the spire height each blast sits at, and how big its fireball is. `kill_large` is
## already a 20 m effect, so these stay small — the beat is the chain up the trunk, not one wall of
## flame across the lens (lead r1 must-fix 5).
const BLAST_HEIGHT: Array[float] = [0.14, 0.46, 0.78]
const BLAST_SCALE: Array[float] = [0.7, 0.9, 1.2]
const SWAP_AT := 1.35              ## s: the destroyed mesh replaces the toppling trunk
const WRECK_SMOKE := 30.0          ## s the column burns (juice §7 permanence)
const SHOT_TIME := 2.0             ## s of camera before control returns
const TOPPLE_TIME := 1.25          ## s the trunk takes to go over
const TOPPLE_ANGLE := 1.05         ## rad it has fallen by the time the destroyed mesh takes over
const RING_RADIUS := 90.0
const DEBRIS := 24
## The hero is shoved clear of the wreck when it is standing this close to the base.
const PUSH_RANGE := 30.0
const PUSH_SPEED := 26.0
const PUSH_LIFT := 9.0

var _visual: FlowHiveVisual = null
var _at: Vector3 = Vector3.ZERO
var _height: float = 60.0
var _step: int = 0
var _t: float = 0.0
var _smoke: Node3D = null
var _swapped: bool = false
var _fall_axis: Vector3 = Vector3.RIGHT
## The camera (lead brief flow-r5b item 2). `_eye` and `_focus` are WORLD points solved by
## `FlowCollapseShot`; the shot is re-pinned to them every tick, because the duel frame the rig reads
## a cinematic's offset in is rebuilt from the live actors — an offset solved once rides the hero.
var _rig: Node = null
var _eye: Vector3 = Vector3.ZERO
var _focus: Vector3 = Vector3.ZERO
var _placed: bool = false
## Which candidate family the stand came from — `&"hero_side"` is the composition the beat wants (the
## mech in the foreground), `&"ring"` is the fallback for a hive whose hero-side is walled in, and
## `&"overhead"` means the site has no stand at all. Read by the collapse-camera test.
var family: StringName = &""
var _shot_open: bool = false
var _reject: Array[Vector3] = []
var _resolves: int = 0
## m the rig may miss the solved eye by before the shot is re-solved. One tick of hero motion (a
## boosting mech covers 0.45 m) plus the landing dip.
const PIN_TOLERANCE := 2.5
## m the hero must keep from the lens — the solver's own floor, re-checked here because the hero
## walks during the shot.
const HERO_CLEAR := FlowCollapseShot.MIN_HERO_GAP
## Re-solving is a sweep of candidate stands; a shot that cannot hold one is re-solved this many times
## and then left where it is, rather than sweeping every tick for two seconds.
const MAX_RESOLVES := 8


## `spire` is the dying node (its position is the blast origin); `visual` may be null.
func run(spire: Node3D, visual: FlowHiveVisual, height: float) -> void:
	_visual = visual
	_at = spire.global_position if spire != null else Vector3.ZERO
	_height = height
	_t = 0.0
	_fall_axis = _fall_axis_away_from_player()
	_shoot()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_t += Feel.real_delta(delta)
	var t := _t
	if t <= SHOT_TIME:
		_camera_tick()
	while _step < BLAST_GAPS.size() and t >= BLAST_GAPS[_step]:
		_blast(_step)
	_topple(clampf((t - BLAST_GAPS[0]) / TOPPLE_TIME, 0.0, 1.0))
	if not _swapped and t >= SWAP_AT:
		_swap_destroyed()
	# The node only has to outlive the shot for the smoke column; without one it goes as soon as the
	# camera has handed the view back.
	if t > (SWAP_AT + WRECK_SMOKE if _smoke != null else SHOT_TIME + 0.5):
		_release()
		queue_free()


# --- the camera (lead brief flow-r5b item 2) -------------------------------------------------------

## One wide shot held for the whole beat: the spire in frame with the hero small in front of it, so
## the topple and the chain up the trunk read as one composition. A push-in was tried and cut — the
## crown blast then filled the lens and the silhouette was lost (lead r1 must-fix 5).
##
## The stand is SOLVED against the city (`FlowCollapseShot`), not assumed: the old fixed offset was
## built in world axes and read in the duel frame, so the hero's yaw rotated it and the lens landed
## wherever that put it — inside a building at A5, behind a wall at A6. The aim lock is released
## first so nothing stale decides the frame.
func _shoot() -> void:
	var rig := Game.camera_rig
	if rig == null or not rig.has_method(&"request_cinematic"):
		return
	var hero := Game.player as Node3D
	if hero == null:
		return
	var aim := hero.call(&"aim") as Node if hero.has_method(&"aim") else null
	if aim != null and aim.has_method(&"lock_to"):
		aim.call(&"lock_to", null)
	_rig = rig
	_shot_open = true
	if rig.has_method(&"hold_fov"):
		rig.call(&"hold_fov", FlowCollapseShot.FOV)
	_place(hero)
	_pin(SHOT_TIME)


## Solve a stand that is in clear air, sees the spire's base and top, and frames the hero — and say so
## when the site has none.
func _place(hero: Node3D) -> void:
	var shot := FlowCollapseShot.solve(_space(), hero.global_position, _at, _height, _reject)
	_eye = shot["eye"] as Vector3
	_focus = shot["focus"] as Vector3
	_placed = bool(shot["ok"])
	family = shot["family"] as StringName
	if not _placed:
		push_warning("FlowHiveCollapse: no stand round the hive at %s is clear — filming from overhead"
				% str(_at))


## Take the lens and hold it there.
##
## An EMPTY shot list is the hook. `CameraCinematic.request` still makes the cinematic active — so the
## rig stops following the hero, stops writing its own transform and keeps advancing only the shake —
## but `_apply` is never called, so the camera unit's collision resolve never runs either. That
## resolve pulls the lens back along a ray from the duel frame's origin (the hero), which cannot reach
## a stand on the far side of a building: at A2 only 42 stands out of 1,344 can see the hive at all,
## and every one of them is across the Interchange Knot. Flow places the lens itself, against the
## world, and re-checks it every tick.
##
## `remaining` of 0 hands the view straight back (`request` cancels, and `end_cinematic` restores the
## arm, the FOV and the look input), which is how the shot closes exactly on `SHOT_TIME`.
func _pin(remaining: float) -> void:
	if _rig == null or not is_instance_valid(_rig):
		return
	_rig.call(&"request_cinematic", [] as Array, maxf(remaining, 0.0))
	var dir := _focus - _eye
	if remaining <= 0.0 or dir.length_squared() < 0.01:
		return
	(_rig as Node3D).global_transform = Transform3D(
			Basis.looking_at(dir.normalized(), Vector3.UP), _eye)
	if _rig.has_method(&"set_arm_length"):
		_rig.call(&"set_arm_length", 0.0)


## Keep the lens on the solved eye, and re-solve the moment it cannot be: the hero walks, and a stand
## that was clear at the core's death can have the mech standing in it a second later. The check is on
## where the CAMERA actually is, landing dip and all.
func _camera_tick() -> void:
	var hero := Game.player as Node3D
	if hero == null or _rig == null or not is_instance_valid(_rig):
		return
	if _t >= SHOT_TIME:
		_pin(0.0)
		return
	_pin(SHOT_TIME - _t)
	if _resolves >= MAX_RESOLVES:
		return
	var cam := _rig.call(&"camera") as Node3D if _rig.has_method(&"camera") else null
	var at := cam.global_position if cam != null else (_rig as Node3D).global_position
	if at.distance_to(_eye) <= PIN_TOLERANCE \
			and at.distance_to(hero.global_position) >= HERO_CLEAR \
			and not FlowCollapseShot.inside(_space(), at):
		return
	_resolves += 1
	_reject.append(_eye)
	_place(hero)
	_pin(SHOT_TIME - _t)


## Hand the view back if the sequence stops early (a respawn rebuilds the spire, `cancel`).
func _end_shot() -> void:
	if not _shot_open:
		return
	_shot_open = false
	if _rig != null and is_instance_valid(_rig) and _rig.has_method(&"request_cinematic"):
		_rig.call(&"request_cinematic", [] as Array, 0.0)


func _space() -> PhysicsDirectSpaceState3D:
	return get_viewport().world_3d.direct_space_state



## The trunk goes over, away from the hero: an accelerating tip about the base, no bounce.
func _topple(t: float) -> void:
	if _visual == null or _swapped:
		return
	_visual.rotation = _fall_axis * (TOPPLE_ANGLE * t * t)


func _fall_axis_away_from_player() -> Vector3:
	var player := Game.player as Node3D
	if player == null:
		return Vector3.RIGHT
	var away := _at - player.global_position
	away.y = 0.0
	if away.length_squared() < 1.0:
		return Vector3.RIGHT
	# Rotating about `axis` by +angle tips the +Y axis towards `-axis × UP`; pick the side the hero is
	# not on, so the spire never falls into the camera.
	var dir := away.normalized()
	return Vector3.UP.cross(dir).normalized()


func _blast(index: int) -> void:
	_step = index + 1
	var at := _at + Vector3.UP * _height * BLAST_HEIGHT[index] \
			+ Vector3(cos(float(index) * 2.1), 0.0, sin(float(index) * 2.1)) * _height * 0.12
	var big := index == BLAST_GAPS.size() - 1
	Feel.play(&"kill_large", at, 1.0 if big else 0.7)
	FxBridge.spawn(self, &"kill_large", at, Vector3.UP, BLAST_SCALE[index])
	FxBridge.ring(self, at, Vector3.UP, RING_RADIUS, 0.5, Color(0.7, 1.0, 0.3))
	if index == 0:
		_shove_hero()
	if big:
		Audio.stinger(&"stinger_spire_cleared")


## SPEC §4 `apply_impulse`: the base blast throws a mech standing in it clear instead of burying it —
## the collapse is a reward, not a punishment for being close. It fires on the first blast, so the
## shove reads as the start of the chain rather than as a late afterthought.
func _shove_hero() -> void:
	var player := Game.player as Node3D
	if player == null or not player.has_method(&"apply_impulse"):
		return
	var away := player.global_position - _at
	away.y = 0.0
	if away.length() > PUSH_RANGE:
		return
	if away.length_squared() < 1.0:
		away = Vector3.FORWARD
	player.call(&"apply_impulse", away.normalized() * PUSH_SPEED + Vector3.UP * PUSH_LIFT)


func _swap_destroyed() -> void:
	_swapped = true
	if _visual != null:
		_visual.rotation = Vector3.ZERO
		_visual.set_state(&"destroyed")
	Feel.slow_mo(0.35, 0.35)
	var lib := FxBridge.library(self)
	if lib == null:
		# No FX library in the tree (a headless run, or `--stub=fx`). There is no smoke column to hold,
		# but the SHOT still has most of a second to run: freeing the node here used to hand the view
		# back at 1.35 s and cut the beat short.
		push_warning("FlowHiveCollapse: no FX library — the wreck burns without its smoke column")
		return
	lib.call(&"spawn_debris", _at + Vector3.UP * _height * 0.4, DEBRIS, 22.0, 3.0)
	_smoke = lib.call(&"emitter", &"smoke_column", _at + Vector3.UP * _height * 0.3, 4.0) as Node3D


func _release() -> void:
	set_physics_process(false)
	_end_shot()
	if _smoke == null:
		return
	var lib := FxBridge.library(self)
	if lib != null:
		lib.call(&"release_emitter", _smoke)
	_smoke = null


## Respawn restore (`FlowHiveSpire.reset_full`): a spire that fell after the checkpoint comes back, so
## the sequence stops here — the wreck smoke goes back to the pool and the node frees itself.
func cancel() -> void:
	if _smoke == null:
		_end_shot()
		queue_free()
		return
	_release()
	queue_free()
