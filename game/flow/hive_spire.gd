class_name FlowHiveSpire
extends StaticBody3D
## A Hive Spire objective (蚀巢, brief §3; SPEC §7.1). 60 m of armoured trunk with four glowing pods
## and a core: 4 × 3,500 + 6,000 = 20,000 HP, all of it in the weak points. The trunk itself is
## immune — that is the whole read of the fight, so `take_hit` answers a body shot with zero damage
## instead of a chip that teaches the player the wrong thing.
##
## While it stands it births rippers from its base every 12 s (cap 8, counted per spire), which is the
## pacing pressure of the arena. `GameFlow` listens to `destroyed` for the objective, the checkpoint,
## the roar and the TimeOfDay step; the spire itself only owns its own fight.

signal pod_burst(index: int, remaining: int)
signal core_exposed()
signal destroyed(spire: FlowHiveSpire)

const POD_HP := 3500.0            ## SPEC §7.1
const CORE_HP := 6000.0
const PODS := 4
const POD_PART := "pod_"
## The spire's own brood: SPEC §8 escalation is the arena's job, this is the floor under it.
const BROOD_TYPE := &"ripper"
const BROOD_INTERVAL := 12.0
const BROOD_CAP := 8
const BROOD_RADIUS := 34.0
const BROOD_SPREAD := 3
## Body shots spark and do nothing (see the header).
const BODY_ABSORB := 0.0
const HURTBOX_GROWTH := 1.35      ## generous weak points: a 16 m mech should not pixel-hunt a 4 m pod

var spire_id: StringName = &"hive"
var arena_id: StringName = &""
var height: float = 60.0
var alive: bool = true

## The weak-point pools are `POD_HP` / `CORE_HP` × this. It is 1.0 in every normal run;
## `--spire-hp-scale` (flow_debug) lowers it so a scripted end-to-end run fits inside its recording
## budget — 20,000 HP a hive at the city's frame rate is six minutes of trigger time per spire. A
## respawn honours it, so a scaled hive never comes back at full strength.
var hp_scale: float = 1.0

var _visual: FlowHiveVisual = null
## The trunk's own body: a plain StaticBody3D with no `take_hit`, so a shot that stops on the shell is
## scenery and shows nothing (see `_build_trunk`).
var _trunk: StaticBody3D = null
var _pod_hp: Array[float] = []
var _core_hp: float = CORE_HP
var _pod_boxes: Array[Hurtbox] = []
var _core_box: Hurtbox = null
var _core_target: Targetable = null
var _brood: Array[Node3D] = []
var _brood_t: float = BROOD_INTERVAL
var _flash: float = 0.0


func _ready() -> void:
	add_to_group(&"hive_spire")
	# The spire NODE carries no collision of its own: the trunk is a child body (see `_build_trunk`),
	# and the weak points are Hurtbox areas. A body with no shape is what keeps the trunk from being a
	# shot receiver.
	collision_layer = 0
	collision_mask = 0
	_pod_hp.resize(PODS)
	_pod_hp.fill(POD_HP * hp_scale)
	_core_hp = CORE_HP * hp_scale
	_build()


func setup(id: StringName, arena: StringName) -> void:
	spire_id = id
	arena_id = arena


## Set the weak-point pools to the SPEC §7.1 numbers times `factor` (see `hp_scale`).
func scale_hp(factor: float) -> void:
	hp_scale = clampf(factor, 0.01, 1.0)
	_pod_hp.fill(POD_HP * hp_scale)
	_core_hp = CORE_HP * hp_scale


## The four pods in world space — the visual owns their placement on the trunk. The E2E bot scores
## candidate firing stands against them (flow_debug_view).
func pod_world_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _visual == null:
		return out
	for at: Vector3 in _visual.pod_positions():
		out.append(to_global(at))
	return out


## Where the core sits and which way it faces, in world space — the harness stands square on it for
## the A/B capture of the torn opening (flow-look-r1 polish 1).
func core_world_position() -> Vector3:
	return to_global(_visual.core_position()) if _visual != null else global_position


func core_out() -> Vector3:
	return _visual.core_normal() if _visual != null else Vector3.FORWARD


# --- construction ---------------------------------------------------------------------------------

func _build() -> void:
	_visual = FlowHiveVisual.new()
	_visual.name = "Visual"
	add_child(_visual)
	_visual.build(height)
	_build_trunk()
	for i in PODS:
		var at := _visual.pod_positions()[i]
		_pod_boxes.append(_weak_point("Pod%d" % i, StringName("%s%d" % [POD_PART, i]),
				at, height * FlowHiveVisual.POD_RADIUS * HURTBOX_GROWTH))
	_core_box = _weak_point("Core", &"core", _visual.core_position(), height * 0.13)
	var core_node := _core_box.get_parent() as Node3D
	_core_target = core_node.get_node_or_null(^"Target") as Targetable
	_expose_core(false)


## The trunk's collision is its OWN body, a plain `StaticBody3D` with no `take_hit` (r5 brief item 7).
## `ShotQuery.deliver` treats any collider that answers `take_hit` as a receiver and emits
## `hit_landed` plus a hit marker for it even when `final_amount` comes back 0 — so leaving the
## collision on the spire node itself drew a white X and a "230" on every trunk tap while the hive's
## HP did not move. The weak points are Hurtboxes, and `Hurtbox.apply` routes those to the spire.
##
## The shape follows the SKIN: monster-assets' `HiveCollision` is a convex hull that stands 4–17 m
## outside the visible mesh along the pod bearings, which buried three of the four pods and the core
## behind invisible air (`FlowHiveSurface.skin_shape`).
func _build_trunk() -> void:
	_trunk = StaticBody3D.new()
	_trunk.name = "Trunk"
	_trunk.collision_layer = Layers.WORLD
	_trunk.collision_mask = 0
	add_child(_trunk)
	var trunk := _trunk
	var shape := CollisionShape3D.new()
	shape.transform = _visual.transform
	var skin := _visual.skin_shape()
	var hull := _visual.hull_shape() if skin == null else null
	if skin != null:
		shape.shape = skin
	elif hull != null:
		push_warning("FlowHiveSpire: no visible hive mesh — the trunk falls back to the collision hull")
		shape.shape = hull
	else:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = _visual.hull_radius(height * 0.5)
		cylinder.height = height
		shape.shape = cylinder
		shape.position += Vector3.UP * height * 0.5
	trunk.add_child(shape)


## The trunk is solid ground and a shot blocker while the spire stands, and neither once it has fallen.
func _set_trunk_solid(on: bool) -> void:
	if _trunk != null and is_instance_valid(_trunk):
		_trunk.collision_layer = Layers.WORLD if on else 0


## A weak point: a Hurtbox the player's shots can find plus a Targetable the lock-on can hold.
func _weak_point(node_name: String, part: StringName, at: Vector3, radius: float) -> Hurtbox:
	var node := Node3D.new()
	node.name = node_name
	node.position = at
	add_child(node)
	var target := Targetable.new()
	target.name = "Target"
	target.radius = radius
	target.is_weak_point = true
	node.add_child(target)
	var box := Hurtbox.new()
	box.name = "Hurtbox"
	box.part = part
	box.is_weak_point = true
	box.collision_layer = Layers.ENEMY_HURTBOX
	box.collision_mask = 0
	var sphere := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = maxf(radius, 2.0)
	sphere.shape = shape
	box.add_child(sphere)
	node.add_child(box)
	return box


func _expose_core(on: bool) -> void:
	if _core_box == null:
		return
	_core_box.collision_layer = Layers.ENEMY_HURTBOX if on else 0
	if _visual != null and _visual.core != null:
		_visual.core.set_open(on and alive)
	# The core is not a lock-on point until the shell is open, or the player could lock a target it
	# cannot hurt.
	if _core_target != null:
		if on and not _core_target.is_in_group(&"targetable"):
			_core_target.add_to_group(&"targetable")
		elif not on and _core_target.is_in_group(&"targetable"):
			_core_target.remove_from_group(&"targetable")


# --- damage (CONTRACTS §4) -----------------------------------------------------------------------

func take_hit(hit: HitInfo) -> void:
	if not alive:
		return
	var part := String(hit.hurtbox_part)
	if part.begins_with(POD_PART):
		_damage_pod(int(part.substr(POD_PART.length())), hit)
	elif part == "core":
		_damage_core(hit)
	else:
		hit.final_amount = BODY_ABSORB
		return
	Events.hit_landed.emit(hit, self)


func _damage_pod(index: int, hit: HitInfo) -> void:
	if index < 0 or index >= PODS or _pod_hp[index] <= 0.0:
		hit.final_amount = BODY_ABSORB
		return
	var dealt := minf(hit.amount, _pod_hp[index])
	_pod_hp[index] -= dealt
	hit.final_amount = dealt
	_flash = 1.0
	if _pod_hp[index] > 0.0:
		return
	_burst_pod(index)


func _burst_pod(index: int) -> void:
	var box := _pod_boxes[index]
	box.collision_layer = 0
	var node := box.get_parent() as Node3D
	var at := node.global_position if node != null else global_position
	var normal := _visual.pod_normal(index) if _visual != null else Vector3.UP
	if _visual != null:
		_visual.burst_pod(index)
	var target := node.get_node_or_null(^"Target") as Targetable if node != null else null
	if target != null:
		target.remove_from_group(&"targetable")
	Feel.play(&"kill_large", at, 0.6)
	FxBridge.spawn(self, &"kill_large", at, normal, 0.5)
	_acid_burst(at, normal)
	Audio.play(&"core_rupture", at)
	var left := _pods_left()
	pod_burst.emit(index, left)
	if left == 0:
		_crack_open()


## A burst pod leaves a mark (look/flow.md item 1): acid vapour and sparks out along the trunk's
## normal, a green flash on the shell, and a scorch scar stamped where the sac was. The sacs
## themselves are gone — this is what stays on the trunk for the rest of the fight.
func _acid_burst(at: Vector3, normal: Vector3) -> void:
	FxBridge.spawn(self, &"spark_burst", at, normal, 2.0)
	FxBridge.spawn(self, &"steam", at + normal * 1.5, normal, 3.0)
	FxBridge.flash(self, at + normal * 2.0, FlowHiveVisual.POD_COLOR, 3.0, 26.0, 8.0)
	FxBridge.ring(self, at, normal, 12.0, 0.45, FlowHiveVisual.POD_COLOR)
	var lib := FxBridge.library(self)
	if lib == null:
		return
	var pool := lib.get(&"decals") as Node
	if pool != null and pool.has_method(&"add"):
		pool.call(&"add", &"scorch", at, normal, 2.4, Color(0.5, 0.8, 0.35))


func _crack_open() -> void:
	if _visual != null:
		_visual.set_state(&"cracked")
		_visual.shake()
	var at := to_global(_visual.core_position()) if _visual != null else global_position
	var normal := _visual.core_normal() if _visual != null else Vector3.UP
	FxBridge.spawn(self, &"steam", at + normal * 2.0, normal, 4.0)
	_expose_core(true)
	Audio.stinger(&"stinger_kill_large")
	core_exposed.emit()


func _damage_core(hit: HitInfo) -> void:
	if _pods_left() > 0:
		hit.final_amount = BODY_ABSORB
		return
	var dealt := minf(hit.amount, _core_hp)
	_core_hp -= dealt
	hit.final_amount = dealt
	_flash = 1.0
	if _core_hp <= 0.0:
		collapse()


func _pods_left() -> int:
	var left := 0
	for hp in _pod_hp:
		if hp > 0.0:
			left += 1
	return left


# --- destruction --------------------------------------------------------------------------------

## The spire dies: the camera takes the fall (`FlowHiveCollapse` solves its own stand), the chain
## explosions run, the model swaps to its destroyed state, the trunk stops being solid ground and the
## objective counter moves. GameFlow owns everything that happens after that.
func collapse() -> void:
	if not alive:
		return
	alive = false
	remove_from_group(&"hive_spire")
	for box in _pod_boxes:
		box.collision_layer = 0
	_expose_core(false)
	_set_trunk_solid(false)
	# The contract signal goes out FIRST, so every beat the flow hangs off it — the checkpoint, the
	# objective, the roar and, on the third spire, the boss gate's vista cinematic — has already asked
	# for the camera before the collapse does. The collapse's shot is then the last request and the one
	# that wins; the other order filmed the third hive's fall through the gate's 300 m vista (r5
	# brief item 8).
	destroyed.emit(self)
	var node := FlowHiveCollapse.new()
	node.name = "Collapse"
	add_child(node)
	node.run(self, _visual, height)


func is_alive() -> bool:
	return alive


func get_team() -> int:
	return 1


func hit_pause(seconds: float) -> void:
	_flash = maxf(_flash, clampf(seconds * 4.0, 0.0, 1.0))


## Aggregate health for the HUD's enemy plates: pods plus core, so the bar reads as one objective
## (20,000 HP) from the first shot, whether or not the core is reachable yet.
func hud_state() -> Dictionary:
	return {"name": "蚀巢 HIVE SPIRE", "hp": total_hp(), "hp_max": PODS * POD_HP + CORE_HP,
			"pods_left": _pods_left(), "alive": alive}


func total_hp() -> float:
	var total := maxf(_core_hp, 0.0)
	for hp in _pod_hp:
		total += maxf(hp, 0.0)
	return total


func core_exposed_now() -> bool:
	return _pods_left() == 0


# --- brood ----------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 4.0, 0.0)
		if _visual != null:
			_visual.flash(_flash)
	if not alive:
		return
	_brood_t -= delta
	if _brood_t > 0.0:
		return
	_brood_t = BROOD_INTERVAL
	_birth_brood()


func _birth_brood() -> void:
	_prune_brood()
	if _brood.size() >= BROOD_CAP or Game.has_flag("no-enemies"):
		return
	var spawner := FlowSpawner.get_spawner(self)
	if spawner == null:
		return
	var base := global_position + Vector3.UP * 2.0
	var seed_t := float(hash(spire_id)) / 4294967296.0
	_brood.append_array(FlowSpawner.spawn_ring(spawner, BROOD_TYPE, base, BROOD_SPREAD,
			BROOD_RADIUS, seed_t))


func _prune_brood() -> void:
	for i in range(_brood.size() - 1, -1, -1):
		var e := _brood[i]
		if not is_instance_valid(e) or (e.has_method(&"is_alive") and not bool(e.call(&"is_alive"))):
			_brood.remove_at(i)


func brood_count() -> int:
	_prune_brood()
	return _brood.size()


## Respawn restore (SPEC §7.1): a spire the checkpoint did not have down comes back whole, so a death
## never leaves a half-eaten objective the player cannot finish reading. A spire that fell AFTER the
## checkpoint is rebuilt from its destroyed state — otherwise it would stand destroyed but uncounted
## and the run could never reach 3/3.
func reset_full() -> void:
	if not alive:
		_rebuild()
	_pod_hp.fill(POD_HP * hp_scale)
	_core_hp = CORE_HP * hp_scale
	for i in PODS:
		_pod_boxes[i].collision_layer = Layers.ENEMY_HURTBOX
		var node := _pod_boxes[i].get_parent() as Node3D
		var target := node.get_node_or_null(^"Target") as Targetable if node != null else null
		if target != null and not target.is_in_group(&"targetable"):
			target.add_to_group(&"targetable")
		if _visual != null:
			_visual.restore_pod(i)
	if _visual != null:
		_visual.rotation = Vector3.ZERO
		_visual.set_state(&"intact")
	_expose_core(false)
	_brood_t = BROOD_INTERVAL


## Undo a collapse: stop the death sequence, put the trunk back on its base and make it solid ground
## and a legal target again.
func _rebuild() -> void:
	for child in get_children():
		if child is FlowHiveCollapse:
			(child as FlowHiveCollapse).cancel()
	alive = true
	_set_trunk_solid(true)
	if not is_in_group(&"hive_spire"):
		add_to_group(&"hive_spire")
