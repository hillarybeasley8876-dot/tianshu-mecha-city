class_name McMaterials
extends RefCounted
## The city material library (city-art). The public API every other unit calls: the 12 `mc_*` roles
## city-build's blockout references BY NAME (blender/city/kit/roles.py), plus the load-time defaults of
## every global shader parameter the art shaders read. One process-wide instance per role; materials
## are shared.
##
## city-art r16 §6 split the 659-line file along its seams, with identical behaviour: the data is
## McMaterialRoles, the cache and the TimeOfDay pushes are McMaterialState, the builders are
## McMaterialBuilders, and this file keeps the API and the three `apply_*` passes that walk a scene.

const ROLE_NAMES: Array[StringName] = McMaterialRoles.ROLE_NAMES
const SURFACES: Dictionary = McMaterialRoles.SURFACES
const NO_DETAIL := McMaterialRoles.NO_DETAIL


## Pushes this unit's load-time defaults into the declared globals. Safe to call any number of times.
static func ensure_globals() -> void:
	McMaterialState.ensure_globals()


## The one accessor: `McMaterials.get_material(&"mc_stone")`. Builds and caches on first use.
## With `--art-debug=roles` every role returns a flat unshaded colour instead, which is how we check
## that city-build's tile geometry actually carries the role we think it does.
static func get_material(role: StringName) -> Material:
	ensure_globals()
	var cached := McMaterialState.cached(role)
	if cached != null:
		return cached
	var mat: Material = null
	if Game.flag("art-debug") == "roles":
		mat = McMaterialBuilders.debug_role(role)
	else:
		mat = McMaterialBuilders.build(role)
	if mat == null:
		push_error("McMaterials: unknown material role '%s'" % role)
		mat = StandardMaterial3D.new()
	else:
		McMaterialState.register(mat as ShaderMaterial)
	McMaterialState.cache(role, mat)
	return mat


## A one-off `mc_surface` for a dressing layer: the named role's spec with `over` merged over it. The
## layers need the SAME material the city uses (so the haze, facade mask and wetness pushes reach
## them) but not always its exact tuning — an arena cover wall wants a 2.4 m panel module and heavier
## grime than a tower facade, and it must not carry a facade window grid at all. `over` may set
## `facade: 0.0` to switch that off. Not cached: a caller that wants a shared instance keeps its own.
static func surface_variant(role: StringName, over: Dictionary = {}) -> ShaderMaterial:
	var spec: Dictionary = (SURFACES.get(role, {}) as Dictionary).duplicate()
	for k in over:
		spec[k] = over[k]
	var mat := McSurface.build(spec)
	McMaterialState.register(mat)
	return mat


## Foliage for the dressing layers' planting (see McMaterialBuilders.foliage).
static func foliage() -> ShaderMaterial:
	return McMaterialBuilders.foliage()


## A tuned `mc_up_accent` variant, cached by key (see McMaterialBuilders.accent_variant).
static func accent_variant(key: StringName, gain: float, steady: float,
		pulse_gain: float, axis: int) -> ShaderMaterial:
	return McMaterialBuilders.accent_variant(key, gain, steady, pulse_gain, axis)


## Road carriageway tuned per corridor kind. `kind` is MAP.md's street kind (avenue|street|alley).
static func road_variant(kind: StringName) -> ShaderMaterial:
	return McMaterialBuilders.road_variant(kind)


## Hologram material for a projector-driven asset (koi dragon, billboards, projected signs).
static func hologram(color_b: Color = ArtPalette.NEON_MAGENTA,
		graphic: Texture2D = null) -> ShaderMaterial:
	return McMaterialBuilders.hologram(color_b, graphic)


## A neon blade sign (review r3 §2), cached by graphic + tint.
static func sign_material(graphic: Texture2D, tint: Color) -> ShaderMaterial:
	return McMaterialBuilders.sign_material(graphic, tint)


## A flat emissive band: shopfront glow at L1 and the parapet light lines on tower roofs (review r3 §2).
static func glow_band(tint: Color, gain: float) -> ShaderMaterial:
	return McMaterialBuilders.glow_band(tint, gain)


## The distant ring's own material (review r3 §3), and city-build's HLOD proxies.
static func skyline() -> ShaderMaterial:
	return McMaterialBuilders.skyline()


static func skyline_hlod() -> ShaderMaterial:
	return McMaterialBuilders.skyline_hlod()


static func skyline_variant(key: StringName, haze_floor: float) -> ShaderMaterial:
	return McMaterialBuilders.skyline_variant(key, haze_floor)


## city-kit (lead 12:10 PRIORITY, user feedback "场景和搭积木有什么区别"): the skin for the Tripo
## architecture kit. `src` is a material as Godot imported it from `world/kit/<id>/<id>.glb`; what
## comes back carries the kit's own textures plus this unit's haze, lit-window layer and infection
## creep, so a modelled building sits in the same atmosphere as the blockout it stands on.
## Cached per source material, so a model placed on twelve tiles is still one material.
## See `kit_material.gd` for the `opts` the window layer takes.
static func kit(src: BaseMaterial3D, opts: Dictionary = {}) -> Material:
	ensure_globals()
	var mat := McKitSkin.skin(src, opts)
	if mat is ShaderMaterial:
		McMaterialState.register(mat as ShaderMaterial)
	return mat


## Adds a material built outside this file (a dressing layer's own shader) to the same push lists every
## city surface is on, so a haze ramp or a wetness change reaches it too.
static func register(mat: ShaderMaterial) -> void:
	McMaterialState.register(mat)


static func set_facade_mask(tex: Texture2D) -> void:
	McMaterialState.set_facade_mask(tex)


static func set_haze(near: Color, near_amount: float, far: Color, far_amount: float,
		band: Color, gain: float) -> void:
	McMaterialState.set_haze(near, near_amount, far, far_amount, band, gain)


static func set_wetness(amount: float) -> void:
	McMaterialState.set_wetness(amount)


static func set_sun(dir: Vector3, face_kill: float) -> void:
	McMaterialState.set_sun(dir, face_kill)


static func set_sky_tint(horizon: Color, zenith: Color) -> void:
	McMaterialState.set_sky_tint(horizon, zenith)


static func set_detail_distance(metres: float, triplanar_m: float = -1.0) -> void:
	McMaterialState.set_detail_distance(metres, triplanar_m)


static func sun() -> Dictionary:
	return McMaterialState.sun()


static func sky_tint() -> Dictionary:
	return McMaterialState.sky_tint()


static func wetness() -> float:
	return McMaterialState.wetness()


static func triplanar_distance() -> float:
	return McMaterialState.triplanar_distance()


static func detail_distance() -> float:
	return McMaterialState.detail_distance()


## How many materials are listening to the mask / haze / horizon-band / wetness pushes (evidence for
## the status file, and the assertion that keeps the r9 `sky_band` bug from coming back silently).
static func registered() -> Dictionary:
	return McMaterialState.registered()


## Replaces every surface in `root` whose material is named `mc_<role>` with this library's version of
## that role. city-build exports its tiles carrying the 12 role NAMES with flat blockout colours
## (blender/city/kit/roles.py), so this is the whole hand-off: the blockout reads warm from Blender,
## and the real materials arrive by name with no per-tile work.
## Returns the number of surfaces replaced; unknown `mc_*` names are reported, never skipped quietly.
static func apply_to(root: Node) -> int:
	ensure_globals()
	var replaced := 0
	var unknown: Dictionary = {}
	for mi in _mesh_instances(root):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(s)
			if mat == null:
				continue
			var role := StringName(mat.resource_name)
			if not String(role).begins_with("mc_"):
				continue
			if not ROLE_NAMES.has(role):
				unknown[role] = int(unknown.get(role, 0)) + 1
				continue
			mi.set_surface_override_material(s, get_material(role))
			replaced += 1
	for role in unknown:
		push_warning("McMaterials: %d surfaces use unknown role '%s' — add it to ROLE_NAMES"
			% [unknown[role], role])
	if replaced == 0:
		push_warning("McMaterials.apply_to: no mc_* surfaces found under %s" % root.name)
	return replaced


## The convenience pass city-kit can call instead of walking the meshes itself: replaces every surface
## under `root` that is NOT already one of city-build's `mc_*` roles with `kit()` of its own material.
## Returns the surfaces changed, so a caller can assert the kit actually landed.
static func apply_kit(root: Node, opts: Dictionary = {}) -> int:
	var changed := 0
	for mi in _mesh_instances(root):
		var mesh := mi.mesh
		if mesh == null:
			continue
		# The window grid is measured up from the model's own base. city-kit pivots at the footprint's
		# base centre, but taking the AABB's min y costs nothing and keeps a centred pivot from putting
		# the podium line halfway up the tower.
		var local := opts.duplicate()
		local["base_y"] = mesh.get_aabb().position.y
		for s in range(mesh.get_surface_count()):
			var src := mesh.surface_get_material(s)
			if src == null or not src is BaseMaterial3D:
				continue
			if String(src.resource_name).begins_with("mc_"):
				continue
			mi.set_surface_override_material(s, kit(src as BaseMaterial3D, local))
			changed += 1
	if changed == 0:
		push_warning("McMaterials.apply_kit: no imported surfaces under %s" % root.name)
	return changed


## Replaces every surface under `root` with `mat`. Returns the surfaces changed.
static func apply_skyline(root: Node, mat: Material = null) -> int:
	ensure_globals()
	var material: Material = mat if mat != null else skyline()
	var changed := 0
	for mi in _mesh_instances(root):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in range(mesh.get_surface_count()):
			mi.set_surface_override_material(s, material)
			changed += 1
	if changed == 0:
		push_warning("McMaterials.apply_skyline: no surfaces under %s" % root.name)
	return changed


static func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		stack.append_array(n.get_children())
	return out
