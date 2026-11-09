class_name ZenithLance
extends Node3D
## Zenith Lance (天顶光枪) — the Overdrive's finale (skills-catalog §4.5, SPEC §6).
##
## 0.8 s of charge with four brackets converging on the muzzle while the world crawls at 0.3x, then a
## 3.0 s beam 16 m wide and 800 m long that ticks 10 times a second for 450 damage and 150 impact,
## pierces everything in the corridor and breaks props. The mech is rooted and can only sweep at
## 40 deg/s, so the lance is a positioning statement, not a flick shot. A 3 s aftermath follows with
## EN regen halved and no dash (owned by the SkillSystem).

enum S { IDLE, CHARGE, BEAM }

const CORE_COLOR := Color(1.0, 1.0, 1.0)
const GOLD_COLOR := Color(1.0, 0.78, 0.25)
const RED_COLOR := Color(1.0, 0.35, 0.2)
## The three drawn layers of the beam (skills-catalog §4.5 "Feel"): white 1.2 m / gold 4 m / red 8 m,
## each scaled up by the S = 2 rule into the 16 m wide beam.
## width m / colour / glow strength / how solid the tube's middle is / reach (fraction of the 800 m
## the layer stays bright over). The outer layers are hollow AND short: a 16 m tube 800 m long covers
## a sixth of the screen from the gameplay camera, and seen almost end-on every one of its fragments
## is at a grazing angle, so a filled middle reads as a flat pink sheet however round the geometry is.
## Hollow middles, hot silhouette rims and a reach that shrinks with width leave concentric
## white/gold/red rings at the muzzle and one bright line running to the horizon (r4 item 3).
const LAYERS: Array[Array] = [[2.4, CORE_COLOR, 4.0, 0.9, 0.92],
		[8.0, GOLD_COLOR, 2.6, 0.05, 0.5], [16.0, RED_COLOR, 2.0, 0.0, 0.24]]
const HAZE_WIDTH := 21.0          ## boiling air around the beam
const SCORCH_EVERY := 0.16        ## seconds between ground scorch marks under the sweep
## FEEL.md asks for "0.15 continuous" shake through the beam. `Feel.shake_floor` states exactly that:
## it holds the camera's trauma at or above 0.15 for the seconds given, instead of this file having to
## re-derive camera_shake.gd's decay constant to top the floor up (audit #3, and the lead's r4 note).
const SHAKE_TRAUMA := 0.15

var ctx: SkillContext = null
var system: SkillSystem = null

var _state: int = S.IDLE
var _t: float = 0.0
var _tick_at: float = 0.0
var _scorch_at: float = 0.0
var _dir: Vector3 = Vector3.FORWARD
var _layers: Array[SkillFxBeam] = []
var _haze: SkillFxHaze = null
var _brackets: SkillFxBrackets = null
var _ticks: int = 0
var _hits: int = 0
var _broken: int = 0


func setup(ctx_: SkillContext, system_: SkillSystem) -> void:
	ctx = ctx_
	system = system_


func is_running() -> bool:
	return _state != S.IDLE


func is_charging() -> bool:
	return _state == S.CHARGE


## The 3 s beam itself, as opposed to `is_running()` which is also true through the 0.8 s charge.
## Callers that photograph or measure the BEAM must wait for this one.
func is_beaming() -> bool:
	return _state == S.BEAM


func ticks_fired() -> int:
	return _ticks


func enemies_hit() -> int:
	return _hits


func props_broken() -> int:
	return _broken


func beam_dir() -> Vector3:
	return _dir


## Starts the 0.8 s charge. The mech is rooted for the whole sequence and only sweeps at 40 deg/s.
func begin() -> bool:
	if _state != S.IDLE or ctx.player == null:
		return false
	_state = S.CHARGE
	_t = 0.0
	_tick_at = 0.0
	_ticks = 0
	_hits = 0
	_broken = 0
	_dir = _aim_dir()
	if ctx.vfx != null:
		_brackets = ctx.vfx.brackets()
		_brackets.open(ctx.socket(&"muzzle_r"), _dir, 5.0, 26.0, ctx.tuning.lance_charge,
				GOLD_COLOR)
		# gold rim, not the red damage vignette (r1 review)
		ctx.vfx.vignette.open(GOLD_COLOR, 0.5, ctx.tuning.lance_charge
				+ ctx.tuning.lance_beam, 0.4, 0.6)
	if ctx.player.has_method(&"lock_movement"):
		# only the charge: the beam's own lock is issued when it opens, because the charge runs on REAL
		# time under a 0.3x slow-mo and the mech's lock timer counts player time (audit #10)
		ctx.player.call(&"lock_movement", ctx.tuning.lance_charge, true)
	if ctx.player.has_method(&"invulnerable_for"):
		ctx.player.call(&"invulnerable_for", ctx.tuning.lance_charge)
	_play_action(&"lance_fire")
	Feel.slow_mo(0.3, ctx.tuning.lance_charge, 0.05, 0.1)
	return true


func tick(delta: float) -> void:
	match _state:
		S.CHARGE:
			# FEEL.md: "enemies 0.3x during the 0.8 s charge" — 0.8 s of REAL time, which the player
			# clock (0.3x for that window) would stretch to ~1.3 s with the last half at full speed
			_tick_charge(Feel.real_delta(delta))
		S.BEAM:
			_tick_beam(delta)
		_:
			pass


## Four brackets converge on the muzzle over the 0.8 s charge (skills-catalog §4.5 "Feel" [TF-LC]);
## the piece is re-aimed every tick so a sweep during the charge carries the brackets with it.
func _tick_charge(delta: float) -> void:
	_t += delta
	var u := clampf(_t / maxf(ctx.tuning.lance_charge, 0.0001), 0.0, 1.0)
	_dir = _aim_dir()
	if _brackets != null:
		_brackets.aim(ctx.socket(&"muzzle_r"), _dir)
		_brackets.set_progress(u)
	if u < 1.0:
		return
	_state = S.BEAM
	_t = 0.0
	_tick_at = 0.0
	_scorch_at = 0.0
	if _brackets != null:
		_brackets.stop()
		_brackets = null
	_open_beam()
	if ctx.player.has_method(&"lock_movement"):
		ctx.player.call(&"lock_movement", ctx.tuning.lance_beam, true)
	var muzzle := ctx.socket(&"muzzle_r")
	SkillFx.flash(self, muzzle, CORE_COLOR, 12.0, 160.0, 6.0)
	Feel.play(&"lance_fire", muzzle)
	Feel.shake(SHAKE_TRAUMA, muzzle)


## The three layers plus the heat sleeve, opened for the whole 3 s beam.
func _open_beam() -> void:
	if ctx.vfx == null:
		return
	_layers.clear()
	for spec: Array in LAYERS:
		var beam := ctx.vfx.beam()
		beam.open(spec[1] as Color, float(spec[3]), float(spec[2]), float(spec[4]))
		_layers.append(beam)
	_haze = ctx.vfx.haze()
	_haze.open(0.07, 10.0, 2.2)   # subtle: the sleeve must not wash the beam out


## 10 damage ticks a second for 3 s. The mech is rooted; the aim may only sweep at 40 deg/s.
func _tick_beam(delta: float) -> void:
	_t += delta
	_sweep(delta)
	_draw_beam()
	_scorch(delta)
	_tick_at -= delta
	if _tick_at <= 0.0:
		_tick_at += 1.0 / maxf(ctx.tuning.lance_rate, 0.1)
		_fire_tick()
	# a floor, not an addition: the camera holds >= 0.15 for the whole beam and decays after it. The
	# request is re-issued every tick on the REAL clock, because the beam itself runs on player time.
	Feel.shake_floor(SHAKE_TRAUMA, Feel.real_delta(delta) * 2.0)
	if _t >= ctx.tuning.lance_beam:
		_finish()


func _sweep(delta: float) -> void:
	var want := _aim_dir()
	var angle := _dir.angle_to(want)
	# Vector3.slerp is undefined for a near-zero angle and returns a degenerate basis, which draws the
	# 800 m beam as an unbounded smear; under the sweep's own step there is nothing to turn anyway.
	if angle > 0.0005:
		var max_step := deg_to_rad(ctx.tuning.lance_turn_deg) * delta
		var next := _dir.slerp(want, clampf(max_step / angle, 0.0, 1.0)).normalized()
		_dir = next if next.is_finite() else want
	var body := ctx.player as Node3D
	if body != null:
		var flat := Vector3(_dir.x, 0.0, _dir.z)
		if flat.length_squared() > 0.0001:
			body.global_basis = Basis.looking_at(flat.normalized(), Vector3.UP)


func _aim_dir() -> Vector3:
	return ctx.aim_dir_from(ctx.socket(&"muzzle_r"))


func _draw_beam() -> void:
	var muzzle := ctx.socket(&"muzzle_r")
	var end := muzzle + _dir * ctx.tuning.lance_length
	for i in _layers.size():
		_layers[i].line(muzzle, end, float((LAYERS[i] as Array)[0]))
	if _haze != null:
		_haze.line(muzzle, end, HAZE_WIDTH)


## The beam chars the deck it sweeps over: one scorch decal every 0.16 s at the point under the beam,
## dropped from three samples along its length so the mark follows the sweep (r1 review).
func _scorch(delta: float) -> void:
	_scorch_at -= delta
	if _scorch_at > 0.0:
		return
	_scorch_at = SCORCH_EVERY
	var muzzle := ctx.socket(&"muzzle_r")
	for i in 3:
		var at := muzzle + _dir * (ctx.tuning.lance_length * (0.1 + 0.35 * float(i)))
		var ground := ctx.ground_point(at)
		# only char the deck the beam can actually reach: a lance fired from 200 m up must not leave
		# scorch marks on the street below it (audit #12)
		if ground.distance_to(at) > ctx.tuning.lance_width:
			continue
		SkillFx.decal(self, &"scorch", ground, Vector3.UP, 1.6)


## Everything inside the 16 m wide corridor along the beam is hit: the lance pierces, so there is no
## first-hit truncation. Props on `Layers.PROPS` are broken on the way through.
func _fire_tick() -> void:
	_ticks += 1
	var t := ctx.tuning
	var muzzle := ctx.socket(&"muzzle_r")
	var half := t.lance_width * 0.5
	for e in ctx.enemies_in_radius(muzzle, t.lance_length):
		var to := ctx.centre_of(e) - muzzle
		var along := to.dot(_dir)
		if along < 0.0 or along > t.lance_length:
			continue
		if (to - _dir * along).length() > half:
			continue
		ctx.damage(e, t.lance_damage, HitInfo.BEAM, &"zenith_lance", t.lance_impact,
				Vector3.ZERO, ctx.centre_of(e))
		# contact sparks where the beam crosses a body: the corridor reads as "everything in it burns"
		SkillFx.spawn(self, &"spark_burst", ctx.centre_of(e), _dir, 1.1)
		_hits += 1
	_break_props(muzzle, half)


## One box query along the corridor: anything on PROPS that can take a hit is destroyed.
func _break_props(from: Vector3, half_width: float) -> void:
	var space := _space()
	if space == null:
		return
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(half_width * 2.0, half_width * 2.0, ctx.tuning.lance_length)
	q.shape = box
	q.transform = Transform3D(Basis.looking_at(_dir, Vector3.UP), from + _dir
			* ctx.tuning.lance_length * 0.5)
	q.collision_mask = Layers.PROPS
	for r in space.intersect_shape(q, 32):
		var n := r["collider"] as Node
		if n == null or not n.has_method(&"take_hit"):
			continue
		var hit := HitInfo.make(9999.0, HitInfo.BEAM, ctx.player, &"zenith_lance")
		hit.position = (r["position"] as Vector3) if r.has("position") else from
		n.call(&"take_hit", hit)
		_broken += 1


func _finish() -> void:
	_state = S.IDLE
	_t = 0.0
	for beam in _layers:
		beam.stop()
	_layers.clear()
	if _haze != null:
		_haze.stop()
		_haze = null
	if ctx.vfx != null:
		ctx.vfx.vignette.close()
	Feel.play(&"lance_fire", ctx.chest(), 1.4)
	SkillFx.spawn(self, &"shockwave_ring", ctx.socket(&"muzzle_r"), _dir, 2.0)
	if system != null:
		system.end_overdrive()


func _space() -> PhysicsDirectSpaceState3D:
	if ctx.player == null or not ctx.player.is_inside_tree():
		return null
	return (ctx.player as Node3D).get_world_3d().direct_space_state


func _play_action(id: StringName) -> void:
	if ctx.model != null and is_instance_valid(ctx.model) and ctx.model.has_method(&"play_action"):
		ctx.model.call(&"play_action", id)


func reset() -> void:
	_state = S.IDLE
	_t = 0.0
	_ticks = 0
	_hits = 0
	_broken = 0
	for beam in _layers:
		beam.stop()
	_layers.clear()
	if _haze != null:
		_haze.stop()
		_haze = null
	if _brackets != null:
		_brackets.stop()
		_brackets = null
