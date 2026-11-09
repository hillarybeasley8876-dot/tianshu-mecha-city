class_name PostGrade
extends RefCounted
## The filmic grade LUT (post-render unit, brief §1). A 32^3 colour-correction cube handed to
## `Environment.adjustment_color_correction`, which Godot samples on the **tonemapped linear** image just
## before the sRGB encode — so all the maths below happens in sRGB (perceptual), and every entry is
## converted back to linear on the way out. Working in linear is what makes hand-built LUTs look wrong.
##
## Two grades, blended by `TimeOfDay.progress`: golden dusk (ART.md §2/§3 — gold highlights, cool
## violet-teal shadows) and storm (progress >= 0.66, the Crown: violet shadows, desaturated highlights).
## Fitted by eye against `art/concept/keyart/{v1_pier,v2_canyon,v8_crown}-1.png`, not derived from them.

const SIZE := 32
## Rebuilding the whole cube costs 2.2 ms, so it only happens when the ramp has actually moved.
const REBUILD_EPS := 0.005
## ART.md §3 escalation: violet is the storm's, and it arrives over the last third of the mission.
const STORM_FROM := 0.66
## Where the highlight desaturation starts, and how far it goes. Keeps a bright warm sky from clipping
## into one flat orange field, which is what the engine tonemap alone leaves behind.
const HIGHLIGHT_ROLL := 0.78
const HIGHLIGHT_DESAT := 0.45
## Weight of the smoothstep half of the S-curve; the linear part does most of the work.
const S_CURVE_MIX := 0.25
## The storm end of the ramp (ART.md §2: violet is reserved for the Crown). Not just "more blue": dusk
## shadows are TEAL, and a storm that only deepens the blue still reads teal. Green has to come down for
## the hue to turn violet, so the shadow gain drops G hard and lifts R above it.
const STORM_SHADOW := Vector3(0.98, 0.76, 1.30)
const STORM_HIGH := Vector3(1.06, 0.94, 1.10)
const STORM_LIFT := Vector3(0.020, 0.008, 0.046)
## Saturation under the storm. Pulled back, but not so far that it cancels the violet split tone above —
## at 0.86 it did exactly that and the storm read identical to dusk in the shadows.
const STORM_DESAT := 0.94

## Overridable by `--post-tune=grade_pivot:0.5,grade_shadow:8a90ff,...` so an A/B sweep does not need a
## code edit per candidate. Production values are the defaults below.
## city-art r15: 0.52 with `contrast` 1.22 put the curve's zero at luma 0.094 — everything below that
## was clipped to black, and since the lift is applied BEFORE the curve a lifted black stayed black.
## Two probe frames at `--tod=0.6` measured `p50 = 0.000`: half the frame was exactly zero, which is
## what "the hero and the enemies read as black blobs" is. 0.42 with contrast 1.06 puts the zero at
## 0.024 and keeps the S-curve's shape. Measured: V1 `shd_p50` 0.029 -> 0.072, clip 0.36 -> 0.16 %.
var pivot: float = 0.42
var shadow_gain := Vector3(0.82, 0.92, 1.26)
var high_gain := Vector3(1.10, 1.00, 0.84)
## city-art r14: the exposure came down 0.72 -> 0.56 to stop the sunlit faces clipping, and the streets
## came down with it (the A1yard frame's median fell to 0.02 against a key-art floor of 0.18). The lift
## is the right lever for that: it raises the darks only, so the highlights the gate measures do not
## move. It also keeps the shadow tint the split-tone wants.
var lift := Vector3(0.034, 0.024, 0.052)
var shadow_span := Vector2(0.02, 0.50)
var high_span := Vector2(0.52, 0.98)

var texture: Texture3D = null
var built_progress: float = -1.0


## `--post-tune=grade_shadow:8a90ff` — hex colours are read as the multiplier/lift triples.
func override(key: String, raw: String) -> bool:
	if raw.is_valid_float():
		match key:
			&"grade_pivot": pivot = float(raw)
			&"grade_shadow_lo": shadow_span.x = float(raw)
			&"grade_shadow_hi": shadow_span.y = float(raw)
			&"grade_high_lo": high_span.x = float(raw)
			&"grade_high_hi": high_span.y = float(raw)
			_: return false
		return true
	var c := Color(raw)
	match key:
		&"grade_shadow": shadow_gain = Vector3(c.r, c.g, c.b)
		&"grade_high": high_gain = Vector3(c.r, c.g, c.b)
		&"grade_lift": lift = Vector3(c.r, c.g, c.b)
		_: return false
	return true


## The cube for this progress, rebuilt only when the ramp moved. Returns the same texture object every
## time (updated in place) so the Environment never sees a resource swap.
func texture_for(progress: float, preset: Dictionary) -> Texture3D:
	if texture != null and absf(progress - built_progress) < REBUILD_EPS:
		return texture
	built_progress = progress
	var slices := _slices(progress, preset)
	if texture == null:
		texture = ImageTexture3D.new()
		if texture.create(Image.FORMAT_RGB8, SIZE, SIZE, SIZE, false, slices) != OK:
			push_error("PostGrade: could not create the %d^3 grade cube" % SIZE)
			texture = null
			built_progress = -1.0
			return null
	else:
		texture.update(slices)
	return texture


func _slices(progress: float, preset: Dictionary) -> Array[Image]:
	var storm := storm_at(progress)
	var contrast := float(preset.get(&"contrast", 1.30))
	var saturation := float(preset.get(&"saturation", 1.10))
	var strength := float(preset.get(&"grade_strength", 1.0))
	var n := SIZE
	var slices: Array[Image] = []
	slices.resize(n)
	var inv := 1.0 / float(n - 1)
	for z in n:
		var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
		for y in n:
			for x in n:
				var out := apply(Vector3(float(x), float(y), float(z)) * inv, storm, contrast,
						saturation, strength)
				img.set_pixel(x, y, Color(out.x, out.y, out.z, 1.0))
		slices[z] = img
	return slices


## Storm weight for a TimeOfDay progress (0 = mission start, 1 = boss).
static func storm_at(progress: float) -> float:
	return smoothstep(STORM_FROM, 1.0, clampf(progress, 0.0, 1.0))


## One cube entry. `c` is linear 0..1; the returned value is linear 0..1.
##
## Every operation is hue-preserving on purpose. A per-channel contrast (the obvious way to write this)
## drives whichever channel is already largest into the clamp first and posterises a warm frame into
## red/blue bands — which is exactly what the first version of this file did to V2. So the split tone is
## applied as a **luma-normalised** gain (it shifts hue without changing brightness), the contrast is a
## curve on luminance that the colour is then scaled by, and the highlights desaturate on the way up the
## way film does.
func apply(c: Vector3, storm: float, contrast: float, saturation: float,
		strength: float) -> Vector3:
	var s := Vector3(_to_srgb(c.x), _to_srgb(c.y), _to_srgb(c.z))
	var original := s

	# --- split tone ---------------------------------------------------------------------------
	var sg := _neutral(shadow_gain.lerp(Vector3(0.80, 0.84, 1.32), storm))
	var hg := _neutral(high_gain.lerp(Vector3(1.06, 0.94, 1.10), storm))
	var lf := lift.lerp(STORM_LIFT, storm)
	var lum := _luma(s)
	var shadow_w := 1.0 - smoothstep(shadow_span.x, shadow_span.y, lum)
	var high_w := smoothstep(high_span.x, high_span.y, lum)
	var tone := Vector3.ONE.lerp(sg, shadow_w) * Vector3.ONE.lerp(hg, high_w)
	s = s * tone + lf * shadow_w * (1.0 - storm * 0.25)

	# --- contrast on luminance, colour scaled by the ratio ------------------------------------
	var k := lerpf(contrast, contrast + 0.12, storm)
	var v := _curve(_luma(s), k, pivot)
	s = s * (v / maxf(_luma(s), 1e-4))

	# --- saturation, then a filmic desaturation of the highlights ------------------------------
	var sat := lerpf(saturation, saturation * STORM_DESAT, storm)
	s = Vector3(v, v, v).lerp(s, sat)
	s = s.lerp(Vector3(v, v, v), smoothstep(HIGHLIGHT_ROLL, 1.0, v) * HIGHLIGHT_DESAT)
	# strength 0 is an exact identity, so a preset can drop the grade without a second code path.
	s = original.lerp(s, clampf(strength, 0.0, 1.0))
	return Vector3(_to_linear(clampf(s.x, 0.0, 1.0)), _to_linear(clampf(s.y, 0.0, 1.0)),
			_to_linear(clampf(s.z, 0.0, 1.0)))


static func _luma(c: Vector3) -> float:
	return maxf(c.dot(Vector3(0.2126, 0.7152, 0.0722)), 0.0)


## Divides a tint by its own luminance, so multiplying by it shifts hue and leaves brightness alone.
static func _neutral(tint: Vector3) -> Vector3:
	return tint / maxf(_luma(tint), 1e-4)


static func _curve(v: float, k: float, pivot: float) -> float:
	var x := clampf((v - pivot) * k + pivot, 0.0, 1.0)
	return lerpf(x, x * x * (3.0 - 2.0 * x), S_CURVE_MIX)


static func _to_srgb(c: float) -> float:
	return 12.92 * c if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


static func _to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)
