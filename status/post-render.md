# post-render status

## Done

**The stack** — `game/world/post/`, one self-installing `Node` (`world/post/post_stack.tscn`, class
`PostStack`). It finds the active `Camera3D` and owns `Camera3D.compositor`, finds city-art's
`WorldEnvironment` through the `&"time_of_day"` group, and owns the grade / exposure / glow rows of it.

| File | What |
|---|---|
| `post_stack.gd` | orchestrator: preset → effects, Environment binding, camera attach, grade ramp, settings, `--no-post` / `--post=` / `--post-tune=` / `--post-bracket` |
| `post_presets.gd` | low / medium / high rows (every effect's numbers, exposure, grade strength) |
| `post_grade.gd` | the 32³ filmic LUT, dusk ↔ storm, hue-preserving |
| `post_compute.gd` | shared RenderingDevice plumbing + the copy shader every pass needs |
| `effects/post_lens.gd` | vignette, edge-only chromatic fringe, animated grain, AMD CAS sharpening |
| `effects/post_bloom.gd` | 6-mip dual-filter bloom + anamorphic streaks |
| `effects/post_sun_shafts.gd` | screen-space god rays from the sun's screen position |
| `effects/post_dof.gd` | cinematic far-field bokeh, off outside cinematics |
| `tests/test_post.gd` | unit test (headless) |
| `tests/lookdev.gd/.tscn` | vista A/B + the `--post-bracket` sweep harness |
| `tests/isolated.gd/.tscn` | isolates the stack's own GPU cost |
| `tests/game_with_post.gd/.tscn` | the shipped `main.tscn` plus the stack, for the in-play A/B |

Brief items delivered: filmic grade LUT (dusk + storm) · bloom that reads · vignette / fringe / grain /
CAS · sun shafts · cinematic DOF · presets + Settings keys · perf measured · A/B sheets.

## In progress / next
Nothing outstanding in the brief. **Ownership moved in r16: `world/post/**` is city-art's** (lead
decision, `reviews/r16-lead-decisions.md`), so the rows this file used to hand over as a patch list are
edited in place here now, with their reasons in `post_presets.gd` and their pins in
`world/post/tests/test_post.gd`.

**r16b (city-art), two changes in this unit's files:**

- `effects/post_lens.gd` — the film grain's hash. It was
  `fract(sin(dot(px + time * 91.7, ...)) * 43758.5453)`, where `time` is the PROCESS'S AGE in seconds:
  after ten minutes the argument is ~3e6 and fp32 has a third of a radian of resolution left, so the
  "white noise" quantised into a coherent diagonal ripple at a fixed screen-space frequency — the
  hatch that covers the sky of every r15 capture (measured at up to 1.24/255, and 261-3 939 peak over
  median in a 5-48 px band). It is an integer hash (xorshift-multiply on `uvec2`) now, which has no
  precision floor at any age (20-24 peak over median = a flat spectrum). `--post-tune=lens_time_offset`
  sets the age the hash is offset by and `--post-tune=lens_legacy_grain:1` puts the sine hash back, so
  the A/B is one flag each way. `--post-tune=lens_<prop>` is new and writes straight into the lens
  pass (grain, sharpen, vignette, fringe), which is not an Environment row.
- `post_stack.gd` — the `lens_*` tune keys above, and nothing else. No preset row moved this round.

## How to verify (exact commands)

```
# compile + unit test
tools/godot.sh check --only=res://world/post/            # 0 errors
tools/godot.sh test  res://world/post/tests/test_post.gd # POST TEST PASS (0 failures)

# the A/B (before = --no-post, after = the stack)
tools/godot.sh shot --scene=res://world/post/tests/lookdev.tscn --out=post_before --env-only \
  --cams=res://world/post/tests/cameras.json --no-post
tools/godot.sh shot --scene=res://world/post/tests/lookdev.tscn --out=post_after --env-only \
  --cams=res://world/post/tests/cameras.json
tools/godot.sh shot --scene=res://world/post/tests/lookdev.tscn --out=poststorm --env-only \
  --cams=res://world/post/tests/cameras.json --tod=1.0        # storm grade
tools/godot.sh shot --scene=res://world/post/tests/lookdev.tscn --out=postlow --env-only \
  --cams=res://world/post/tests/cameras.json --quality=low    # low preset

# in play, on the shipped game graph
tools/godot.sh drive --scene=res://world/post/tests/game_with_post.tscn --skip-menu \
  --enemies=ripper:6,juggernaut:2 --seed=7 --spawn=-583,20,640,143 \
  --timeline=res://enemies/tests/fight_timeline.json --shots=14,28 --out=postfight
tools/godot.sh drive ... --out=prefight --no-post

# perf: the stack's own GPU cost, A/B'd inside one run at 1600x900
tools/godot.sh shot --scene=res://world/post/tests/isolated.tscn --out=iso --times=300 --env-only
tools/godot.sh shot --scene=res://world/post/tests/isolated.tscn --out=iso --times=300 --env-only --quality=low

# a renderer sweep without editing another unit's files
tools/godot.sh shot --scene=res://world/post/tests/lookdev.tscn --out=brk --times=300 --post=none \
  --post-cam=V2 --env-only \
  --post-bracket="a:tonemap_exposure:0.7;b:tonemap_exposure:0.7,fog_depth_begin:250,fog_sky_affect:0.05"
```

## Evidence (paths, numbers)

**A/B sheets** — `captures/post_ab_V1.jpg`, `post_ab_V2.jpg`, `post_ab_V8.jpg`, `post_ab_fight.jpg`
(before | after | key art; the V8 sheet's "after" is the `--tod=1.0` storm pass). Also
`captures/postlow_V*.jpg` (low preset) and `captures/poststorm_V*.jpg`.

Numeric read of the same frames (`tmp/post-render/stats.py`: sRGB luminance std = contrast,
p5→p95 = tonal range, warm = mean R − mean B):

| frame | contrast (std) | p5 | p95 | range | warm |
|---|---|---|---|---|---|
| V2 before | 0.121 | 0.280 | 0.742 | 0.462 | +0.218 |
| V2 after | **0.174** | 0.130 | 0.778 | **0.648** | +0.223 |
| V1 before | 0.202 | 0.102 | 0.734 | 0.632 | +0.214 |
| V1 after | **0.227** | 0.012 | 0.700 | **0.688** | +0.187 |
| V8 before | 0.208 | 0.277 | 0.986 | 0.709 | +0.211 |
| V8 storm | **0.302** | 0.015 | 0.969 | **0.954** | **+0.119** |
| fight before | 0.187 | 0.160 | 0.665 | 0.505 | +0.100 |
| fight after | **0.205** | 0.038 | 0.603 | **0.565** | +0.090 |

V2 — the flattest frame — gains 44 % contrast and 40 % tonal range. V8's storm grade cools the whole
frame (warm +0.211 → +0.119) while nearly doubling the range.

**Perf** (`tests/isolated.tscn`, 3 passes × 180 frames each, vsync off, `Engine.max_fps = 0`, 1600×900):

| preset | post on | post off | delta | budget |
|---|---|---|---|---|
| high | 3.80 ms | 3.34 ms | **0.46 – 0.54 ms** | 2.5 ms |
| medium | — | — | 0.03 – 0.45 ms | — |
| low | 2.97 ms | 2.93 ms | **0.03 – 0.23 ms** | 0.8 ms |

Honest caveats: (a) Metal reports 0 for GPU timings (godot-tech rule 2), so frame time is the only
number available; (b) the delta is measured against a *no-city* scene, because the full city is CPU-bound
at 8 ms/frame and a whole-scene A/B there resolves nothing (8.36 ms off vs 8.45 ms on at V1); (c) run to
run the delta moves by ±0.2 ms, so the ranges above are what repeated runs actually produced, not one
sample. In the full city at the 60 fps cap, `--frametimes` on the fight timeline gives p50 = 16.9 ms with
the stack and 16.7 ms without — both pinned to the cap, and the machine was carrying a 4.4–6.2 load
average from other units, so that number is not usable as a cost measurement either way.

**Tuning choices** (all live in `post_presets.gd` / `post_grade.gd`; **the grade and exposure rows moved
in city-art r14/r15 and are current as of r16**, the rest are this unit's originals):
exposure **0.66** (r14 0.72 -> 0.56 -> r15 0.66), AgX white 8.0, AgX contrast 1.30, grade contrast
**1.06**, saturation **1.10**, grade pivot **0.42** (was 0.52), shadow gain (0.82, 0.92, 1.26), highlight
gain (1.10, 1.00, 0.84), bloom threshold 2.6 / knee 0.25 / strength 0.22 / 6 mips, streak 0.06, shafts
strength 0.14 / 24 steps, vignette 0.22, fringe 1.0 px, grain 1.6 %, CAS 0.62, DOF far-field only over
90 m. `world/post/tests/test_post.gd` pins exposure / contrast / saturation / pivot and checks that a
lifted black stays off zero (shipped sRGB luma 0.0035 against a 0.0020 floor; r14's 0.52 / 1.22 pair
measures 0.0000, which is the failure the check exists to catch).

## Known issues

- **The brief's hook does not exist.** It says "The environment exposes `CityEnvironment.compositor`".
  In 4.7.2 `Environment` has no `compositor` property; `Compositor` lives on `Camera3D`. `PostStack`
  therefore owns `Camera3D.compositor` itself and nothing in city-art has to change for the hook. It
  re-points the Compositor whenever the active camera changes, so the vista harness swapping cameras is
  handled.
- **The flat frame is not a post problem, and post alone does not fix it.** The r5 captures are clipped
  in the red channel before any grade runs (`captures/bracket_V2_e100.jpg`), so a per-channel contrast
  posterises them — the first version of `post_grade.gd` did exactly that and turned V2 into red/blue
  bands. The grade had to become hue-preserving (luma-normalised split tone + a curve on luminance),
  and the exposure had to come down 1.28 → 0.72 to give the frame headroom. What is left is city-art's
  fog and ambient; see Requests.
- **A pushed-down exposure is a look decision, not a free win.** 0.72 is right for the golden-hour
  vistas; if the lead wants a brighter game, raise `exposure` in `post_presets.gd` rather than reverting
  the grade — the grade's contrast is what is doing the work.
- The stack needs a `RenderingDevice`; headless runs disable all four effects with a warning each. That
  is expected, and the unit test covers everything up to the GPU.
- `--post-tune` / `--post-bracket` are look-dev hooks. Nothing in the shipped presets depends on them.
- Two scratch tools live in `tmp/post-render/` (`grade_preview.py` mirrors `post_grade.gd` offline on a
  capture so a grade candidate costs milliseconds instead of a 90 s windowed run; `stats.py` reads
  contrast/range numerically). They are scratch and are not committed — if this look gets tuned again,
  they are worth rebuilding.

## Requests (to the lead / other units)

**1. lead — instance the stack (blocking for it to ship).** Add one node to `main.tscn`:
```
[ext_resource type="PackedScene" path="res://world/post/post_stack.tscn" id="post"]
[node name="PostStack" parent="." instance=ExtResource("post")]
```
It is a no-op with no `&"time_of_day"` node and no camera (so the sandbox is unaffected), and
`--no-post` turns it off. `world/post/tests/game_with_post.tscn` is exactly `main.tscn` + this node and
is what the in-play A/B was shot on.

**2. lead — two Settings keys** (CONTRACTS §2 accessibility list). Until they exist
`PostStack._setting()` falls back to "on", which is the correct default but means the sliders do nothing:
```gdscript
&"fx_lens": true,        ## post-render: vignette + chromatic fringe
&"fx_film_grain": true,  ## post-render: film grain (also removed by `photosensitive`)
```

**3. city-art — the renderer patch list. LANDED (r14/r15), kept for the record.** This unit owns the
tonemap, the grade cube and the glow at runtime (see `PostStack._apply_renderer_settings`), so these
already took effect; the point of the list was to move the source of truth into city-art's files so the
two agreed. They do: the exposure / grade / bloom rows are in `post_presets.gd` and `post_grade.gd`
(city-art owns `world/post/**` from r16), the fog rows are in `time_of_day.gd` and `environment.gd`, and
`world/post/tests/test_post.gd` pins them. The "now" column below is what the table looked like when it
was written. Measured with `--post-bracket` (V2, before the grade, glow off):

| where | now | proposed | why (measured) |
|---|---|---|---|
| `CityEnv.build` `tonemap_exposure` | 1.28 | **0.72** | the frame is clipped in red before any grade runs |
| `CityEnv.build` `tonemap_agx_white` | 10.5 | **9.0** | with the exposure down, 10.5 leaves the mids muddy |
| `CityEnv.build` `tonemap_agx_contrast` | 1.15 | **1.34** | the S-curve the flat frame needs |
| `CityEnv.build` `adjustment_*` + `grade_lut()` | 16³ split tone | **this unit's 32³ cube** | the 16³ grade is superseded; leaving both on double-grades |
| `ArtQuality.apply` `glow_*` | threshold 1.45, screen blend | **glow off** on medium/high | the compute bloom replaces it; the two together are a wash. Low keeps glow, retuned to threshold 1.15 / intensity 0.35 / **additive** (screen blend at a low threshold is a full-frame wash — that was measured, it looked worse than no bloom) |
| `TimeOfDay._apply` `fog_depth_begin` | `lerp(90, 30, p)` | **`lerp(250, 120, p)`** | everything past 90 m fogs, so the whole city is one value. The current ramp gets *worse* over the mission |
| `TimeOfDay._apply` `fog_light_energy` | `lerp(0.85, 1.15, p)` | **`lerp(0.5, 0.7, p)`** | the beige wash (measured: warm +0.340 → +0.308, same contrast) |
| `TimeOfDay._apply` `fog_sky_affect` | `lerp(0.22, 0.45, p)` | **`lerp(0.06, 0.14, p)`** | the sky is the brightest thing in frame and it is being fogged too |
| `CityEnv.build` `fog_aerial_perspective` | 0.40 | **0.15** | ditto; `mc_haze` already does the layered aerial perspective |
| `ArtQuality` high `vol_density` | 0.0013 | **0.0009** | the god rays now come from `PostSunShafts`, so the froxel slab can be thinner and keep the shafts |

The fog rows are a modest win, not a dramatic one: the bracket shows contrast and range essentially
unchanged (std 0.173 → 0.174, range 0.707 → 0.706) and the gain is a less warm wash and better
silhouetting of the distant towers. Worth doing, but the exposure + grade + bloom are what moved the
numbers in the table above. Please A/B them yourselves before adopting — I ran out of image budget to
verify them in the full stack.

**4. city-art — not mine, but you will see it.** `mc_surface.gdshader:248` reported
`Assignment to uniform` → `Shader compilation failed` in one windowed run (it did not reproduce in later
runs the same session, so it may already be fixed).

**5. feel — no conflict, but worth stating.** This unit's lens runs *pre-tonemap* as a
`CompositorEffect` (optics: vignette, fringe, grain, CAS); `fx/screen_fx` runs *post-tonemap* on a
`CanvasLayer` (gameplay juice). They stack in that order and neither duplicates the other: the damage
vignette is yours, the lens vignette is a constant 18 % corner falloff, and `photosensitive` removes this
unit's grain, fringe and streaks.
