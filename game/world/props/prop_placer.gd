class_name PropPlacer
extends RefCounted
## District prop placement rules (city-art). A pure function of the map layout: it emits one
## Transform3D list per prop name, with no scene access, so the whole dressing plan is testable
## head-less. PropScatter turns the plan into MultiMeshes.
##
## Two layout sources. city-build's runtime `res://world/city/layout.json` carries `prop_slots` with
## the exact position, yaw and size of every roof machine, crane, plume, statue and hologram, taken
## from the real geometry — those always win. The design-time `data/map/city_layout.json` adds the
## streets and buildings the runtime layout drops, which is where sidewalk furniture and parked
## vehicles come from.
##
## Blender -> Godot: (x, y, z) -> (x, z, -y); a Blender `rot` about +Z is the same yaw about +Y.
## All distances are metres and all spacing comes from briefs/city-art.md ("sidewalk furniture every
## 18-30 m", "rooftop machinery on every tier B-D roof slot").

const TILE := 200.0
const KERB_SETBACK := 3.5         ## furniture sits this far back from the carriageway edge
const FURNITURE_MIN := 18.0
const FURNITURE_MAX := 30.0
const VEHICLE_MIN := 45.0
const VEHICLE_MAX := 95.0
const ROOF_MARGIN := 4.0          ## keep rooftop units off the parapet

## Sidewalk pool per district (MAP.md §4 identities).
const STREET_POOL: Dictionary = {
	"D1": [&"barrier", &"container_stack", &"streetlamp"],
	"D2": [&"barrier", &"streetlamp", &"vending"],
	"D3": [&"streetlamp", &"food_stall", &"vending", &"blossom_tree"],
	"D4": [&"streetlamp", &"planter_tree", &"guardian_lion"],
	"D5": [&"streetlamp", &"barrier", &"vending", &"bus_shelter"],
	"D6": [&"barrier", &"pipe_cluster", &"storage_tank"],
	"D7": [&"streetlamp", &"planter_tree", &"bus_shelter"],
}
## Rooftop pool per district; tier A sheds get the light end of it.
const ROOF_POOL: Dictionary = {
	"D1": [&"ac_cluster", &"container_stack", &"storage_tank"],
	"D2": [&"ac_cluster", &"antenna_array", &"billboard_frame"],
	"D3": [&"water_tank", &"ac_cluster", &"solar_array"],
	"D4": [&"antenna_array", &"ac_cluster", &"solar_array"],
	"D5": [&"ac_cluster", &"antenna_array", &"billboard_frame", &"water_tank"],
	"D6": [&"pipe_cluster", &"storage_tank", &"ac_cluster", &"water_tank"],
	"D7": [&"antenna_array", &"ac_cluster", &"billboard_frame", &"solar_array"],
}
const VEHICLES: Array[StringName] = [&"hovercar_a", &"hovercar_b", &"truck", &"bus"]
const WRECKS: Array[StringName] = [&"wreck_car", &"wreck_mech"]

## The target longest dimension (metres) each prop was processed to, mirroring
## blender/props/prop_table.py. `slot_scale` fits a prop to a city-build slot without overhang.
const PROP_SIZE_M: Dictionary = {
	&"hovercar_a": 5.0, &"hovercar_b": 6.0, &"truck": 14.0, &"bus": 18.0, &"maglev_car": 25.0,
	&"wreck_car": 5.0, &"wreck_mech": 16.0, &"streetlamp": 12.0, &"vending": 2.4,
	&"bus_shelter": 6.0, &"barrier": 4.0, &"food_stall": 4.0, &"anchor_node": 3.0,
	&"holo_projector": 2.5, &"lift_platform": 12.0, &"planter_tree": 9.0, &"blossom_tree": 8.0,
	&"ac_cluster": 6.0, &"antenna_array": 8.0, &"pipe_cluster": 7.0, &"solar_array": 10.0,
	&"storage_tank": 9.0, &"water_tank": 7.0, &"billboard_frame": 14.0, &"container_stack": 12.0,
	&"crane": 60.0, &"mech_statue": 20.0, &"guardian_lion": 4.0, &"pagoda_top": 14.0,
	&"koi_dragon": 60.0,
}

## Props whose shadows read at mech scale. Everything else casts none: godot-tech §4.4 says small
## props should not cast, and with 4 PSSM splits every caster is drawn up to five times per frame.
const SHADOW_CASTERS: Array[StringName] = [
	&"crane", &"mech_statue", &"guardian_lion", &"pagoda_top", &"container_stack", &"storage_tank",
	&"water_tank", &"truck", &"bus", &"maglev_car", &"wreck_mech", &"wreck_car", &"lift_platform",
	&"bus_shelter", &"food_stall", &"billboard_frame", &"planter_tree", &"blossom_tree",
]

## city-build slot kinds that are gameplay or already-built geometry, not dressing.
const IGNORED_SLOTS: Array[String] = ["breakable_cover", "spawn_socket", "hive_spire"]

## city-build slot kind -> the prop that fills it. Roof machines pick from the district pool instead.
const SLOT_PROPS: Dictionary = {
	"gantry_crane": &"crane",
	"statue": &"mech_statue",
	"pagoda_top": &"pagoda_top",
	"maglev_car": &"maglev_car",
	"holo_projector": &"holo_projector",
}

var plan: Dictionary = {}         ## prop name -> Array[Transform3D]
## r10: prop name -> Array[int], parallel to `plan[prop]`, saying which settle rule each instance
## takes. It cannot be a per-NAME table: `container_stack`, `pipe_cluster` and `storage_tank` are in
## both the street and the rooftop pools, so the same prop stands on a kerb in D1 and on a roof in D6.
var rules: Dictionary = {}
var hologram_plan: Dictionary = {}  ## key -> Array[Transform3D], rendered with mc_hologram
var effect_plan: Dictionary = {}    ## CityLife effect name -> Array[Vector3]
var sign_plan: Array = []           ## [position, yaw, width, height] rows for ClothLines/holo signs
var hive_sites: Dictionary = {}     ## site id -> world position, for the creep field
var landmarks_done: bool = false    ## `_landmarks` already dressed the decks from its own layout


## Builds the whole dressing plan. `seed` keeps captures and tests reproducible.
## `design` is the design-time layout (data/map/city_layout.json) when it is available: it carries the
## streets and buildings that city-build's runtime layout.json drops. Only the runtime layout is
## needed for the slots, so an exported build still gets the roof/landmark dressing.
func build(layout: Dictionary, seed: int = 20261101, design: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	plan = {}
	rules = {}
	hologram_plan = {} as Dictionary
	effect_plan = {} as Dictionary
	landmarks_done = false
	var slots: Array = layout.get("prop_slots", [])
	if not slots.is_empty():
		_from_slots(slots, layout.get("hives", []), rng)
	else:
		_landmarks(layout, rng)
		landmarks_done = true
	var streets: Array = design.get("streets", layout.get("streets", []))
	var buildings: Array = design.get("buildings", layout.get("buildings", []))
	if not streets.is_empty():
		_street_furniture(streets, buildings, rng)
		_parked_vehicles(streets, rng)
	if slots.is_empty() and not buildings.is_empty():
		_rooftops(buildings, rng)
	# The Sky Garden's blossom and planters only exist in the design layout (city-build's runtime
	# layout drops `decks`), and `_landmarks` never runs once it hands out slots — so the one garden in
	# the city was bare in every capture. Dress it from whichever layout has the decks.
	if not landmarks_done:
		var decks: Dictionary = design if design.has("decks") else layout
		_garden(decks, rng)
	return plan


## Scale that fits a prop inside a city-build slot without overhanging the parapet.
static func slot_scale(prop: StringName, size: Array) -> float:
	var target := float(PROP_SIZE_M.get(prop, 6.0))
	if size.size() < 3:
		return 1.0
	var longest := maxf(float(size[0]), maxf(float(size[1]), float(size[2])))
	return clampf(longest / maxf(target, 0.01), 0.35, 2.5)


## city-build hands out exact prop slots from the real geometry; those positions win over any
## rule of ours, because only they know where a roof's parapet and a facade's normal actually are.
func _from_slots(slots: Array, hives: Array, rng: RandomNumberGenerator) -> void:
	for s in slots:
		var kind := String(s.get("kind", ""))
		if IGNORED_SLOTS.has(kind):
			continue
		var pos := to_godot(s.get("pos", [0.0, 0.0, 0.0]), float(s.get("pos", [0, 0, 0])[2]))
		var yaw := float(s.get("yaw_deg", 0.0))
		var size: Array = s.get("size", [])
		match kind:
			"roof_machine":
				var pool: Array = ROOF_POOL.get(_district_of(s), ROOF_POOL["D4"])
				var prop: StringName = pool[rng.randi_range(0, pool.size() - 1)]
				_add(prop, placed(pos, yaw, slot_scale(prop, size)), CitySettle.RULE_ROOF)
			"smoke_plume":
				_effect(&"smoke_column", pos)
			"koi_hologram":
				hologram_plan[&"koi_dragon"] = [placed(pos, yaw)] as Array[Transform3D]
				_add(&"holo_projector", placed(pos + Vector3.DOWN * 24.0, yaw))
			"traffic_hologram":
				hologram_plan[&"traffic"] = [placed(pos, yaw)] as Array[Transform3D]
			"spire_beacon":
				_add(&"holo_projector", placed(pos, yaw))
				_effect(&"tether", pos)
			"passage_sign":
				sign_plan.append([pos, yaw, 9.0, 3.2])
			_:
				if SLOT_PROPS.has(kind):
					var named: StringName = SLOT_PROPS[kind]
					_add(named, placed(pos, yaw, slot_scale(named, size)))
	# Hive creep sites come from the layout, so the creep field and the props agree on where they are.
	for h in hives:
		if h.has("pos"):
			hive_sites[StringName(h.get("id", ""))] = to_godot(h["pos"], float(h["pos"][2]))


func _effect(kind: StringName, at: Vector3) -> void:
	if not effect_plan.has(kind):
		effect_plan[kind] = [] as Array[Vector3]
	(effect_plan[kind] as Array).append(at)


## "D7_w000" -> "D7"; a slot without a building id falls back to the civic core palette.
func _district_of(slot: Dictionary) -> String:
	var id := String(slot.get("building", ""))
	return id.substr(0, 2) if id.length() >= 2 else "D4"


func tile_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.z / TILE)))


func prop_count() -> int:
	var n := 0
	for name in plan:
		n += (plan[name] as Array).size()
	return n


func _add(prop: StringName, xf: Transform3D, rule: int = CitySettle.RULE_STREET) -> void:
	if not plan.has(prop):
		plan[prop] = [] as Array[Transform3D]
		rules[prop] = [] as Array[int]
	(plan[prop] as Array).append(xf)
	(rules[prop] as Array).append(rule)


static func to_godot(xy: Array, z: float) -> Vector3:
	return Vector3(float(xy[0]), z, -float(xy[1]))


static func placed(pos: Vector3, yaw_deg: float, scale: float = 1.0) -> Transform3D:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3(scale, scale, scale))
	return Transform3D(b, pos)


## Walks a polyline in Blender coordinates, returning [position, tangent] every `spacing` metres.
static func walk(points: Array, spacing: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for i in range(points.size() - 1):
		var a := Vector2(points[i][0], points[i][1])
		var b := Vector2(points[i + 1][0], points[i + 1][1])
		var seg := b - a
		var length := seg.length()
		if length < 1e-3:
			continue
		var dir := seg / length
		var t := rng.randf() * spacing
		while t < length:
			out.append([a + dir * t, dir])
			t += spacing * rng.randf_range(0.82, 1.18)
	return out


## Nearest building's district, so a street without a district still dresses in its own language.
static func district_near(xy: Vector2, buildings: Array, fallback: String = "D4") -> String:
	var best := fallback
	var best_d := INF
	for b in buildings:
		var d := Vector2(b["center"][0], b["center"][1]).distance_squared_to(xy)
		if d < best_d:
			best_d = d
			best = String(b["district"])
	return best


func _street_furniture(streets: Array, buildings: Array, rng: RandomNumberGenerator) -> void:
	for s in streets:
		var width := float(s.get("width", 44.0))
		var z := float(s.get("z", 0.0))
		var spacing := rng.randf_range(FURNITURE_MIN, FURNITURE_MAX)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		for step in walk(s.get("points", []), spacing, rng):
			var p: Vector2 = step[0]
			var dir: Vector2 = step[1]
			var district := district_near(p, buildings)
			var pool: Array = STREET_POOL.get(district, STREET_POOL["D4"])
			var off := dir.orthogonal() * side * (width * 0.5 + KERB_SETBACK)
			var pos := to_godot([p.x + off.x, p.y + off.y], z)
			# Furniture faces the street: yaw from the tangent, mirrored on the left kerb.
			_add(pool[rng.randi_range(0, pool.size() - 1)],
				placed(pos, rad_to_deg(atan2(dir.x, -dir.y)) + (180.0 if side < 0.0 else 0.0)))
			side = -side


func _parked_vehicles(streets: Array, rng: RandomNumberGenerator) -> void:
	for s in streets:
		if String(s.get("kind", "street")) == "alley":
			continue
		var width := float(s.get("width", 44.0))
		var z := float(s.get("z", 0.0))
		for step in walk(s.get("points", []), rng.randf_range(VEHICLE_MIN, VEHICLE_MAX), rng):
			var p: Vector2 = step[0]
			var dir: Vector2 = step[1]
			var yaw := rad_to_deg(atan2(dir.x, -dir.y))
			var off := dir.orthogonal() * (width * 0.5 - 3.0)
			var pos := to_godot([p.x + off.x, p.y + off.y], z)
			# One in twelve is a wreck: the infestation has been through here.
			var name: StringName = WRECKS[rng.randi_range(0, 0)] if rng.randf() < 0.08 \
				else VEHICLES[rng.randi_range(0, VEHICLES.size() - 1)]
			_add(name, placed(pos, yaw + rng.randf_range(-4.0, 4.0)))


## Rooftop machinery on every tier B-D roof (ART.md §4); tier A sheds get one small unit.
func _rooftops(buildings: Array, rng: RandomNumberGenerator) -> void:
	for b in buildings:
		var tier := String(b.get("tier", "B"))
		if tier == "A" and not bool(b.get("roof_walkable", false)) and rng.randf() > 0.35:
			continue
		var district := String(b.get("district", "D4"))
		var pool: Array = ROOF_POOL.get(district, ROOF_POOL["D4"])
		var size: Array = b.get("size", [20.0, 20.0])
		var half := Vector2(float(size[0]) * 0.5 - ROOF_MARGIN, float(size[1]) * 0.5 - ROOF_MARGIN)
		if half.x < 2.0 or half.y < 2.0:
			continue
		var count := 1 if tier == "A" else rng.randi_range(2, 4)
		var rot := float(b.get("rot", 0.0))
		for i in range(count):
			var local := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
			var rotated := local.rotated(deg_to_rad(rot))
			var centre: Array = b["center"]
			var pos := to_godot([float(centre[0]) + rotated.x, float(centre[1]) + rotated.y],
				float(b.get("base_z", 0.0)) + float(b.get("height", 0.0)))
			_add(pool[rng.randi_range(0, pool.size() - 1)],
				placed(pos, rot + rng.randf_range(0.0, 360.0), rng.randf_range(0.85, 1.15)),
				CitySettle.RULE_ROOF)


## Signature dressing (ART.md §4, MAP.md §4): the plaza statues, the harbour cranes, the pagoda
## crown, the reactor stacks and the koi hologram. Holograms go into `hologram_plan` because they
## need the additive hologram material instead of the shared prop body material.
func _landmarks(layout: Dictionary, rng: RandomNumberGenerator) -> void:
	for lm in layout.get("landmarks", []):
		var kind := String(lm.get("kind", ""))
		var pos: Array = lm.get("pos", [0.0, 0.0, 0.0])
		var params: Dictionary = lm.get("params", {})
		match kind:
			"spire":
				_plaza(pos, rng)
			"cranes":
				for p in params.get("positions", []):
					_add(&"crane", placed(to_godot(p, 0.0), rng.randf_range(0.0, 360.0)))
			"pagoda":
				_add(&"pagoda_top", placed(to_godot(pos, float(params.get("top_z", 128.0)) - 14.0), 45.0))
				_ring(to_godot(pos, float(params.get("stilt_base_z", 32.0))), 46.0, 6,
					[&"blossom_tree", &"food_stall"], rng)
			"stacks":
				for p in params.get("positions", []):
					_ring(to_godot(p, 0.0), 40.0, 3, [&"pipe_cluster", &"storage_tank"], rng)
			"block9":
				var holo: Dictionary = params.get("hologram", {})
				var hz := float(holo.get("z", 232.0))
				hologram_plan[&"koi_dragon"] = [placed(to_godot(pos, hz), 0.0)] as Array[Transform3D]
				_ring(to_godot(pos, hz - 8.0), float(holo.get("width", 120.0)) * 0.45, 4,
					[&"holo_projector"], rng)
			"hologram":
				_add(&"holo_projector", placed(to_godot(pos, float(pos[2])) + Vector3.UP * 2.0, 0.0))
			"knot":
				_ring(to_godot(pos, 32.0), 120.0, 8, [&"streetlamp", &"barrier"], rng)
	_garden(layout, rng)


func _plaza(pos: Array, rng: RandomNumberGenerator) -> void:
	# Spire Plaza: guardian lions flanking the approach, mech statues on the outer ring.
	var centre := to_godot(pos, float(pos[2]))
	for i in range(4):
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var at := centre + Vector3(cos(a), 0.0, sin(a)) * 96.0
		_add(&"mech_statue", placed(at + Vector3.UP * 4.0, rad_to_deg(-a)))
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var at := centre + Vector3(cos(a), 0.0, sin(a)) * 58.0
		_add(&"guardian_lion", placed(at + Vector3.UP * 1.0, rad_to_deg(-a) + 180.0))
	for i in range(6):
		var a := TAU * float(i) / 6.0 + 0.4
		_add(&"planter_tree", placed(centre + Vector3(cos(a), 0.0, sin(a)) * 132.0 + Vector3.UP * 1.0,
			rad_to_deg(-a)))


func _garden(layout: Dictionary, rng: RandomNumberGenerator) -> void:
	# Sky Garden (A6): cherry blossoms and planters on the garden decks.
	for deck in layout.get("decks", []):
		if String(deck.get("kind", "")) != "garden":
			continue
		var poly: Array = deck.get("polygon", [])
		if poly.is_empty():
			continue
		var centre := Vector2.ZERO
		for p in poly:
			centre += Vector2(p[0], p[1])
		centre /= float(poly.size())
		var radius := 0.0
		for p in poly:
			radius = maxf(radius, centre.distance_to(Vector2(p[0], p[1])))
		_ring(to_godot([centre.x, centre.y], float(deck.get("z", 144.0))), radius * 0.7, 14,
			[&"blossom_tree", &"planter_tree"], rng)


func _ring(centre: Vector3, radius: float, count: int, pool: Array,
		rng: RandomNumberGenerator) -> void:
	for i in range(count):
		var a := TAU * float(i) / float(maxi(count, 1)) + rng.randf_range(-0.12, 0.12)
		var r := radius * rng.randf_range(0.78, 1.0)
		var at := centre + Vector3(cos(a), 0.0, sin(a)) * r
		_add(pool[rng.randi_range(0, pool.size() - 1)], placed(at, rad_to_deg(-a) + 180.0))


