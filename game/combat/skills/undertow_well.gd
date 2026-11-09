class_name UndertowWell
extends Node3D
## S7 Undertow Well (暗流引井) — crowd control and primer (skills-catalog §4.4 S7, radius and throw x2).
##
## The core is lobbed in a 90 m/s arc to at most 100 m and arms on impact, or after 1.2 s in flight.
## For 3.5 s a 24 m violet field pulls Swarmers and Stalkers toward its centre at up to 18 m/s, slows
## Brutes by 40 % and bosses by 15 %, and primes everything inside for 5 s. A detonator — Shockcore,
## Hailstorm, Plunge, the charged-slash wave or the rifle's stage 2 — then triggers **COLLAPSE**:
## 900 damage and 700 impact in 20 m, +2 % OD per collapse.
##
## `detonate_primes` is reached through the `&"prime_detonators"` group (CONTRACTS §4), so any other
## unit's detonator resolves the payoff without knowing this file exists.

enum S { IDLE, FLIGHT, FIELD }

const GRAVITY := 40.0               ## matches the enemies unit's lob gravity so the arc reads right
const CORE_COLOR := Color(0.72, 0.42, 1.0)
const FIELD_COLOR := Color(0.55, 0.28, 0.95, 0.22)
const COLLAPSE_COLOR := Color(0.85, 0.6, 1.0)
const RIM_GAP := 0.3                 ## seconds between violet rim pulses on primed enemies
const RIM_RADIUS := 7.0
const RIPPLE_GAP := 0.5              ## seconds between the ground ripples running into the lens
const RIPPLE_COLOR := Color(0.78, 0.5, 1.0)

var ctx: SkillContext = null
var system: SkillSystem = null

var _state: int = S.IDLE
var _t: float = 0.0
var _pos: Vector3 = Vector3.ZERO
var _vel: Vector3 = Vector3.ZERO
var _core: MeshInstance3D = null
var _field: MeshInstance3D = null
var _inflow: SkillFxInflow = null
var _rim_at: float = 0.0
var _ripple_at: float = 0.0
var _armed: int = 0
var _collapsed: int = 0


func setup(ctx_: SkillContext, system_: SkillSystem) -> void:
	ctx = ctx_
	system = system_
	_core = _sphere("WellCore", 1.8, SkillFx.glow(CORE_COLOR, 4.0))
	_field = _sphere("WellField", 1.0, SkillFx.glow(FIELD_COLOR, 1.4, true))
	_core.visible = false
	_field.visible = false


func _sphere(node_name: String, radius: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	m.mesh = sphere
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func is_active() -> bool:
	return _state == S.FIELD


## Checked BEFORE the charge is spent: one core in the air at a time.
func can_begin() -> bool:
	return _state == S.IDLE and ctx.player != null


func centre() -> Vector3:
	return _pos


func armed_count() -> int:
	return _armed


func collapsed_count() -> int:
	return _collapsed


func field_left() -> float:
	return maxf(ctx.tuning.well_field - _t, 0.0) if _state == S.FIELD else 0.0


## Lobs the core. With a hard or soft lock it lands on the LOCKED actor's ground position — the
## reticle ray runs metres off a locked target (camera-aim), so aiming the well by the crosshair put
## the field 50 m past the juggernaut it was meant to prime (r4 item 2). With no lock it goes to the
## crosshair, and a core that meets a body on the way arms on the ground under that body.
func begin() -> bool:
	if _state != S.IDLE or ctx.player == null:
		return false
	var from := ctx.socket(&"hand_l")
	var locked := ctx.lock_target()
	var to := ctx.ground_point(locked.global_position) if locked != null else ctx.aim_point()
	var flat := to - from
	if flat.length() > ctx.tuning.well_range:
		to = from + flat.normalized() * ctx.tuning.well_range
	_pos = from
	_vel = _arc_velocity(from, to, ctx.tuning.well_throw)
	_state = S.FLIGHT
	_t = 0.0
	_armed = 0
	_core.visible = true
	_core.global_position = from
	_play_action(&"well_throw")
	return true


## Ballistic lob: the launch elevation that puts the core on `to` at `speed`, low arc (the high arc
## would sail over a rooftop fight).
func _arc_velocity(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var delta := to - from
	var flat := Vector3(delta.x, 0.0, delta.z)
	var x := maxf(flat.length(), 0.001)
	var y := delta.y
	var s2 := speed * speed
	var disc := s2 * s2 - GRAVITY * (GRAVITY * x * x + 2.0 * y * s2)
	if disc < 0.0:
		return delta.normalized() * speed
	var angle := atan((s2 - sqrt(disc)) / (GRAVITY * x))
	var dir := flat / x
	return dir * speed * cos(angle) + Vector3.UP * speed * sin(angle)


# --- flight and field ----------------------------------------------------------------------------

func tick(delta: float) -> void:
	match _state:
		S.FLIGHT:
			_tick_flight(delta)
		S.FIELD:
			_tick_field(delta)
		_:
			pass


func _tick_flight(delta: float) -> void:
	_t += delta
	var from := _pos
	_vel.y -= GRAVITY * delta
	_pos += _vel * delta
	_core.global_position = _pos
	var met := _meet_enemy(from, _pos)
	if met != null:
		# the core is a thrown body: it arms where it struck, on the deck under that body
		_arm_at(ctx.ground_point(met.global_position))
		return
	if _t >= ctx.tuning.well_arm_time or _hit_scenery(from, _pos):
		_arm()
		return
	if ctx.origin().distance_to(_pos) > ctx.tuning.well_range * 1.5:
		_end()


## The first enemy whose body the flight segment crosses, or null. `MASK_SIGHT` alone let the core fly
## straight through a juggernaut and arm on the street behind it, so nothing was ever primed.
func _meet_enemy(from: Vector3, to: Vector3) -> Node3D:
	var span := from.distance_to(to)
	if span < 0.001:
		return null
	var best: Node3D = null
	var best_u := INF
	for e in ctx.enemies_in_radius((from + to) * 0.5, span * 0.5 + 60.0):
		var centre := ctx.centre_of(e)
		var u := clampf((centre - from).dot(to - from) / (span * span), 0.0, 1.0)
		if u >= best_u:
			continue
		if from.lerp(to, u).distance_to(centre) <= _body_radius(e):
			best_u = u
			best = e
	return best


## The enemy's collision radius plus the core's own: `body_height * 0.3` is the capsule radius every
## archetype (and the test dummy) builds itself with.
func _body_radius(e: Node3D) -> float:
	var h: Variant = e.get(&"body_height")
	return maxf(float(h) if h != null else 6.0, 2.0) * 0.3 + 1.8


func _hit_scenery(from: Vector3, to: Vector3) -> bool:
	if ctx.player == null or not ctx.player.is_inside_tree():
		return false
	var space := (ctx.player as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.MASK_SIGHT)
	return not space.intersect_ray(q).is_empty()


func _arm() -> void:
	_arm_at(_pos)


func _arm_at(at: Vector3) -> void:
	_pos = at
	_state = S.FIELD
	_t = 0.0
	_field.visible = true
	_field.global_position = _pos
	_field.scale = Vector3.ONE * ctx.tuning.well_radius
	SkillFx.ring(self, _pos, Vector3.UP, ctx.tuning.well_radius, 0.4, COLLAPSE_COLOR)
	SkillFx.flash(self, _pos, CORE_COLOR, 4.0, ctx.tuning.well_radius * 2.0, 5.0)
	_rim_at = 0.0
	_ripple_at = 0.0
	if ctx.vfx != null:
		# spiral inflow for the whole field: the well visibly drinks the ground it stands on
		_inflow = ctx.vfx.inflow()
		_inflow.fire(_pos + Vector3.UP * 1.0, ctx.tuning.well_radius, ctx.tuning.well_field,
				Color(0.72, 0.45, 1.0), 140, 16.0, 1.2, 1.4)
		# the ground ring only when the core is near a surface: a well that armed in mid-air after its
		# 1.2 s fuse must not draw its rim on the street below (audit #12)
		var deck := ctx.ground_near(_pos, ctx.tuning.well_radius)
		if deck != _pos:
			ctx.vfx.ring().fire(deck + Vector3.UP * 0.4, Vector3.UP, 2.0,
					ctx.tuning.well_radius, 0.6, CORE_COLOR, 0.09, 2.2)
	Feel.play(&"collapse", _pos, 0.4)


## Every enemy inside the field is pulled toward the centre through the enemies unit's own status
## hooks, slowed by class, and primed for the 5 s COLLAPSE window.
func _tick_field(delta: float) -> void:
	_t += delta
	_armed = 0
	for e in ctx.enemies_in_radius(_pos, ctx.tuning.well_radius):
		var s := ctx.status_of(e)
		if s == null:
			continue
		if s.has_method(&"prime"):
			s.call(&"prime", ctx.tuning.well_prime)
			_armed += 1
		var to := _pos - e.global_position
		to.y = 0.0
		if to.length_squared() < 4.0:
			continue
		if ctx.is_boss(e):
			_slow(s, ctx.tuning.well_slow_boss)
		elif ctx.is_heavy(e):
			_slow(s, ctx.tuning.well_slow_heavy)
		elif s.has_method(&"apply_pull"):
			# arrive: the pull eases off near the centre so a Swarmer orbits instead of jittering
			var speed := ctx.tuning.well_pull * clampf(to.length() / ctx.tuning.well_radius, 0.2, 1.0)
			s.call(&"apply_pull", to.normalized() * speed * 4.0, 0.1)
	_core.global_position = _pos + Vector3.UP * sin(_t * 4.0) * 2.0
	if _inflow != null:
		_inflow.move_to(_pos + Vector3.UP * 1.0, ctx.tuning.well_radius)
	_prime_rims(delta)
	_ground_ripple(delta)
	if _t >= ctx.tuning.well_field:
		_end()


## A violet ring contracting from the field rim into the lens every 0.5 s: the well's pull is the
## whole point of the skill and the spiral motes alone were too quiet to read at 50 m (r2 review).
func _ground_ripple(delta: float) -> void:
	_ripple_at -= delta
	if _ripple_at > 0.0 or ctx.vfx == null:
		return
	_ripple_at = RIPPLE_GAP
	var deck := ctx.ground_near(_pos, ctx.tuning.well_radius)
	if deck == _pos:
		return   # nothing close enough under the lens to ripple (audit #12)
	ctx.vfx.ring().fire(deck + Vector3.UP * 0.5, Vector3.UP, ctx.tuning.well_radius, 3.0,
			RIPPLE_GAP, RIPPLE_COLOR, 0.11, 2.0)


## A violet rim pulse on every primed body, so "this one is loaded" is readable before the detonator
## lands (r1 review). Pooled shells, re-fired on a timer instead of one per enemy per frame.
func _prime_rims(delta: float) -> void:
	_rim_at -= delta
	if _rim_at > 0.0 or ctx.vfx == null:
		return
	_rim_at = RIM_GAP
	var shown := 0
	for e in ctx.enemies_in_radius(_pos, ctx.tuning.well_radius):
		if shown >= 6:
			break
		ctx.vfx.shell().fire(ctx.centre_of(e), RIM_RADIUS * 0.7, RIM_RADIUS, RIM_GAP + 0.12,
				Color(0.62, 0.3, 1.0), Color(0.9, 0.7, 1.0), 1.6, 1.6)
		shown += 1


func _slow(s: Object, factor: float) -> void:
	if s.has_method(&"apply_slow"):
		s.call(&"apply_slow", factor, 0.1)


func _end() -> void:
	_state = S.IDLE
	_t = 0.0
	_armed = 0
	if _inflow != null:
		_inflow.stop()
		_inflow = null
	_core.visible = false
	_field.visible = false


# --- COLLAPSE ------------------------------------------------------------------------------------

## Resolves every primed enemy inside `radius` of `center`. Each one implodes for 900 damage / 700
## impact and its 20 m rupture catches whatever is standing next to it. Returns how many collapsed.
func detonate(center: Vector3, radius: float, _source: Node) -> int:
	if ctx == null or ctx.tuning == null:
		return 0
	var t := ctx.tuning
	var n := 0
	for e in ctx.enemies_in_radius(center, radius):
		var s := ctx.status_of(e)
		if s == null or not s.has_method(&"is_primed") or not bool(s.call(&"is_primed")):
			continue
		# `clear_prime()` (enemies/status_component.gd) spends the mark through the status component's
		# own `primed_changed` signal, so the HUD plate hears the collapse; writing `primed` directly
		# left every listener showing a primed body that had already imploded.
		if s.has_method(&"clear_prime"):
			s.call(&"clear_prime")
		else:
			s.set(&"primed", false)
		_collapse(e, t)
		n += 1
	if n > 0:
		_collapsed += n
		if ctx.player != null and ctx.player.has_method(&"add_overdrive"):
			ctx.player.call(&"add_overdrive", t.collapse_od * float(n))
		Events.prime_collapsed.emit(center, n)
	return n


## One COLLAPSE: the primed enemy itself plus everything inside 20 m of it.
func _collapse(victim: Node3D, t: SkillTuning) -> void:
	var at := ctx.centre_of(victim)
	ctx.damage(victim, t.collapse_damage, HitInfo.EXPLOSIVE, &"collapse", t.collapse_impact,
			Vector3.ZERO, at)
	for other in ctx.enemies_in_radius(at, t.collapse_radius):
		if other == victim:
			continue
		var dir := (ctx.centre_of(other) - at).normalized()
		ctx.damage(other, t.collapse_damage, HitInfo.EXPLOSIVE, &"collapse", t.collapse_impact,
				ctx.knockback_for(other, 12.0, 4.0, dir), ctx.centre_of(other))
	Feel.local_hit_stop([victim], 4.0 / 60.0)
	Feel.play(&"collapse", at)
	# COLLAPSE reads violet, not orange: the prime implodes inward before it lets go.
	if ctx.vfx != null:
		ctx.vfx.shell().fire(at, 0.5, t.collapse_radius * 0.6, 0.3, Color(0.62, 0.3, 1.0),
				Color(0.95, 0.8, 1.0), 2.6, 2.0)
		ctx.vfx.ring().fire(at, Vector3.UP, 1.0, t.collapse_radius, 0.34, COLLAPSE_COLOR,
				0.12, 2.6)
	SkillFx.spawn(self, &"spark_burst", at, Vector3.UP, 1.4)
	SkillFx.flash(self, at, COLLAPSE_COLOR, 5.0, t.collapse_radius * 2.5, 4.0)


func _play_action(id: StringName) -> void:
	if ctx.model != null and is_instance_valid(ctx.model) and ctx.model.has_method(&"play_action"):
		ctx.model.call(&"play_action", id)


func hud_state() -> Dictionary:
	return {"well_active": _state == S.FIELD, "well_left": field_left(),
			"well_primed": _armed}


func reset() -> void:
	_end()
	_collapsed = 0
	_vel = Vector3.ZERO
