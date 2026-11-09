class_name DecalTextures
extends RefCounted
## Procedural decal textures (feel unit). Generated once at load instead of shipping PNGs: the shapes
## are simple enough that a radial falloff plus value noise reads correctly as scorch, crater rim and
## bullet hole, and it keeps the repo free of binary art.

const SIZE := 128
const HOLE_SIZE := 64

static var _cache: Dictionary = {}


## Cached albedo texture for a decal kind (&"scorch", &"scorch_ring", &"land_crater", &"bullet_hole").
static func albedo(kind: StringName) -> Texture2D:
	if not _cache.has(kind):
		_cache[kind] = _make(kind)
	return _cache[kind]


static func _make(kind: StringName) -> Texture2D:
	match kind:
		&"scorch_ring":
			return _build(SIZE, _scorch_ring)
		&"land_crater":
			return _build(SIZE, _crater)
		&"bullet_hole":
			return _build(HOLE_SIZE, _hole)
		&"impact_glow":
			return _build(HOLE_SIZE, _glow)
	return _build(SIZE, _scorch)


static func _build(size: int, fn: Callable) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.frequency = 0.06
	noise.seed = 1337
	for y in size:
		for x in size:
			var uv := Vector2(float(x) / float(size - 1), float(y) / float(size - 1))
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			img.set_pixel(x, y, fn.call(uv, n))
	return ImageTexture.create_from_image(img)


## r = distance from the centre, 0..1 (1 at the inscribed circle edge).
static func _radius(uv: Vector2) -> float:
	return (uv - Vector2(0.5, 0.5)).length() * 2.0


static func _scorch(uv: Vector2, n: float) -> Color:
	var r := _radius(uv)
	var a := clampf(1.0 - r * (0.85 + n * 0.5), 0.0, 1.0)
	a = pow(a, 1.6) * (0.55 + n * 0.45)
	var c := Color(0.05, 0.045, 0.05).lerp(Color(0.16, 0.13, 0.11), n)
	return Color(c, clampf(a, 0.0, 1.0))


static func _scorch_ring(uv: Vector2, n: float) -> Color:
	var r := _radius(uv)
	var band := 1.0 - clampf(absf(r - 0.72) / 0.3, 0.0, 1.0)
	var a := pow(band, 1.4) * (0.5 + n * 0.5)
	var c := Color(0.06, 0.05, 0.05).lerp(Color(0.3, 0.16, 0.06), n * band)
	return Color(c, clampf(a, 0.0, 1.0))


static func _crater(uv: Vector2, n: float) -> Color:
	var r := _radius(uv)
	var floor_k := 1.0 - clampf(r / 0.72, 0.0, 1.0)
	var rim := 1.0 - clampf(absf(r - 0.8) / 0.22, 0.0, 1.0)
	var a := clampf(floor_k * 0.75 + rim * 0.6 * (0.6 + n * 0.4), 0.0, 1.0)
	var c := Color(0.09, 0.085, 0.08).lerp(Color(0.42, 0.4, 0.36), rim * n)
	return Color(c, clampf(pow(a, 1.3), 0.0, 1.0))


static func _hole(uv: Vector2, n: float) -> Color:
	var r := _radius(uv)
	var core := 1.0 - clampf(r / 0.45, 0.0, 1.0)
	var rim := 1.0 - clampf(absf(r - 0.6) / 0.35, 0.0, 1.0)
	var a := clampf(core + rim * 0.45 * (0.5 + n * 0.5), 0.0, 1.0)
	return Color(Color(0.04, 0.04, 0.05).lerp(Color(0.5, 0.45, 0.4), rim * 0.6), a)


## Hot glow left on the surface a shot just hit: a bright core fading through orange to nothing.
## Short-lived (DecalPool fades it out over ~0.25 s), so it reads as heat rather than a mark.
static func _glow(uv: Vector2, n: float) -> Color:
	var r := _radius(uv)
	var a := pow(clampf(1.0 - r * (0.92 + n * 0.16), 0.0, 1.0), 2.2)
	var c := Color(1.0, 0.86, 0.6).lerp(Color(1.0, 0.38, 0.08), clampf(r * 1.3, 0.0, 1.0))
	return Color(c * (0.75 + n * 0.5), a)
