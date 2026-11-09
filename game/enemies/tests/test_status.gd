extends Node
## Status numbers test (enemies unit). Run: tools/godot.sh test res://enemies/tests/test_status.gd
## Checks the skills-catalog §4.1/§4.6/§4.7 tables exactly: stability pool, decay delay/rate,
## stagger + immunity, marks, primed, combo scaling, weak-point and staggered multipliers, armour,
## and that a kill emits Events.enemy_killed exactly once.

const DT := 1.0 / 120.0

var _fails: int = 0
var _checks: int = 0
var _kills: int = 0
var _staggers: int = 0
var _hit_events: int = 0


func _ready() -> void:
	Events.enemy_killed.connect(func(_e: Node, _h: HitInfo) -> void: _kills += 1)
	Events.enemy_staggered.connect(func(_e: Node, _h: HitInfo) -> void: _staggers += 1)
	_stability_tables()
	_decay()
	_stagger_and_immunity()
	_marks()
	_primed()
	_combo_scaling()
	_damage_multipliers()
	_armour()
	_kill_events()
	print("STATUS TEST %d checks, %d failures" % [_checks, _fails])
	print("PASS" if _fails == 0 else "FAIL")
	get_tree().quit(0 if _fails == 0 else 1)


func _eq(what: String, got: float, want: float, tol: float = 0.001) -> void:
	_checks += 1
	if absf(got - want) > tol:
		_fails += 1
		print("FAIL %s: got %f want %f" % [what, got, want])


func _is(what: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_fails += 1
		print("FAIL %s: got %s want %s" % [what, str(got), str(want)])


func _make(type: StringName) -> StatusComponent:
	var s := StatusComponent.new()
	s.configure(EnemyTypes.STATS[type])
	return s


## skills-catalog §4.6 table: swarmer 150 / stalker 700 / brute 2,600, with their decay rows.
func _stability_tables() -> void:
	_eq("ripper stability", _make(EnemyTypes.RIPPER).stability_max, 150.0)
	_eq("mantis stability", _make(EnemyTypes.MANTIS).stability_max, 700.0)
	_eq("juggernaut stability", _make(EnemyTypes.JUGGERNAUT).stability_max, 2600.0)
	_eq("spitter stability", _make(EnemyTypes.SPITTER).stability_max, 900.0)
	_eq("harrier stability", _make(EnemyTypes.HARRIER).stability_max, 300.0)
	var r := _make(EnemyTypes.RIPPER)
	r.add_impact(100.0)
	_eq("impact drains the pool", r.stability, 50.0)
	r.add_impact(50.0)
	_eq("pool floors at 0", r.stability, 0.0)
	_is("staggered at 0", r.is_staggered(), true)


## "decay 30 %/s after 0.8 s" (swarmer) — nothing regenerates inside the delay, then the pool
## refills at decay × max per second.
func _decay() -> void:
	var s := _make(EnemyTypes.RIPPER)
	s.add_impact(100.0)
	_advance(s, 0.7)
	_eq("no decay inside the delay", s.stability, 50.0)
	_advance(s, 0.2)   ## 0.1 s past the 0.8 s delay at 45/s
	_eq("ripper decay 30 %/s of 150", s.stability, 50.0 + 0.1 * 45.0, 0.05)
	var m := _make(EnemyTypes.MANTIS)
	m.add_impact(600.0)
	_advance(m, 1.1)
	_eq("no stalker decay before 1.2 s", m.stability, 100.0)
	_advance(m, 1.0)
	_eq("stalker decay 15 %/s of 700", m.stability, 100.0 + 0.9 * 105.0, 0.2)
	var b := _make(EnemyTypes.JUGGERNAUT)
	b.add_impact(2000.0)
	_advance(b, 2.0)
	_eq("brute decay 12 %/s of 2600", b.stability, 600.0 + 0.5 * 312.0, 0.5)
	_eq("decay never exceeds max", b.stability_max, 2600.0)


func _advance(s: StatusComponent, seconds: float) -> void:
	var steps := int(round(seconds / DT))
	for i in steps:
		s.tick(DT)


## Stagger duration per archetype and the immunity window that follows it.
func _stagger_and_immunity() -> void:
	var r := _make(EnemyTypes.RIPPER)
	r.add_impact(150.0)
	_is("swarmer staggered", r.is_staggered(), true)
	_eq("swarmer stagger 0.8 s", r.stagger_time, 0.8)
	_advance(r, 0.79)
	_is("still staggered at 0.79 s", r.is_staggered(), true)
	_advance(r, 0.03)
	_is("stagger ends at 0.8 s", r.is_staggered(), false)
	_eq("pool refilled after stagger", r.stability, 150.0)
	_eq("swarmer has no immunity", r.immunity_time, 0.0)

	var m := _make(EnemyTypes.MANTIS)
	m.add_impact(700.0)
	_eq("stalker stagger 1.4 s", m.stagger_time, 1.4)
	_advance(m, 1.45)
	_is("stalker recovered", m.is_staggered(), false)
	_is("stalker immune after stagger", m.is_immune(), true)
	_is("immune blocks a new stagger", m.add_impact(700.0), false)
	_advance(m, 1.5)
	_is("immunity expires after 1.5 s", m.is_immune(), false)

	var b := _make(EnemyTypes.JUGGERNAUT)
	b.add_impact(2600.0)
	_eq("brute stagger 2.6 s", b.stagger_time, 2.6)
	_eq("brute immunity 3 s", b.immunity_time, 3.0)


## skills-catalog §4.1: 2 / 4 rifle hits = 1 / 2 marks, expiring 5 s after the last hit.
func _marks() -> void:
	var s := _make(EnemyTypes.RIPPER)
	s.add_mark_hit()
	_eq("1 hit = no mark", float(s.marks), 0.0)
	s.add_mark_hit()
	_eq("2 hits = 1 mark", float(s.marks), 1.0)
	s.add_mark_hit(2)
	_eq("4 hits = 2 marks", float(s.marks), 2.0)
	s.add_mark_hit(4)
	_eq("marks cap at 2", float(s.marks), 2.0)
	_advance(s, 4.9)
	_eq("marks still live at 4.9 s", float(s.marks), 2.0)
	_advance(s, 0.2)
	_eq("marks expire after 5 s", float(s.marks), 0.0)
	s.add_mark_hit(2)
	_eq("marks come back", float(s.marks), 1.0)
	_advance(s, 3.0)
	s.add_mark_hit()
	_eq("a new hit restarts the 5 s timer", float(s.marks), 1.0)


## Undertow prime window (skills-catalog §4.7: primed 5 s) and the COLLAPSE detonator's clear
## (CONTRACTS §4: `clear_prime()` emits `primed_changed`, so the HUD plate hears about it).
func _primed() -> void:
	var s := _make(EnemyTypes.RIPPER)
	var events: Array[bool] = []
	s.primed_changed.connect(func(p: bool) -> void: events.append(p))
	_is("not primed by default", s.is_primed(), false)
	s.prime()
	_is("primed", s.is_primed(), true)
	_advance(s, 4.9)
	_is("still primed at 4.9 s", s.is_primed(), true)
	_advance(s, 0.2)
	_is("prime ends at 5 s", s.is_primed(), false)
	_is("expiry announced once", str(events), str([true, false]))
	s.prime()
	_is("clear_prime reports it cleared one", s.clear_prime(), true)
	_is("clear_prime unprimes", s.is_primed(), false)
	_is("clear_prime announced it", str(events), str([true, false, true, false]))
	_is("clear_prime on a clean target is a no-op", not s.clear_prime() and events.size() == 4,
			true)
	_advance(s, 6.0)
	_is("a cleared prime does not come back", not s.is_primed() and events.size() == 4, true)


## Combo scaling: hits 1–6 at 100 %, −6 % per hit after, floor 55 %, reset after 1.5 s, and
## suspended while the target is staggered.
func _combo_scaling() -> void:
	var s := _make(EnemyTypes.JUGGERNAUT)
	for i in 6:
		_eq("hit %d at 100 %%" % (i + 1), s.combo_multiplier(), 1.0)
		s.commit_hit()
	var want := 1.0
	for i in 7:
		want = maxf(0.55, 1.0 - 0.06 * float(i + 1))
		_eq("scaled hit %d" % (i + 7), s.combo_multiplier(), want)
		s.commit_hit()
	_eq("floor is 55 %", s.combo_multiplier(), 0.55)
	_advance(s, 1.6)
	_eq("combo resets after 1.5 s", s.combo_multiplier(), 1.0)
	_eq("combo counter reset", float(s.combo_hits()), 0.0)
	for i in 8:
		s.commit_hit()
	s.add_impact(2600.0)
	_eq("scaling suspended while staggered", s.combo_multiplier(), 1.0)


# --- actor level (EnemyBase.take_hit) -----------------------------------------------------------

func _spawn(type: StringName) -> EnemyBase:
	var packed := load("res://enemies/%s/%s.tscn" % [type, type]) as PackedScene
	var e := packed.instantiate() as EnemyBase
	add_child(e)
	return e


func _hit(amount: float, kind: StringName, part: StringName, weak: bool, weapon: StringName,
		stagger: float = 0.0) -> HitInfo:
	var h := HitInfo.make(amount, kind, null, weapon)
	h.hurtbox_part = part
	h.weak_point = weak
	h.stagger = stagger
	return h


## Weak points ×2.5 (SPEC §7), staggered targets ×1.8 melee/charged and ×1.35 everything else
## (skills-catalog §4.6).
func _damage_multipliers() -> void:
	var e := _spawn(EnemyTypes.SPITTER)
	var before := e.hp
	e.take_hit(_hit(100.0, HitInfo.BEAM, &"body", false, &"beam_rifle"))
	_eq("body hit at ×1", before - e.hp, 100.0)
	before = e.hp
	e.take_hit(_hit(100.0, HitInfo.BEAM, &"weak", true, &"beam_rifle"))
	_eq("weak point ×2.5", before - e.hp, 250.0)
	_is("weak point flags a crit", e.status.marks, 1)

	e.status.add_impact(900.0)
	_is("spitter staggered", e.status.is_staggered(), true)
	before = e.hp
	e.take_hit(_hit(100.0, HitInfo.MELEE, &"body", false, &"melee_l1"))
	_eq("staggered ×1.8 melee", before - e.hp, 180.0)
	before = e.hp
	e.take_hit(_hit(100.0, HitInfo.BEAM, &"body", false, &"rifle_stage2"))
	_eq("staggered ×1.8 charged", before - e.hp, 180.0)
	before = e.hp
	e.take_hit(_hit(100.0, HitInfo.BEAM, &"body", false, &"rifle_stage1"))
	_eq("staggered ×1.8 charge stage 1", before - e.hp, 180.0)
	before = e.hp
	e.take_hit(_hit(100.0, HitInfo.BALLISTIC, &"body", false, &"gatling"))
	_eq("staggered ×1.35 other", before - e.hp, 135.0)
	before = e.hp
	e.take_hit(_hit(100.0, HitInfo.MELEE, &"weak", true, &"melee_l1"))
	_eq("weak point and stagger stack", before - e.hp, 100.0 * 2.5 * 1.8)
	e.queue_free()


## The juggernaut's front plate and body armour blunt damage; its back weak point does not.
func _armour() -> void:
	var e := _spawn(EnemyTypes.JUGGERNAUT)
	var before := e.hp
	e.take_hit(_hit(1000.0, HitInfo.BEAM, &"plate", false, &"beam_rifle"))
	_eq("front plate ×0.15", before - e.hp, 150.0)
	before = e.hp
	e.take_hit(_hit(1000.0, HitInfo.BEAM, &"body", false, &"beam_rifle"))
	_eq("brute body ×0.35", before - e.hp, 350.0)
	before = e.hp
	e.take_hit(_hit(1000.0, HitInfo.BEAM, &"weak", true, &"beam_rifle"))
	_eq("back weak point ×2.5", before - e.hp, 2500.0)
	var weak_box := e.get_node_or_null(^"Hurtbox_weak") as Hurtbox
	_is("weak hurtbox exists", weak_box != null, true)
	_is("weak hurtbox is flagged", weak_box.is_weak_point, true)
	var plate_box := e.get_node_or_null(^"Hurtbox_plate") as Hurtbox
	_is("plate hurtbox exists", plate_box != null, true)
	e.queue_free()


## A killing blow emits Events.enemy_killed once, sets final_amount and clears `alive`.
func _kill_events() -> void:
	var e := _spawn(EnemyTypes.RIPPER)
	var on_hit := func(_h: HitInfo, _r: Node) -> void: _hit_events += 1
	Events.hit_landed.connect(on_hit)
	var h := _hit(500.0, HitInfo.BEAM, &"body", false, &"beam_rifle")
	e.take_hit(h)
	_eq("final_amount written", h.final_amount, 500.0)
	_eq("hp floors at 0", e.hp, 0.0)
	_is("dead", e.is_alive(), false)
	_eq("enemy_killed emitted once", float(_kills), 1.0)
	_eq("hit_landed emitted once", float(_hit_events), 1.0)
	e.take_hit(_hit(500.0, HitInfo.BEAM, &"body", false, &"beam_rifle"))
	_eq("no second kill event", float(_kills), 1.0)
	Events.hit_landed.disconnect(on_hit)
	_is("team is monsters", e.get_team(), 1)
	var hud := e.hud_state()
	_is("hud_state has hp", hud.has("hp"), true)
	_is("hud_state has stability", hud.has("stability"), true)
	_is("hud_state has marks", hud.has("marks"), true)
	_is("hud_state has primed", hud.has("primed"), true)
	_is("hud_state has staggered", hud.has("staggered"), true)
	_is("hud_state has a name", String(hud["name"]) != "", true)
	e.queue_free()
