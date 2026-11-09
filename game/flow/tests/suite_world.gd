class_name FlowWorldSuite
extends RefCounted
## The r1 review fixes: the encounter tables live inside `res://`, FlowWorld reads the live world's
## markers instead of the Blender source layout, the spire emits the contract signal, the tutorial
## prompts go through the HUD API and the collapse is a cinematic beat that shoves the hero clear.

const ARENAS: Array[StringName] = [&"A1", &"A2", &"A3", &"A4", &"A5", &"A6", &"sandbox"]


static func run(h: FlowTestHarness) -> void:
	_res_only(h)
	_world_markers(h)
	await _spire_contract(h)
	_prompts(h)
	await _collapse_beat(h)
	await _drop_in(h)
	_roam_bounds(h)


# --- 6: the drop-in is armed, not counting from boot (audit #1, #2) -------------------------------

static func _drop_in(h: FlowTestHarness) -> void:
	var rig := FlowFakeRig.new()
	rig.name = "DropRig"
	h.root.add_child(rig)
	var keep_rig := Game.camera_rig
	Game.camera_rig = rig
	var drop := FlowDropIn.new()
	h.root.add_child(drop)
	await h.settle()
	h.ok(not drop.is_physics_processing(),
			"the drop-in timer only runs between begin() and the landing (audit #1)")
	h.eq(rig.shots.size(), 0, "and it starts no cinematic before the drop begins")
	var landed: Array[bool] = []
	drop.finished.connect(func(_at: Vector3, _hard: bool) -> void: landed.append(true))
	drop.begin(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 60.0)))
	h.ok(drop.is_physics_processing(), "begin() arms the fall")
	h.eq(rig.shots.size(), 1, "the drop is a cinematic")
	Events.landed.emit(60.0)
	h.eq(landed.size(), 1, "the landing finishes the sequence once")
	h.eq(rig.ended, 1, "and hands the camera back (audit #2)")
	h.ok(not drop.is_physics_processing(), "the timer stops at the landing")
	# A second run (retry, or a scripted re-drop) must work: begin() re-arms the finished sequence.
	drop.begin(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 60.0)))
	Events.landed.emit(60.0)
	h.eq(landed.size(), 2, "begin() re-arms a finished drop-in")
	drop.queue_free()
	Game.camera_rig = keep_rig
	rig.queue_free()


# --- 7: roaming packs stay on the map (audit #3) --------------------------------------------------

static func _roam_bounds(h: FlowTestHarness) -> void:
	var dir := FlowEncounterDirector.new()
	dir.name = "RoamEncounters"
	var at_spawn: Array[Vector3] = []
	dir.spawn_hook = func(_t: StringName, at: Vector3, count: int) -> Array:
		at_spawn.append(at)
		var made: Array = []
		for i in count:
			var e := FlowFakeEnemy.new()
			h.root.add_child(e)
			made.append(e)
		return made
	h.root.add_child(dir)
	dir.build_sandbox(Vector3.ZERO, 200.0)
	# The player stands in the corner of the map, so every bearing wants to put a pack past the edge.
	h.player.global_position = Vector3(690.0, 5.0, 690.0)
	dir.arm_roam()
	dir.tick(0.1)
	var limit := FlowEncounterDirector.MAP_HALF - FlowEncounterWaves.GROUP_SPREAD \
			- FlowEncounterDirector.SPAWN_MARGIN
	h.ok(not at_spawn.is_empty(), "a roaming pack spawns when its timer is up")
	var inside := true
	for at in at_spawn:
		inside = inside and absf(at.x) <= limit + 0.01 and absf(at.z) <= limit + 0.01
	h.ok(inside, "and it lands inside the city's ground, not past the edge (audit #3)")
	h.player.global_position = Vector3(0.0, 1.0, 60.0)
	dir.queue_free()


# --- 1: nothing outside res:// --------------------------------------------------------------------

static func _res_only(h: FlowTestHarness) -> void:
	h.ok(FlowEncounterWaves.DIR.begins_with("res://"), "the encounter tables are read from res://")
	h.ok(FlowEncounterDirector.ROAM_FILE.begins_with("res://"), "the roaming table is read from res://")
	FlowEncounterWaves.reset_cache()
	var loaded := 0
	for id in ARENAS:
		if not FlowEncounterWaves.waves(id).is_empty():
			loaded += 1
	h.eq(loaded, ARENAS.size(), "every shipped arena table loads from the packaged folder")
	h.ok(FileAccess.file_exists(FlowEncounterDirector.ROAM_FILE), "roam.json ships with the project")


# --- 2: the live world is the map -----------------------------------------------------------------

static func _world_markers(h: FlowTestHarness) -> void:
	var world := Node3D.new()
	world.name = "FakeCity"
	h.root.add_child(world)
	var keep := Game.world
	var sandbox := Game.has_flag("sandbox")
	Game.world = world
	Game.flags.erase(&"sandbox")
	_markers(world)
	var hives := FlowWorld.hives()
	h.eq(hives.size(), 1, "one hive per &\"hive_site\" marker")
	if not hives.is_empty():
		h.eq(hives[0]["id"], &"hive_a", "the site's own id is the spire id")
		h.near(hives[0]["pos"].y, 12.0, "the spire stands where the marker is")
		h.near(hives[0]["height"], 48.0, "the marker carries the spire height")
	var arenas := FlowWorld.arenas()
	h.eq(arenas.size(), 1, "one arena per &\"arena\" Area3D")
	if not arenas.is_empty():
		h.eq(arenas[0]["id"], &"A9", "the arena's own arena_id is its id")
		h.eq((arenas[0]["parts"] as Array).size(), 1, "the arena's convex footprint is reused")
		h.ok(float(arenas[0]["hi"]) > float(arenas[0]["lo"]), "the trigger volume has a vertical span")
	var sockets := arenas[0]["sockets"] as Array[Dictionary] if not arenas.is_empty() else []
	h.eq(sockets.size(), FlowWorld.SOCKETS_PER_ARENA, "an arena without spawn zones gets its sockets")
	h.ok(sockets.size() > 1 and String(sockets[0]["id"]) == "A9_sp1", "sockets are named <arena>_spN")
	world.queue_free()
	Game.world = keep
	if sandbox:
		Game.flags[&"sandbox"] = true


## The markers CONTRACTS §7 promises: a hive site, one arena Area3D with a real convex footprint and
## the insertion point.
static func _markers(world: Node3D) -> void:
	var site := Marker3D.new()
	site.name = "Hive_hive_a"
	site.position = Vector3(100.0, 12.0, -40.0)
	site.set_meta(&"site_id", &"hive_a")
	site.set_meta(&"arena", &"A9")
	site.set_meta(&"height", 48.0)
	site.add_to_group(&"hive_site")
	world.add_child(site)
	var area := Area3D.new()
	area.name = "Arena_A9"
	area.set_meta(&"arena_id", &"A9")
	var hull := ConvexPolygonShape3D.new()
	hull.points = PackedVector3Array([Vector3(-60.0, 0.0, -60.0), Vector3(60.0, 0.0, -60.0),
			Vector3(60.0, 0.0, 60.0), Vector3(-60.0, 0.0, 60.0)])
	var shape := CollisionShape3D.new()
	shape.shape = hull
	shape.position = Vector3.UP * 50.0
	shape.scale = Vector3(1.0, 80.0, 1.0)
	area.add_child(shape)
	area.add_to_group(&"arena")
	world.add_child(area)


# --- 3: the spire contract ------------------------------------------------------------------------

static func _spire_contract(h: FlowTestHarness) -> void:
	var spire := _spire_at(h, Vector3(0.0, 0.0, -600.0))
	if spire == null:
		return
	var seen: Array[Array] = []
	Events.spire_destroyed.connect(func(s: Node3D, down: int, total: int) -> void:
			seen.append([s, down, total]), CONNECT_ONE_SHOT)
	h.burst_all_pods(spire)
	h.hit(spire, &"core", FlowHiveSpire.CORE_HP)
	await h.settle()
	h.eq(seen.size(), 1, "Events.spire_destroyed fires once per spire (CONTRACTS §6)")
	if seen.is_empty():
		spire.queue_free()
		return
	h.eq(seen[0][0], spire, "the signal carries the spire node")
	h.eq(seen[0][2], FlowProgress.SPIRE_TOTAL, "and the objective total")
	var lit := 0
	var visual := spire.get_node(^"Visual") as FlowHiveVisual
	for pod in visual.pods:
		if pod.visible:
			lit += 1
	h.eq(lit, 0, "cracking the shell open does not put the burst pods back on the trunk")
	spire.queue_free()


# --- 4: tutorial prompts through the HUD ----------------------------------------------------------

static func _prompts(h: FlowTestHarness) -> void:
	var hud := FlowFakeHud.new()
	hud.name = "FakeHud"
	h.root.add_child(hud)
	var keep := Game.hud
	Game.hud = hud
	var tutor := FlowTutorialDirector.new()
	h.root.add_child(tutor)
	tutor.begin()
	h.eq(hud.prompted, [&"move"] as Array[StringName], "the first verb is prompted on begin")
	for i in FlowTutorialDirector.PROMPTS.size():
		tutor.advance()
	h.eq(hud.prompted.size(), FlowTutorialDirector.PROMPTS.size(),
			"every verb of brief §4 is taught exactly once")
	h.eq(hud.dismissed.size(), FlowTutorialDirector.PROMPTS.size(),
			"each one is taken down again before the next goes up")
	h.eq(tutor.hint_text(), "", "with the HUD API nothing rides on the objective line")
	tutor.begin()
	h.eq(hud.prompted.size(), FlowTutorialDirector.PROMPTS.size() + 1, "begin() starts over")
	tutor.finish()
	h.ok(hud.dismissed.has(&"move"), "finish() takes the prompt on screen down")
	Game.hud = keep
	tutor.queue_free()
	hud.queue_free()


# --- 5: the collapse beat -------------------------------------------------------------------------

static func _collapse_beat(h: FlowTestHarness) -> void:
	var rig := FlowFakeRig.new()
	rig.name = "FakeRig"
	h.root.add_child(rig)
	var keep_rig := Game.camera_rig
	Game.camera_rig = rig
	# Standing 20 m from the base: inside the blast, so the wreck throws the mech clear.
	h.player.global_position = Vector3(0.0, 1.0, -580.0)
	var spire := _spire_at(h, Vector3(0.0, 0.0, -600.0))
	if spire != null:
		h.burst_all_pods(spire)
		h.hit(spire, &"core", FlowHiveSpire.CORE_HP)
		# The base blast waits for the camera to arrive, so the shove lands a quarter of a second in.
		await h.settle(60)
	h.ok(rig.shots.size() >= 1, "the fall takes the lens (it is a scripted beat, not a free-for-all)")
	if not rig.shots.is_empty():
		h.near(rig.durations[0], FlowHiveCollapse.SHOT_TIME, "control comes back after the beat",
				0.01)
		# r5b item 2: the beat takes the lens with an EMPTY shot list and places the camera itself. The
		# camera unit's own resolve pulls a shot back along a ray from the hero, which cannot reach a
		# stand on the far side of a building — at A2 that is every stand that can see the hive.
		h.ok((rig.shots[0] as Array).is_empty(),
				"and it takes it with an empty shot list, so nothing re-resolves the placement")
		h.near(rig.fov_held, FlowCollapseShot.FOV, "the shot holds its own FOV", 0.01)
		h.near(rig.arm_length, 0.0, "and collapses the spring arm onto the lens", 0.01)
		# The invariants of the PLACEMENT (the old duel-frame offset put the lens 300 m past the deck
		# whenever the rig's hard target was stale, and inside a building whenever the hero's yaw was
		# not 0): the lens stands well back, on the far side of the hero from the hive, looking at the
		# trunk.
		var eye := rig.global_position
		var toward := (spire.global_position - h.player.global_position)
		toward.y = 0.0
		toward = toward.normalized()
		h.ok(eye.distance_to(h.player.global_position) > 40.0,
				"the wide shot stands well back from the hero (%.0f m)"
				% eye.distance_to(h.player.global_position))
		h.ok((eye - h.player.global_position).dot(toward) < -20.0,
				"and it stands on the far side of the hero from the hive (dot %.0f)"
				% (eye - h.player.global_position).dot(toward))
		var at_trunk := spire.global_position + Vector3.UP * spire.height * 0.45 - eye
		h.ok((-rig.global_basis.z).dot(at_trunk.normalized()) > 0.99,
				"while the lens looks straight at the trunk (dot %.3f)"
				% (-rig.global_basis.z).dot(at_trunk.normalized()))
	h.ok(h.player.last_impulse.length() > 1.0, "the blast shoves a hero standing inside it")
	h.ok(h.player.last_impulse.dot(Vector3.UP) > 0.0, "and lifts it clear of the wreck")
	Game.camera_rig = keep_rig
	rig.queue_free()
	if spire != null:
		spire.queue_free()


static func _spire_at(h: FlowTestHarness, at: Vector3) -> FlowHiveSpire:
	var packed := load(FlowProgress.SPIRE_SCENE) as PackedScene
	if not h.ok(packed != null, "hive_spire.tscn loads"):
		return null
	var spire := (packed as PackedScene).instantiate() as FlowHiveSpire
	spire.height = 60.0
	spire.setup(&"contract_hive", &"test")
	spire.position = at
	h.root.add_child(spire)
	h.flow.progress.adopt(spire)
	var pods := spire.get_node(^"Visual").call(&"pod_positions") as Array[Vector3]
	var visual := spire.get_node(^"Visual") as FlowHiveVisual
	var lowest := INF
	var highest := -INF
	for p in pods:
		lowest = minf(lowest, p.y)
		highest = maxf(highest, p.y)
	h.ok(lowest > 8.0, "the pods sit up the trunk, not at the hero's feet (lead r1 #4)")
	# The spread and the hull placement both come from the model's own pod sockets; without the model
	# (monster-assets owns it) the stand-in puts all four on one ring and there is nothing to check.
	if visual.hull_shape() == null:
		h.skip("the pod spread and hull placement — no hive model (enemies/models/hive_model.gd)")
		return spire
	h.ok(highest - lowest > 10.0, "and they are spread over the spire, not bunched at its base")
	var on_the_shell := true
	for i in pods.size():
		on_the_shell = on_the_shell and _sits_on_the_shell(visual, pods[i], visual.pod_normal(i))
	h.ok(on_the_shell, "every pod sits on the trunk's own hull, not in the air beside it "
			+ "(look/flow.md item 1)")
	return spire


## A pod is on the shell when a ray from outside along the trunk's normal finds the VISIBLE mesh within
## a couple of metres of the anchor (`FlowHiveSurface.SINK` is how far inside it sits). The old check
## compared against the 13.2 m guess, which is exactly the number that put the discs in mid-air, and
## the collision hull is no substitute either — it is metres fatter than the skin along most bearings.
static func _sits_on_the_shell(visual: FlowHiveVisual, at: Vector3, normal: Vector3) -> bool:
	var faces := visual.skin_faces()
	if faces.is_empty():
		return Vector2(at.x, at.z).length() >= visual.hull_radius(at.y) - 2.0
	var from := at + normal.normalized() * 12.0
	var nearest := INF
	for i in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, at, faces[i], faces[i + 1],
				faces[i + 2])
		if hit != null:
			nearest = minf(nearest, at.distance_to(hit))
	# No hit at all: the anchor is hanging in the air outside the shell. Too far: it is buried.
	return nearest <= FlowHiveVisual.POD_SINK + 1.5
