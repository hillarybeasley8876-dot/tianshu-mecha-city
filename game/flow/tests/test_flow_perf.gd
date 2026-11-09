extends Node
## Flow's own cost in the REAL city (lead r3: "flow's per-frame cost in the city stays < 1 ms").
## Seven monitoring arena triggers cost ~40 ms a frame before r3 — this is the check that keeps the
## next one from coming back.
##
##   tools/godot.sh test res://flow/tests/test_flow_perf.gd -- \
##       --skip-menu --no-enemies --spawn=-514.5,112,105.1,-66.4 --timeout=300
##
## It boots the real `main.tscn`, waits for the city and for flow's own deferred start, then measures
## three arms of `SAMPLE_S` seconds of WALL time each:
##
##   * flow running,
##   * flow held (`FlowGameFlow.set_frame_work(false)`),
##   * flow running with `perf_busy_ms = BUSY_MS` of deliberate busy-loop in its own physics tick.
##
## The third arm is what makes this a gate. The previous version averaged `Performance.TIME_PROCESS` /
## `TIME_PHYSICS_PROCESS` over 120 frames — those monitors refresh about once a wall second, so both
## arms read the same stale number and the answer was always "flow costs 0.000 ms". Wall time over
## `SAMPLE_S` seconds per arm cannot do that, and the busy arm proves it: if a 2 ms cost inside flow
## does not move the measurement by at least `BUSY_SEEN_MS`, the harness is blind and the run FAILS.
##
## Headless: this measures the CPU flow owns, not the GPU cost of its spires.
##
## The wave machine is disarmed first: at V2 the hero is inside A2, so the encounter director starts a
## real fight, and the monsters it spawns cost the enemies unit 5 ms of physics that has nothing to do
## with flow's own per-frame work. The check is about flow's bodies.

const SAMPLE_S := 2.0          ## s of wall time per arm (the old 120-frame sample was under 1 s)
const SETTLE := 30             ## frames discarded before each sample
const WARM := 600              ## frames of city warm-up before the first sample is believed
const PAIRS := 2               ## A/B pairs: the machine is shared, so the MINIMUM pair is believed
const BUDGET_MS := 1.0         ## flow's own per-frame cost, the lead's ceiling
## The busy-loop arm, and how much of it the measurement has to see for the gate to count as able to
## fail. 2 ms of work must show up as at least 1 ms.
const BUSY_MS := 2.0
const BUSY_SEEN_MS := 1.0

var _flow: Node = null
var _checks: int = 0
var _failed: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if Game.has_flag("sandbox"):
		_fail("run in the city, not the sandbox: --skip-menu --no-enemies --spawn=-514.5,112,105.1,-66.4")
		_finish()
		return
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("cannot load res://main.tscn")
		_finish()
		return
	add_child(packed.instantiate())
	if not await _wait_for_world():
		_fail("the city never finished building")
		_finish()
		return
	# The world reports built before the flow's deferred `_start()` has placed the spires and the
	# zones: sampling now would measure a flow that is not running yet.
	for i in SETTLE:
		await get_tree().physics_frame
	_flow = _find_flow()
	if _flow == null:
		_fail("no FlowGameFlow in the tree")
		_finish()
		return
	_disarm_waves()
	await _measure()
	_finish()


## Stop the encounter director spawning: what it spawns belongs to the enemies unit's budget.
func _disarm_waves() -> void:
	var director := _flow.get(&"director") as Node
	if director == null:
		return
	director.set(&"enabled", false)
	for id in director.call(&"arena_ids") as Array:
		director.call(&"reset_arena", id)
	print("PERF measuring with %d enemies on the field (waves disarmed)"
			% get_tree().get_nodes_in_group(&"enemy").size())


## PAIRS interleaved measurements of the three arms. The number that counts is the cheapest of each: a
## city that has just finished building is still paying one-off costs (broadphase, navmesh sync, first
## material uploads) and this box is shared with the other units' perf runs, so a single A-then-B
## sample books somebody else's spike to flow.
func _measure() -> void:
	for i in WARM:
		await get_tree().physics_frame
	var on := INF
	var off := INF
	var busy := INF
	for i in PAIRS:
		var a := await _sample(0.0)
		var b := await _sample_held()
		var c := await _sample(BUSY_MS)
		print("PERF pair %d: flow %.3f / held %.3f / busy %.3f ms per frame"
				% [i + 1, a, b, c])
		on = minf(on, a)
		off = minf(off, b)
		busy = minf(busy, c)
	var cost := on - off
	print("PERF flow costs %.3f ms per frame (%.3f with, %.3f held); the busy arm reads %.3f ms"
			% [cost, on, off, busy - off])
	_checks += 1
	if cost > BUDGET_MS:
		_fail("flow's per-frame cost is %.3f ms, over the %.1f ms budget" % [cost, BUDGET_MS])
	# The gate has to be able to FAIL. A 2 ms busy-loop inside flow's own tick must move the number.
	_checks += 1
	var seen := busy - off
	if seen < BUSY_SEEN_MS:
		_fail("a %.1f ms busy-loop in flow's tick only moved the measurement by %.3f ms — the gate "
				% [BUSY_MS, seen] + "cannot see flow's cost, so it cannot fail")
	else:
		print("PERF the busy arm moved the measurement by %.3f ms, so the gate can fail" % seen)


## `busy_ms` of deliberate work added to flow's own physics tick, or 0 for the plain arm.
func _sample(busy_ms: float) -> float:
	_flow.set(&"perf_busy_ms", busy_ms)
	return await _wall_per_frame()


func _sample_held() -> float:
	_flow.call(&"set_frame_work", false)
	var out := await _wall_per_frame()
	_flow.call(&"set_frame_work", true)
	return out


func _wait_for_world() -> bool:
	for i in 2400:
		if Game.world_built() and Game.player != null:
			return true
		await get_tree().physics_frame
	return false


## The flow, wherever main put it: the one node in the tree with the frame-work seam.
func _find_flow() -> Node:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_method(&"set_frame_work"):
			return node
		stack.append_array(node.get_children())
	return null


## Mean WALL time per physics frame over `SAMPLE_S` seconds. Under `--fixed-fps` the engine runs the
## loop as fast as the work allows, so this is the frame's real cost — and unlike the `Performance`
## monitors it does not quantise to a wall second.
func _wall_per_frame() -> float:
	for i in SETTLE:
		await get_tree().physics_frame
	var frames := 0
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < int(SAMPLE_S * 1000000.0):
		await get_tree().physics_frame
		frames += 1
	if frames == 0:
		return 0.0
	return float(Time.get_ticks_usec() - start) / float(frames) / 1000.0


func _fail(what: String) -> void:
	_failed += 1
	print("TEST FAIL ", what)


func _finish() -> void:
	print("TEST %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
