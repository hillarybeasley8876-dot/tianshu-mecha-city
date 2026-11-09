extends Node
## hero-v3 r9 item 1: does the hero's sole sit ON the floor the player sees? (headless, CPU-skinned)
##   tools/godot.sh test res://player/model/hero3/tests/probe_float.gd -- --case=idle
##
## The measure is the LOWEST SKINNED FOOT/TOE VERTEX of each planted foot, in world space, against
## two floors:
##   * RENDER  — `ArtSurfaces`, the same trimesh index the settle pass and the lead's float audit use,
##               so the gate measures the world the game ships and not the blockout colliders;
##   * COLLIDE — the physics ray every other gate uses, against `Layers.WORLD`.
## gap = sole - floor: positive floats, negative is buried.
##
## `--case=` picks one scenario (default: all). `--world=sandbox|city`. The report is one row per
## case, printed as `FLOATROW <json>` so the status table is copied, never retyped.

const SANDBOX := preload("res://core/sandbox/sandbox.tscn")
const PLAYER := preload("res://player/player_mech.tscn")
const CITY := "res://world/city.tscn"
## How far above the sole the floor ray starts. Far enough that a foot sunk into a kerb still finds
## the surface over it, short enough that a roof 12 m up is never mistaken for the floor.
const RAY_UP := 1.5
const RAY_DOWN := 200.0
const VSTRIDE := 2
## The gate: a planted foot within this of the RENDERED floor, in this share of planted frames.
const GATE_NEAR := 0.10
const GATE_SHARE := 0.95
const GATE_MAX_ABOVE := 0.25
## A foot whose sole overhangs a step edge is not floating and not buried: the ray under its lowest
## vertex finds the surface BELOW the edge while the boot is standing on the surface ABOVE it. A
## planted frame is judged only when the rendered floor under the sole is level to within this over a
## EDGE_SPAN patch; the rest are counted in the row's `edge` column and reported, never hidden.
const EDGE_LEVEL := 0.25
const EDGE_SPAN := 0.8

var player: PlayerMech
var loco: MechLocomotion
var model: Node3D
var skeleton: Skeleton3D
var gait: Hero3Gait
var sole: Hero3SoleProbe
var surfaces: Hero3Surfaces = null
var world: Node3D
var _rows: Array[Dictionary] = []
var _case: String = "all"
var _world_kind: String = "sandbox"
var _query: PhysicsRayQueryParameters3D
var _debug: bool = false
## `--nofix` reproduces the shipping build in the same binary: the model node goes back on the body
## origin and the sole trim is zeroed. That is the BEFORE column of the status table.
var _nofix: bool = false
var _debug_n: int = 0

## Every scenario the brief names. `hold` is a list of `[action, strength]` pressed for the whole
## window; `turn` spins the body in place at that rate (deg/s); `drop` teleports the mech that high
## first, so the landing it measures is the one the player would have got.
##   id            at (x, z)             yaw   hold                                turn  drop  warm  ticks
const CASES: Array = [
	["idle_flat", Vector2(0.0, 60.0), 0.0, [], 0.0, 0.0, 60, 240],
	["walk_flat", Vector2(0.0, 60.0), 0.0, [["move_forward", 0.5]], 0.0, 0.0, 180, 360],
	["run_flat", Vector2(0.0, 60.0), 0.0, [["move_forward", 1.0]], 0.0, 0.0, 180, 360],
	["strafe_flat", Vector2(0.0, 60.0), 0.0, [["aim", 1.0], ["move_right", 0.6]], 0.0, 0.0, 180, 360],
	["turn_flat", Vector2(0.0, 60.0), 0.0, [], 55.0, 0.0, 120, 300],
	["slide_flat", Vector2(0.0, 60.0), 0.0, [["move_forward", 1.0], ["boost", 1.0]], 0.0, 0.0, 200, 260],
	["hop_flat", Vector2(0.0, 60.0), 0.0, [], 0.0, 0.0, 40, 240],
	["heavy_flat", Vector2(0.0, 60.0), 0.0, [], 0.0, 90.0, 20, 320],
	["walk_ramp", Vector2(-220.0, 70.0), 180.0, [["move_forward", 0.5]], 0.0, 0.0, 200, 420],
	["walk_kerb", Vector2(-120.0, 30.0), 0.0, [["move_forward", 0.5]], 0.0, 0.0, 180, 420],
	["idle_kerb", Vector2(-120.0, 0.0), 0.0, [], 0.0, 0.0, 90, 240],
]

## A 2 m kerb, the stepping edge SPEC §4 is written against, on the flat ground west of the cover
## field — the same range `mech_test_base.gd` builds (the core sandbox is lead-owned, so the probe
## brings its own obstacle rather than editing it).
const KERB: Array = [Vector3(-120.0, 1.0, 0.0), Vector3(40.0, 2.0, 12.0)]


func _ready() -> void:
	_case = _arg("--case=", "all")
	_debug = not _arg("--debug=", "").is_empty()
	_nofix = not _arg("--nofix=", "").is_empty()
	_world_kind = _arg("--world=", "sandbox")
	world = await _build_world()
	surfaces = _build_surfaces()
	player = PLAYER.instantiate() as PlayerMech
	add_child(player)
	loco = player.get_node("Locomotion") as MechLocomotion
	model = player.get_node("Model") as Node3D
	skeleton = model.get_node("Model/Hero3Rig/Skeleton3D") as Skeleton3D
	gait = model.get_node("Hero3Gait") as Hero3Gait
	if _nofix:
		# the shipping build, in the same binary: the model node back on the body origin, no measured
		# sole trim, no roll profile and no per-foot ground ray. `--hero3-mirror` adds the stick's sign.
		model.position.y = 0.0
		gait.sole.trim = [0.0, 0.0]
		gait.sole.roll_trim = []
		gait.sole.ground = null
		Hero3Pelvis.drop_bias = 0.07
	_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN)
	_query.collision_mask = Layers.WORLD
	_query.collide_with_areas = false
	await _step(30)
	sole = Hero3SoleProbe.new()
	sole.setup(skeleton)
	if _debug:
		print("FLOATDBG probe (0,5,60) at setup -> %s" % str(surfaces.top_below(Vector3(0.0, 5.0, 60.0))))
		await _step(60)
		print("FLOATDBG probe (0,5,60) after 60 -> %s" % str(surfaces.top_below(Vector3(0.0, 5.0, 60.0))))
	print("FLOAT setup: world=%s %s surfaces=%d foot verts=%d body origin y=%.3f sole trim %s"
			% [_world_kind, "BEFORE (--nofix)" if _nofix else "AFTER", 
			surfaces.size() if surfaces != null else 0, sole.verts.size(),
			player.global_position.y, gait.report()["trim"]])
	for case: Array in CASES:
		if _case != "all" and String(case[0]) != _case:
			continue
		await _run_case(case)
	_report()


## The world the case runs in. The sandbox is the movement unit's own range; the city is what the
## player actually stands on, and its surfaces come from the kit index rather than a node walk.
func _build_world() -> Node3D:
	var packed: PackedScene = SANDBOX
	if _world_kind == "city" and ResourceLoader.exists(CITY):
		packed = load(CITY) as PackedScene
		_world_kind = "city"
	else:
		_world_kind = "sandbox"
	var w := packed.instantiate() as Node3D
	add_child(w)
	(get_node(^"/root/Game") as Node).set(&"world", w)
	if _world_kind == "sandbox":
		var body := StaticBody3D.new()
		body.name = "ProbeKerb"
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.position = KERB[0] as Vector3
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = KERB[1] as Vector3
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = KERB[1] as Vector3
		mesh.mesh = bm
		body.add_child(mesh)
		w.add_child(body)
	await _step(20)
	return w


## The RENDERED floor index. In the city that is `ArtSurfaces.build`, which is the settle pass's own
## view (kit detail meshes + tile render meshes); in the sandbox every visible MeshInstance3D is a
## support, because the arena IS its grey boxes.
func _build_surfaces() -> Hero3Surfaces:
	var s := Hero3Surfaces.new()
	if not s.setup(world.get_world_3d()):
		return null
	if _world_kind == "city":
		var tiles := world.get_node_or_null(^"Tiles")
		if tiles != null:
			s.add_tree(tiles)
		var kit := world.get_node_or_null(^"KitPlacer")
		if kit != null and kit.has_method(&"near_batches"):
			for batch: Dictionary in kit.call(&"near_batches"):
				if String(batch["tier"]) != "detail":
					continue
				var list: Array = batch["list"]
				for i in list.size():
					s.add(batch["mesh"] as Mesh, list[i] as Transform3D, Hero3Surfaces.ROOF)
		return s
	s.add_tree(world)
	return s


func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return fallback


func _step(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## One scenario: reset the mech onto its spot, hold the inputs, and sample every tick.
func _run_case(case: Array) -> void:
	var id := String(case[0])
	var at: Vector2 = case[1]
	var yaw := float(case[2])
	var hold: Array = case[3]
	var turn := float(case[4])
	var drop := float(case[5])
	var warm := int(case[6])
	var ticks := int(case[7])
	await _reset(Vector3(at.x, 8.0 + drop, at.y), yaw)
	if id.begins_with("hop"):
		await _hop()
	for row: Array in hold:
		Input.action_press(StringName(row[0]), float(row[1]))
	var stat := _new_stat()
	var airborne := -1
	var since_land := -1
	for tick in ticks:
		if turn != 0.0:
			player.rotation.y += deg_to_rad(turn) / 120.0
		await get_tree().physics_frame
		if id.ends_with("heavy") or id.begins_with("hop"):
			# a landing case measures ONE landing: the ticks from the touchdown through the settle,
			# not the walk-away afterwards
			if player.is_on_floor():
				if airborne > 0 and since_land < 0:
					since_land = 0
				airborne = 0
			else:
				airborne = 1
			if since_land >= 0:
				since_land += 1
				if since_land > 90:
					break
		if tick < warm and since_land < 0 and not _debug:
			continue
		if _debug:
			_trace_tick()
		_sample(stat)
	for row: Array in hold:
		Input.action_release(StringName(row[0]))
	stat["id"] = id
	stat["state"] = String(player.move_state())
	stat["speed"] = snappedf(loco.flat_speed(), 0.1)
	_rows.append(stat)


## A hop: the smallest jump the game has, so the landing it measures is a `land_light`.
func _hop() -> void:
	Input.action_press(&"jump")
	await _step(3)
	Input.action_release(&"jump")
	await _step(6)


## One line per tick: where each leg is in its own period, and how far its plant is from its hip.
func _trace_tick() -> void:
	var parts: Array[String] = []
	for i in gait.step.legs.size():
		var leg: Dictionary = gait.step.legs[i]
		var u := Hero3Timing.leg_phase(gait.step.phase, i)
		var hip := gait.frame.hip_ground(leg)
		var back := (leg["planted"] as Vector3).z - hip.z
		parts.append("%s u %.2f used %d step %d t %.2f plantZ %+.1f hipZ %+.1f"
				% [leg["spec"]["side"], u, int(leg["used"]), int(leg["stepping"]),
				float(leg["t"]), back, 0.0])
	print("TRACETICK phase %.3f swing %.2f drop %.2f | %s"
			% [gait.step.phase, gait.timing.swing(), float(gait.report()["drop"]),
			" | ".join(parts)])


func _new_stat() -> Dictionary:
	return {"id": "", "state": "", "speed": 0.0, "n": 0, "near_r": 0, "near_c": 0,
			"worst_above_r": -INF, "worst_above_c": -INF, "worst_below_r": INF, "worst_below_c": INF,
			"miss_r": 0, "miss_c": 0, "side_r": [INF, -INF], "side_l": [INF, -INF], "gaps": [],
			"edge": 0}


## One tick: the sole of each PLANTED foot against both floors. A foot in the air is not measured --
## the gate is about the foot that is supposed to be holding the mech up.
func _sample(stat: Dictionary) -> void:
	# a frame in the air has no planted foot to measure: the mech is between surfaces, and the ray
	# under it finds the floor it is about to leave or land on
	if not player.is_on_floor():
		return
	var stepping := String(gait.report()["stepping"])
	var feet := sole.sample()
	for i in 2:
		var side := "L" if i == 0 else "R"   # Hero3SoleProbe.sample(): index 0 is the LEFT foot
		if stepping.contains(side):
			continue
		var y := float(feet[i]["y"])
		if is_inf(y):
			continue
		var at: Vector3 = feet[i]["at"]
		if _on_edge(at, y):
			stat["edge"] = int(stat["edge"]) + 1
			continue
		stat["n"] = int(stat["n"]) + 1
		var gap := y - _render_floor(at, y)
		if _debug and _debug_n < 400:
			_debug_n += 1
			# `Hero3SoleProbe` is indexed by MESH SIDE (0 = left); `Hero3Stepper.LEGS` is ordered R, L
			var li := 1 if side == "L" else 0
			var tgt := gait.ankle_targets()[li]
			var leg: Dictionary = gait.step.legs[li]
			var hip := skeleton.global_transform * skeleton.get_bone_global_pose(int(leg["thigh"])).origin
			var ankle := skeleton.global_transform * skeleton.get_bone_global_pose(int(leg["foot"])).origin
			print("FLOATDBG %s sole %.3f gap %+.3f roll %+.1f | target %s ankle %s hip %s plant %s | %s"
					% [side, y, gap, rad_to_deg(gait.sole.rolls()[i]), str(tgt.snapped(Vector3.ONE*0.01)),
					str(ankle.snapped(Vector3.ONE*0.01)), str(hip.snapped(Vector3.ONE*0.01)),
					str((leg["planted"] as Vector3).snapped(Vector3.ONE*0.01)), str(gait.report())])
		_accumulate(stat, "r", gap)
		_accumulate(stat, "c", y - _collide_floor(at, y))
		var key := "side_l" if side == "L" else "side_r"
		var span: Array = stat[key]
		stat[key] = [minf(float(span[0]), gap), maxf(float(span[1]), gap)]
		var gaps: Array = stat["gaps"]
		gaps.append(gap)


## Is the rendered floor under this sole a step edge? Four probes around the sole, `EDGE_SPAN` out.
func _on_edge(at: Vector3, sole_y: float) -> bool:
	if surfaces == null:
		return false
	var here := _render_floor(at, sole_y)
	if is_nan(here):
		return false
	for d: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var there := _render_floor(at + d * EDGE_SPAN, sole_y)
		if is_nan(there) or absf(there - here) > EDGE_LEVEL:
			return true
	return false


func _accumulate(stat: Dictionary, key: String, gap: float) -> void:
	if is_nan(gap):
		return
	stat["miss_" + key] = int(stat["miss_" + key]) + (0 if is_finite(gap) else 1)
	if not is_finite(gap):
		return
	if absf(gap) <= GATE_NEAR:
		stat["near_" + key] = int(stat["near_" + key]) + 1
	stat["worst_above_" + key] = maxf(float(stat["worst_above_" + key]), gap)
	stat["worst_below_" + key] = minf(float(stat["worst_below_" + key]), gap)


## The rendered surface under a sole: `ArtSurfaces`, the settle pass's own index. Returns the floor
## height, or NAN when the ray found nothing (which the row counts as a miss).
func _render_floor(at: Vector3, sole_y: float) -> float:
	if surfaces == null:
		return NAN
	var hit := surfaces.top_below(Vector3(at.x, sole_y + RAY_UP, at.z))
	if _debug and _debug_n < 6:
		_debug_n += 1
		print("FLOATDBG render at %s -> %s" % [Vector3(at.x, sole_y + RAY_UP, at.z), str(hit)])
	return float(hit["y"]) if not hit.is_empty() else NAN


## The collision floor under a sole: the same physics ray every other gate uses.
func _collide_floor(at: Vector3, sole_y: float) -> float:
	_query.from = Vector3(at.x, sole_y + RAY_UP, at.z)
	_query.to = _query.from + Vector3.DOWN * RAY_DOWN
	var hit := world.get_world_3d().direct_space_state.intersect_ray(_query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else NAN


## Put the mech on its mark with nothing held, and let it settle on the floor before the case runs.
func _reset(at: Vector3, yaw: float) -> void:
	for row: Array in CASES:
		for held: Array in row[3]:
			Input.action_release(StringName(held[0]))
	loco.debug_reset()
	player.heal(player.hp_max)
	player.debug_teleport([at.x, at.y, at.z], yaw)
	var guard := 0
	while guard < 600:
		await get_tree().physics_frame
		guard += 1
		if player.is_on_floor() and not String(player.move_state()).begins_with("land"):
			break
	await _step(2)


## One row per case, and the verdict. `near` is the share of planted-foot frames within GATE_NEAR of
## that floor; `above` is the worst float, `below` the worst burial.
func _pct(sorted_gaps: Array, q: float) -> float:
	if sorted_gaps.is_empty():
		return NAN
	return float(sorted_gaps[clampi(int(q * sorted_gaps.size()), 0, sorted_gaps.size() - 1)])


func _report() -> void:
	print("FLOAT %-11s %-10s %5s | %-28s | %-28s" % ["case", "state", "m/s", "RENDERED floor",
			"COLLISION floor"])
	var bad := 0
	for row: Dictionary in _rows:
		var n := maxi(int(row["n"]), 1)
		var line := "FLOAT %-11s %-10s %5.1f |" % [row["id"], row["state"], float(row["speed"])]
		for key in ["r", "c"]:
			var near := float(row["near_" + key]) / n
			var above := float(row["worst_above_" + key])
			var below := float(row["worst_below_" + key])
			line += " near %3.0f%%  above %+6.2f  below %+6.2f |" % [near * 100.0, above, below]
			if key == "r" and (near < GATE_SHARE or above > GATE_MAX_ABOVE):
				bad += 1
		var gaps: Array = row["gaps"]
		gaps.sort()
		line += " p50 %+6.2f p90 %+6.2f edge %d" % [_pct(gaps, 0.5), _pct(gaps, 0.9), int(row["edge"])]
		print(line)
		var copy := row.duplicate()
		copy.erase("gaps")
		print("FLOATROW %s" % JSON.stringify(copy))
	print("FLOAT %s: %d case(s) outside the rendered-floor gate" % ["FAIL" if bad > 0 else "PASS", bad])
	get_tree().quit(0)
