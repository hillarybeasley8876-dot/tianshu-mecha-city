class_name HoloGraphics
extends RefCounted
## Procedurally generated signage for the holograms and holo billboards (city-art, ART.md §4:
## "fictional Chinese/English brands — never real ones"). Everything is drawn from a seeded RNG as
## blocky stroke glyphs, so no font, no real brand and no downloaded texture is involved, and the
## same seed always yields the same sign (deterministic captures).

const WIDTH := 256
const HEIGHT := 512
const GLYPH := 48           ## one "character" cell, pixels


## A vertical shop sign: 4-6 blocky glyphs in a column, a latin strapline and a border.
static func shop_sign(seed: int, tint: Color = ArtPalette.NEON_CYAN) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var margin := 18
	_frame(img, Rect2i(margin, margin, WIDTH - margin * 2, HEIGHT - margin * 2), tint * 0.85, 4)
	var rows := rng.randi_range(4, 6)
	var cell := float(HEIGHT - margin * 4) / float(rows)
	for r in range(rows):
		var box := Rect2i(WIDTH / 2 - int(cell * 0.4), margin * 2 + int(cell * float(r)),
			int(cell * 0.8), int(cell * 0.8))
		_glyph(img, box, rng, tint)
	# Latin strapline: a row of short bars that reads as type at billboard distance.
	var y := HEIGHT - margin - 26
	var x := margin + 12
	while x < WIDTH - margin - 12:
		var w := rng.randi_range(8, 22)
		_block(img, Rect2i(x, y, w, 12), tint * 0.7)
		x += w + rng.randi_range(6, 12)
	return ImageTexture.create_from_image(img)


## A wide billboard face: a big glyph block, a colour band and a bar "paragraph".
static func billboard(seed: int, tint: Color = ArtPalette.NEON_MAGENTA) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create_empty(512, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_block(img, Rect2i(0, 0, 512, 10), tint)
	_block(img, Rect2i(0, 246, 512, 10), tint * 0.6)
	for i in range(rng.randi_range(2, 3)):
		_glyph(img, Rect2i(24 + i * 118, 30, 100, 100), rng, tint)
	for r in range(4):
		var w := rng.randi_range(160, 420)
		_block(img, Rect2i(24, 150 + r * 22, w, 12), tint * 0.75)
	return ImageTexture.create_from_image(img)


## One blocky "character": a random set of horizontal and vertical strokes inside the cell.
static func _glyph(img: Image, box: Rect2i, rng: RandomNumberGenerator, tint: Color) -> void:
	var strokes := rng.randi_range(3, 6)
	for s in range(strokes):
		var horizontal := rng.randf() < 0.55
		var thickness := maxi(3, int(float(box.size.x) * 0.12))
		if horizontal:
			var w := rng.randi_range(int(float(box.size.x) * 0.45), box.size.x)
			var y := box.position.y + rng.randi_range(0, maxi(box.size.y - thickness, 1))
			_block(img, Rect2i(box.position.x, y, w, thickness), tint)
		else:
			var h := rng.randi_range(int(float(box.size.y) * 0.45), box.size.y)
			var x := box.position.x + rng.randi_range(0, maxi(box.size.x - thickness, 1))
			_block(img, Rect2i(x, box.position.y, thickness, h), tint)


static func _block(img: Image, r: Rect2i, c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(maxi(r.position.y, 0), mini(r.position.y + r.size.y, h)):
		for x in range(maxi(r.position.x, 0), mini(r.position.x + r.size.x, w)):
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))


static func _frame(img: Image, r: Rect2i, c: Color, thickness: int) -> void:
	_block(img, Rect2i(r.position.x, r.position.y, r.size.x, thickness), c)
	_block(img, Rect2i(r.position.x, r.position.y + r.size.y - thickness, r.size.x, thickness), c)
	_block(img, Rect2i(r.position.x, r.position.y, thickness, r.size.y), c)
	_block(img, Rect2i(r.position.x + r.size.x - thickness, r.position.y, thickness, r.size.y), c)
