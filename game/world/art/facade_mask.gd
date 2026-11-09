class_name FacadeMask
extends RefCounted
## Top-down "what is this column of the city?" map (city-art, review r3 §1).
##
## The `mc_*` roles are city-build's contract and one role covers a whole 200 m tile, so a shader
## cannot tell a tower facade from a viaduct parapet by material alone — both are `mc_concrete`.
## This rasterises the DESIGN layout's building footprints into a small RGBA image that every facade
## material samples by world XZ:
##   R = inside a building footprint (0/1)
##   G = tier C/D, i.e. the curtain-wall towers
##   B = base_z / 64 (so a facade knows where its own podium ends)
##   A = per-building hash, the seed for its window pattern
## Resolution only has to separate buildings, not resolve them: every texel of one wall carries the
## same value, so 512 over the 1.4 km map (2.7 m/texel) is exact where it matters and costs ~50 k
## pixel writes at load.

const SIZE := 512
const HALF := 700.0                    ## map bounds half-extent (city_layout.json meta.bounds.half)
const SPAN := HALF * 2.0
const BASE_SCALE := 64.0               ## metres encoded in the blue channel
const TIERS_CURTAIN: Array[String] = ["C", "D"]

var texture: ImageTexture = null
var buildings: int = 0
var walls: int = 0              ## podium escarpments rasterised on top of the footprints


## Rasterises `design["buildings"]`, then the runtime layout's `podium_walls`. Returns the texture
## (also kept in `texture`).
func build(design: Dictionary, runtime: Dictionary = {}) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * 4)
	var px := 1.0 / float(SIZE)
	for b in design.get("buildings", []):
		if _raster_building(data, b as Dictionary, px):
			buildings += 1
	# city-build r3 exports the megablock podium escarpments (the canyon walls at A4, the terraces at
	# A6). They carry no design-time footprint, so the canyon was blank at eye level: a 32 m wall of
	# flat concrete right where the player fights. They are tier B masonry, punched windows, no curtain.
	for w in runtime.get("podium_walls", []):
		var wall := (w as Dictionary).duplicate()
		wall["tier"] = "B"
		wall["id"] = String(wall.get("id", "podium_wall"))
		wall["rot"] = float(wall.get("yaw_deg", 0.0))
		if _raster_building(data, wall, px):
			walls += 1
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
	texture = ImageTexture.create_from_image(img)
	return texture


## One rotated footprint, scanline-filled. Returns false when the row is degenerate.
func _raster_building(data: PackedByteArray, b: Dictionary, px: float) -> bool:
	var centre: Array = b.get("center", [0.0, 0.0])
	var size: Array = b.get("size", [10.0, 10.0])
	var half := Vector2(float(size[0]) * 0.5, float(size[1]) * 0.5)
	if half.x < 1.0 or half.y < 1.0:
		return false
	# Blender XY -> Godot XZ mirrors Y, so the footprint rotation flips sense with it.
	var rot := -deg_to_rad(float(b.get("rot", 0.0)))
	var org := Vector2(float(centre[0]), -float(centre[1]))
	var tier := String(b.get("tier", "B"))
	var curtain := 255 if TIERS_CURTAIN.has(tier) else 0
	var base := clampi(int(float(b.get("base_z", 0.0)) / BASE_SCALE * 255.0), 0, 255)
	var hash_byte := int(abs(String(b.get("id", "")).hash())) % 256

	# Bounding box in texel space, then a point-in-rotated-rect test per texel centre.
	var extent := absf(half.x * cos(rot)) + absf(half.y * sin(rot))
	var extent_z := absf(half.x * sin(rot)) + absf(half.y * cos(rot))
	var lo := _texel(org - Vector2(extent, extent_z))
	var hi := _texel(org + Vector2(extent, extent_z))
	var inv := Vector2(cos(-rot), sin(-rot))
	for ty in range(maxi(lo.y, 0), mini(hi.y + 1, SIZE)):
		for tx in range(maxi(lo.x, 0), mini(hi.x + 1, SIZE)):
			var d := Vector2(float(tx) * px * SPAN - HALF, float(ty) * px * SPAN - HALF) - org
			var local := Vector2(d.x * inv.x - d.y * inv.y, d.x * inv.y + d.y * inv.x)
			if absf(local.x) > half.x or absf(local.y) > half.y:
				continue
			var o := (ty * SIZE + tx) * 4
			data[o] = 255
			data[o + 1] = curtain
			data[o + 2] = base
			data[o + 3] = hash_byte
	return true


func _texel(p: Vector2) -> Vector2i:
	return Vector2i(int((p.x + HALF) / SPAN * float(SIZE)), int((p.y + HALF) / SPAN * float(SIZE)))
