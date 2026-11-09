class_name InfectionField
extends Node
## Infection creep driver (city-art). The node in group &"infection" (CONTRACTS §7):
##   set_intensity(site_id: StringName, value: float, seconds: float)
## Site ids are the layout's `hives[].id`. There is no per-building geometry: `mc_surface` reads the
## four hive globals (position + radius) and the per-hive levels, so creep appears on every surface
## near a hive — walls, decks, roads — with zero extra draw calls, and recedes when a spire falls.

const MAX_SITES := 4
## Review r2: creep is a stain around a nest, not a city-wide skin — the shader field falls to nothing
## at this radius, and `register_site` clamps anything larger down to it.
const DEFAULT_RADIUS := 120.0
const PULSE_HZ := 0.25

## MAP.md §2 hive sites in GODOT coordinates (Blender (x, y, z) -> Godot (x, z, -y)).
const DEFAULT_SITES: Array[Dictionary] = [
	{"id": &"hive_a2", "pos": Vector3(-470.0, 32.0, 40.0), "radius": DEFAULT_RADIUS},
	{"id": &"hive_a5", "pos": Vector3(470.0, 80.0, 200.0), "radius": DEFAULT_RADIUS},
	{"id": &"hive_a6", "pos": Vector3(-60.0, 144.0, 450.0), "radius": DEFAULT_RADIUS},
]

var master: float = 1.0            ## global creep multiplier; 0 = the city is clean again

var _sites: Array[Dictionary] = []  ## {id, pos, radius, level, target, rate}
var _time: float = 0.0


func _ready() -> void:
	add_to_group(&"infection")
	McMaterials.ensure_globals()
	for s in DEFAULT_SITES:
		register_site(s["id"], s["pos"], s["radius"])
	RenderingServer.global_shader_parameter_set(&"mc_infection", master)


## Adds or moves a creep site. Anything beyond MAX_SITES is refused with a readable error, and the
## radius is clamped to DEFAULT_RADIUS: a bigger stain reads as wallpaper, not an infection.
func register_site(id: StringName, pos: Vector3, radius: float = DEFAULT_RADIUS) -> void:
	var r := clampf(radius, 10.0, DEFAULT_RADIUS)
	for s in _sites:
		if s["id"] == id:
			s["pos"] = pos
			s["radius"] = r
			_push_sites()
			return
	if _sites.size() >= MAX_SITES:
		push_error("InfectionField: cannot register '%s', only %d hive slots exist" % [id, MAX_SITES])
		return
	_sites.append({"id": id, "pos": pos, "radius": r, "level": 0.0, "target": 0.0, "rate": 0.0})
	_push_sites()


## CONTRACTS §7 hook: creep intensity for one hive site, tweened over `seconds`.
func set_intensity(site_id: StringName, value: float, seconds: float = 2.0) -> void:
	for s in _sites:
		if s["id"] != site_id:
			continue
		s["target"] = clampf(value, 0.0, 1.0)
		s["rate"] = absf(float(s["target"]) - float(s["level"])) / maxf(seconds, 0.01)
		return
	push_warning("InfectionField: unknown site id '%s' (registered: %s)"
		% [site_id, str(_sites.map(func(s: Dictionary) -> String: return String(s["id"])))])


## Master creep level; the flow unit drops it to 0 when the infestation is cleared.
func set_master(value: float, seconds: float = 2.0) -> void:
	var target := clampf(value, 0.0, 1.0)
	create_tween().tween_method(_set_master_now, master, target, maxf(seconds, 0.01))


func _set_master_now(v: float) -> void:
	master = v
	RenderingServer.global_shader_parameter_set(&"mc_infection", master)


## The creep radius a site was registered with, after clamping. 0 for an unknown id.
func site_radius(site_id: StringName) -> float:
	for s in _sites:
		if s["id"] == site_id:
			return float(s["radius"])
	return 0.0


func site_level(site_id: StringName) -> float:
	for s in _sites:
		if s["id"] == site_id:
			return float(s["level"])
	return 0.0


func _process(delta: float) -> void:
	if _sites.is_empty():
		return
	var real := Feel.real_delta(delta)
	_time += real
	var dirty := false
	for s in _sites:
		if is_equal_approx(float(s["target"]), float(s["level"])):
			continue
		s["level"] = move_toward(float(s["level"]), float(s["target"]), float(s["rate"]) * real)
		dirty = true
	if dirty:
		_push_sites()
	RenderingServer.global_shader_parameter_set(&"mc_time", _time)


func _push_sites() -> void:
	var levels := Vector4.ZERO
	var names: Array[StringName] = [&"mc_hive0", &"mc_hive1", &"mc_hive2", &"mc_hive3"]
	for i in range(MAX_SITES):
		var slot := Vector4.ZERO
		if i < _sites.size():
			var p: Vector3 = _sites[i]["pos"]
			slot = Vector4(p.x, p.y, p.z, float(_sites[i]["radius"]))
			var comps: Array[float] = [levels.x, levels.y, levels.z, levels.w]
			comps[i] = float(_sites[i]["level"])
			levels = Vector4(comps[0], comps[1], comps[2], comps[3])
		RenderingServer.global_shader_parameter_set(names[i], slot)
	RenderingServer.global_shader_parameter_set(&"mc_hive_levels", levels)
