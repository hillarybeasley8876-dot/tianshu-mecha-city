class_name MeleeHandSuite
extends RefCounted
## Review r4 — "the saber must stay in the hand". The drawn blade's transform IS the `saber_r`
## socket's; the arc maths may stay for the hit volume, but nothing may place the blade on it.
##
## For every move the component can play this samples the drawn blade every physics tick and checks:
##   1. the blade root sits on the socket origin (≤ 0.5 m);
##   2. the tip is exactly one blade length from the socket origin (the ignition scale folded in);
##   3. the angle between the drawn blade axis and the socket's own axis never changes — a blade
##      driven by anything but the socket swings against it and the angle moves;
##   4. the tip really travels (the rig's socket swings, so a frozen blade cannot pass);
##   5. the tip is NOT the table's arc point — the direct anti-regression for the old `place_swing`.

## Contract tolerance from the review's gate: the blade stays within 0.5 m of the socket line.
const TOL := 0.5
## How far the tip must travel across a move before the check is worth anything.
const MIN_TRAVEL := 5.0
## How far the drawn tip must get from the arc-placed tip at least once.
const ARC_GAP := 3.0
## Degrees the blade-vs-socket angle may drift across a move (it should not drift at all).
const ANGLE_DRIFT_DEG := 2.0
## Fraction of the table's reach the DRAWN tip must cover, measured from the same pivot (r5 item 2).
const REACH_COVER := 0.95


class Sample:
	extends RefCounted
	var worst_root: float = 0.0      ## furthest the blade root strayed from the socket origin
	var worst_length: float = 0.0    ## worst |tip distance − blade length × extend|
	var worst_angle: float = 0.0     ## worst drift of the blade-vs-socket angle, degrees
	var angle_base: float = -1.0
	var travel: float = 0.0          ## how far the tip moved between its extremes
	var arc_gap: float = 0.0         ## largest gap between the drawn tip and the arc-placed tip
	var reach_seen: float = 0.0      ## furthest the DRAWN tip got from the arc pivot in the active window
	var reach_want: float = 0.0      ## what the hit volume reaches to on the same move
	var ticks: int = 0
	var lo := Vector3.ZERO
	var hi := Vector3.ZERO


static func run(h: MeleeTestHarness) -> void:
	await _move(h, MeleeTable.L1, "l1")
	await _move(h, MeleeTable.L2, "l2")
	await _move(h, MeleeTable.L3, "l3")
	await _move(h, MeleeTable.LUNGE, "lunge")
	await _move(h, MeleeTable.CHARGE_SLASH, "charge_slash")
	await _move(h, MeleeTable.AIR_L1, "air_l1")
	await _move(h, MeleeTable.AIR_L2, "air_l2")
	await _string(h)


## Runs one move from a clean rig and samples the drawn blade on every physics tick of it.
static func _move(h: MeleeTestHarness, id: StringName, label: String) -> void:
	h.fresh()
	if MeleeTable.AIR_CHAIN.has(id):
		h.player.grounded = false
	var target := h.add_dummy(40.0 if id == MeleeTable.LUNGE else 20.0)
	if id == MeleeTable.LUNGE:
		h.aim.lock(target)
	await h.step(0.1)
	h.system._begin(id)
	h.eq("hand.%s_started" % label, h.system.move, id)
	var s := await _sample(h, id)
	_report(h, label, s)
	h.player.grounded = true
	h.aim.lock(null)


## The whole ground string back to back: three moves, one continuous sample.
static func _string(h: MeleeTestHarness) -> void:
	h.fresh()
	h.add_dummy(20.0)
	await h.step(0.1)
	var s := Sample.new()
	for id: StringName in MeleeTable.GROUND_CHAIN:
		h.system._begin(id)
		_merge(s, await _sample(h, id))
	_report(h, "string", s)


## Every physics tick of `id`: where the drawn blade is, against where the socket is and where the
## old arc placement would have put it.
static func _sample(h: MeleeTestHarness, id: StringName) -> Sample:
	var s := Sample.new()
	var saber: SaberVisual = h.system.saber
	var socket := saber.socket()
	if socket == null:
		return s
	var total := MeleeTable.ticks(MeleeTable.total_frames(id)) + 2
	var active_from := MeleeTable.ticks(MeleeTable.field(id, "startup"))
	var active_n := maxi(MeleeTable.ticks(MeleeTable.field(id, "active")), 1)
	for i in total:
		await h.tree.physics_frame
		if not saber.lit:
			continue
		_tick_sample(h, s, saber, socket, id, i - active_from, active_n)
	return s


static func _tick_sample(h: MeleeTestHarness, s: Sample, saber: SaberVisual, socket: Node3D,
		id: StringName, active_tick: int, active_n: int) -> void:
	var pts := saber.blade_points()
	var root: Vector3 = pts[0]
	var tip: Vector3 = pts[1]
	var origin := socket.global_position
	var drawn := tip - root
	var len_want := saber.drawn_length()
	if drawn.length_squared() < 0.0001:
		return
	s.ticks += 1
	s.worst_root = maxf(s.worst_root, root.distance_to(origin))
	s.worst_length = maxf(s.worst_length, absf(drawn.length() - len_want))
	var angle := rad_to_deg(drawn.normalized().angle_to(-socket.global_basis.z))
	if s.angle_base < 0.0:
		s.angle_base = angle
	s.worst_angle = maxf(s.worst_angle, absf(angle - s.angle_base))
	if s.ticks == 1:
		s.lo = tip
		s.hi = tip
	s.lo = Vector3(minf(s.lo.x, tip.x), minf(s.lo.y, tip.y), minf(s.lo.z, tip.z))
	s.hi = Vector3(maxf(s.hi.x, tip.x), maxf(s.hi.y, tip.y), maxf(s.hi.z, tip.z))
	s.travel = s.hi.distance_to(s.lo)
	if active_tick < 0 or active_tick >= active_n:
		return
	## Review r5 item 2: the hit volume may not reach further than the blade the player can see.
	## Both are measured from the same pivot, so the comparison is the whole point of the check.
	var pivot := h.system.strike.pivot()
	s.reach_seen = maxf(s.reach_seen, tip.distance_to(pivot))
	s.reach_want = MeleeTable.field(id, "reach")
	## Where the deleted `place_swing` would have put the tip on this active tick.
	var k := clampf(float(active_tick) / float(maxi(active_n - 1, 1)), 0.0, 1.0)
	var arc := pivot + MeleeTable.blade_dir(id, h.system.strike.facing(), k) * MeleeTable.BLADE_LENGTH
	s.arc_gap = maxf(s.arc_gap, tip.distance_to(arc))


static func _merge(into: Sample, other: Sample) -> void:
	into.ticks += other.ticks
	into.worst_root = maxf(into.worst_root, other.worst_root)
	into.worst_length = maxf(into.worst_length, other.worst_length)
	if into.angle_base < 0.0:
		into.angle_base = other.angle_base
	into.worst_angle = maxf(into.worst_angle, other.worst_angle)
	into.arc_gap = maxf(into.arc_gap, other.arc_gap)
	into.reach_seen = maxf(into.reach_seen, other.reach_seen)
	into.reach_want = maxf(into.reach_want, other.reach_want)
	if into.ticks == other.ticks:
		into.lo = other.lo
		into.hi = other.hi
	else:
		into.lo = into.lo.min(other.lo)
		into.hi = into.hi.max(other.hi)
	into.travel = into.hi.distance_to(into.lo)


static func _report(h: MeleeTestHarness, label: String, s: Sample) -> void:
	h.check("hand.%s_sampled" % label, s.ticks > 4, "%d ticks with the blade drawn" % s.ticks)
	h.near("hand.%s_root_on_the_socket" % label, s.worst_root, 0.0, TOL)
	h.near("hand.%s_tip_one_blade_out" % label, s.worst_length, 0.0, TOL)
	h.near("hand.%s_axis_locked_to_the_socket" % label, s.worst_angle, 0.0, ANGLE_DRIFT_DEG)
	h.check("hand.%s_tip_really_moves" % label, s.travel >= MIN_TRAVEL,
			"tip travelled %.1f m" % s.travel)
	h.check("hand.%s_not_the_arc" % label, s.arc_gap >= ARC_GAP,
			"furthest from the arc-placed tip %.1f m" % s.arc_gap)
	## The drawn blade has to cover the hit volume (review r5 item 2). `REACH_COVER` is the fraction
	## of the table's reach the visible tip must reach; the swept box is BLADE_WIDTH wide, so a small
	## shortfall at the very end of the arc is still inside the volume.
	h.check("hand.%s_visible_reach_covers_the_hitbox" % label,
			s.reach_seen >= s.reach_want * REACH_COVER,
			"tip reaches %.1f m from the pivot, hitbox %.1f m" % [s.reach_seen, s.reach_want])


