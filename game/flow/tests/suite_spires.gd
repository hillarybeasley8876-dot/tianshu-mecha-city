class_name FlowSpireSuite
extends RefCounted
## Hive Spire: pods → core → destroyed, the body absorbing everything, and the objective contract the
## HUD reads (group `&"hive_spire"`, hurtboxes, `hud_state`).


static func run(h: FlowTestHarness) -> void:
	var spire := _fresh(h)
	if spire == null:
		return
	# The reachability probe is a physics query, so the Hurtbox areas have to be registered first.
	await h.settle(2)
	_pod_look(h, spire)
	_pod_sockets(h, spire)
	_core_look(h, spire)
	_pods(h, spire)
	_core(h, spire)
	_destroyed(h, spire)


## look/flow.md item 1: the pods are sac clusters on the trunk's own hull, not four flat spheres
## floating at a guessed radius, and the spire collides with that same hull.
static func _pod_look(h: FlowTestHarness, spire: FlowHiveSpire) -> void:
	var visual := spire.get_node(^"Visual") as FlowHiveVisual
	h.ok(visual != null, "the spire carries its visual")
	if visual == null:
		return
	h.eq(visual.pods.size(), FlowHiveSpire.PODS, "one mesh per pod")
	var merged := true
	var smooth := true
	var shaped_geo := true
	for pod in visual.pods:
		var mesh := pod.mesh as ArrayMesh
		merged = merged and mesh != null and mesh.get_surface_count() == 1
		# A 12x6 sphere — the disc the user called a gizmo — commits 168 faces. A 32x16 one commits
		# ~1,088, so three sacs is ~3,264; the bound is loose enough to survive an engine change and
		# still an order of magnitude above the old geometry.
		smooth = smooth and mesh != null \
				and mesh.get_faces().size() / 3 >= FlowHivePods.SACS_MIN \
						* FlowHivePods.SAC_SEGMENTS * FlowHivePods.SAC_RINGS
		# The membrane shader reads NORMAL and UV: a cluster committed without them would be a
		# black silhouette, not a lit sac.
		shaped_geo = shaped_geo and mesh != null \
				and mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] != null \
				and mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] != null
	h.ok(merged, "every sac of a cluster is merged into one surface (one draw call per pod)")
	h.ok(smooth, "the sacs are at least %dx%d, not a faceted 12-sided disc"
			% [FlowHivePods.SAC_SEGMENTS, FlowHivePods.SAC_RINGS])
	h.ok(shaped_geo, "the merged cluster keeps the normals and UVs the membrane shader reads")
	var shaped := true
	for pod in visual.pods:
		var mat := pod.material_override as ShaderMaterial
		shaped = shaped and mat != null and mat.shader == FlowHivePods.SHADER \
				and float(mat.get_shader_parameter(&"core_energy")) <= 1.5
	h.ok(shaped, "the pods use the fresnel membrane shader at 1.5 emission or less")
	_trunk_collision(h, spire, visual)
	_pods_are_the_first_hit(h, spire, visual)
	_trunk_shows_nothing(h, spire)

	# The point of look/flow.md item 1: a pod must touch something the player can SEE. The solve runs
	# against the 164-face collision hull; this measures the gap to the 60,000-face visible mesh, which
	# is the thing that decides whether a sac reads as growing out of the trunk or floating beside it.
	var skin := visual.skin_faces()
	if skin.is_empty():
		h.skip("the pod-to-skin gap — no visible hive mesh")
		return
	var worst := 0.0
	var gaps: Array[float] = []
	for i in FlowHiveSpire.PODS:
		var gap := _gap_to_skin(skin, visual.pod_positions()[i], visual.pod_normal(i))
		gaps.append(gap)
		worst = maxf(worst, gap)
	# 5 m, not 1: the anchor is `POD_SINK` inside the shell along the horizontal ray that solved it,
	# but the face normal leans, so the same point is further from the surface measured along the
	# normal. A pod hanging in the air has no face at all within 12 m (INF), and one solved against
	# the fat collision hull instead of the skin measured 11 m — both are far outside this.
	h.ok(worst <= 5.0, "every pod is within 5 m of the visible mesh (gaps %s), not hanging in the air"
			% str(gaps))


## Distance from the pod anchor out along its normal to the first face of the visible mesh. The anchor
## sits `POD_SINK` inside the hull, so a well-placed pod answers with a small positive number. The ray
## runs OUTSIDE-IN like the solve does: the GLB's two shells are wound the other way round from each
## other, and a ray leaving the trunk finds nothing on the visible mesh.
static func _gap_to_skin(skin: PackedVector3Array, at: Vector3, normal: Vector3) -> float:
	var from := at + normal.normalized() * 12.0
	for i in range(0, skin.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, at, skin[i], skin[i + 1],
				skin[i + 2])
		if hit != null:
			return at.distance_to(hit)
	return INF


## flow-look-r1 polish 2: monster-assets moved the pod sockets (pod_0 10.3 → 18.8 m, pod_1 24.0 →
## 27.8 m). Nothing in flow may assume the old heights, so this pins the CONTRACT — every pod sits at
## the height of the model's own `pod_*` socket — instead of pinning any number. Move a socket and the
## suite still passes; stop reading the sockets and it fails.
## r5 brief item 7: the trunk's shot collision follows the SKIN. monster-assets' `HiveCollision` is a
## convex hull that stands 4-17 m outside the visible mesh along the pod bearings, which put three of
## every hive's four pods and the core behind invisible air. The shape is now flow's own decimated
## trimesh of the mesh the player sees, on its own body.
static func _trunk_collision(h: FlowTestHarness, spire: FlowHiveSpire, visual: FlowHiveVisual) -> void:
	var trunk := spire.get_node_or_null(^"Trunk") as StaticBody3D
	h.ok(trunk != null, "the trunk has its own body, separate from the spire node")
	if trunk == null:
		return
	h.eq(trunk.collision_layer, Layers.WORLD, "and it is on WORLD, so it blocks shots and bodies")
	h.ok(not trunk.has_method(&"take_hit"),
			"but it is not a shot receiver, so a hit on the bare shell shows nothing")
	var shaped := false
	for child in trunk.get_children():
		var box := child as CollisionShape3D
		shaped = shaped or (box != null and box.shape is ConcavePolygonShape3D)
	h.ok(shaped, "the trunk collides with a trimesh, not a guessed cylinder")
	# Duck-typed: this suite has to COMPILE against the pre-r5 visual, which has neither method, so
	# the run reports a readable failure instead of a parse error.
	if not visual.has_method(&"skin_shape") or not visual.has_method(&"skin_face_count"):
		h.ok(false, "FlowHiveVisual has no skin_shape / skin_face_count for the trunk collision")
		return
	if visual.call(&"skin_shape") == null:
		# monster-assets owns hive_model.gd; when it does not compile there is no visible mesh and the
		# spire falls back to the hull. Say so instead of failing flow's suite.
		h.skip("the skin-following trunk collision - no visible hive mesh")
		return
	var faces := int(visual.call(&"skin_face_count"))
	print("HIVECOLL trunk shot collision: %d triangles (the skin is %d)"
			% [faces, visual.skin_faces().size() / 3])
	h.ok(faces > 200, "the trunk's collision is the decimated skin (%d triangles)" % faces)
	h.ok(faces < 20000, "and it is decimated enough to ship on three spires (%d triangles)" % faces)


## The gate the finding asks for, and the one the old suite could not see: from the OPEN side of the
## hive, the pod's own Hurtbox must be the FIRST collider a shot meets. `MASK_PLAYER_ATTACK`, areas
## and bodies, nothing excluded - the old probe masked ENEMY_HURTBOX only and excluded the spire's
## own RID, so it could never see the hull that was burying them.
static func _pods_are_the_first_hit(h: FlowTestHarness, spire: FlowHiveSpire,
		visual: FlowHiveVisual) -> void:
	var space := spire.get_world_3d().direct_space_state
	var first := 0
	for i in FlowHiveSpire.PODS:
		var pod_node := spire.get_node_or_null(NodePath("Pod%d" % i)) as Node3D
		if pod_node == null:
			continue
		var n := visual.pod_normal(i)
		var at := spire.to_global(pod_node.position)
		var query := PhysicsRayQueryParameters3D.create(at + n * 60.0, at - n * 2.0,
				Layers.MASK_PLAYER_ATTACK)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and (hit["collider"] as Node).get_parent() == pod_node:
			first += 1
	h.eq(first, FlowHiveSpire.PODS,
			"every pod's Hurtbox is the FIRST collider a one-hit shot meets from the open side")


## A shot that stops on the bare trunk must show nothing: `ShotQuery.deliver` emits `hit_landed` and a
## hit marker for any collider that answers `take_hit`, even one that returns `final_amount` 0.
static func _trunk_shows_nothing(h: FlowTestHarness, spire: FlowHiveSpire) -> void:
	var trunk := spire.get_node_or_null(^"Trunk") as StaticBody3D
	h.ok(trunk != null and not trunk.has_method(&"take_hit"),
			"a hit on the bare trunk is scenery: no receiver, so no marker and no number")
	h.ok(spire.get(&"collision_layer") == 0,
			"and the spire node itself carries no collision that a shot could reach")


static func _pod_sockets(h: FlowTestHarness, spire: FlowHiveSpire) -> void:
	var visual := spire.get_node(^"Visual") as FlowHiveVisual
	var model := visual.get_node_or_null(^"Model") as Node3D
	if model == null or not model.has_method(&"weak_points"):
		h.skip("the pods follow the model's sockets — no model")
		return
	var heights: Array[float] = []
	for node: Variant in model.call(&"weak_points"):
		var marker := node as Node3D
		if marker != null and String(marker.name).begins_with("pod_"):
			heights.append(visual.to_local(marker.global_position).y)
	if heights.size() != FlowHiveSpire.PODS:
		h.skip("the pods follow the model's sockets — the rig lists %d pod markers" % heights.size())
		return
	heights.sort()
	var got: Array[float] = []
	for at: Vector3 in visual.pod_positions():
		got.append(at.y)
	got.sort()
	var worst := 0.0
	for i in heights.size():
		worst = maxf(worst, absf(heights[i] - got[i]))
	# The solve walks a horizontal ray in along the socket's bearing, so the pod keeps the socket's
	# height exactly; anything else means flow fell back to its own ring.
	h.ok(worst <= 0.01, "every pod sits at its own socket's height (sockets %s, pods %s)"
			% [str(heights), str(got)])
	# The heights the review quotes must be the model's, not flow's: four distinct sockets spread over
	# the trunk, not four pods on one ring.
	var spread := heights[heights.size() - 1] - heights[0]
	h.ok(spread > spire.height * 0.3, "the pods are spread over %.0f m of trunk, not on one ring"
			% spread)


## flow-look-r1 polish 1: the exposed core is a ruptured boil, not a flat violet ellipse — a torn
## collar, a dished cavity, merged sacs sunk into it, a 1.2 Hz heartbeat and a small unshadowed lamp.
static func _core_look(h: FlowTestHarness, spire: FlowHiveSpire) -> void:
	var visual := spire.get_node(^"Visual") as FlowHiveVisual
	var core := visual.core
	h.ok(core != null, "the spire carries a core")
	if core == null:
		return
	h.ok(not core.visible, "the core is shut while the shell is intact")
	var parts: Array[Node] = []
	var lamp: OmniLight3D = null
	for child in core.get_children():
		parts.append(child)
		var light := child as OmniLight3D
		if light != null:
			lamp = light
	h.eq(parts.size(), 4, "the core is a collar, a cavity, the sacs and a lamp — not one ellipse")
	var sacs := core.get_node_or_null(^"Sacs") as MeshInstance3D
	h.ok(sacs != null, "the core carries a sac cluster")
	if sacs != null:
		var mesh := sacs.mesh as ArrayMesh
		h.ok(mesh != null and mesh.get_surface_count() == 1,
				"every sac of the core is merged into one surface")
		h.ok(mesh != null and mesh.get_faces().size() / 3 >= FlowHivePods.SACS_MIN \
						* FlowHivePods.SAC_SEGMENTS * FlowHivePods.SAC_RINGS,
				"the core's sacs are smooth, not a faceted disc")
		var mat := sacs.material_override as ShaderMaterial
		var beating := mat != null \
				and is_equal_approx(float(mat.get_shader_parameter(&"pulse_lo")), FlowHiveCore.PULSE_LO) \
				and is_equal_approx(float(mat.get_shader_parameter(&"pulse_hi")), FlowHiveCore.PULSE_HI) \
				and is_equal_approx(float(mat.get_shader_parameter(&"pulse_hz")), FlowHiveCore.PULSE_HZ)
		h.ok(beating, "the core breathes %.1f → %.1f at %.1f Hz (review polish 1)"
				% [FlowHiveCore.PULSE_LO, FlowHiveCore.PULSE_HI, FlowHiveCore.PULSE_HZ])
		# The review's ceiling is 1.5 emission. `core_energy` scales the pulse band, so the PEAK is what
		# has to stay under it, not the base.
		var peak := float(mat.get_shader_parameter(&"core_energy")) * FlowHiveCore.PULSE_HI
		h.ok(peak <= 1.5, "the core's peak emission is %.2f, under the 1.5 ceiling" % peak)
		h.ok(sacs.position.y > 0.0 and sacs.position.y < core.radius,
				"the sacs sit inside the wound (%.1f m up a %.1f m opening), not on top of it"
				% [sacs.position.y, core.radius])
	h.ok(lamp != null, "the core carries a lamp")
	if lamp != null:
		h.ok(not lamp.shadow_enabled, "the core's lamp casts no shadow (engine rules)")
		h.ok(lamp.omni_range <= core.radius * 4.0, "the core's lamp is small (%.0f m range)"
				% lamp.omni_range)
		h.ok(lamp.light_color.is_equal_approx(FlowHiveVisual.CORE_COLOR),
				"the core's lamp is the core's violet")
	# Every piece of the wound has to sit in FRONT of the trunk: the shell is opaque, so anything behind
	# it is invisible and the core reads as a sticker again. The sacs are exempt — they are meant to be
	# sunk into the shell, that is what makes them look like they are growing out of it.
	var buried := 0
	var worst := 0.0
	for part_name in ["Collar", "Cavity"]:
		var mi := core.get_node_or_null(NodePath(part_name)) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for v: Vector3 in mi.mesh.get_faces():
			var clear := core.clearance(v)
			worst = minf(worst, clear)
			if clear < -0.01:
				buried += 1
	h.eq(buried, 0, "the torn collar and the cavity all sit in front of the trunk (worst %.2f m)"
			% worst)


## A spire of its own, so the state suite's flow-owned spires are untouched.
static func _fresh(h: FlowTestHarness) -> FlowHiveSpire:
	var packed := load(FlowProgress.SPIRE_SCENE) as PackedScene
	if not h.ok(packed != null, "hive_spire.tscn loads"):
		return null
	var spire := (packed as PackedScene).instantiate() as FlowHiveSpire
	if not h.ok(spire != null, "hive_spire.tscn root is a FlowHiveSpire"):
		return null
	spire.height = 60.0
	spire.setup(&"test_hive", &"test")
	spire.position = Vector3(0.0, 0.0, -300.0)
	h.root.add_child(spire)
	h.ok(spire.is_in_group(&"hive_spire"), "a live spire joins the &\"hive_spire\" group")
	h.eq(spire.get_team(), 1, "spires are on the monster team")
	h.eq(spire.total_hp(), FlowHiveSpire.PODS * FlowHiveSpire.POD_HP + FlowHiveSpire.CORE_HP,
			"a whole spire is 4x3,500 + 6,000 = 20,000 HP (SPEC §7.1)")
	var state := spire.hud_state()
	h.ok(state.has("hp") and state.has("hp_max") and state.has("pods_left"),
			"hud_state carries hp / hp_max / pods_left")
	h.eq(int(state["pods_left"]), FlowHiveSpire.PODS, "four pods to start")
	return spire


static func _pods(h: FlowTestHarness, spire: FlowHiveSpire) -> void:
	var burst: Array[int] = []
	spire.pod_burst.connect(func(_i: int, left: int) -> void: burst.append(left))
	var core_open: Array[bool] = []
	spire.core_exposed.connect(func() -> void: core_open.append(true))
	# The core is sealed while any pod stands.
	h.eq(h.hit(spire, &"core", 5000.0).final_amount, 0.0, "the core is sealed until the pods burst")
	h.eq(h.hit(spire, &"body", 5000.0).final_amount, 0.0, "the trunk absorbs everything")
	h.near(spire.total_hp(), 20000.0, "a body or core shot changes nothing")
	var part := h.hit(spire, &"pod_0", FlowHiveSpire.POD_HP + 500.0)
	h.near(part.final_amount, FlowHiveSpire.POD_HP, "a pod only takes the HP it had left")
	h.eq(burst.size(), 1, "one pod_burst after the first pod dies")
	h.eq(burst[0], 3, "three pods left")
	h.ok(not spire.core_exposed_now(), "the core is still sealed with three pods up")
	h.burst_all_pods(spire)
	h.eq(burst.size(), FlowHiveSpire.PODS, "one pod_burst per pod")
	h.eq(burst[3], 0, "the last pod_burst reports none left")
	h.eq(core_open.size(), 1, "core_exposed fires once, when the last pod bursts")
	h.ok(spire.core_exposed_now(), "the core is open")


static func _core(h: FlowTestHarness, spire: FlowHiveSpire) -> void:
	# Polish 1's boil opens with the shell and shuts again on a checkpoint restore, lamp and all.
	var visual := spire.get_node(^"Visual") as FlowHiveVisual
	h.ok(visual.core.visible, "the boil is open once every pod has burst")
	var lamp := visual.core.get_node_or_null(^"Glow") as OmniLight3D
	h.ok(lamp != null and lamp.visible, "and its lamp is lit")
	h.ok(visual.core.is_processing(), "and it is beating")
	h.eq(h.hit(spire, &"pod_0", 1000.0).final_amount, 0.0, "a dead pod takes no more damage")
	h.near(spire.total_hp(), FlowHiveSpire.CORE_HP, "only the core's 6,000 HP is left")
	var half := h.hit(spire, &"core", 3000.0)
	h.near(half.final_amount, 3000.0, "the core takes the hit in full")
	h.near(spire.total_hp(), 3000.0, "half the core is gone")
	h.ok(spire.is_alive(), "the spire still stands")


static func _destroyed(h: FlowTestHarness, spire: FlowHiveSpire) -> void:
	var gone: Array[bool] = []
	spire.destroyed.connect(func(_s: FlowHiveSpire) -> void: gone.append(true))
	h.hit(spire, &"core", 3000.0)
	h.eq(gone.size(), 1, "destroyed fires once")
	h.ok(not spire.is_alive(), "the spire is dead")
	h.ok(not spire.is_in_group(&"hive_spire"), "a destroyed spire leaves the group")
	h.near(spire.total_hp(), 0.0, "no HP left")
	h.eq(h.hit(spire, &"core", 1000.0).final_amount, 0.0, "a dead spire ignores further hits")
	spire.collapse()
	h.eq(gone.size(), 1, "collapse is idempotent")
	# SPEC §7.1: a spire that fell AFTER the checkpoint comes back whole on respawn. Without this it
	# stood as a wreck the objective counter had never seen, and the run could never reach 3/3.
	spire.reset_full()
	h.ok(spire.is_alive(), "a restored spire stands again")
	h.ok(spire.is_in_group(&"hive_spire"), "and rejoins the group the HUD and the boss read")
	h.near(spire.total_hp(), float(FlowHiveSpire.PODS) * FlowHiveSpire.POD_HP + FlowHiveSpire.CORE_HP,
			"with all 20,000 HP back")
	h.ok(not spire.core_exposed_now(), "its shell is closed again")
	var visual := spire.get_node(^"Visual") as FlowHiveVisual
	h.ok(not visual.core.visible, "and the boil is shut, lamp and all")
	h.ok(not visual.core.is_processing(), "and it is not beating behind a sealed shell")
	h.near(h.hit(spire, &"pod_1", 1000.0).final_amount, 1000.0, "and its pods take damage again")
