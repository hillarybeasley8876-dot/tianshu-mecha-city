extends Node
## feel r5 item 1 — the movie the lead watches. The REAL main.tscn composition (real PlayerMech, real
## camera rig, the FeelDirector main.gd instances) in the sandbox, with the swarm suite's rounds
## 25-55 m ahead of the camera. On screen: the round, the live Engine.time_scale and a 3 s strip
## chart of it, so a world freeze is visible as the trace dropping to the floor.
##
##   tools/godot.sh movie --movie=<abs>/feel_r5_swarm.avi --movie-size=1600x900 \
##     --scene=res://fx/tests/swarm_feel.tscn --timeline=res://fx/tests/swarm_timeline.json \
##     --sandbox --skip-menu --no-enemies --god
##
## Before the fix the gatling string froze the world 8 times in 12 kills; after it, the trace never
## leaves 1.0 and only the victims hold.

const SETTLE := 3.0          ## real seconds for the camera rig to swing in behind the hero
const GATLING_GAP := 0.20
const GATLING_COUNT := 12
const SALVO_COUNT := 6
const SALVO_GAP := 0.30
const MANTIS_GAP := 0.6
const MANTIS_COUNT := 4
const CHART_SECONDS := 3.0
const CHART_SAMPLES := 180

var _chart: StripChart
var _round_label: Label
var _scale_label: Label
var _freezes: int = 0
var _was_frozen: bool = false


## The 3 s strip chart of Engine.time_scale. 1.0 sits on the top rule, 0.0 on the baseline, and the
## 0.9 line is the "the world must not stop" threshold the swarm gate checks.
class StripChart:
	extends Control

	const WIDTH := 520.0
	const HEIGHT := 150.0
	const FLOOR := 0.9
	## The trace needs a margin or a scale of exactly 1.0 draws on the border and vanishes.
	const MARGIN := 10.0

	var samples: PackedFloat32Array = PackedFloat32Array()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, Vector2(WIDTH, HEIGHT))
		draw_rect(r, Color(0.0, 0.0, 0.0, 0.55), true)
		draw_rect(r, Color(0.6, 0.7, 0.8, 0.8), false, 2.0)
		var floor_y := _y(FLOOR)
		draw_line(Vector2(0.0, floor_y), Vector2(WIDTH, floor_y), Color(1.0, 0.45, 0.2, 0.8), 2.0)
		if samples.size() < 2:
			return
		var pts := PackedVector2Array()
		for i in samples.size():
			var x := WIDTH * float(i) / float(samples.size() - 1)
			pts.append(Vector2(x, _y(samples[i])))
		draw_polyline(pts, Color(0.31, 0.9, 1.0), 2.0)

	func _y(scale: float) -> float:
		return MARGIN + (HEIGHT - MARGIN * 2.0) * (1.0 - clampf(scale, 0.0, 1.0))


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	add_child((load("res://main.tscn") as PackedScene).instantiate())
	var waited := 0
	while (not Game.world_built() or Game.player == null or Game.camera_rig == null) and waited < 60000:
		await get_tree().physics_frame
		waited += 1
	await _real_wait(SETTLE)
	_hud()
	var director := get_tree().get_first_node_in_group(&"feel_director") as FeelDirector
	if director == null or Game.player == null:
		push_error("swarm_feel: no FeelDirector or no player in main.tscn")
		get_tree().quit(3)
		return
	var spawner := EnemySpawner.new()
	spawner.auto_spawn = false
	add_child(spawner)
	await _round("A  gatling string: 12 rippers, one per 0.20 s", spawner, &"ripper", GATLING_COUNT,
			GATLING_GAP)
	await _salvo(spawner)
	await _round("C  4 mantis, one per 0.6 s", spawner, &"mantis", MANTIS_COUNT, MANTIS_GAP)
	_round_label.text = "done - %d global stop(s)" % _freezes
	await _real_wait(2.0)
	print("SWARMFEEL freezes=%d" % _freezes)
	get_tree().quit(0)


# --- rounds -------------------------------------------------------------------------------------

## Spawns `count` of `type` 25-55 m ahead of the camera and kills them one every `gap` seconds,
## the way the gatling does (BALLISTIC HitInfo).
func _round(label: String, spawner: EnemySpawner, type: StringName, count: int, gap: float) -> void:
	_round_label.text = label
	var pack := await _pack(spawner, type, count)
	var director := get_tree().get_first_node_in_group(&"feel_director")
	if director != null:
		director.call(&"reset_rate_limits")
	for e in pack:
		var t0 := Feel.real_now()
		_kill(e)
		await _gap(t0, gap)
	await _real_wait(1.2)


## Two salvos of six in a single frame, 0.30 s apart — the case the row cooldown used to swallow.
func _salvo(spawner: EnemySpawner) -> void:
	_round_label.text = "B  salvo: 6 in one frame, twice, 0.30 s apart"
	var pack := await _pack(spawner, &"ripper", SALVO_COUNT * 2)
	var director := get_tree().get_first_node_in_group(&"feel_director")
	if director != null:
		director.call(&"reset_rate_limits")
	for salvo in 2:
		var t0 := Feel.real_now()
		for i in SALVO_COUNT:
			_kill(pack[salvo * SALVO_COUNT + i])
		await _gap(t0, SALVO_GAP)
	await _real_wait(1.2)


func _pack(spawner: EnemySpawner, type: StringName, count: int) -> Array[EnemyBase]:
	var cam := get_viewport().get_camera_3d()
	var player := Game.player as Node3D
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var out: Array[EnemyBase] = []
	for i in count:
		var at: Vector3 = player.global_position + fwd * (25.0 + floorf(float(i) / 4.0) * 15.0) \
				+ right * ((float(i % 4) - 1.5) * 10.0)
		var e := spawner.spawn(type, EnemySpawner.face_towards(at, player.global_position))
		if e != null:
			out.append(e)
	await _real_wait(0.6)
	return out


func _kill(e: EnemyBase) -> void:
	if not is_instance_valid(e) or not e.is_alive():
		return
	var hit := HitInfo.make(e.hp_max * 3.0, HitInfo.BALLISTIC, Game.player, &"swarm_feel")
	hit.hurtbox_part = &"body"
	e.take_hit(hit)


# --- hud ----------------------------------------------------------------------------------------

func _hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SwarmHud"
	layer.layer = 70
	add_child(layer)
	_round_label = _text(layer, Vector2(40.0, 48.0), 32)
	_scale_label = _text(layer, Vector2(40.0, 96.0), 28)
	_chart = StripChart.new()
	_chart.name = "Chart"
	_chart.position = Vector2(40.0, 144.0)
	_chart.custom_minimum_size = Vector2(StripChart.WIDTH, StripChart.HEIGHT)
	_chart.size = Vector2(StripChart.WIDTH, StripChart.HEIGHT)
	layer.add_child(_chart)
	_text(layer, Vector2(40.0, 304.0), 20).text = \
			"orange = 0.9, the swarm floor; a kill_large may still take one global stop per 2 s"


func _text(layer: CanvasLayer, at: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override(&"outline_size", 8)
	layer.add_child(label)
	return label


func _process(_delta: float) -> void:
	if _scale_label == null or _chart == null:
		return
	var s := Engine.time_scale
	_scale_label.text = "time_scale %.2f   global stops %d" % [s, _freezes]
	var frozen := s < 0.1
	if frozen and not _was_frozen:
		_freezes += 1
	_was_frozen = frozen
	_chart.samples.append(s)
	while _chart.samples.size() > CHART_SAMPLES:
		_chart.samples.remove_at(0)
	_chart.queue_redraw()


# --- helpers ------------------------------------------------------------------------------------

func _gap(t0: float, gap: float) -> void:
	await _real_wait(maxf(gap - (Feel.real_now() - t0), 0.0))


func _real_wait(seconds: float) -> void:
	var t0 := Feel.real_now()
	var guard := 0
	while Feel.real_now() - t0 < seconds and guard < 100000:
		await get_tree().process_frame
		guard += 1
