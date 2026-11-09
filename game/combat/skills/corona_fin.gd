class_name CoronaFin
extends RefCounted
## One of the hero's six thrown wing blades (skills-catalog §4.4 S4): its own mesh, its own station on
## the 18 m sphere around the target, its own 4-beam volley and its own 400 HP. Split out of
## corona_fins.gd so that file stays about the volley as a whole — how many fins a send launches, which
## blades leave the back, and the Ward hand-off.

enum F { DOCKED, OUT, RETURN, WARD }

var mesh: MeshInstance3D = null
var state: int = F.DOCKED
var target: Node3D = null
var station: Vector3 = Vector3.ZERO
var hp: float = 400.0
var beams_left: int = 0
var next_beam: float = 0.0
var preflash: bool = false
var aim_at: Vector3 = Vector3.ZERO   ## the crosshair point this fin was thrown at (no-lock case)
var trail_at: float = 0.0
var trail_from: Vector3 = Vector3.ZERO
var life: float = 0.0
var respawn: float = 0.0
var side: int = 0                   ## -1 = launched from `wing_l`, +1 = `wing_r`

var ctx: SkillContext = null


func _init(ctx_: SkillContext, side_: int) -> void:
	ctx = ctx_
	side = side_


func busy() -> bool:
	return state != F.DOCKED or respawn > 0.0


## Is this blade off the model's back right now (flying, returning or holding the Ward)?
func deployed() -> bool:
	return state != F.DOCKED


func dock_socket() -> Vector3:
	return ctx.socket(&"wing_l" if side < 0 else &"wing_r")


## The socket the fin should launch from: its own blade when the model can say where that blade is
## (Hero3 `drone_tip`), else the wing socket it rides.
func launch_from(drone: int) -> Vector3:
	if drone >= 0 and ctx.model != null and is_instance_valid(ctx.model) \
			and ctx.model.has_method(&"drone_tip"):
		return ctx.model.call(&"drone_tip", drone)
	return dock_socket()


func launch(target_: Node3D, aim: Vector3, station_: Vector3, drone: int) -> void:
	state = F.OUT
	target = target_
	aim_at = aim
	station = station_
	hp = ctx.tuning.fin_hp
	beams_left = ctx.tuning.fin_beams
	next_beam = 0.0
	life = 0.0
	mesh.visible = true
	mesh.global_position = launch_from(drone)
	trail_from = mesh.global_position
	trail_at = 0.0
	preflash = false
	CoronaFinFx.look_along(mesh, (station - mesh.global_position).normalized())


## One physics tick of this blade's own state machine.
func tick(delta: float) -> void:
	_tick_trail(delta)
	if respawn > 0.0:
		respawn = maxf(respawn - delta, 0.0)
	match state:
		F.OUT:
			_tick_out(delta)
		F.RETURN:
			_tick_return(delta)
		_:
			pass


## A thrown blade drags a short cyan ribbon behind it, so six fins in flight stay readable as six
## objects instead of six dots (r1 review).
func _tick_trail(delta: float) -> void:
	if state == F.DOCKED or ctx.vfx == null or not mesh.visible:
		return
	trail_at -= delta
	if trail_at > 0.0:
		return
	trail_at = CoronaFinFx.TRAIL_GAP
	var at := mesh.global_position
	CoronaFinFx.trail(ctx.vfx, trail_from, at)
	trail_from = at


## Seek + arrive steering toward the station (skills-catalog §4.4 S4 "Godot"). Once on station the
## fin holds and starts its 4-beam volley; after 2.4 s it turns around and flies home.
func _tick_out(delta: float) -> void:
	life += delta
	if target != null and is_instance_valid(target) and ctx.is_alive(target):
		station = target.global_position + (station - target.global_position).normalized() \
				* ctx.tuning.fin_station
	elif target != null and (not is_instance_valid(target) or not ctx.is_alive(target)):
		beams_left = 0
	var to := station - mesh.global_position
	var dist := to.length()
	var step := ctx.tuning.fin_speed * delta
	if dist > step:
		mesh.global_position += to / dist * step
		CoronaFinFx.look_along(mesh, to / dist)
	else:
		mesh.global_position = station
		_face_target()
		_tick_beams(delta)
	if life >= ctx.tuning.fin_return:
		begin_return()


func _face_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	var d := ctx.centre_of(target) - mesh.global_position
	if d.length_squared() > 0.01:
		CoronaFinFx.look_along(mesh, d.normalized())


func _tick_beams(delta: float) -> void:
	if beams_left <= 0:
		return
	next_beam -= delta
	# 4 f of pre-flash at the fin's own muzzle, so the volley is telegraphed from the drone
	if not preflash and next_beam <= CoronaFinFx.PRE_FLASH:
		preflash = true
		CoronaFinFx.pre_flash(ctx.vfx, mesh.global_position, beam_dir())
	if next_beam > 0.0:
		return
	next_beam = ctx.tuning.fin_beam_gap
	preflash = false
	beams_left -= 1
	_fire_beam()


func beam_dir() -> Vector3:
	return (beam_aim() - mesh.global_position).normalized()


## Where this fin's next beam lands: the locked target's centre of mass, else the crosshair point it
## was thrown at.
func beam_aim() -> Vector3:
	if target != null and is_instance_valid(target) and ctx.is_alive(target):
		return ctx.centre_of(target)
	return aim_at if aim_at != Vector3.ZERO else station


## One beam from the fin to the target: 110 damage / 45 impact. With no lock it goes to the crosshair
## point the fin was thrown at, not to its own station — the station is where the fin already is,
## which made every no-lock beam zero-length and invisible (audit #11).
func _fire_beam() -> void:
	var aim := beam_aim()
	CoronaFinFx.fire_beam(ctx.vfx, mesh.global_position, aim)
	CoronaFinFx.hit_spark(ctx.vfx, aim)
	SkillFx.spawn(mesh, &"spark_beam", aim, Vector3.UP, 0.7)
	SkillFx.flash(mesh, aim, CoronaFinFx.BEAM_COLOR, 3.0, 45.0, 3.0)
	if target != null and is_instance_valid(target):
		ctx.damage(target, ctx.tuning.fin_damage, HitInfo.BEAM, &"corona_fin",
				ctx.tuning.fin_impact, Vector3.ZERO, aim)
	Feel.play(&"fins_launch", aim, 0.35)


func begin_return() -> void:
	state = F.RETURN
	life = 0.0


func _tick_return(delta: float) -> void:
	life += delta
	var to := dock_socket() - mesh.global_position
	var step := ctx.tuning.fin_speed * 1.2 * delta
	if to.length() > step:
		mesh.global_position += to.normalized() * step
		CoronaFinFx.look_along(mesh, to.normalized())
		return
	dock()


func dock() -> void:
	mesh.global_position = dock_socket()
	mesh.visible = false
	state = F.DOCKED
	target = null


## A fin that was shot down respawns after 6 s (skills-catalog §4.4 S4 "Tension").
func take_damage(amount: float) -> bool:
	if state == F.DOCKED or amount <= 0.0:
		return false
	hp -= amount
	if hp > 0.0:
		return false
	begin_return()
	respawn = ctx.tuning.fin_respawn
	mesh.visible = false
	SkillFx.spawn(mesh, &"spark_burst", mesh.global_position, Vector3.UP, 0.8)
	return true


func place(at: Vector3, dir: Vector3) -> void:
	mesh.visible = true
	mesh.global_position = at
	if dir.length_squared() > 0.0001:
		CoronaFinFx.look_along(mesh, dir.normalized())
