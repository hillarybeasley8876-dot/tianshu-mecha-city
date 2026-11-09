class_name SoftTextures
extends RefCounted
## Procedural particle textures (city-art). No downloaded art: a soft radial falloff for glow and
## dust, and a noise-broken puff for smoke and steam, both cached so every emitter shares one image.

const SIZE := 128
const PUFF_OCTAVES := 3

static var _cache: Dictionary = {}


static func radial(power: float = 2.0) -> Texture2D:
	var key := "radial_%0.2f" % power
	if _cache.has(key):
		return _cache[key]
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := float(SIZE - 1) * 0.5
	for y in range(SIZE):
		for x in range(SIZE):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := clampf(pow(1.0 - clampf(d, 0.0, 1.0), power), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return _store(key, img)


## A smoke puff: radial falloff broken up by value noise so a column does not read as blobs.
static func puff(seed: int = 1) -> Texture2D:
	var key := "puff_%d" % seed
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var offsets: Array[Vector2] = []
	for i in range(PUFF_OCTAVES):
		offsets.append(Vector2(rng.randf() * 64.0, rng.randf() * 64.0))
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := float(SIZE - 1) * 0.5
	for y in range(SIZE):
		for x in range(SIZE):
			var p := Vector2(float(x), float(y))
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var n := 0.0
			var amp := 0.6
			var freq := 0.045
			for i in range(PUFF_OCTAVES):
				n += _noise(p * freq + offsets[i]) * amp
				amp *= 0.5
				freq *= 2.1
			var a := clampf(1.0 - clampf(d, 0.0, 1.0), 0.0, 1.0)
			a = clampf(a * (0.35 + 1.1 * n) * smoothstep(1.0, 0.55, d), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return _store(key, img)


static func _store(key: String, img: Image) -> Texture2D:
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _hash(p: Vector2) -> float:
	var v := Vector2(p.x * 127.1 + p.y * 311.7, p.x * 269.5 + p.y * 183.3)
	var s := sin(v.x + v.y * 0.7) * 43758.5453
	return s - floor(s)


static func _noise(p: Vector2) -> float:
	var i := Vector2(floor(p.x), floor(p.y))
	var f := p - i
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := _hash(i)
	var b := _hash(i + Vector2(1.0, 0.0))
	var c := _hash(i + Vector2(0.0, 1.0))
	var d := _hash(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)
