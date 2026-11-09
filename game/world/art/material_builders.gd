class_name McMaterialBuilders
extends RefCounted
## The city material library's BUILDERS (city-art r16 §6): every function that constructs a
## `mc_*` material or one of its variants. Split out of `material_library.gd`; the cache and the push
## lists live in McMaterialState and the role data in McMaterialRoles.

## Flat unshaded identity colours, one per role (debug only).
static func debug_role(role: StringName) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(float(String(role).hash() % 1000) / 1000.0,
		float(String(role).hash() / 1000 % 1000) / 1000.0,
		float(String(role).hash() / 1000000 % 1000) / 1000.0)
	return m


static func build(role: StringName) -> Material:
	if McMaterialRoles.SURFACES.has(role):
		return McSurface.build(McMaterialRoles.SURFACES[role])
	match role:
		&"mc_window":
			return window()
		&"mc_glass":
			return glass()
		&"mc_road":
			return road_variant(&"avenue")
		&"mc_water":
			return water()
		&"mc_up_accent":
			return accent()
	return null


## Review r2: at dusk the lit cells are the strongest read in the image, so they carry a higher
## emission gain and a wider warm/cool mix (2,700 K interiors against 5,000 K office fluorescents).
## Review r3: 3.6 clipped to pure white at arm's length (flythrough frame 3700 — the left wall lost its
## mullions entirely) and it was also pushing V2/V3/V8 brighter than their key art. 2.6 keeps the
## distant read, which the `fwidth` dissolve now carries on its own.
static func window() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = McMaterialRoles.SH_WINDOW
	m.set_shader_parameter(&"warm", ArtPalette.WINDOW_WARM)
	m.set_shader_parameter(&"cool", ArtPalette.WINDOW_COOL)
	m.set_shader_parameter(&"dark_glass", ArtPalette.GLASS)
	# city-art r14: 2.6 clipped. Measured at the shipping default, every lit cell in the T1fac street
	# frame was at 255/255 and the lit windows were 9.8 % of it — the frame's brightest thing is
	# supposed to be the sun and the neon, not every office on the block. 1.5 still reads as a lit
	# window against the darker wall r14 gives it, and leaves headroom for the bloom to halo it.
	# r16b §4: 1.5 is still over the gate on the frames that are mostly facade — S04fight clipped 2.57 %
	# at tod 0 and 1.93 % at 0.5 on the lit cells alone (mean clipped colour (253, 153, 86), the warm
	# lamp), and T1fac 2.21 % at tod 1.0. The clip gate sits at about 1.66 linear (see mc_up_accent),
	# the lamp is 1.0 at gain 1.0, and the pane's own specular is what carries it over.
	m.set_shader_parameter(&"emission_gain", 1.15)
	m.set_shader_parameter(&"cool_chance", 0.22)
	return m


static func glass() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = McMaterialRoles.SH_GLASS
	m.set_shader_parameter(&"glass_color", ArtPalette.GLASS)
	m.set_shader_parameter(&"sheen_color", ArtPalette.WINDOW_COOL)
	return m


static func water() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = McMaterialRoles.SH_WATER
	m.set_shader_parameter(&"deep_color", ArtPalette.WATER)
	m.set_shader_parameter(&"shallow_color", ArtPalette.WATER.lerp(Color(0.5, 0.6, 0.6), 0.5))
	return m


static func accent() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = McMaterialRoles.SH_ACCENT
	m.set_shader_parameter(&"accent", ArtPalette.NEON_CYAN)
	return m


## Foliage for the dressing layers' planting: a two-tone leaf mass, unshaded at the top so a planter
## keeps a green read in a warm frame. COLOR.r is the per-instance hue jitter.
static var _foliage: ShaderMaterial = null

static func foliage() -> ShaderMaterial:
	if _foliage != null:
		return _foliage
	var m := ShaderMaterial.new()
	m.shader = McMaterialRoles.SH_FOLIAGE
	m.set_shader_parameter(&"leaf_a", ArtPalette.FOLIAGE)
	m.set_shader_parameter(&"leaf_b", ArtPalette.FOLIAGE_LIGHT)
	_foliage = m
	return m


## A tuned `mc_up_accent` variant, cached by key: the Spire's shaft strips want a steady climb while
## its ring edges want a near-solid glow (review r2 §5), and both are the same shader.
static func accent_variant(key: StringName, gain: float, steady: float,
		pulse_gain: float, axis: int) -> ShaderMaterial:
	var cache_key := StringName("mc_accent_" + String(key))
	var cached := McMaterialState.cached(cache_key) as ShaderMaterial
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = McMaterialRoles.SH_ACCENT
	m.set_shader_parameter(&"accent", ArtPalette.NEON_CYAN)
	m.set_shader_parameter(&"gain", gain)
	m.set_shader_parameter(&"steady", steady)
	m.set_shader_parameter(&"pulse_gain", pulse_gain)
	m.set_shader_parameter(&"axis", axis)
	McMaterialState.cache(cache_key, m)
	return m


## Road carriageway tuned per corridor kind. `kind` is MAP.md's street kind (avenue|street|alley).
static func road_variant(kind: StringName) -> ShaderMaterial:
	var key := StringName("mc_road_" + String(kind))
	var cached := McMaterialState.cached(key) as ShaderMaterial
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = McMaterialRoles.SH_ROAD
	m.set_shader_parameter(&"asphalt", ArtPalette.ROAD)
	match kind:
		&"street":
			m.set_shader_parameter(&"width_m", 44.0)
			m.set_shader_parameter(&"lane_count", 2)
			m.set_shader_parameter(&"crossing_every", 180.0)
		&"alley":
			m.set_shader_parameter(&"width_m", 28.0)
			m.set_shader_parameter(&"lane_count", 0)
			m.set_shader_parameter(&"paint_wear", 0.8)
			# Alleys drain badly, so they hold the most water — a bias over the city-wide `wet`.
			m.set_shader_parameter(&"wet_bias", 1.35)
		_:
			m.set_shader_parameter(&"width_m", 64.0)
			m.set_shader_parameter(&"lane_count", 4)
			m.set_shader_parameter(&"crossing_every", 240.0)
			m.set_shader_parameter(&"wet_bias", 0.85)
	McMaterialState.register(m)
	McMaterialState.cache(key, m)
	return m


## Hologram material for a projector-driven asset (koi dragon, billboards, projected signs).
static func hologram(color_b: Color = ArtPalette.NEON_MAGENTA,
		graphic: Texture2D = null) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = McMaterialRoles.SH_HOLOGRAM
	m.set_shader_parameter(&"color_a", ArtPalette.NEON_CYAN)
	m.set_shader_parameter(&"color_b", color_b)
	# city-art r14: the shader default of 2.2 on a white brand graphic put every holo billboard over
	# 248/255 — 2.6 % of the A3st street frame on one sign. A hologram has to read as a bright accent
	# against a darker wall (brief §5), not as the brightest thing in the city.
	m.set_shader_parameter(&"gain", 0.45)
	m.set_shader_parameter(&"fresnel_gain", 0.8)
	if graphic != null:
		m.set_shader_parameter(&"graphic", graphic)
		m.set_shader_parameter(&"use_graphic", 1.0)
	return m


## A neon blade sign (review r3 §2): the generated glyph strip on a dark backing plate, `unshaded` so it
## reads as self-luminous signage instead of a lit poster, and NOT fog-disabled — a blade is close-range
## dressing, and letting the built-in fog touch it keeps it sitting in the same air as the props.
static func sign_material(graphic: Texture2D, tint: Color) -> ShaderMaterial:
	var key := StringName("mc_sign_" + String(graphic.resource_name) + "_%d" % tint.to_rgba32())
	var cached := McMaterialState.cached(key) as ShaderMaterial
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = McMaterialRoles.SH_SIGN
	m.set_shader_parameter(&"graphic", graphic)
	m.set_shader_parameter(&"tint", tint)
	McMaterialState.cache(key, m)
	McMaterialState.register(m)
	return m


## A flat emissive band: shopfront glow at L1 and the parapet light lines on tower roofs (review r3 §2).
## Cached by colour+gain so the whole layer is two materials.
static func glow_band(tint: Color, gain: float) -> ShaderMaterial:
	var key := StringName("mc_band_%d_%d" % [tint.to_rgba32(), int(gain * 100.0)])
	var cached := McMaterialState.cached(key) as ShaderMaterial
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = McMaterialRoles.SH_BAND
	m.set_shader_parameter(&"tint", tint)
	m.set_shader_parameter(&"gain", gain)
	McMaterialState.cache(key, m)
	McMaterialState.register(m)
	return m


## The distant ring's own material (review r3 §3). `apply_skyline` finds city.gd's "Skyline" child and
## overrides every surface on it: the ring ships as one `mc_concrete` surface, which made it a lit wall.
static func skyline() -> ShaderMaterial:
	var m := skyline_variant(&"ring", 0.50)
	# A narrow depth response only: the ring is a field of blocks spread over ~400 m of radius, and a
	# wide distance term turns that real spread into a mosaic of pale rectangles (lead r4). Enough to
	# separate the near arc from the far one, not enough to stripe it.
	m.set_shader_parameter(&"haze_top", 0.95)
	m.set_shader_parameter(&"depth_lo", 0.92)
	m.set_shader_parameter(&"depth_hi", 1.10)
	# Explicit rather than inherited from the shader defaults: these are the numbers the r9 assertions
	# read back, and a default that moves in the shader should not silently move the ring.
	m.set_shader_parameter(&"band_gain", 0.30)
	m.set_shader_parameter(&"spark_m", 3.2)
	m.set_shader_parameter(&"spark_density", 0.030)
	m.set_shader_parameter(&"window_gain", 0.85)
	m.set_shader_parameter(&"edge_gain", 0.55)
	return m


## city-build's HLOD proxies. They render from 430 m, which is far closer than the 900 m ring the
## numbers above were tuned for, and they are merged block massing rather than a ring — so they need a
## lower haze floor (they are nearer), a denser sparkle (they are nearer) and almost no edge rim, or
## every merged facet lights its own corner (lead r4).
static func skyline_hlod() -> ShaderMaterial:
	var m := skyline_variant(&"hlod", 0.34)
	m.set_shader_parameter(&"spark_m", 3.8)
	m.set_shader_parameter(&"spark_density", 0.042)
	m.set_shader_parameter(&"window_gain", 0.70)
	m.set_shader_parameter(&"block_m", 55.0)
	m.set_shader_parameter(&"rim_gain", 0.34)
	m.set_shader_parameter(&"edge_gain", 0.26)
	m.set_shader_parameter(&"band_gain", 0.40)
	m.set_shader_parameter(&"depth_lo", 0.80)
	m.set_shader_parameter(&"depth_hi", 1.26)
	return m


## Cached by key. `haze_floor` is how much air even the NEAREST, LOWEST surface of this group sits in —
## the ring is 900 m out (0.50), while city-build's HLOD proxies start only ~430 m from the middle of
## the map and need a lower floor or they would vanish into the sky. `sky_band` is seeded from the
## pushed horizon colour, not from a constant: `mc_skyline` is the one material that carries `sky_band`
## WITHOUT `haze_near_amount`, so it rides the band list, not the haze list (review r9).
static func skyline_variant(key: StringName, haze_floor: float) -> ShaderMaterial:
	var cache_key := StringName("mc_skyline_" + String(key))
	var cached := McMaterialState.cached(cache_key) as ShaderMaterial
	if cached != null:
		return cached
	var m := ShaderMaterial.new()
	m.shader = McMaterialRoles.SH_SKYLINE
	m.set_shader_parameter(&"body", ArtPalette.SKYLINE_BODY)
	m.set_shader_parameter(&"rim", ArtPalette.SUN_COLOR)
	m.set_shader_parameter(&"sky_band", McMaterialState.haze_band())
	m.set_shader_parameter(&"haze_floor", haze_floor)
	McMaterialState.cache(cache_key, m)
	McMaterialState.register(m)
	return m
