extends Node
## post-render unit test (world/post/tests/test_post.gd). Head-less, so there is no RenderingDevice and
## the four CompositorEffects disable themselves — what is testable here is everything the stack decides
## before the GPU: the preset rows, which effects a preset builds, the grade cube (including the storm
## blend), the accessibility keys, and the Environment rows the stack owns.
## The GPU side is evidenced by captures and `world/post/tests/isolated.tscn`.
## Run: tools/godot.sh test res://world/post/tests/test_post.gd

## The shipped grade rows, PINNED here so a tuning pass cannot move them silently. They are city-art's
## from r16 (lead decision: `world/post/**` is this unit's) and each number carries its reason:
##   exposure 0.66   — r14 cut it 0.72 -> 0.56 to stop the sunlit faces clipping, and the streets went
##                     with it (A1yard median 0.02 against a key-art floor of 0.18). r15 put it back to
##                     0.66 once the sky exposure and the ambient carried the darks; r15 §5.2 measured
##                     0.72 with sky_ambient 1.90 as SIX clip-gate regressions, so 0.66 is the ceiling
##                     the clip gate allows.
##   contrast 1.06   — with pivot 0.42 (below). At r14's 1.22/0.52 the curve's zero sat at luma 0.094.
##   saturation 1.10 — r15, measured on the probe's lit/shade masks.
##   pivot 0.42      — `PostGrade._curve` is `clamp((v - pivot) * k + pivot, 0, 1)`, so the pivot IS the
##                     black point: at 0.52/1.22 everything below luma 0.094 became exactly zero, and
##                     the lift is applied BEFORE the curve, so a lifted black stayed black. Two probe
##                     frames at --tod=0.6 measured p50 = 0.000 — half the frame literally zero, which is
##                     what "the hero and the enemies read as black blobs" was. `TOE_FLOOR` below is the
##                     check that keeps that from coming back.
const SHIPPED_EXPOSURE := 0.66
const SHIPPED_CONTRAST := 1.06
const SHIPPED_SATURATION := 1.10
const SHIPPED_PIVOT := 0.42
## The darkest a lifted black may get, as an sRGB luma (0.002 is ~0.5/255). The shipped row measures
## 0.0033; r14's pivot 0.52 / contrast 1.22 measures exactly 0.000.
const TOE_FLOOR := 0.002
## r14's pair, kept so the toe check can prove it has teeth inside this suite.
const R14_PIVOT := 0.52
const R14_CONTRAST := 1.22

const STACK := preload("res://world/post/post_stack.tscn")


## Stands in for city-art's TimeOfDay: the stack only relies on the `&"time_of_day"` group, a
## `WorldEnvironment` + `Sun` child and a `progress` property (CONTRACTS §7).
class FakeTimeOfDay:
	extends Node3D
	var progress: float = 0.0


var _failures: int = 0
var _stack: PostStack


func _ready() -> void:
	_check_presets()
	_check_grade()
	var env := _fake_environment()
	_check_stack(env)
	_check_settings(env)
	print("POST TEST %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## Channel `a` over channel `b` — the hue ratio, independent of level.
func _hue(c: Vector3, a: int, b: int) -> float:
	return c[a] / maxf(c[b], 1e-5)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL ", what)


func _check_presets() -> void:
	_expect(PostPresets.rows_complete(), "every preset row carries every key")
	for name: StringName in [&"low", &"medium", &"high"]:
		var row := PostPresets.get_preset(name)
		_expect(is_equal_approx(float(row[&"exposure"]), SHIPPED_EXPOSURE),
				"%s exposure is the shipped %.2f, got %.3f"
				% [name, SHIPPED_EXPOSURE, float(row[&"exposure"])])
		_expect(is_equal_approx(float(row[&"contrast"]), SHIPPED_CONTRAST),
				"%s contrast is the shipped %.2f, got %.3f"
				% [name, SHIPPED_CONTRAST, float(row[&"contrast"])])
		_expect(is_equal_approx(float(row[&"saturation"]), SHIPPED_SATURATION),
				"%s saturation is the shipped %.2f, got %.3f"
				% [name, SHIPPED_SATURATION, float(row[&"saturation"])])
		_expect(float(row[&"bloom_strength"]) >= 0.0, "%s bloom strength is sane" % name)
	# The low preset must be the cheap one in every dimension the brief budgets.
	var low := PostPresets.get_preset(&"low")
	var high := PostPresets.get_preset(&"high")
	_expect(not bool(low[&"bloom"]), "low runs no compute bloom")
	_expect(not bool(low[&"shafts"]), "low runs no sun shafts")
	_expect(not bool(low[&"dof"]), "low runs no depth of field")
	_expect(int(low[&"bloom_mips"]) < int(high[&"bloom_mips"]), "low has fewer bloom mips than high")
	_expect(float(low[&"sharpen"]) <= float(high[&"sharpen"]), "low sharpens no harder than high")
	_expect(PostPresets.get_preset(&"nonsense") == PostPresets.get_preset(), "unknown preset falls back")


## The grade cube: 32^3, cool in the shadows, gold in the highlights, darker and more violet with the
## storm. These are the properties the key art depends on, checked numerically so a refactor cannot
## quietly soften them — and checked at the SHIPPED contrast, saturation and pivot, which is what the
## r16 review found this suite was not doing (it ran post-render's first row, 1.32 / 1.06).
func _check_grade() -> void:
	var g := PostGrade.new()
	var preset := PostPresets.get_preset(&"high")
	var contrast := float(preset[&"contrast"])
	var saturation := float(preset[&"saturation"])
	_expect(is_equal_approx(g.pivot, SHIPPED_PIVOT),
			"the grade pivot is the shipped %.2f, got %.3f" % [SHIPPED_PIVOT, g.pivot])
	var tex := g.texture_for(0.0, preset)
	_expect(tex != null, "the dusk cube builds")
	if tex != null:
		_expect(tex.get_width() == PostGrade.SIZE, "the cube is %d^3" % PostGrade.SIZE)
	var dark := g.apply(Vector3(0.06, 0.06, 0.06), 0.0, contrast, saturation, 1.0)
	_expect(dark.z > dark.x, "dusk shadows are cool (blue above red)")
	var bright := g.apply(Vector3(0.72, 0.72, 0.72), 0.0, contrast, saturation, 1.0)
	_expect(bright.x > bright.z, "dusk highlights are warm (red above blue)")
	# The property is the HUE, not the level: the storm also raises contrast and drops saturation, so no
	# single channel is simply "bigger". Dusk shadows are TEAL; the storm has to turn them VIOLET, which
	# means red climbing above green as well as blue staying above both.
	var storm_dark := g.apply(Vector3(0.06, 0.06, 0.06), 1.0, contrast, saturation, 1.0)
	_expect(_hue(storm_dark, 0, 1) > _hue(dark, 0, 1),
			"the storm lifts red above green in the shadows (violet, not teal)")
	_expect(_hue(storm_dark, 2, 1) > _hue(dark, 2, 1),
			"the storm keeps blue further above green than dusk")
	_expect(PostGrade.storm_at(0.0) == 0.0, "no storm at progress 0")
	_expect(PostGrade.storm_at(0.5) == 0.0, "no storm before progress 0.66")
	_expect(is_equal_approx(PostGrade.storm_at(1.0), 1.0), "full storm at progress 1")
	# strength 0 must be an exact identity, so a preset can disable the grade without a second code path.
	var raw := Vector3(0.3, 0.5, 0.7)
	var off := g.apply(raw, 0.0, contrast, saturation, 0.0)
	_expect(off.distance_to(raw) < 0.01, "grade_strength 0 is an identity")
	_check_toe(g, contrast, saturation)


## city-art r16 §7: the toe. `_curve` is `clamp((v - pivot) * k + pivot, 0, 1)`, so a lifted black only
## survives if the lift lands above the curve's zero — and the lift is applied BEFORE the curve. At
## r14's pivot 0.52 / contrast 1.22 that zero is luma 0.094, the lift (0.028) is below it, and a black
## pixel comes out at exactly 0.000: the two probe frames that measured `p50 = 0.000`. The check is on
## the SHIPPED row, and it proves it has teeth by running r14's pair through the same maths.
func _check_toe(g: PostGrade, contrast: float, saturation: float) -> void:
	var shipped := _toe_luma(g, SHIPPED_PIVOT, contrast, saturation)
	_expect(shipped >= TOE_FLOOR,
			"a lifted black stays off zero at the shipped row: sRGB luma %.4f, floor %.4f"
			% [shipped, TOE_FLOOR])
	var r14 := _toe_luma(g, R14_PIVOT, R14_CONTRAST, saturation)
	_expect(r14 < TOE_FLOOR,
			"the toe check has teeth: r14's pivot %.2f / contrast %.2f measures %.4f, below the floor"
			% [R14_PIVOT, R14_CONTRAST, r14])
	print("POST toe shipped %.4f vs r14 %.4f (floor %.4f)" % [shipped, r14, TOE_FLOOR])


## The sRGB luma a pure black pixel comes out at, through the whole grade.
func _toe_luma(g: PostGrade, pivot: float, contrast: float, saturation: float) -> float:
	var keep := g.pivot
	g.pivot = pivot
	var out := g.apply(Vector3.ZERO, 0.0, contrast, saturation, 1.0)
	g.pivot = keep
	var srgb := Color(out.x, out.y, out.z).linear_to_srgb()
	return 0.2126 * srgb.r + 0.7152 * srgb.g + 0.0722 * srgb.b


## Builds the stack against a throwaway WorldEnvironment shaped like city-art's (a `&"time_of_day"`
## node with a WorldEnvironment and a Sun child), so the binding path itself is covered.
func _fake_environment() -> Environment:
	var tod := FakeTimeOfDay.new()
	tod.name = "TimeOfDay"
	tod.add_to_group(&"time_of_day")
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	we.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	we.environment.tonemap_exposure = 1.28
	we.environment.glow_enabled = true
	we.environment.glow_hdr_threshold = 1.45
	tod.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	tod.add_child(sun)
	add_child(tod)
	return we.environment


func _check_stack(env: Environment) -> void:
	_stack = STACK.instantiate() as PostStack
	add_child(_stack)
	_stack._bind_environment()
	_expect(_stack.bound_environment == env, "the stack binds city-art's Environment")
	_expect(env.adjustment_enabled, "the grade LUT is installed on the bound Environment")
	_expect(env.adjustment_color_correction != null, "a colour-correction cube is assigned")
	_expect(is_equal_approx(env.tonemap_exposure, float(_stack.preset[&"exposure"])),
			"exposure comes from this unit's preset")
	_expect(is_equal_approx(env.tonemap_agx_contrast, float(_stack.preset[&"agx_contrast"])),
			"AgX contrast comes from this unit's preset")
	# With the compute bloom on, the engine glow must be off: two blooms stacked is a wash.
	if _stack.effects.has(&"bloom"):
		_expect(not env.glow_enabled, "engine glow is off while the compute bloom runs")
	else:
		_expect(env.glow_enabled, "engine glow is the fallback when the compute bloom is off")
	# Every effect the preset asked for exists, and nothing the preset disabled does.
	var row := _stack.preset
	_expect(_stack.effects.has(&"lens"), "the lens pass is always built")
	_expect(_stack.effects.has(&"bloom") == bool(row[&"bloom"]), "bloom follows the preset")
	_expect(_stack.effects.has(&"shafts") == bool(row[&"shafts"]), "shafts follow the preset")
	_expect(_stack.effects.has(&"dof") == bool(row[&"dof"]), "depth of field follows the preset")
	# Render order: shafts, then DOF, then bloom, then the lens (PostStack.ORDER).
	var names: Array[StringName] = []
	for e in _stack._compositor.compositor_effects:
		for key: StringName in _stack.effects:
			if _stack.effects[key] == e:
				names.append(key)
	var want: Array[StringName] = []
	for key in PostStack.ORDER:
		if names.has(key):
			want.append(key)
	_expect(names == want, "the compositor runs in %s, got %s" % [PostStack.ORDER, names])
	# The storm grade follows the ramp.
	_stack._time_of_day.set(&"progress", 1.0)
	_stack._update_grade()
	_expect(_stack._grade.built_progress == 1.0, "the grade cube rebuilds for a new progress")
	_expect(is_equal_approx(_stack._grade.storm_at(_stack._grade.built_progress), 1.0),
			"progress 1 builds the storm cube")


func _check_settings(_env: Environment) -> void:
	var lens := _stack.effects.get(&"lens") as PostLens
	var bloom := _stack.effects.get(&"bloom") as PostBloom
	_expect(lens != null, "the lens pass is reachable for the accessibility keys")
	if lens == null:
		return
	var preset_grain := float(_stack.preset[&"grain"])
	var preset_fringe := float(_stack.preset[&"fringe"])
	Settings.set_value(&"photosensitive", false)
	Settings.set_value(&"fx_lens", true)
	Settings.set_value(&"fx_film_grain", true)
	_stack._apply_settings()
	_expect(lens.grain > 0.0, "grain is on by default")
	_expect(lens.fringe > 0.0, "the chromatic fringe is on by default")
	# photosensitive removes grain, the colour fringe and the anamorphic streaks (CONTRACTS §2).
	Settings.set_value(&"photosensitive", true)
	_stack._apply_settings()
	_expect(lens.grain == 0.0, "photosensitive removes the film grain")
	_expect(lens.fringe == 0.0, "photosensitive removes the chromatic fringe")
	if bloom != null:
		_expect(bloom.streak == 0.0, "photosensitive removes the anamorphic streaks")
	Settings.set_value(&"photosensitive", false)
	Settings.set_value(&"fx_film_grain", false)
	_stack._apply_settings()
	_expect(lens.grain == 0.0, "fx_film_grain off removes the grain")
	Settings.set_value(&"fx_film_grain", true)
	Settings.set_value(&"fx_lens", false)
	_stack._apply_settings()
	_expect(lens.vignette == 0.0, "fx_lens off removes the vignette")
	_expect(lens.fringe == 0.0, "fx_lens off removes the fringe")
	Settings.set_value(&"fx_lens", true)
	_stack._apply_settings()
	_expect(is_equal_approx(lens.grain, preset_grain), "grain comes back at the preset value")
	_expect(is_equal_approx(lens.fringe, preset_fringe), "the fringe comes back at the preset value")
	# Depth of field is a cinematic-only effect.
	var dof := _stack.effects.get(&"dof") as PostDof
	if dof != null:
		_expect(not dof.active, "depth of field is off outside a cinematic")
		_stack.set_cinematic(true, 120.0)
		_expect(dof.active, "set_cinematic(true) arms the depth of field")
		_expect(is_equal_approx(dof.focus, 120.0), "the focus distance is taken")
		_stack.set_cinematic(false)
		_expect(not dof.active, "set_cinematic(false) disarms it again")
