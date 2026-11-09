class_name PostPresets
extends RefCounted
## Tuning table for the post stack. One row per `Settings.quality`, because the whole stack is
## load-time: toggling a CompositorEffect or its mip chain mid-game recompiles pipelines
## (godot-tech §4.6). Brief budget: high <= 2.5 ms, low <= 0.8 ms of the 16.6 ms frame.
##
## These rows are city-art's from r16 (lead decision: `world/post/**` belongs to this unit), and the
## grade / exposure rows below carry the reason they are where they are. They are applied to the
## Environment this stack binds, and `world/post/tests/test_post.gd` pins them:
##   exposure 0.66   — r14 cut it 0.72 -> 0.56 to stop the sunlit faces clipping and the streets went
##                     with it (A1yard median 0.02 against a key-art floor of 0.18). r15 put it back to
##                     0.66; 0.72 with `sky_ambient` 1.90 measured SIX clip-gate regressions, so 0.66
##                     is the ceiling the gate allows.
##   contrast 1.06 / saturation 1.10 — r15, measured on the value probe's sunlit and shaded masks.
##                     1.06 pairs with `PostGrade.pivot` 0.42: at r14's 1.22/0.52 the contrast curve's
##                     zero sat at luma 0.094 and two probe frames measured `p50 = 0.000`.
##
## city-art r14 (lead brief r14 §4, "the bright sky must not bloom across the city"): the threshold is
## in LINEAR HDR luminance, and a golden-hour sky sits at 1.5-4 there. At 0.85 the bright pass let the
## whole sky through, so the bloom was a second exposure rather than a halo — measured at the shipping
## default, 25 % of V7 and V8 and 36 % of the T1fac street frame were clipped to >= 248/255, against a
## gate of 1.5 %. 2.6 is above the sky and below the emitters (lit windows, neon, the tether, muzzle
## flashes), which is the brief's "only true emitters bloom". Shafts came down with it: at 0.38 they
## laid a wash over the whole upper frame and flattened it.

const PRESETS: Dictionary = {
	&"low": {
		# --- grade / exposure (Environment, replaces city-art's 16^3 split tone) ---
		&"exposure": 0.66, &"agx_white": 8.0, &"agx_contrast": 1.30,
		&"grade_strength": 1.0, &"saturation": 1.10, &"contrast": 1.06,
		# --- lens ---
		&"vignette": 0.20, &"fringe": 0.0, &"grain": 0.0, &"sharpen": 0.45,
		# --- bloom ---
		&"bloom": false, &"bloom_mips": 0, &"bloom_threshold": 2.6, &"bloom_knee": 0.25,
		&"bloom_strength": 0.0, &"streak": 0.0,
		# --- shafts / dof ---
		&"shafts": false, &"shaft_strength": 0.0, &"shaft_steps": 0,
		&"dof": false, &"dof_blur": 0.0,
	},
	&"medium": {
		&"exposure": 0.66, &"agx_white": 8.0, &"agx_contrast": 1.30,
		&"grade_strength": 1.0, &"saturation": 1.10, &"contrast": 1.06,
		&"vignette": 0.21, &"fringe": 0.7, &"grain": 0.012, &"sharpen": 0.55,
		&"bloom": true, &"bloom_mips": 4, &"bloom_threshold": 2.6, &"bloom_knee": 0.25,
		&"bloom_strength": 0.20, &"streak": 0.05,
		&"shafts": true, &"shaft_strength": 0.12, &"shaft_steps": 16,
		&"dof": true, &"dof_blur": 6.0,
	},
	&"high": {
		&"exposure": 0.66, &"agx_white": 8.0, &"agx_contrast": 1.30,
		&"grade_strength": 1.0, &"saturation": 1.10, &"contrast": 1.06,
		&"vignette": 0.22, &"fringe": 1.0, &"grain": 0.016, &"sharpen": 0.62,
		&"bloom": true, &"bloom_mips": 6, &"bloom_threshold": 2.6, &"bloom_knee": 0.25,
		&"bloom_strength": 0.22, &"streak": 0.06,
		&"shafts": true, &"shaft_strength": 0.14, &"shaft_steps": 24,
		&"dof": true, &"dof_blur": 8.0,
	},
}

## Keys every preset row must define; a missing one is a typo, not a taste call.
const REQUIRED: Array[StringName] = [
	&"exposure", &"agx_white", &"agx_contrast", &"grade_strength", &"saturation", &"contrast",
	&"vignette", &"fringe", &"grain", &"sharpen",
	&"bloom", &"bloom_mips", &"bloom_threshold", &"bloom_knee", &"bloom_strength", &"streak",
	&"shafts", &"shaft_strength", &"shaft_steps", &"dof", &"dof_blur",
]


## The row for the active `Settings.quality`, falling back to high (same rule as city-art's ArtQuality).
## A COPY: `PostStack.retune` writes grade rows for a look-dev sweep, and handing out the table itself
## would let one `--post-tune` run permanently rewrite the shipped presets.
static func get_preset(name: StringName = &"") -> Dictionary:
	var key := name
	if not PRESETS.has(key):
		var q := StringName(String(Settings.get_value(&"quality")))
		key = q if PRESETS.has(q) else &"high"
	return (PRESETS[key] as Dictionary).duplicate()


## Self-check used by the tests: every row carries every key, so a pass can index without a default.
static func rows_complete() -> bool:
	for key: StringName in PRESETS:
		var row: Dictionary = PRESETS[key]
		for need in REQUIRED:
			if not row.has(need):
				push_error("PostPresets: preset '%s' is missing '%s'" % [key, need])
				return false
	return true
