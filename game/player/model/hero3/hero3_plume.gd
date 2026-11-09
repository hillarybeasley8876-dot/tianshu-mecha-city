class_name Hero3Plume
extends RefCounted
## hero-v3 r10 — what the backpack plumes are MADE OF, in one place.
##
## r9 put the two plumes on the measured nozzles (root within 0.043 m) and they read as **flat white
## slabs**: `ALBEDO = tint * (0.35 + 2.4 * core) * throttle * flicker` over a cone with no radial term
## at all, so every fragment of the cone was the same near-white at the same alpha and the silhouette
## was a hard elliptical cut. This file is the fix, and it is the ONLY place the numbers live:
##
##   * `hero3_thruster.gdshader` takes every one of them as a UNIFORM this file writes, so there is
##     nothing left to keep in sync by hand;
##   * `shade()` below is a line-for-line GDScript mirror of the shader's `fragment()`, so
##     `tests/hero3_plume_check.gd` can measure the look headless — core alpha at the nozzle, the
##     alpha at the tip, the hue at mid-plume, the radial falloff and the shock diamonds — without a
##     single pixel. `mat.params_match_the_profile` is what stops the two from drifting.
##
## The look, and why each term is here:
##   * **core** — `exp(-along / CORE_SPAN)` off the nozzle is the hot near-white head; by 22 % of the
##     plume it is under a third and the colour is the hero's own accent (the cyan of the seams,
##     `Hero3Shade.ACCENT`), which is what the lead asked the falloff to land on.
##   * **radial** — `pow(|dot(N, V)|, RADIAL_POW) * smoothstep(0, EDGE_KILL, |dot(N, V)|)` is a shell's
##     chord length through the volume: brightest where the view ray runs along the surface (the
##     middle of the projected plume) and exactly 0 at the silhouette, so there is no hard edge. The
##     cone keeps its bottom CAP, whose normal is along the axis — that cap is what makes the plume
##     read from directly BEHIND, where every side fragment is edge-on and would otherwise vanish.
##   * **diamonds** — shock-diamond banding along the axis, enveloped so it never touches the nozzle
##     (the core gate is measured there) and fades out past `DIAMOND_FADE`.
##   * **flicker** — a fast, shallow wobble on the whole plume.
##
## Length and width are NOT shader terms any more: the rig scales the plume node by
## `reach(level)` along its axis and `width(level)` across it, so the mesh's own tip IS the tip of the
## flame and the gate measures the plume's real world length instead of a mirrored number.

const SHADER := "res://player/model/hero3/hero3_thruster.gdshader"

## The plume cone's own length in metres at scale 1. `Hero3Rig.PLUME_LENGTH` re-exports it.
const LENGTH := 3.4
## How far along the cone the flame reaches at a given throttle, as a fraction of `LENGTH`. The floor
## is the nozzle ember's own length, so a grounded mech still has a mouth and not a stub.
const REACH_MIN := 0.055
const REACH_MAX := 1.0
## `pow(level, REACH_CURVE)`: under 1 so the first third of the throttle already buys most of the
## plume, which is what makes a hover read as a hover rather than as a pilot light.
const REACH_CURVE := 0.75
## The plume's width across the axis, as a fraction of the measured mouth radius. A grounded mech's
## ember is a small disc in the middle of the plate, not the whole plate.
const WIDTH_MIN := 0.34
const WIDTH_MAX := 1.0

## Hot near-white head. A jet core is white-hot, so this is a hair warm rather than blue.
const CORE := Color(1.00, 0.98, 0.95)
## Where the falloff lands: the hero's own accent, the cyan of the seams.
const ACCENT := Color(0.30, 0.90, 1.00)

## Below this throttle there is no flame at all — only the ember. r9's gate is "walking has no flame",
## and `MechContact.thruster_level` is exactly 0.0 on the ground.
const GATE_SPAN := 0.05
## The plume is at full brightness out to this fraction of its length, then falls to 0 at the tip.
const BODY_HEAD := 0.35
const CORE_POW := 2.0
## e-folding length of the white core, as a fraction of the plume.
const CORE_SPAN := 0.18
## e-folding length of the INTENSITY, as a fraction of the plume, over a `GLOW_FLOOR` that keeps the
## tail from going black so the shock diamonds still read down there. Without this the accent cyan is
## multiplied by the full gain for the whole first third and clips to WHITE on screen: measured on an
## offline render of this exact maths (`tmp/hero-v3/plume_preview.py`), the "hot core" was the top
## 25 % of the flame and the rest of it was a white slab -- the lead's complaint, just smaller.
const GLOW_SPAN := 0.40
const GLOW_FLOOR := 0.18
## The radial falloff. `EDGE_KILL` is the band over which the silhouette goes to exactly 0.
const RADIAL_POW := 1.5
const EDGE_KILL := 0.18
## Where the cone's bottom cap fades out, as a fraction of its own radius. A cap's normal points
## straight down the axis, so `abs(dot(NORMAL, VIEW))` is 1 right out to its edge and the rear view
## was a hard-edged uniform white disc until this existed.
const RIM_START := 0.30
## Shock diamonds: `DIAMOND_N` bands over the plume, drifting at `DIAMOND_HZ`, never touching the
## nozzle (`DIAMOND_RAMP`) and gone by `DIAMOND_FADE`.
const DIAMOND_N := 4.0
const DIAMOND_DEPTH := 0.34
const DIAMOND_HZ := 5.0
const DIAMOND_RAMP := 0.10
const DIAMOND_FADE := 0.55
## The fast wobble on the whole plume.
const FLICKER_HZ := 22.0
const FLICKER_DEPTH := 0.13
const FLICKER_WAVE := 9.0
## Additive brightness at the ground and at the assault. `GAIN_MIN` is what the ember burns at.
const GAIN_MIN := 0.90
const GAIN_MAX := 2.60
## The always-on nozzle glow: a faint disc at the mouth so a grounded mech still has a live nozzle.
## `Hero3Rig` scales it by `Hero3Shade.power`, so a wreck's nozzles go out with the rest of it.
const IDLE_GLOW := 0.30
const IDLE_SPAN := 0.045

## Every uniform the shader declares, in the order the profile writes them. The gate asserts the
## shader's source declares all of them AND that the material carries the profile's value for each,
## so a shader edit that stops taking these numbers fails instead of quietly looking wrong.
const UNIFORMS: Array[String] = [
	"level", "height", "radius_base", "radius_tip", "time_s", "core_color", "accent_color",
	"gate_span", "body_head", "core_pow", "core_span", "glow_span", "glow_floor", "radial_pow",
	"edge_kill", "rim_start", "diamond_n", "diamond_depth", "diamond_hz", "diamond_ramp",
	"diamond_fade", "flicker_hz", "flicker_depth", "flicker_wave", "gain_min", "gain_max",
	"idle_glow", "idle_span",
]

## The two uniforms that are GEOMETRY rather than look: the cone's own radii. `Hero3Rig` writes them
## from the measured nozzle, so they are not in `VALUES` and the params gate does not check them.
const GEOMETRY: Array[String] = ["radius_base", "radius_tip"]

## The profile's value for each uniform. `level` and `time_s` are per-frame and start at 0.
const VALUES: Dictionary = {
	"height": LENGTH,
	"core_color": CORE,
	"accent_color": ACCENT,
	"gate_span": GATE_SPAN,
	"body_head": BODY_HEAD,
	"core_pow": CORE_POW,
	"core_span": CORE_SPAN,
	"glow_span": GLOW_SPAN,
	"glow_floor": GLOW_FLOOR,
	"radial_pow": RADIAL_POW,
	"edge_kill": EDGE_KILL,
	"rim_start": RIM_START,
	"diamond_n": DIAMOND_N,
	"diamond_depth": DIAMOND_DEPTH,
	"diamond_hz": DIAMOND_HZ,
	"diamond_ramp": DIAMOND_RAMP,
	"diamond_fade": DIAMOND_FADE,
	"flicker_hz": FLICKER_HZ,
	"flicker_depth": FLICKER_DEPTH,
	"flicker_wave": FLICKER_WAVE,
	"gain_min": GAIN_MIN,
	"gain_max": GAIN_MAX,
	"idle_glow": IDLE_GLOW,
	"idle_span": IDLE_SPAN,
}


## The plume material, with every number above already written into it.
static func material() -> ShaderMaterial:
	var shader := load(SHADER) as Shader
	if shader == null:
		push_error("Hero3Plume: cannot load %s, the backpack has no flame shader" % SHADER)
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for key: String in VALUES:
		mat.set_shader_parameter(StringName(key), VALUES[key])
	return mat


## How far along its own axis the flame reaches at `level`, as a fraction of `LENGTH`. Monotonic in
## `level` by construction (`pow` of a clamped positive, then a linear mix) — the gate measures it off
## the real node anyway.
static func reach(level: float) -> float:
	var lv := clampf(level, 0.0, 1.0)
	return lerpf(REACH_MIN, REACH_MAX, pow(lv, REACH_CURVE))


## The flame's real world length in metres at `level`.
static func length(level: float) -> float:
	return LENGTH * reach(level)


## How wide the flame is across its axis, as a fraction of the measured mouth radius.
static func width(level: float) -> float:
	return lerpf(WIDTH_MIN, WIDTH_MAX, clampf(level, 0.0, 1.0))


## A LINE-FOR-LINE mirror of `hero3_thruster.gdshader`'s `fragment()`. `along` is 0 at the nozzle and
## 1 at the tip; `soft` is the radial coordinate the shader mixes from `abs(dot(NORMAL, VIEW))` on the
## wall and the disc's own radius on the cap -- 1 in the middle of the projected plume and 0 at its
## edge. Returns `{"rgb": Color, "alpha": float}` — the two things the shader writes.
##
## KEEP THIS AND THE SHADER TOGETHER. `tests/hero3_plume_check.gd` measures the whole look through
## this function and separately asserts that every uniform above reaches the material.
static func shade(along: float, soft: float, level: float, t: float) -> Dictionary:
	var a := clampf(along, 0.0, 1.0)
	var lv := clampf(level, 0.0, 1.0)
	var gate := smoothstep(0.0, GATE_SPAN, lv)
	var body := 1.0 - smoothstep(BODY_HEAD, 1.0, a)
	var core := pow(body, CORE_POW) * exp(-a / maxf(CORE_SPAN, 0.001)) * gate
	var edge := clampf(absf(soft), 0.0, 1.0)
	var radial := pow(edge, RADIAL_POW) * smoothstep(0.0, EDGE_KILL, edge)
	var band := 0.5 + 0.5 * sin(a * DIAMOND_N * TAU - t * DIAMOND_HZ * TAU)
	var env := smoothstep(0.0, DIAMOND_RAMP, a) * (1.0 - smoothstep(DIAMOND_FADE, 1.0, a))
	var diamonds := 1.0 + DIAMOND_DEPTH * (band * 2.0 - 1.0) * env * lv
	var flick := 1.0 - FLICKER_DEPTH * (0.5 + 0.5 * sin(t * FLICKER_HZ * TAU + a * FLICKER_WAVE))
	var ember := IDLE_GLOW * (1.0 - smoothstep(0.0, IDLE_SPAN, a))
	var tint := ACCENT.lerp(CORE, core)
	var glow := GLOW_FLOOR + (1.0 - GLOW_FLOOR) * exp(-a / maxf(GLOW_SPAN, 0.001))
	var gain := lerpf(GAIN_MIN, GAIN_MAX, lv) * glow
	# alpha is COVERAGE, albedo is INTENSITY -- see the note in the shader's fragment()
	return {"rgb": tint * gain * diamonds * flick,
			"alpha": clampf(radial * maxf(body * gate, ember), 0.0, 1.0)}


## The radial coordinate the shader uses on the cone's bottom CAP: the disc's own radius, because a
## cap's normal points straight down the axis and `abs(dot(NORMAL, VIEW))` is 1 right out to its edge.
static func cap_soft(rim: float) -> float:
	return 1.0 - smoothstep(RIM_START, 1.0, clampf(rim, 0.0, 1.0))


## The light the plume actually ADDS to the frame: what `blend_add` computes, `ALBEDO * ALPHA`, as a
## scalar. This is what every "is there a core, a falloff, a banding" question is measured on, because
## it is the only quantity the screen sees.
static func emit(along: float, facing: float, level: float, t: float) -> float:
	var row := shade(along, facing, level, t)
	var c: Color = row["rgb"]
	return (c.r + c.g + c.b) / 3.0 * float(row["alpha"])


## Hue in degrees, 0..360. Godot's `Color.h` is 0..1 and the gate is written in degrees.
static func hue_deg(c: Color) -> float:
	return fposmod(c.h, 1.0) * 360.0
