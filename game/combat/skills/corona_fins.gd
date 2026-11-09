class_name CoronaFins
extends Node3D
## S4 Corona Fins (日冕翼片) — the hero's six wing blades used as remote drones (skills-catalog §4.4
## S4, range and radii x2). Tap sends 2 + 2 x Marks fins (2 / 4 / 6) at 150 m/s; they take stations
## on an 18 m sphere around the target and each fires 4 beams 0.22 s apart for 110 / 45, then return
## after 2.4 s. Holding the action for 0.35 s raises the Corona Ward instead (corona_ward.gd).
##
## SPEC §6 S4 makes the fins the hero's OWN blades, so a fin that is out takes its blade off the back
## with it: `HeroModel.set_drones_docked(mask)` (bit i set = `Drone_{i+1}` deployed and hidden). This
## file owns the volley as a whole — how many fins a send launches, which blades leave the back, and
## the Ward hand-off; `corona_fin.gd` owns one blade's flight, beams and return.

const STATION_EPSILON := 2.5        ## metres at which a fin counts as "on station"

var ctx: SkillContext = null
var system: SkillSystem = null
var ward: CoronaWard = null
var ward_fin_indices: Array[int] = []

var _fins: Array[CoronaFin] = []
var _mask: int = 0               ## the drone mask last pushed to the model
var _out_count: int = 0
var _sends: int = 0


func setup(ctx_: SkillContext, system_: SkillSystem) -> void:
	ctx = ctx_
	system = system_
	for i in ctx.tuning.fins_max:
		var fin := CoronaFin.new(ctx, -1 if i % 2 == 0 else 1)
		fin.mesh = CoronaFinFx.blade_mesh()
		add_child(fin.mesh)
		fin.mesh.visible = false
		_fins.append(fin)
	ward = CoronaWard.new()
	ward.name = "CoronaWard"
	add_child(ward)
	ward.setup(ctx, system, self)


## Which model drone a fin takes off the back: `Drone_{i+1}`, 0-based bit index. Fins alternate sides
## (even = `wing_l`, odd = `wing_r`), three a side, so the left wing spends `Drone_2..4` and the right
## `Drone_5..7`. `Drone_1` (bit 0) is the blade that always stays docked — `fins_max` is 6 and there
## are 7 blades.
static func drone_for_fin(index: int) -> int:
	return index / 2 + (1 if index % 2 == 0 else 4)


# --- sending -------------------------------------------------------------------------------------

## Number of fins a send would launch against `target`: 2 + 2 x Marks, capped at 6 (skills-catalog
## §4.7 "Rifle -> Fins"). Marks are read, not consumed: the rifle keeps its own bookkeeping.
func fin_count_for(target: Node3D) -> int:
	return clampi(ctx.tuning.fins_base + ctx.tuning.fins_per_mark * ctx.marks_of(target),
			ctx.tuning.fins_base, ctx.tuning.fins_max)


## Checked BEFORE the charge is spent: nothing to throw means nothing spent.
func can_send() -> bool:
	return available_fins() >= ctx.tuning.fins_base


func available_fins() -> int:
	var n := 0
	for f in _fins:
		if not f.busy():
			n += 1
	return n


## Launches the fins at the locked target. With no lock they fly to the crosshair point instead.
func send() -> bool:
	var target := ctx.lock_target()
	var want := fin_count_for(target)
	var aim := ctx.centre_of(target) if target != null else ctx.aim_point()
	var launched := 0
	for i in _fins.size():
		var f := _fins[i]
		if launched >= want or f.busy():
			continue
		f.launch(target, aim, _station_point(aim, launched, want), drone_for_fin(i))
		launched += 1
	if launched == 0:
		return false
	_sends += 1
	_apply_drone_mask()
	Feel.play(&"fins_launch", ctx.chest())
	_play_action(&"fins_send")
	return true


## Even stations on the 18 m sphere around the target: a golden-angle spiral reads better than a ring
## because no two fins ever line up with the camera.
func _station_point(centre: Vector3, index: int, total: int) -> Vector3:
	var n := maxi(total, 1)
	var y := 1.0 - 2.0 * (float(index) + 0.5) / float(n)
	var r := sqrt(maxf(1.0 - y * y, 0.0))
	var theta := float(index) * 2.39996323
	return centre + Vector3(cos(theta) * r, y, sin(theta) * r) * ctx.tuning.fin_station


## Pushes the deployed-blade mask to the hero model: a fin that is out, returning, dead-respawning or
## holding the Ward takes its own blade off the back, and every other blade stays. The mask is
## absolute, so a single call a tick is both the hide and the show.
func _apply_drone_mask() -> void:
	var model := ctx.model
	if model == null or not is_instance_valid(model) or not model.has_method(&"set_drones_docked"):
		return
	var mask := 0
	for i in _fins.size():
		if _fins[i].deployed():
			mask |= 1 << drone_for_fin(i)
	if mask == _mask:
		return
	_mask = mask
	model.call(&"set_drones_docked", mask)


## The mask the model is currently showing (0 = every blade docked).
func drone_mask() -> int:
	return _mask


# --- flight ---------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	for f in _fins:
		f.tick(delta)
	_apply_drone_mask()
	_out_count = _count_out()
	ward.tick(delta)


## A fin that was shot down respawns after 6 s (skills-catalog §4.4 S4 "Tension").
func damage_fin(index: int, amount: float) -> bool:
	if index < 0 or index >= _fins.size():
		return false
	var killed := _fins[index].take_damage(amount)
	if killed:
		_apply_drone_mask()
	return killed


# --- the Ward hand-off ----------------------------------------------------------------------------

## Raises the tetrahedral barrier (the hold half of the input).
func raise_ward() -> bool:
	return ward.raise_ward()


## Checked BEFORE the charge is spent: the barrier needs four free fins plus the escort pair.
func can_ward() -> bool:
	return ward.can_raise()


## Fins the Ward may borrow: everything that is not already airborne.
func free_fin_indices() -> Array[int]:
	var out: Array[int] = []
	for i in _fins.size():
		if not _fins[i].busy():
			out.append(i)
	return out


## Hands `n` docked fins to the Ward: they become part of the barrier and cannot be sent until it
## drops, which is what makes the hold a real trade (skills-catalog §4.4 S4).
func take_for_ward(n: int) -> Array[int]:
	var taken: Array[int] = []
	for i in free_fin_indices():
		if taken.size() >= n:
			break
		_fins[i].state = CoronaFin.F.WARD
		_fins[i].mesh.visible = true
		taken.append(i)
	if not taken.is_empty():
		_apply_drone_mask()
	return taken


func release_ward_fins(indices: Array[int]) -> void:
	for i in indices:
		if i < 0 or i >= _fins.size():
			continue
		_fins[i].state = CoronaFin.F.DOCKED
		_fins[i].mesh.visible = false
	_apply_drone_mask()


## Places one borrowed fin; the Ward drives the tetrahedron and the escort pair from here.
func place_fin(index: int, at: Vector3, dir: Vector3) -> void:
	if index < 0 or index >= _fins.size():
		return
	_fins[index].place(at, dir)


func fin_position(index: int) -> Vector3:
	if index < 0 or index >= _fins.size():
		return ctx.chest()
	return _fins[index].mesh.global_position


## The escort fins auto-fire at whatever is closest to the hero (60 damage every 0.5 s).
func escort_shot(from: Vector3) -> float:
	var best: Node3D = null
	var best_d := INF
	for e in ctx.enemies_in_radius(ctx.chest(), ctx.tuning.fins_range):
		var d := from.distance_squared_to(ctx.centre_of(e))
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return 0.0
	var aim := ctx.centre_of(best)
	return ctx.damage(best, ctx.tuning.ward_escort_damage, HitInfo.BEAM, &"corona_escort",
			ctx.tuning.fin_impact, Vector3.ZERO, aim)


# --- public ---------------------------------------------------------------------------------------

func beams_fired() -> int:
	return ctx.tuning.fin_beams * _sends


## Fins that are off the model right now: attacking, returning or holding the Ward.
func fins_out() -> int:
	_out_count = _count_out()
	return _out_count


func _count_out() -> int:
	var n := 0
	for f in _fins:
		if f.deployed():
			n += 1
	return n


func sends() -> int:
	return _sends


func hud_state() -> Dictionary:
	# NOT `fins_ready`: that key is the `fins` slot's boolean in SkillSlots.hud() (the HUD contract
	# is <id>_ready for every id), and merging over it would publish a count where a bool belongs.
	return {"fins_out": _out_count, "fins_available": available_fins(),
			"ward_left": ward.time_left(), "ward_absorb": ward.absorb_left(),
			"ward_absorb_max": ctx.tuning.ward_absorb, "ward_active": ward.is_active()}


func reset() -> void:
	for f in _fins:
		f.state = CoronaFin.F.DOCKED
		f.target = null
		f.mesh.visible = false
		f.respawn = 0.0
		f.life = 0.0
	ward_fin_indices.clear()
	_mask = -1
	_apply_drone_mask()
	_out_count = 0
	_sends = 0
	ward.reset()


func _play_action(id: StringName) -> void:
	if ctx.model != null and is_instance_valid(ctx.model) and ctx.model.has_method(&"play_action"):
		ctx.model.call(&"play_action", id)
