extends RefCounted
## hero-v3 r10 — the plume LOOK, measured headless.
##
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_thruster.gd
##
## The lead's finding on r9 was a LOOK ("flat white slabs: one uniform white, a hard edge, no core and
## no colour"), and a look can only be confirmed in pixels the lead runs. So everything that DECIDES
## those pixels is pinned here instead, the way melee-defense's `suite_visual.gd` pins the Mirror
## Guard:
##
##   * the shader COMPILES (the dummy renderer's material storage parses it on `Shader.code = ...` and
##     logs `SHADER ERROR`; `tools/godot.sh check` does NOT catch that, measured);
##   * every uniform `Hero3Plume` writes really exists on the shader, and the material really carries
##     the profile's value for it -- so a shader or profile edit that stops taking those numbers fails
##     instead of quietly looking wrong;
##   * the core alpha at the nozzle is over 0.8 and the alpha at the tip under 0.1, measured over a
##     full flicker sweep so the WORST frame is the one that has to pass;
##   * the colour at mid-plume is the hero's accent hue within 15 deg;
##   * the plume has a soft radial falloff (no hard silhouette edge) and the white core is a CORE --
##     the regression the lead actually named;
##   * the shock-diamond banding exists and moves with time.
##
## All of it goes through `Hero3Plume.shade()`, the line-for-line GDScript mirror of the shader's
## `fragment()`. `params_match_the_profile` is what keeps the mirror and the shader from drifting.

const ErrorCounter := preload("res://tools/error_counter.gd")

## The lead's numbers, restated here so the gate fails if either side moves.
const CORE_ALPHA_MIN := 0.80
const TIP_ALPHA_MAX := 0.10
const HUE_TOLERANCE := 15.0
## A silhouette is "hard" if the plume is still this bright this close to its edge.
const EDGE_FACING := 0.12
const EDGE_RATIO_MAX := 0.35
## The white core is a core, not the plume: the share of the flame that is both near-white and solid.
const WHITE_SAT := 0.25
const WHITE_ALPHA := 0.50
const WHITE_SHARE_MAX := 0.35
## How many local maxima the axial profile must show (the shock diamonds), and how far a crest has to
## stand above the window around it -- as a FRACTION of the crest, because the profile is measured in
## emitted light and its absolute scale moves with the throttle.
const DIAMOND_MIN_PEAKS := 2
const DIAMOND_MIN_PROMINENCE := 0.05
const DIAMOND_WINDOW := 5
## The core has to be a core: the light the nozzle adds against the light the plume's BACK HALF adds.
## A mean over a span rather than a single sample, because the shock diamonds legitimately swing the
## tail by +-34 % and a single-sample ratio would be a gate on the diamond phase.
const FALLOFF_FROM := 0.60
const FALLOFF_RATIO_MIN := 4.0
## Sweep resolution: seconds, and samples. One second is 22 flicker cycles and 5 diamond cycles.
const SWEEP_SECONDS := 1.0
const SWEEP_STEPS := 4000
const AXIS_STEPS := 240


## Every check, in one call. Returns the failure messages; prints its own PASS/FAIL lines.
static func run() -> Array[String]:
	var failures: Array[String] = []
	_compiles(failures)
	_uniforms(failures)
	_look(failures)
	return failures


## --- the shader -----------------------------------------------------------------------------------

## The GLSL is COMPILED here, not just loaded. `get_shader_uniform_list()` is what makes the dummy
## material storage actually PARSE the code; without it a broken shader is silent here and only shows
## up as the host's `TEST ERRORS`.
static func _compiles(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string(Hero3Plume.SHADER)
	_ok(failures, "shader.source_reads", not source.is_empty(), "cannot read " + Hero3Plume.SHADER)
	if source.is_empty():
		return
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var probe := Shader.new()
	probe.code = source
	probe.get_shader_uniform_list()
	OS.remove_logger(counter)
	_ok(failures, "shader.compiles", counter.errors == 0, "%d error(s): %s" % [counter.errors,
			counter.first_errors[0] if counter.first_errors.size() > 0 else ""])


## Every uniform the profile writes is declared by the shader AND the material carries the profile's
## value for it.
static func _uniforms(failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string(Hero3Plume.SHADER)
	var missing: Array[String] = []
	for name: String in Hero3Plume.UNIFORMS:
		if source.find("uniform") < 0 or not _declares(source, name):
			missing.append(name)
	_ok(failures, "shader.declares_every_uniform", missing.is_empty(),
			"missing: %s" % ", ".join(missing))
	var mat := Hero3Plume.material()
	_ok(failures, "shader.material_builds", mat != null and mat.shader != null)
	if mat == null:
		return
	var wrong: Array[String] = []
	for key: String in Hero3Plume.VALUES:
		var want: Variant = Hero3Plume.VALUES[key]
		var got: Variant = mat.get_shader_parameter(StringName(key))
		if want is Color:
			if not (got is Color) or not _color_near(got as Color, want as Color):
				wrong.append(key)
		elif not is_equal_approx(float(got), float(want)):
			wrong.append(key)
	_ok(failures, "shader.params_match_the_profile", wrong.is_empty(),
			"the material and Hero3Plume disagree on: %s" % ", ".join(wrong))


static func _declares(source: String, name: String) -> bool:
	for line: String in source.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("uniform ") and trimmed.find(" %s " % name) >= 0:
			return true
	return false


static func _color_near(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)


## --- the look -------------------------------------------------------------------------------------

## Every look gate, measured through `Hero3Plume.shade()`. `facing` is 1 looking straight into the
## surface (the middle of the projected plume) and 0 at the silhouette.
static func _look(failures: Array[String]) -> void:
	_core(failures)
	_tip(failures)
	_falloff(failures)
	_hue(failures)
	_radial(failures)
	_white(failures)
	_diamonds(failures)
	_ground(failures)


## The lead's first bullet end to end: a HOT core at the nozzle FALLING OFF along the plume. Measured
## on the light the plume actually adds (`Hero3Plume.emit`), in the worst frame of a flicker sweep, so
## a plume that is bright everywhere -- or one whose brightness rides the flicker instead of the
## shape -- fails.
static func _falloff(failures: Array[String]) -> void:
	var worst := INF
	var worst_t := 0.0
	for i in 201:
		var t := float(i) / 200.0 * SWEEP_SECONDS
		var head := Hero3Plume.emit(0.0, 1.0, 1.0, t)
		var tail := 0.0
		for j in 21:
			tail += Hero3Plume.emit(lerpf(FALLOFF_FROM, 1.0, float(j) / 20.0), 1.0, 1.0, t)
		var ratio := head / maxf(tail / 21.0, 1e-6)
		if ratio < worst:
			worst = ratio
			worst_t = t
	print("PLUME  core falloff: the nozzle adds %.1fx the mean light of the plume past %.0f%%, worst frame at t=%.3f (gate %.1fx)"
			% [worst, FALLOFF_FROM * 100.0, worst_t, FALLOFF_RATIO_MIN])
	_ok(failures, "look.hot_core_falls_off_along_the_plume", worst >= FALLOFF_RATIO_MIN,
			"worst %.2fx at t=%.3f, gate %.1fx" % [worst, worst_t, FALLOFF_RATIO_MIN])


## The hot core at the nozzle: alpha over `CORE_ALPHA_MIN` at FULL throttle, in the WORST frame of a
## whole flicker sweep -- not in whichever frame happens to be brightest.
static func _core(failures: Array[String]) -> void:
	var worst := 1.0
	var worst_t := 0.0
	for i in SWEEP_STEPS + 1:
		var t := float(i) / float(SWEEP_STEPS) * SWEEP_SECONDS
		var a := float(Hero3Plume.shade(0.0, 1.0, 1.0, t)["alpha"])
		if a < worst:
			worst = a
			worst_t = t
	print("PLUME  core alpha at the nozzle, full throttle, worst frame %.4f at t=%.3f (gate %.2f)"
			% [worst, worst_t, CORE_ALPHA_MIN])
	_ok(failures, "look.core_alpha_at_the_nozzle", worst >= CORE_ALPHA_MIN,
			"worst %.4f at t=%.3f, gate %.2f" % [worst, worst_t, CORE_ALPHA_MIN])


## The tip has to be gone: alpha under `TIP_ALPHA_MAX` at the tip, in the WORST frame, at EVERY
## throttle the game drives (the six `MechContact.thruster_level` states plus 0).
static func _tip(failures: Array[String]) -> void:
	var worst := 0.0
	var worst_level := 0.0
	for level: float in [0.0, 0.25, 0.45, 0.55, 0.6, 0.8, 0.85, 1.0]:
		for i in 41:
			var t := float(i) / 40.0 * SWEEP_SECONDS
			var a := float(Hero3Plume.shade(1.0, 1.0, level, t)["alpha"])
			if a > worst:
				worst = a
				worst_level = level
	print("PLUME  tip alpha, worst frame over every throttle %.4f at level %.2f (gate %.2f)"
			% [worst, worst_level, TIP_ALPHA_MAX])
	_ok(failures, "look.tip_alpha", worst <= TIP_ALPHA_MAX,
			"worst %.4f at level %.2f, gate %.2f" % [worst, worst_level, TIP_ALPHA_MAX])


## Where the falloff lands: the colour at mid-plume is the hero's accent hue, within 15 degrees.
static func _hue(failures: Array[String]) -> void:
	var want := Hero3Plume.hue_deg(Hero3Plume.ACCENT)
	var worst := 0.0
	var worst_at := 0.0
	for i in AXIS_STEPS + 1:
		var along := float(i) / float(AXIS_STEPS)
		if along < 0.25 or along > 0.75:
			continue
		for j in 41:
			var t := float(j) / 40.0 * SWEEP_SECONDS
			var rgb: Color = Hero3Plume.shade(along, 1.0, 1.0, t)["rgb"]
			var d := absf(Hero3Plume.hue_deg(rgb) - want)
			d = minf(d, 360.0 - d)
			if d > worst:
				worst = d
				worst_at = along
	print("PLUME  mid-plume hue off the accent (%.1f deg): worst %.1f deg at along %.2f (gate %.0f)"
			% [want, worst, worst_at, HUE_TOLERANCE])
	_ok(failures, "look.mid_plume_is_the_accent_hue", worst <= HUE_TOLERANCE,
			"worst %.1f deg at along %.2f, gate %.0f" % [worst, worst_at, HUE_TOLERANCE])


## No hard silhouette edge: the plume is exactly 0 at the silhouette and still faint well inside it.
static func _radial(failures: Array[String]) -> void:
	var worst_ratio := 0.0
	var worst_at := 0.0
	for i in AXIS_STEPS + 1:
		var along := float(i) / float(AXIS_STEPS)
		var mid := Hero3Plume.emit(along, 1.0, 1.0, 0.37)
		if mid <= 0.0:
			continue
		var edge := Hero3Plume.emit(along, EDGE_FACING, 1.0, 0.37)
		var ratio := edge / mid
		if ratio > worst_ratio:
			worst_ratio = ratio
			worst_at = along
	var rim := Hero3Plume.emit(0.0, 0.0, 1.0, 0.37)
	print("PLUME  radial falloff: edge/middle %.4f at along %.2f (gate %.2f), silhouette alpha %.4f"
			% [worst_ratio, worst_at, EDGE_RATIO_MAX, rim])
	_ok(failures, "look.soft_radial_falloff", worst_ratio <= EDGE_RATIO_MAX,
			"edge is still %.1f%% of the middle at along %.2f, gate %.0f%%"
			% [worst_ratio * 100.0, worst_at, EDGE_RATIO_MAX * 100.0])
	_ok(failures, "look.silhouette_is_zero", is_zero_approx(rim), "alpha %.4f at facing 0" % rim)


## The lead's actual complaint, as a number: r9 drew the WHOLE cone one uniform white. The share of
## the flame that is both near-white and solid has to be a core, not the plume.
##
## Measured on the DISPLAY value, not the linear one. This is the difference between a gate that
## works and one that does not: in linear space the accent cyan at full gain is (0.78, 2.34, 2.60),
## whose saturation is a perfectly respectable 0.70 -- and which is pure white the moment it is
## tonemapped. The first version of this gate passed at 9.1 % while an offline render of the same
## maths showed a solid white slab over the top quarter of the flame.
static func _white(failures: Array[String]) -> void:
	var hits := 0
	var total := 0
	var worst := 1.0
	var worst_at := 0.0
	for i in AXIS_STEPS + 1:
		var along := float(i) / float(AXIS_STEPS)
		for j in 11:
			var t := float(j) / 10.0 * SWEEP_SECONDS
			var row := Hero3Plume.shade(along, 1.0, 1.0, t)
			total += 1
			var sat := _display_saturation(row["rgb"] as Color)
			if sat < worst:
				worst = sat
				worst_at = along
			if sat < WHITE_SAT and float(row["alpha"]) > WHITE_ALPHA:
				hits += 1
	var share := float(hits) / float(maxi(total, 1))
	print("PLUME  near-white and solid over %.1f%% of the flame (gate %.0f%%); the least saturated point is %.2f at along %.2f"
			% [share * 100.0, WHITE_SHARE_MAX * 100.0, worst, worst_at])
	_ok(failures, "look.white_is_a_core_not_the_plume", share <= WHITE_SHARE_MAX,
			"%.1f%% of the flame is near-white and solid, gate %.0f%%"
			% [share * 100.0, WHITE_SHARE_MAX * 100.0])


## Saturation after a Reinhard tonemap -- the shape the game's own tonemapper and bloom put on the
## frame. An approximation on purpose: the point is that a channel at 2.6 is WHITE on screen whatever
## its linear saturation says.
static func _display_saturation(c: Color) -> float:
	var r := c.r / (1.0 + maxf(c.r, 0.0))
	var g := c.g / (1.0 + maxf(c.g, 0.0))
	var b := c.b / (1.0 + maxf(c.b, 0.0))
	var hi := maxf(r, maxf(g, b))
	var lo := minf(r, minf(g, b))
	return 0.0 if hi <= 0.0 else (hi - lo) / hi


## Shock-diamond banding: the axial brightness profile has local maxima inside the flame, and they
## MOVE with time (a static banding would be a texture, not a jet).
static func _diamonds(failures: Array[String]) -> void:
	var now := _peak_positions(0.0)
	var first := now[0] if not now.is_empty() else -1.0
	var later := _first_peak(0.5 / Hero3Plume.DIAMOND_HZ)
	var drift := absf(later - first)
	print("PLUME  shock diamonds: %d peaks at along %s; half a cycle later the first is at %.3f (drift %.3f)"
			% [now.size(), ", ".join(_fmt(now)), later, drift])
	_ok(failures, "look.shock_diamond_banding", now.size() >= DIAMOND_MIN_PEAKS,
			"%d local maxima in the axial profile, gate %d" % [now.size(), DIAMOND_MIN_PEAKS])
	_ok(failures, "look.diamonds_move_with_time", drift > 0.02,
			"the banding drifted %.4f of the plume in half a cycle, gate 0.02" % drift)


static func _fmt(rows: Array[float]) -> Array[String]:
	var out: Array[String] = []
	for v: float in rows:
		out.append("%.3f" % v)
	return out


## Local maxima of the axial alpha profile at time `t`. Two things this has to get right, both found
## by the gate failing on a profile that is obviously right:
##   * the prominence is measured over a WINDOW, not against the immediate neighbours -- a sine is
##     flat at its crest, so at 120 samples per plume the one-sample drop is 0.008 and a real shock
##     diamond reads as no peak at all;
##   * the window minimum is taken on EACH SIDE separately. Taking it over both sides at once makes
##     every sample on the falling tail of the flame a "peak" (the right-hand edge is 0.05 lower all
##     the way down), which is how the second version counted 16.
static func _first_peak(t: float) -> float:
	var found := _peak_positions(t)
	return found[0] if not found.is_empty() else -1.0


static func _peak_positions(t: float) -> Array[float]:
	var n := 120
	var win := DIAMOND_WINDOW
	var found: Array[float] = []
	for i in range(win, n - win):
		var b := float(i) / float(n)
		var vb := Hero3Plume.emit(b, 1.0, 1.0, t)
		var left := vb
		var right := vb
		for k in range(1, win + 1):
			left = minf(left, Hero3Plume.emit(float(i - k) / float(n), 1.0, 1.0, t))
			right = minf(right, Hero3Plume.emit(float(i + k) / float(n), 1.0, 1.0, t))
		if vb - left > vb * DIAMOND_MIN_PROMINENCE and vb - right > vb * DIAMOND_MIN_PROMINENCE:
			# A crest is flat over the window, so one shock diamond reports as 3-4 adjacent samples.
			# Merge anything closer than half a banding period, or the count is a count of samples.
			if found.is_empty() or b - found[-1] > 0.5 / Hero3Plume.DIAMOND_N:
				found.append(b)
	return found


## A grounded mech has no flame -- only the nozzle ember (lead r9's gate, kept). `MechContact` drives
## `thruster_level` to exactly 0.0 in GROUND, and the ember is the one thing allowed to survive it.
static func _ground(failures: Array[String]) -> void:
	var worst := 0.0
	var worst_at := 0.0
	for i in AXIS_STEPS + 1:
		var along := float(i) / float(AXIS_STEPS)
		var a := float(Hero3Plume.shade(along, 1.0, 0.0, 0.37)["alpha"])
		if a > worst:
			worst = a
			worst_at = along
	print("PLUME  grounded: brightest fragment %.4f at along %.2f, all of it inside the %.3f ember"
			% [worst, worst_at, Hero3Plume.IDLE_SPAN])
	_ok(failures, "look.grounded_mech_has_only_an_ember",
			worst <= Hero3Plume.IDLE_GLOW + 0.001 and worst_at <= Hero3Plume.IDLE_SPAN + 0.001,
			"a grounded mech burns at %.4f as far as along %.3f" % [worst, worst_at])


## --- reporting ------------------------------------------------------------------------------------

static func _ok(failures: Array[String], label: String, cond: bool, detail: String = "") -> void:
	# the detail is the FAILURE's explanation; on a pass the number is already in the PLUME line above
	print("%s %s%s" % ["PASS" if cond else "FAIL", label, "" if cond else ("  [" + detail + "]")])
	if not cond:
		failures.append(label if detail.is_empty() else "%s: %s" % [label, detail])
