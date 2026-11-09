class_name SkillSystem
extends Node3D
## Skill component of the PlayerMech (CONTRACTS §5): owns the eight active abilities and the Zenith
## Overdrive ultimate, their cooldowns / charges / EN costs, and the input that drives them. The
## abilities themselves live in one script each under this folder; this file only routes.
##
## It also owns the two cross-skill systems: the **Ambush** window (Rift Step) and the **Overdrive**
## buff multipliers every skill reads through `SkillContext.scale_damage / scale_impact`, and it joins
## the `&"prime_detonators"` group so any COLLAPSE detonator (rifle stage 2, missiles, charged wave,
## burst, plunge) can resolve Undertow primes through `detonate_primes`.
##
## hud_state() keys: <id>_cd, <id>_cd_max, <id>_charges, <id>_ready for every id in IDS, plus
## od, od_max, overdrive_active, overdrive_left, overdrive_igniting, lance_ready, lance_charging,
## lance_firing, ambushing, anchor_attached, fins_out, ward_left, ward_absorb, well_left,
## last_hit_usec, last_hit_kind.

const SHOWCASE := "res://combat/skills/tests/showcase.gd"
const TUNING_PATH := "res://combat/skills/tuning/skill_tuning.tres"
## Skills with a cooldown slot. `ward` is the hold half of the fins and carries its own, longer CD.
const IDS: Array[StringName] = [&"rift_step", &"anchor", &"fins", &"ward", &"burst", &"well", &"plunge"]

var ctx: SkillContext = null
var tuning: SkillTuning = null
var vfx: SkillVfx = null

var rift: RiftStep = null
var anchor: SkyhookAnchor = null
var fins: CoronaFins = null
var burst: ShockcoreBurst = null
var well: UndertowWell = null
var plunge: PlungeBreaker = null
var zenith: ZenithOverdrive = null

var _slots: SkillSlots = null
var _input: SkillInput = null
var _od: SkillOverdriveState = null
var _player: Node = null
var _ambush_left: float = 0.0

var last_hit_usec: int = 0
var last_hit_kind: StringName = &""


func _ready() -> void:
	tuning = load(TUNING_PATH) as SkillTuning
	if tuning == null:
		push_warning("SkillSystem: %s missing, using script defaults" % TUNING_PATH)
		tuning = SkillTuning.new()
	ctx = SkillContext.new(tuning)
	_input = SkillInput.new(self)
	# The skills' own signature effects (one pool, built once): `fx/**` is the feel unit's, so every
	# shell / ring / beam / column the abilities draw comes from here.
	vfx = SkillVfx.new()
	vfx.name = "SkillVfx"
	add_child(vfx)
	ctx.vfx = vfx
	_build_slots()
	_build_skills()
	add_to_group(&"prime_detonators")
	_refresh()
	Events.hit_landed.connect(_on_hit_landed)
	Events.boost_started.connect(_on_boost_started)
	_maybe_start_showcase()
	set_physics_process(true)


## Capture aid: `--skills-showcase=<clip|all> --shots=<abs dir>` drives the real rig and writes the
## per-skill stills from code (tests/showcase.gd). Never present in a normal run.
func _maybe_start_showcase() -> void:
	if not Game.has_flag("skills-showcase"):
		return
	var which := Game.flag("skills-showcase", "all")
	var dir := Game.flag("shots", ProjectSettings.globalize_path("res://../captures"))
	# Loaded by path, never named: tests/ is not in the export, and a class reference would not compile.
	var script := load(SHOWCASE) as Script
	if script == null:
		push_warning("SkillSystem: --skills-showcase needs %s (dev builds only)" % SHOWCASE)
		return
	var show := script.new() as Node
	show.name = "SkillShowcase"
	add_child(show)
	show.setup(self)
	show.start(which, dir)


func _build_slots() -> void:
	_slots = SkillSlots.new()
	_slots.add(&"rift_step", tuning.rift_cd, tuning.rift_cost, 1)
	_slots.add(&"anchor", tuning.anchor_recharge, tuning.anchor_cost, tuning.anchor_charges)
	_slots.add(&"fins", tuning.fins_cd, tuning.fins_cost, 1)
	_slots.add(&"ward", tuning.ward_cd, tuning.ward_cost, 1)
	_slots.add(&"burst", tuning.burst_cd, tuning.burst_cost, 1)
	_slots.add(&"well", tuning.well_cd, tuning.well_cost, 1)
	_slots.add(&"plunge", tuning.plunge_cd, tuning.plunge_cost, 1)


func _build_skills() -> void:
	for n: Array in [
		[RiftStep.new(), "RiftStep"], [SkyhookAnchor.new(), "SkyhookAnchor"],
		[CoronaFins.new(), "CoronaFins"], [ShockcoreBurst.new(), "ShockcoreBurst"],
		[UndertowWell.new(), "UndertowWell"], [PlungeBreaker.new(), "PlungeBreaker"],
		[ZenithOverdrive.new(), "ZenithOverdrive"]]:
		var node := n[0] as Node3D
		node.name = String(n[1])
		add_child(node)
		node.call(&"setup", ctx, self)
	rift = get_node(^"RiftStep") as RiftStep
	anchor = get_node(^"SkyhookAnchor") as SkyhookAnchor
	fins = get_node(^"CoronaFins") as CoronaFins
	burst = get_node(^"ShockcoreBurst") as ShockcoreBurst
	well = get_node(^"UndertowWell") as UndertowWell
	plunge = get_node(^"PlungeBreaker") as PlungeBreaker
	zenith = get_node(^"ZenithOverdrive") as ZenithOverdrive
	# The Overdrive window / meter / aftermath lives in its own object (overdrive_state.gd); it needs
	# `zenith` and `vfx`, so it is built last.
	_od = SkillOverdriveState.new()
	_od.setup(self)


## The mech instances this component before its model / aim siblings are guaranteed ready, so the
## references are refreshed every tick until they resolve (same rule as the WeaponSystem).
func _refresh() -> void:
	var p := get_parent()
	if p != _player:
		_player = p
	ctx.refresh(p)
	if _od != null:
		_od.attach(p)


# --- cooldown / charge / EN bookkeeping -----------------------------------------------------------

func slot(id: StringName) -> SkillSlots.Slot:
	return _slots.get_slot(id)


func is_ready(id: StringName) -> bool:
	var s := slot(id)
	return s != null and s.ready() and _has_energy(s.cost)


func _has_energy(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if _player == null or not _player.has_method(&"consume_energy"):
		return true
	return float(_player.get(&"energy")) >= cost


## Spend a charge and its EN, then announce it. Returns false (and spends nothing) when the skill is
## still cooling or the gauge is short — callers must not act on a false return.
func pay(id: StringName) -> bool:
	_refresh()  # a skill may be fired from a tool or a test before the first physics tick
	var s := slot(id)
	if s == null or not s.ready() or not _has_energy(s.cost):
		return false
	if s.cost > 0.0 and _player != null and _player.has_method(&"consume_energy"):
		if not bool(_player.call(&"consume_energy", s.cost)):
			return false
	s.spend()
	Events.skill_used.emit(id)
	return true


## skills-catalog §4.5: activating the Overdrive resets every cooldown.
func reset_all_cooldowns() -> void:
	for id in _slots.reset_all():
		Events.skill_ready.emit(id)


func _tick_cooldowns(delta: float) -> void:
	var rate := tuning.od_cd_tick if _od.active() else 1.0
	for id in _slots.tick_all(delta, rate):
		Events.skill_ready.emit(id)


func _on_hit_landed(hit: HitInfo, receiver: Node) -> void:
	if hit == null or hit.source != _player:
		return
	last_hit_usec = Time.get_ticks_usec()
	last_hit_kind = &"kill" if not bool(receiver.call(&"is_alive")) else &"normal"


## SPEC §4.5: dashes are free inside the Overdrive. Refunded on the bus so the EN change goes through
## MechEnergy's own `add_energy` (which also clears the post-Outage restart lock).
func _on_boost_started(kind: StringName) -> void:
	if kind != &"quick" or not _od.active() or _player == null:
		return
	if _player.has_method(&"add_energy"):
		_player.call(&"add_energy", _dash_cost())


func _dash_cost() -> float:
	var t := ctx.mech_tuning()
	if t == null:
		return 110.0
	return float(t.get(&"dash_cost") if ctx.grounded() else t.get(&"dash_air_cost"))


# --- per-frame -----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_refresh()
	# CONTRACTS §3 clocks: cooldowns / charges / OD / buff windows and the skills' own state machines
	# run on the player clock (full speed in witch time, frozen by a global hit-stop); the hold
	# thresholds that turn a press into a gesture run on the real clock.
	var pdt := Feel.player_delta(delta)
	_tick_cooldowns(pdt)
	_tick_buffs(pdt)
	_input.setup(_player)
	_input.tick(Feel.real_delta(delta))
	for s: Node3D in [rift, anchor, fins, burst, well, plunge, zenith]:
		if s != null:
			s.call(&"tick", pdt)
	_refresh_multipliers()


func _tick_buffs(delta: float) -> void:
	_ambush_left = maxf(_ambush_left - delta, 0.0)
	_od.tick(delta)


## Ambush and Overdrive stack multiplicatively on every damage and impact number a skill deals.
func _refresh_multipliers() -> void:
	ctx.damage_mult = (tuning.od_damage if _od.active() else 1.0) \
			* (tuning.rift_ambush_damage if _ambush_left > 0.0 else 1.0)
	ctx.impact_mult = (tuning.od_impact if _od.active() else 1.0) \
			* (tuning.rift_ambush_impact if _ambush_left > 0.0 else 1.0)


# --- activation API (also the test / tool entry points) --------------------------------------------

## May the mech start a skill right now? The movement state owns the answer (CONTRACTS §5).
func can_act() -> bool:
	if _player == null or not _player.has_method(&"can_cancel"):
		return true
	return bool(_player.call(&"can_cancel", &"skill"))


## The one skills teardown the mech calls on the killing blow (skills r4 item 6, r5): SkillInput
## fires it on the first dead tick and mech-move's death gate calls it directly, so it must be
## idempotent. A corpse keeps no grapple line, no barrier, no Overdrive window and no lance beam.
## It touches no charge, no cooldown and no EN — those are carry-over — and it is the ONLY place the
## mech has to reach: nothing else of ours is called from the death gate.
func on_player_died() -> void:
	if anchor != null:
		anchor.detach_silently()
	if fins != null and fins.ward != null:
		fins.ward.drop()
	if zenith != null:
		zenith.reset()  # a beam mid-fire stops with its owner; `reset()` never re-arms anything
	if _od != null:
		_od.end_on_death()


## S1 Rift Step. Returns true when the blink started.
## Every `try_*` checks `can_*` BEFORE `pay`: a refused activation must never spend a charge or EN.
func try_rift_step() -> bool:
	if not can_act() or not rift.can_begin() or not pay(&"rift_step"):
		return false
	return rift.begin()


## S2 Skyhook Anchor. `aim_dir` is optional; the skill aims at the crosshair when it is omitted.
func try_anchor() -> bool:
	if not anchor.can_begin() or not pay(&"anchor"):
		return false
	return anchor.begin()


func try_fins() -> bool:
	if not can_act() or not fins.can_send() or not pay(&"fins"):
		return false
	return fins.send()


func try_ward() -> bool:
	if not can_act() or not fins.can_ward() or not pay(&"ward"):
		return false
	return fins.raise_ward()


func try_burst() -> bool:
	if not can_act() or not burst.can_begin() or not pay(&"burst"):
		return false
	return burst.begin()


func try_well() -> bool:
	if not can_act() or not well.can_begin() or not pay(&"well"):
		return false
	return well.begin()


func try_plunge() -> bool:
	if not plunge.can_begin() or not pay(&"plunge"):
		return false
	return plunge.begin()


## Zenith Overdrive: gated on a full OD meter, not on a cooldown (skills-catalog §4.5). The window,
## the meter and the aftermath are `SkillOverdriveState`'s; this only refreshes the mech reference
## first, because a tool or a test may call it before the first physics tick.
func try_overdrive() -> bool:
	_refresh()
	return _od.begin()


func od_full() -> bool:
	return _od.full()


## Called by ZenithOverdrive when the lance sequence ends: the Overdrive window closes with it and
## the 3 s aftermath starts. A corpse pays nothing (see `SkillOverdriveState.end`).
func end_overdrive() -> void:
	_od.end()


func overdrive_left() -> float:
	return _od.left()


func is_overdrive_active() -> bool:
	return _od.active()


func is_aftermath() -> bool:
	return _od.aftermath() > 0.0


## skills-catalog §4.5: no dash during the 3 s aftermath. Other units may ask.
func dashes_blocked() -> bool:
	return _od.aftermath() > 0.0


func grant_ambush() -> void:
	_ambush_left = tuning.rift_ambush

func is_ambushing() -> bool:
	return _ambush_left > 0.0


func ambush_left() -> float:
	return _ambush_left


## COLLAPSE (skills-catalog §4.7): reached through the `&"prime_detonators"` group by any detonator.
func detonate_primes(center: Vector3, radius: float, source: Node) -> int:
	return well.detonate(center, radius, source)


func hud_state() -> Dictionary:
	var out: Dictionary = {}
	out.merge(_slots.hud_all(), true)
	out.merge(_od.hud(), true)
	out["lance_charging"] = zenith.is_charging()
	out["lance_firing"] = zenith.is_firing()
	out["ambushing"] = _ambush_left > 0.0
	out["ambush_left"] = _ambush_left
	out["anchor_attached"] = anchor != null and anchor.is_attached()
	for s: Node3D in [fins, well]:
		if s != null and s.has_method(&"hud_state"):
			out.merge(s.call(&"hud_state"), true)
	out["last_hit_usec"] = last_hit_usec
	out["last_hit_kind"] = last_hit_kind
	return out


## Tools and tests: put every skill back on cooldown zero and clear the field effects.
func reset() -> void:
	_slots.reset_all()
	_ambush_left = 0.0
	_od.reset()
	_input.reset()
	for s: Node3D in [rift, anchor, fins, burst, well, plunge, zenith]:
		if s != null and s.has_method(&"reset"):
			s.call(&"reset")
