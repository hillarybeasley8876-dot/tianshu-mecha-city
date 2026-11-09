class_name PierceLightRifle
extends Node3D
## P1 Pierce-Light rifle (贯光步枪) — semi-auto hitscan with a two-stage charge.
## Tap fires one round; holding stages the shot (0.6 s → pierce 1, 1.2 s → pierce all + blast) and
## holding 3 s fires stage 2 by itself. Ranges are the dossier's ×2 (skills-catalog §4.2 P1).
##
## Clock (CONTRACTS §3): the rate cap, the reload and the charge accumulator all take
## `Feel.player_delta` — a stage-2 charge still takes 1.2 s of the player's own time in witch time,
## and a global hit-stop freezes the charge instead of charging through the freeze.

const ID := &"beam_rifle"
## hit.weapon per charge stage: enemies give charged shots the ×1.8 staggered bonus by these ids (SPEC §7.1).
const STAGE_IDS: Array[StringName] = [&"beam_rifle", &"rifle_stage1", &"rifle_stage2"]
const PIERCE_ALL := 24

@export var tuning: RifleTuning

var ctx: WeaponContext = null
var ammo: int = 0
var reloading: bool = false
var shots_fired: int = 0
var hits_landed: int = 0

var _cd: float = 0.0
var _charge: float = 0.0
var _charging: bool = false
var _stage: int = 0
var _reload_left: float = 0.0
var _empty_left: float = 0.0


func _ready() -> void:
	if tuning == null:
		tuning = RifleTuning.new()
	if ammo <= 0:
		ammo = tuning.magazine


func setup(c: WeaponContext) -> void:
	ctx = c


func reset_state() -> void:
	ammo = tuning.magazine
	reloading = false
	_reload_left = 0.0
	_empty_left = 0.0
	_cd = 0.0
	_charge = 0.0
	_charging = false
	_stage = 0


func update(player_dt: float, held: bool, pressed: bool, released: bool) -> void:
	_cd = maxf(_cd - player_dt, 0.0)
	if reloading:
		_reload_left -= player_dt
		if _reload_left <= 0.0:
			reloading = false
			ammo = tuning.magazine
		return
	# An empty cell must never be a silent no-op (look review: '0 / 9 CHARGE' with a dead trigger):
	# the press reloads, and an idle empty cell reloads itself shortly after the last round leaves.
	if ammo <= 0:
		if pressed:
			reload()
			return
		_empty_left += player_dt
		if _empty_left >= tuning.auto_reload_delay:
			reload()
		return
	_empty_left = 0.0
	if pressed:
		_charging = true
		_charge = 0.0
		_stage = 0
	if _charging and held:
		_charge += player_dt
		_advance_stage()
		if _charge >= tuning.auto_fire_time:
			_release()
			return
	if released and _charging:
		_release()


func _advance_stage() -> void:
	var s := stage_for(_charge)
	if s == _stage:
		return
	_stage = s
	if s == 1:
		Feel.play(&"rifle_charge_1", ctx.socket(&"muzzle_r"))
		ctx.play_action(&"charge_r")
	elif s == 2:
		Feel.play(&"rifle_charge_2", ctx.socket(&"muzzle_r"))


func stage_for(charge: float) -> int:
	if charge >= tuning.stage2_time:
		return 2
	return 1 if charge >= tuning.stage1_time else 0


func _release() -> void:
	var want := stage_for(_charge)
	_charging = false
	_charge = 0.0
	_stage = 0
	var stage := _affordable(want)
	if stage == 0:
		_fire_normal()
	else:
		_fire_charged(stage)


## Highest stage the cell and the EN gauge can actually pay for (0 = plain shot).
func _affordable(want: int) -> int:
	for s in range(want, 0, -1):
		if ammo >= _rounds(s) and ctx.has_energy(_energy(s)):
			return s
	return 0


func _rounds(stage: int) -> int:
	return tuning.stage1_rounds if stage == 1 else tuning.stage2_rounds


func _energy(stage: int) -> float:
	return tuning.stage1_energy if stage == 1 else tuning.stage2_energy


func _fire_normal() -> void:
	if _cd > 0.0:
		return
	if ammo <= 0:
		reload()
		return
	ammo -= 1
	_cd = tuning.fire_interval
	_shoot(tuning.damage, tuning.impact, 0, 0.0, 0)


func _fire_charged(stage: int) -> void:
	if _cd > 0.0:
		return
	ammo -= _rounds(stage)
	if not ctx.consume_energy(_energy(stage)):
		push_warning("PierceLightRifle: EN check passed but the spend failed")
	_cd = tuning.fire_interval
	var pierce := PIERCE_ALL if stage == 2 else tuning.stage1_pierce
	var blast := tuning.stage2_blast_radius if stage == 2 else 0.0
	var dmg := tuning.stage1_damage if stage == 1 else tuning.stage2_damage
	var imp := tuning.stage1_impact if stage == 1 else tuning.stage2_impact
	_shoot(dmg, imp, pierce, blast, stage)


## The shot itself: pierce ray, damage with range falloff, beam + muzzle ring, feel rows.
func _shoot(damage: float, impact: float, pierce: int, blast_radius: float, stage: int) -> void:
	var muzzle := ctx.socket(&"muzzle_r")
	var dir := ctx.aim_dir_from(muzzle)
	var max_hits := (pierce + 1) if pierce < PIERCE_ALL else PIERCE_ALL
	var hits := ctx.query.ray_hits(muzzle, dir, tuning.max_range, Layers.MASK_PLAYER_ATTACK, max_hits)
	var end := muzzle + dir * tuning.max_range
	var actors: Array[Node] = []
	var last_actor := false
	for h: Dictionary in hits:
		var point: Vector3 = h["position"]
		var normal: Vector3 = h["normal"]
		var falloff := tuning.damage_at(muzzle.distance_to(point))
		var hit := HitInfo.make(damage * falloff, HitInfo.BEAM, ctx.player, STAGE_IDS[stage])
		hit.stagger = impact * falloff
		var actor := ctx.query.deliver(hit, h["collider"], point, normal, blast_radius)
		var spark := 1.6 + 1.4 * float(stage)
		if actor == null:                      # scenery stops the beam
			end = point
			ctx.sparks.spark_beam(point, normal, spark)
			last_actor = false
			break
		actors.append(actor)
		hits_landed += 1
		end = point
		last_actor = true
		ctx.sparks.spark_beam(point, normal, spark * 1.5)
	if blast_radius > 0.0 and last_actor:
		ctx.query.blast(end, blast_radius, damage * 0.5, impact * 0.5, HitInfo.BEAM, ID, actors)
	_visuals(muzzle, end, dir, stage, blast_radius > 0.0, not actors.is_empty())
	shots_fired += 1
	Events.weapon_fired.emit(ID, muzzle, dir)
	Audio.play(&"beam_rifle_fire", muzzle)
	ctx.play_action(&"fire_r")
	Feel.play(&"rifle_fire", muzzle)


## Beam, muzzle ring and (stage 2) the shock ring + afterglow. The muzzle flash light is the fx
## unit's pool when it exists. Everything anchored at the muzzle goes through the first-person size
## and opacity rule (lead r5 item 1): the cockpit lens is ~6 m from `muzzle_r`, where a 9.6 m stage-2
## ring and a 7 m glow tube white out the whole canopy.
func _visuals(muzzle: Vector3, end: Vector3, dir: Vector3, stage: int, stage2: bool,
		hit_actor: bool) -> void:
	var a := ctx.fp_alpha()
	ctx.beams.beam(ctx.fp_beam_from(muzzle, dir), end, ctx.fp_size(tuning.core_radius(stage)),
			ctx.fp_size(tuning.glow_radius(stage)), tuning.core_color, tuning.glow_color,
			tuning.beam_life, tuning.afterglow_time * (1.0 if stage > 0 else 0.35), a)
	ctx.beams.ring(muzzle, dir, tuning.glow_color,
			ctx.fp_size(tuning.muzzle_ring_radius * (1.0 + float(stage))), 0.14, a)
	ctx.beams.flash(muzzle, tuning.glow_color, ctx.fp_light_energy(1.6 + 2.0 * float(stage)),
			ctx.fp_light_range(26.0), 3.0)
	if stage2:
		ctx.beams.ring(muzzle, dir, tuning.core_color, ctx.fp_size(tuning.shock_ring_radius),
				tuning.shock_ring_time, a)
	if hit_actor:
		Feel.play(&"rifle_stage2_hit" if stage2 else &"rifle_hit", end)


func reload() -> bool:
	if reloading or ammo >= tuning.magazine or ctx == null:
		return false
	reloading = true
	_reload_left = tuning.reload_time_partial if ammo > 0 else tuning.reload_time
	_empty_left = 0.0
	_charging = false
	_charge = 0.0
	ctx.play_action(&"reload")
	return true


func is_firing() -> bool:
	return _charging


## Put the rifle away mid-charge (weapon swap): the cell keeps its rounds, the charge is lost.
func cancel() -> void:
	_charging = false
	_charge = 0.0
	_stage = 0


func charge_ratio() -> float:
	return clampf(_charge / maxf(tuning.stage2_time, 0.001), 0.0, 1.0)


func hud_state() -> Dictionary:
	return {
		"ammo": ammo,
		"ammo_max": tuning.magazine,
		"reloading": reloading,
		"charge": charge_ratio(),
		"charge_stage": stage_for(_charge) if _charging else 0,
	}
