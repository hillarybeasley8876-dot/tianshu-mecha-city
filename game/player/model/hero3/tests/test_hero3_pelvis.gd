extends Node
## hero-v3 gate A1 (lead r3): the pelvis curve.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_pelvis.gd
##
## The first accepted walk had a 2.2 m W-shaped bob with 8 local minima in 3.8 steps, because the
## pelvis followed the furthest foot and the two feet are symmetric about the hip during double
## support. This gate measures the shape, not the depth alone: peak-to-peak, and how many times the
## height reverses by more than 2 cm inside a step.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 120.0
## Lead r3 item A1.
const WALK_DIP_GATE := 0.70
const RUN_DIP_GATE := 1.20
const WIGGLE := 0.02      ## reversals smaller than this are noise, not a bounce

var failures: Array[String] = []


func _ready() -> void:
	await _run("walk", &"walk", 9.0, WALK_DIP_GATE)
	await _run("run", &"run", 16.0, RUN_DIP_GATE)
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


func _run(label: String, state: StringName, speed: float, gate: float) -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	var gait: Hero3Gait = model.gait
	model.set_locomotion(state, speed, Vector2(0.0, -1.0))
	gait.reset()
	var heights := PackedFloat64Array()
	for tick in 720:
		model.position += Vector3(0.0, 0.0, -speed * DT)
		gait.update(DT)
		if tick >= 240:
			heights.append(gait.pelvis_height())
	var lo := heights[0]
	var hi := heights[0]
	for h in heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var steps := float(heights.size()) * DT * float(gait.report()["cadence"])
	var counts := _reversals(heights)
	print("PELVIS %s  %.2f..%.2f m  dip %.3f m (gate %.2f)  %.1f steps  %d minima  %d maxima"
			% [label, lo, hi, hi - lo, gate, steps, counts.x, counts.y])
	if hi - lo > gate:
		_fail("%s pelvis dip %.3f m, gate %.2f m" % [label, hi - lo, gate])
	# one trough and one crest per step, to the nearest whole step
	if absf(float(counts.x) - steps) > 1.0 or absf(float(counts.y) - steps) > 1.0:
		_fail("%s pelvis reversed %d times down and %d up in %.1f steps -- a clean gait has one of "
				% [label, counts.x, counts.y, steps] + "each per step")
	model.queue_free()
	await get_tree().process_frame


## Count the direction reversals that are bigger than `WIGGLE`, using a running extreme so a flat
## trough or crest counts once instead of once per sample. Returns (minima, maxima).
func _reversals(values: PackedFloat64Array) -> Vector2i:
	var minima := 0
	var maxima := 0
	var n := values.size()
	var i := 1
	while i < n and absf(values[i] - values[0]) <= WIGGLE:
		i += 1
	if i >= n:
		return Vector2i.ZERO
	var rising := values[i] > values[0]
	var extreme := values[i]
	for j in range(i + 1, n):
		var v := values[j]
		if rising:
			if v > extreme:
				extreme = v
			elif extreme - v > WIGGLE:
				maxima += 1
				rising = false
				extreme = v
		else:
			if v < extreme:
				extreme = v
			elif v - extreme > WIGGLE:
				minima += 1
				rising = true
				extreme = v
	return Vector2i(minima, maxima)


func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL %s" % message)
