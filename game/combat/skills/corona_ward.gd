class_name CoronaWard
extends Node3D
## Corona Ward (防护罩) — the hold half of the Corona Fins (skills-catalog §4.4 S4).
##
## Four of the six wing blades take the vertices of a tetrahedron around the hero and hold a barrier
## on `Layers.BARRIER` for 6 s that absorbs 3,000 points of PROJECTILE damage. It does not stop melee,
## shockwaves, or anything fired from inside the sphere — that is the counterplay, and it is why the
## barrier is a positioning tool rather than a wall. The remaining two fins escort, auto-firing 60
## damage every 0.5 s at whatever is nearest.
##
## The absorption runs through `PlayerMech.add_damage_filter`, the contract's own hook, so nothing in
## the player's damage pipeline needs to know the ward exists.

const RADIUS := 14.0                 ## [tuning] a shade over the 16 m mech's half-height, so the
                                     ## barrier hugs the silhouette without clipping the ground
const SHELL_COLOR := Color(0.35, 0.85, 1.0, 0.16)
const RIPPLE_COLOR := Color(0.6, 0.95, 1.0)
const PASSES_THROUGH: Array[StringName] = [HitInfo.MELEE, HitInfo.CRUSH, HitInfo.EMP]

var ctx: SkillContext = null
var system: SkillSystem = null
var fins: CoronaFins = null

var _left: float = 0.0
var _absorb: float = 0.0
var _filter: Callable = Callable()
var _area: Area3D = null
var _shell: MeshInstance3D = null
var _tetra: Array[int] = []
var _escort: Array[int] = []
var _escort_at: float = 0.0
var _ripple: float = 0.0
var _hits: int = 0


func setup(ctx_: SkillContext, system_: SkillSystem, fins_: CoronaFins) -> void:
	ctx = ctx_
	system = system_
	fins = fins_
	_build_shell()
	_build_area()
	_filter = _absorb_hit


func _build_shell() -> void:
	_shell = MeshInstance3D.new()
	_shell.name = "WardShell"
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	_shell.mesh = sphere
	_shell.material_override = SkillFx.glow(SHELL_COLOR, 1.2, true)
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.visible = false
	add_child(_shell)


## `Layers.BARRIER` is part of MASK_ENEMY_ATTACK (core-owned), so enemy shots meet this volume in the
## physics world even when the damage filter is what actually eats them.
func _build_area() -> void:
	_area = Area3D.new()
	_area.name = "WardVolume"
	_area.collision_layer = 0   ## live only while the barrier is up (raise_ward / _drop)
	_area.collision_mask = 0
	_area.monitoring = false
	_area.monitorable = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	_area.add_child(shape)
	add_child(_area)


func is_active() -> bool:
	return _left > 0.0


func time_left() -> float:
	return maxf(_left, 0.0)


func absorb_left() -> float:
	return maxf(_absorb, 0.0)


func hits_absorbed() -> int:
	return _hits


## Enough free fins to stand the barrier up (four for the tetrahedron plus the escort pair)? Checked
## before the charge is spent.
func can_raise() -> bool:
	if is_active() or fins == null:
		return false
	var need := ctx.tuning.ward_fins + ctx.tuning.ward_escort_fins
	return fins.free_fin_indices().size() >= need


## Raises the barrier. Returns false when the fins are all busy (they are already out attacking).
func raise_ward() -> bool:
	if not can_raise():
		return false
	_left = ctx.tuning.ward_time
	_absorb = ctx.tuning.ward_absorb
	_hits = 0
	_escort_at = 0.0
	_ripple = 0.0
	_shell.visible = true
	_area.collision_layer = Layers.BARRIER
	_tetra = fins.take_for_ward(ctx.tuning.ward_fins)
	_escort = fins.take_for_ward(ctx.tuning.ward_escort_fins)
	fins.ward_fin_indices = _tetra + _escort
	if ctx.player != null and ctx.player.has_method(&"add_damage_filter"):
		ctx.player.call(&"add_damage_filter", _filter)
	_play_action(&"ward")
	Feel.play(&"ward_hit", ctx.chest(), 0.4)
	SkillFx.ring(self, ctx.chest(), Vector3.UP, RADIUS, 0.35, RIPPLE_COLOR)
	return true


## The damage filter the player runs for us: `func(hit: HitInfo) -> bool`, true = consumed.
## Projectiles arriving from OUTSIDE the sphere are absorbed until the 3,000 point budget is gone;
## melee, shockwaves (CRUSH) and anything spawned inside pass straight through.
func _absorb_hit(hit: HitInfo) -> bool:
	if not is_active() or hit == null or _absorb <= 0.0:
		return false
	if hit.kind in PASSES_THROUGH:
		return false
	var from := hit.position
	var src := hit.source as Node3D
	if src != null and is_instance_valid(src):
		if ctx.chest().distance_to(ctx.centre_of(src)) <= RADIUS:
			return false  # fired from inside the barrier: not stopped
	if ctx.chest().distance_to(from) <= 1.0:
		return false  # no meaningful travel: treat as point blank, let it land
	_absorb = maxf(_absorb - maxf(hit.amount, 0.0), 0.0)
	_hits += 1
	_ripple = 1.0
	SkillFx.spawn(self, &"spark_beam", from, Vector3.UP, 0.8)
	Feel.play(&"ward_hit", ctx.chest(), 0.6)
	if _absorb <= 0.0:
		_drop()
	return true


func _physics_process(delta: float) -> void:
	# only the ripple decay, and only the ripple: the barrier timer and the escort fire rate are
	# player timers and are ticked from CoronaFins on `Feel.player_delta` (audit #4)
	if _ripple > 0.0:
		_ripple = maxf(_ripple - delta * 3.0, 0.0)


## `pdt` is the player delta (CONTRACTS §3). Driven by CoronaFins.tick, so the barrier drains at the
## same rate as every other player timer even inside a witch-time window.
func tick(pdt: float) -> void:
	if not is_active():
		return
	_left = maxf(_left - pdt, 0.0)
	_follow_hero()
	_tick_escort(pdt)
	if _left <= 0.0:
		_drop()


## The barrier is carried by the mech: the tetrahedron vertices sit on a 14 m sphere around the chest
## and the shell breathes with each absorbed hit.
func _follow_hero() -> void:
	var centre := ctx.chest()
	_shell.global_position = centre
	_area.global_position = centre
	var mat := _shell.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color.a = SHELL_COLOR.a + 0.22 * _ripple
	_shell.scale = Vector3.ONE * (1.0 + 0.06 * _ripple)
	for i in _tetra.size():
		var dir := _tetra_dir(i)
		fins.place_fin(_tetra[i], centre + dir * RADIUS, -dir)
	# the escort pair rides on the hero's flanks, level with the chest and facing outward
	var right := ctx.facing().cross(Vector3.UP).normalized()
	for i in _escort.size():
		var side := right * (1.0 if i == 0 else -1.0)
		fins.place_fin(_escort[i], centre + side * (RADIUS * 0.6) + Vector3.UP * 2.0, side)


## The four vertices of a regular tetrahedron on the unit sphere.
func _tetra_dir(i: int) -> Vector3:
	const V := [Vector3(1.0, 1.0, 1.0), Vector3(1.0, -1.0, -1.0),
			Vector3(-1.0, 1.0, -1.0), Vector3(-1.0, -1.0, 1.0)]
	return (V[i % V.size()] as Vector3).normalized()


## The two fins that are not holding the barrier keep shooting: 60 damage every 0.5 s.
func _tick_escort(delta: float) -> void:
	_escort_at -= delta
	if _escort_at > 0.0:
		return
	_escort_at = ctx.tuning.ward_escort_gap
	if fins == null:
		return
	for i in _escort.size():
		var from := fins.fin_position(_escort[i])
		if fins.escort_shot(from) > 0.0:
			SkillFx.spawn(self, &"spark_beam", from, Vector3.UP, 0.4)


## Public drop for the death path (skills r4 item 6): a corpse must not keep a barrier standing.
func drop() -> void:
	if is_active():
		_drop()


func _drop() -> void:
	_left = 0.0
	_absorb = 0.0
	_shell.visible = false
	# the volume must leave the BARRIER layer with the barrier: left standing it kept eating enemy
	# shots wherever the ward happened to be when it expired
	_area.collision_layer = 0
	if fins != null:
		fins.release_ward_fins(_tetra + _escort)
		fins.ward_fin_indices.clear()
	_tetra.clear()
	_escort.clear()
	if ctx.player != null and ctx.player.has_method(&"remove_damage_filter"):
		ctx.player.call(&"remove_damage_filter", _filter)
	SkillFx.spawn(self, &"shockwave_ring", ctx.chest(), Vector3.UP, 1.2)


func _play_action(id: StringName) -> void:
	if ctx.model != null and is_instance_valid(ctx.model) and ctx.model.has_method(&"play_action"):
		ctx.model.call(&"play_action", id)


func reset() -> void:
	if is_active():
		_drop()
	_hits = 0
