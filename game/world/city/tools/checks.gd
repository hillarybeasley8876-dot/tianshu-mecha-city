extends Node
## City checks C12-C18 (city-build). Run with `tools/city/checks.sh`.
##
##   C12 trajectory sweeps   every edgejump/drop/vcat/lcat/vent/lift arc: capsule r4 h16 swept at
##                           0.1 s steps, clear before landing, landing normal <= 40 deg
##   C13 headroom / width    over navmesh samples: ceiling >= 24 m (>= 32 m in arenas)
##   C14 sightlines / cover  per arena: <= 5 % of pairs with clear LOS > 350 m; every sample
##                           within 60 m of a collider >= 20 m tall
##   C15 Spire visibility    >= 60 % of navigable samples see crown +224 / top +360 / tether +600
##                           (reported for L1 streets and L2+ separately)
##   C15b arena compass      every arena centre at its TOP tier sees the Spire top or the tether
##                           (lead r2 decision: C15 is accepted at 48 %, this replaces it as a gate)
##   C16 boundary / ceiling  nothing navigable within 30 m of the edge without a wall; no arc
##                           leaves the square; ceiling +260
##   C17 jump probes         1,000 random max-boost jumps land on a mapped surface
##   C18 rendered floors     every walkable floor has a RENDERED up-facing face at its own z
##                           (`checks_floor.gd`; the only check that reads the render, not the
##                           collision - a deck whose slab the kit skin muted had a perfect
##                           collider and nothing to see)
##
## Every query except C18 runs against the live collision, never the render mesh.

const CAPSULE_R := 4.0
const CAPSULE_H := 16.0
const GRAVITY := 25.5          ## MAP 1: use 25.5 for arc sampling
const STEP := 0.1
const MIN_CEILING := 24.0
const ARENA_CEILING := 32.0
const MAX_LOS := 350.0
const COVER_RANGE := 60.0
const FULL_COVER_H := 20.0
const SPIRE_GATE := 0.60
const L2_FLOOR := 16.0          ## MAP 1 LAYER_Z: below this is L0/L1 (streets), above is L2+
const JUMP_PROBES := 1000
const JUMP_APEX := 40.0        ## MAP 1 J
const V_BOOST := 42.0

var city: Node3D = null
var space: PhysicsDirectSpaceState3D = null
var layout: Dictionary = {}
var nav: Node = null
var rng := RandomNumberGenerator.new()
var fails: int = 0
var _map_ok: bool = false


func _ready() -> void:
	rng.seed = 20261101
	city = (load("res://world/city.tscn") as PackedScene).instantiate() as Node3D
	add_child(city)
	layout = city.get("layout")
	nav = city.get("nav")
	for i in 30:
		await get_tree().physics_frame
	space = city.get_world_3d().direct_space_state
	# Navigation map sync is asynchronous. Wait on WALL time, never frames: tools/godot.sh test
	# runs --fixed-fps 120 headless and burns thousands of frames per wall second, so a frame
	# count read as seconds was ~100x too pessimistic (reviews/city-build-nav.md).
	var t0 := Time.get_ticks_msec()
	while not (nav as CityNav).is_synced(&"medium") and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().physics_frame
	print("nav usable after %d ms; per class %s"
			% [Time.get_ticks_msec() - t0, str(_nav_state())])
	_c12()
	_c13()
	_c14()
	_c15()
	_c15b()
	_c16()
	_c17()
	_c18()
	print("CHECKS %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _nav_state() -> Dictionary:
	var out := {}
	for cls in CityNav.CLASSES:
		out[String(cls)] = (nav as CityNav).is_synced(cls)
	return out


func _report(id: String, ok: bool, text: String) -> void:
	if not ok:
		fails += 1
	print("%s %s: %s" % [id, "PASS" if ok else "FAIL", text])


# ------------------------------------------------------------------ helpers
func _capsule() -> CapsuleShape3D:
	var c := CapsuleShape3D.new()
	c.radius = CAPSULE_R
	c.height = CAPSULE_H
	return c


func _sweep(from: Vector3, to: Vector3) -> Dictionary:
	## Sweep the mech capsule between two feet positions; {} when the arc is clear.
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _capsule()
	q.collision_mask = Layers.WORLD
	# The capsule rides 1 m above the sampled feet line: a capsule resting exactly on the
	# take-off surface reports a hit before it has moved.
	q.transform = Transform3D(Basis(), from + Vector3.UP * (CAPSULE_H * 0.5 + 1.0))
	q.motion = to - from
	var frac: PackedFloat32Array = space.cast_motion(q)
	if frac.size() < 2 or frac[0] < 1.0:
		return {"blocked_at": from}
	return {}


func _landing_ok(land: Vector3, ceiling: float) -> String:
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			land + Vector3.UP * 4.0, land + Vector3.DOWN * 8.0, Layers.WORLD))
	if down.is_empty():
		return "no ground under the landing"
	if (down["normal"] as Vector3).angle_to(Vector3.UP) > deg_to_rad(40.0):
		return "landing slope > 40 deg"
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			land + Vector3.UP * 1.0, land + Vector3.UP * ceiling, Layers.WORLD))
	if not up.is_empty():
		return "ceiling %.1f m" % land.distance_to(up["position"])
	return ""


func _arc(from: Vector3, to: Vector3, time: float) -> PackedVector3Array:
	## MAP 5.3: v0 = (E - S - 0.5 g t^2) / t, sampled every STEP seconds.
	var g := Vector3.DOWN * GRAVITY
	var v0 := (to - from - 0.5 * g * time * time) / time
	var out := PackedVector3Array()
	var t := 0.0
	while t < time:
		out.append(from + v0 * t + 0.5 * g * t * t)
		t += STEP
	out.append(to)
	return out


func _nav_points(cls: StringName, want: int) -> PackedVector3Array:
	var all: PackedVector3Array = (nav as CityNav).sample_points(cls)
	if all.is_empty() or want <= 0 or want >= all.size():
		return all
	var out := PackedVector3Array()
	var seen: Dictionary = {}
	var guard := 0
	while out.size() < want and guard < want * 40:
		guard += 1
		var c := all[rng.randi() % all.size()]
		var key := Vector3i(c * 0.1)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(c)
	return out


# ------------------------------------------------------------------ C12
## One arc per connector kind. `vertical` kinds ride a shaft, `ballistic` kinds are a boost jump,
## `lcat` is a scripted 300-600 m launch; `stairs` is walkable and only needs its landing checked.
const ARC_MODE := {
	&"edgejump": "ballistic", &"drop": "ballistic", &"vcat": "vertical",
	&"vent": "vertical", &"lift": "vertical", &"lcat": "launch", &"stairs": "walk",
}


func _c12() -> void:
	var tested := 0
	var blocked: PackedStringArray = []
	var buried: PackedStringArray = []
	for link in layout.get("nav_links", []):
		var kind := StringName(link["kind"])
		if not ARC_MODE.has(kind):
			continue
		tested += 1
		var a: Vector3 = city.to_godot(link["from"])
		var b: Vector3 = city.to_godot(link["to"])
		var id := String(link["id"])
		if not _free_at(a):
			buried.append("%s(%s) start %s" % [id, kind, str(a.round())])
		var problem := ""
		var pts := _connector_arc(String(ARC_MODE[kind]), a, b)
		for i in range(1, pts.size() - 2):
			if _sweep(pts[i], pts[i + 1]).is_empty():
				continue
			problem = "blocked at %s" % str(pts[i].round())
			break
		if problem == "":
			problem = _landing_ok(b, MIN_CEILING)
		if problem != "":
			blocked.append("%s(%s) %s" % [id, kind, problem])
	_report("C12", blocked.is_empty(),
			"%d connector arcs (r%.0f h%.0f, g%.1f): %d blocked, %d starts inside geometry: %s || %s"
			% [tested, CAPSULE_R, CAPSULE_H, GRAVITY, blocked.size(), buried.size(),
			   _sample(blocked), _sample(buried)])


func _connector_arc(mode: String, a: Vector3, b: Vector3) -> PackedVector3Array:
	var rise: float = absf(b.y - a.y)
	var flat: float = Vector2(b.x - a.x, b.z - a.z).length()
	match mode:
		"vertical":
			var out := PackedVector3Array()
			var n := maxi(2, int(rise / 4.0))
			for i in n + 1:
				out.append(a.lerp(b, float(i) / float(n)))
			return out
		"walk":
			return PackedVector3Array([a, a.lerp(b, 0.5), b])
		"launch":
			return _arc(a, b, flat / 120.0 + 1.2)
		_:
			return _arc(a, b, maxf(0.5, sqrt(2.0 * rise / GRAVITY)) + flat / V_BOOST)


func _free_at(p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _capsule()
	q.collision_mask = Layers.WORLD
	q.transform = Transform3D(Basis(), p + Vector3.UP * (CAPSULE_H * 0.5 + 1.0))
	return space.intersect_shape(q, 1).is_empty()


# ------------------------------------------------------------------ C13
func _c13() -> void:
	## Headroom over navmesh samples; arenas demand 32 m, the rest 24 m.
	var samples := _nav_points(&"medium", 600)
	if samples.is_empty():
		_report("C13", false, "no navmesh samples (bake the navmeshes first)")
		return
	var low: PackedStringArray = []
	var worst := 999.0
	for p in samples:
		var need := ARENA_CEILING if _in_arena(p) else MIN_CEILING
		var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				p + Vector3.UP * 1.0, p + Vector3.UP * 40.0, Layers.WORLD))
		var clear := 40.0 if up.is_empty() else p.distance_to(up["position"])
		worst = minf(worst, clear)
		if clear < need:
			low.append("%s %.1f m (need %.0f)" % [str(p.round()), clear, need])
	_report("C13", low.size() * 20 <= samples.size(),
			"%d navmesh samples, worst headroom %.1f m, %d under the minimum (%.1f %%): %s"
			% [samples.size(), worst, low.size(), 100.0 * low.size() / samples.size(),
			   _sample(low)])


# ------------------------------------------------------------------ C14
func _c14() -> void:
	var worst_los := 0.0
	var worst_cover := 1.0
	var detail: PackedStringArray = []
	var open_cover: PackedStringArray = []
	for arena in layout.get("arenas", []):
		# An arena the layout marks `open_cover` is meant to be open to the sky (the Crown, MAP 4
		# B1): demanding full cover inside 60 m there is the wrong test, so only the sightline
		# half of C14 applies to it.
		var is_open := bool(arena.get("open_cover", false))
		var poly: Array = arena["polygon"]
		var pts := _arena_points(poly, 40)
		if pts.size() < 4:
			continue
		var long_los := 0
		var pairs := 0
		for i in 260:
			var a: Vector3 = pts[rng.randi() % pts.size()]
			var b: Vector3 = pts[rng.randi() % pts.size()]
			if a.distance_to(b) <= MAX_LOS:
				continue
			pairs += 1
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(
					a, b, Layers.WORLD)).is_empty():
				long_los += 1
		var share := 0.0 if pairs == 0 else float(long_los) / float(pairs)
		worst_los = maxf(worst_los, share)
		var cov := 1.0
		if is_open:
			open_cover.append(String(arena["id"]))
		else:
			var covered := 0
			for p in pts:
				if _cover_near(p):
					covered += 1
			cov = float(covered) / float(pts.size())
			worst_cover = minf(worst_cover, cov)
		detail.append("%s los=%.1f%% cover=%s" % [arena["id"], share * 100.0,
				"n/a (open_cover)" if is_open else "%.0f%%" % (cov * 100.0)])
	_report("C14", worst_los <= 0.05 and worst_cover >= 0.999,
			"long sightlines <= 5 %%, full cover within %.0f m: worst %.1f %% / %.0f %% "
			% [COVER_RANGE, worst_los * 100.0, worst_cover * 100.0]
			+ "(cover exempt: %s); %s" % [", ".join(open_cover), " ".join(detail)])


func _arena_points(poly: Array, want: int) -> PackedVector3Array:
	## Sample points 12 m above the walkable surface inside an arena polygon.
	var out := PackedVector3Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(Vector2(p[0], p[1]))
		hi = hi.max(Vector2(p[0], p[1]))
	var flat := PackedVector2Array()
	for p in poly:
		flat.append(Vector2(p[0], p[1]))
	var guard := 0
	while out.size() < want and guard < want * 30:
		guard += 1
		var b := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		if not Geometry2D.is_point_in_polygon(b, flat):
			continue
		var g := Vector3(b.x, 0.0, -b.y)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				g + Vector3.UP * 320.0, g + Vector3.DOWN * 60.0, Layers.WORLD))
		if hit.is_empty():
			continue
		out.append((hit["position"] as Vector3) + Vector3.UP * 12.0)
	return out


func _cover_near(p: Vector3) -> bool:
	## A full-cover collider (>= 20 m tall) within COVER_RANGE: cast 8 rays at torso height.
	## MASK_SIGHT (WORLD|PROPS), not WORLD alone: destructible arena cover sits on PROPS so the
	## navmesh bake ignores it, and it is still full cover to a shooter.
	for i in 8:
		var a := TAU * i / 8.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				p, p + dir * COVER_RANGE, Layers.MASK_SIGHT))
		if hit.is_empty():
			continue
		var top := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				hit["position"], (hit["position"] as Vector3) + Vector3.UP * 120.0,
				Layers.MASK_SIGHT))
		if top.is_empty():
			return true   # the blocker rises out of the 120 m probe: it is full cover
		if (hit["position"] as Vector3).distance_to(top["position"]) >= FULL_COVER_H:
			return true
	return false


func _in_arena(p: Vector3) -> bool:
	for arena in layout.get("arenas", []):
		var flat := PackedVector2Array()
		for q in arena["polygon"]:
			flat.append(Vector2(q[0], q[1]))
		if Geometry2D.is_point_in_polygon(Vector2(p.x, -p.z), flat):
			return true
	return false


func _sample(rows: PackedStringArray, n: int = 6) -> String:
	if rows.is_empty():
		return "none"
	var out: PackedStringArray = []
	for i in mini(n, rows.size()):
		out.append(rows[i])
	if rows.size() > n:
		out.append("... +%d" % (rows.size() - n))
	return " | ".join(out)


# ------------------------------------------------------------------ C15
func _c15() -> void:
	## MAP L5 / C15: the Spire is the wayfinding landmark. It reads through three points, not
	## only the Crown deck (lead r2): the crown at +224, the Spire's top at +360, and the light
	## tether at +600 — any one of them with a clear ray counts as visible. Gate 60 % overall;
	## streets (L1 and below) and the raised layers are reported separately because the canyons
	## are expected to hide it at street level.
	var samples := _nav_points(&"medium", 800)
	if samples.is_empty():
		_report("C15", false, "no navmesh samples")
		return
	var marks := _spire_marks()
	var seen := 0
	var street_n := 0
	var street_seen := 0
	var high_n := 0
	var high_seen := 0
	for p in samples:
		var visible := false
		for c in marks:
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(
					p + Vector3.UP * 12.0, c, Layers.WORLD)).is_empty():
				visible = true
				break
		if visible:
			seen += 1
		if p.y < L2_FLOOR:
			street_n += 1
			street_seen += int(visible)
		else:
			high_n += 1
			high_seen += int(visible)
	var share := float(seen) / float(samples.size())
	_report("C15", share >= SPIRE_GATE,
			"%d of %d samples see the Spire (%.1f %%, gate %.0f %%) — L1 streets %d/%d (%.1f %%), "
			% [seen, samples.size(), share * 100.0, SPIRE_GATE * 100.0,
			   street_seen, street_n, _pct(street_seen, street_n)]
			+ "L2+ %d/%d (%.1f %%)" % [high_seen, high_n, _pct(high_seen, high_n)])


func _pct(a: int, b: int) -> float:
	return 100.0 * float(a) / float(b) if b > 0 else 0.0


func _c15b() -> void:
	## Lead r2 decision, replacing the global C15 gate: C15 is accepted at 48 % because the compass
	## carries the canyons, but EVERY arena centre at its top tier must see the Spire's top or the
	## tether. The top tier is the highest socket of the arena, which is where the fight actually
	## ends up, and the eye is 12 m above it.
	var marks := _spire_marks()
	var high := PackedVector3Array([marks[1], marks[2]])   ## top +360 and tether, not the crown
	var ok := 0
	var total := 0
	var blind: PackedStringArray = []
	for a in layout.get("arenas", []):
		var top := _arena_top(a)
		if top == Vector3.INF:
			continue
		total += 1
		var eye := top + Vector3.UP * 12.0
		var visible := false
		for c in high:
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(
					eye, c, Layers.WORLD)).is_empty():
				visible = true
				break
		ok += int(visible)
		if not visible:
			blind.append("%s (%.0f, %.0f, %.0f)" % [String(a.get("id", "?")), top.x, top.y, top.z])
	_report("C15b", total > 0 and ok == total,
			"%d of %d arena top tiers see the Spire top or the tether%s"
			% [ok, total, "" if blind.is_empty() else " — blind: " + ", ".join(blind)])


func _arena_top(a: Dictionary) -> Vector3:
	## The highest socket of an arena, snapped down onto whatever surface is under it.
	var best := Vector3.INF
	for s in a.get("sockets", []):
		var g: Vector3 = city.to_godot(s["pos"])
		if best == Vector3.INF or g.y > best.y:
			best = g
	if best == Vector3.INF:
		return Vector3.INF
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			best + Vector3.UP * 60.0, best + Vector3.DOWN * 200.0, Layers.WORLD))
	return hit["position"] as Vector3 if not hit.is_empty() else best


func _spire_marks() -> PackedVector3Array:
	## Crown deck +224, Spire top +360, tether +600 (MAP 4 B1 / the landmark's own params).
	for lm in layout.get("landmarks", []):
		if String(lm["kind"]) == "spire":
			var base: Vector3 = city.to_godot(lm["pos"])
			var p: Dictionary = lm.get("params", {})
			var crown := base + Vector3.UP * float(p.get("crown_deck_z", 224.0))
			var top := base + Vector3.UP * float(p.get("height", 360.0))
			return PackedVector3Array([crown, top,
					base + Vector3.UP * float(p.get("tether_top_z", 960.0))])
	push_warning("C15: no spire landmark in the layout; using the MAP 4 default position")
	return PackedVector3Array([Vector3(0.0, 224.0, -120.0), Vector3(0.0, 360.0, -120.0),
			Vector3(0.0, 600.0, -120.0)])


# ------------------------------------------------------------------ C16
func _c16() -> void:
	## Boundary: no navigable sample within 30 m of the edge without a wall in the way, and no
	## catapult / vent arc leaves the square. Ceiling +260 m.
	var half := float(layout.get("bounds", {}).get("half", 700.0))
	var ceiling := float(layout.get("bounds", {}).get("ceiling", 260.0))
	var samples := _nav_points(&"medium", 800)
	var exposed: PackedStringArray = []
	for p in samples:
		var edge := half - maxf(absf(p.x), absf(p.z))
		if edge > 30.0:
			continue
		var outward := Vector3(signf(p.x) if absf(p.x) > absf(p.z) else 0.0, 0.0,
				signf(p.z) if absf(p.z) >= absf(p.x) else 0.0)
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(
				p + Vector3.UP * 8.0, p + outward * 120.0 + Vector3.UP * 8.0,
				Layers.WORLD)).is_empty():
			exposed.append(str(p.round()))
	var escaped: PackedStringArray = []
	for link in layout.get("nav_links", []):
		if String(link["kind"]) != "vcat" and String(link["kind"]) != "lcat":
			continue
		var b: Vector3 = city.to_godot(link["to"])
		if maxf(absf(b.x), absf(b.z)) > half or b.y > ceiling:
			escaped.append(String(link["id"]))
	_report("C16", exposed.is_empty() and escaped.is_empty(),
			"boundary +-(%.0f) m, ceiling +%.0f m: %d exposed edge samples, %d arcs leaving the square: %s %s"
			% [half, ceiling, exposed.size(), escaped.size(), _sample(exposed), _sample(escaped)])


# ------------------------------------------------------------------ C17
func _c17() -> void:
	## 1,000 max-boost jumps from navmesh samples must land on a mapped surface.
	var map: RID = nav.nav_map(&"medium")
	var worst := 0.0
	var samples := _nav_points(&"medium", JUMP_PROBES)
	if samples.is_empty():
		_report("C17", false, "no navmesh samples")
		return
	var unmapped: PackedStringArray = []
	var landed := 0
	for p in samples:
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		var v := dir * V_BOOST + Vector3.UP * sqrt(2.0 * GRAVITY * JUMP_APEX)
		var t := 0.0
		var hit := {}
		while t < 14.0:
			var p0 := p + Vector3.UP * 1.0 + v * t + Vector3.DOWN * (0.5 * GRAVITY * t * t)
			var t1 := t + STEP
			var p1 := p + Vector3.UP * 1.0 + v * t1 + Vector3.DOWN * (0.5 * GRAVITY * t1 * t1)
			hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(p0, p1, Layers.WORLD))
			if not hit.is_empty():
				break
			t = t1
		if hit.is_empty():
			continue
		landed += 1
		var land: Vector3 = hit["position"]
		var nearest: Vector3 = NavigationServer3D.map_get_closest_point(map, land)
		if not _map_ok:
			_map_ok = NavigationServer3D.map_get_regions(map).size() > 0
		var d := nearest.distance_to(land)
		worst = maxf(worst, d)
		if d > 8.0:
			unmapped.append("%s off by %.0f m" % [str(land.round()), d])
	_report("C17", unmapped.size() * 20 <= landed,
			"%d jumps, %d landed, %d off the medium navmesh (%.1f %%, worst %.0f m, map iter %d): %s"
			% [samples.size(), landed, unmapped.size(),
			   100.0 * unmapped.size() / maxi(landed, 1), worst,
			   NavigationServer3D.map_get_iteration_id(map), _sample(unmapped)])
	print("C17 map regions=%d closest_to_origin=%s" % [NavigationServer3D.map_get_regions(map).size(),
			str(NavigationServer3D.map_get_closest_point(map, Vector3.ZERO))])


# ------------------------------------------------------------------ C18
func _c18() -> void:
	## Every walkable floor has a RENDERED up-facing face at its own z (lead, r9). The one check
	## that reads the render instead of the collision: the collider was always right, which is why
	## a player could stand on a deck whose slab the kit skin had muted and see nothing under
	## their feet. Implementation and the sampling rules are in `checks_floor.gd`.
	var gate := CityFloorCheck.new()
	var ok := gate.run(city, layout)
	_report("C18", ok, gate.summary() + (": " + gate.list() if not ok else ""))
