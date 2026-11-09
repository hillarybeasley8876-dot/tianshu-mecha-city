# hero-v3 status

## Done

### r10 — the plumes read as jets (lead brief r10)

The lead's finding on r9: the plumes were in the right place but read as **flat white slabs — one
uniform white, a hard edge, no core and no colour**. That was a LOOK, so the fix had to be a look and
the gate had to be a look. Both are below; every number is measured, and the two defects that only an
image could show were found by rendering the shader's own maths offline (`tmp/hero-v3/plume_preview.py`)
rather than by asserting them.

#### 1. What was actually wrong

`hero3_thruster.gdshader` was `ALBEDO = tint * (0.35 + 2.4 * core) * throttle * flicker` with **no
radial term at all**. Every fragment of the cone came out the same near-white at the same alpha with
a hard elliptical silhouette — the slab, exactly as described. Four separate causes, in the order
they were found:

| # | cause | how it was found |
| --- | --- | --- |
| 1 | no radial falloff — `abs(dot(NORMAL, VIEW))` was never read, so the silhouette was a hard cut | reading the shader |
| 2 | the accent cyan was multiplied by the FULL gain for the whole first third of the plume, so it clipped to **white on screen**. The core was the top **25 %** of the flame | the offline render — the gate measured linear saturation (0.70, "not white") and passed while the image was a white slab |
| 3 | the cone's bottom cap has its normal along the axis, so `dot(NORMAL, VIEW)` is 1 right out to its edge: the rear view was a **hard-edged uniform white disc** | the offline render |
| 4 | the shock diamonds lived in `ALPHA`, where `body * diamonds * flick` peaks at **1.34** and clipped flat at 1.0 — the banding vanished from the brightest third of the plume, the one place it reads | the gate's own peak finder: 2 peaks 0.008 apart (one crest, double-counted) and none before along 0.54 |

#### 2. The look now

`hero3_thruster.gdshader` rewritten, with **every number a uniform written by `Hero3Plume`** (new file,
`hero3_plume.gd`) — one place to read, one place to A/B, and answerable from a test:

* **core** — `pow(body, CORE_POW) * exp(-along / CORE_SPAN)` off the nozzle: near-white, gone by
  ~3 × 0.18 up the plume;
* **falloff to the accent** — the colour lands on `Hero3Shade.ACCENT`, the cyan of the seams, and the
  INTENSITY falls with its own `exp(-along / GLOW_SPAN)` over a `GLOW_FLOOR`. That second term is
  cause 2: without it the accent at full gain is (0.78, 2.34, 2.60), whose linear saturation is a
  respectable 0.70 and which is pure white the moment it is tonemapped;
* **radial** — on the WALL, the shell's chord through the volume (`pow(|dot(N, V)|, 1.5)`), which is
  exactly 0 at the silhouette; on the CAP, the disc's own radius (`RIM_START`), which is cause 3. The
  shader tells them apart with `smoothstep(0.7, 0.95, abs(NORMAL.y))` in the vertex stage;
* **shock diamonds** — 4 bands along the axis, drifting at 5 Hz, enveloped off the nozzle and faded
  out before the tip. They live in `ALBEDO`, not `ALPHA` (cause 4): **alpha is coverage, albedo is
  intensity**;
* **flicker** — 22 Hz, 13 % deep, on the whole plume.

Additive and `depth_draw_never`, unchanged: the plume adds light and never writes depth, so it can
never hide the hero behind it.

#### 3. Scale with thrust — the length is now GEOMETRY, not a fade

r9 faded the flame out inside a fixed 3.4 m cone. `Hero3Rig` now scales the plume node by
`Hero3Plume.reach(level)` along its axis and `Hero3Plume.width(level)` across it, so the mesh's own
tip IS the tip of the flame and the gate measures the plume's real world length off the transformed
vertices instead of a mirrored number.

| state | `MechContact.thruster_level` | flame length | flame width |
| --- | --- | --- | --- |
| rest / walk | 0.00 | **0.19 m** (a nozzle ember and nothing else) | 0.23 m |
| hover | 0.45 | **1.95 m** | 0.43 m |
| dash / boost | 0.80 | **2.90 m** | 0.58 m |
| flight 50 m/s | 0.85 | **3.03 m** | 0.60 m |
| assault / flight 84 m/s | 1.00 | **3.40 m** | 0.67 m |

The r9 states and the r8 flight lean are untouched. A grounded mech has **no flame at all** — only a
faint nozzle ember, which is the lead's "a faint nozzle glow only, or nothing" — and the ember rides
`Hero3Shade.power`, so a wreck's nozzles go out with the rest of its emissives (r8 3b).

#### 4. The gate — `test_hero3_thruster`, extended

The look half is `tests/hero3_plume_check.gd`, the same discipline as melee-defense's
`suite_visual.gd`: the shader is COMPILED in an error window (the dummy material storage parses it on
`Shader.code = …`; `tools/godot.sh check` does **not** catch a broken shader, measured), every uniform
the profile writes is declared by the shader AND carries the profile's value on the material, and the
look itself is measured through `Hero3Plume.shade()` — a line-for-line GDScript mirror of the shader's
`fragment()` — so a shader edit that stops taking those numbers fails instead of quietly looking wrong.

| gate | measured |
| --- | --- |
| `shader.compiles` | 0 errors |
| `shader.declares_every_uniform` (28) and `params_match_the_profile` | all present, all equal |
| `look.core_alpha_at_the_nozzle` ≥ 0.80, worst frame of a 4000-sample sweep | **1.0000** |
| `look.tip_alpha` ≤ 0.10, worst frame at every throttle the game drives | **0.0000** |
| `look.hot_core_falls_off_along_the_plume` ≥ 4× | **13.8×** (the nozzle against the mean of the plume past 60 %) |
| `look.mid_plume_is_the_accent_hue` ±15° | **0.7°** off 188.6° |
| `look.soft_radial_falloff`, edge/middle ≤ 0.35 | **0.031** |
| `look.silhouette_is_zero` | **0.0000** at facing 0 |
| `look.white_is_a_core_not_the_plume` ≤ 35 %, measured on the **display** value | **19.5 %** |
| `look.shock_diamond_banding` ≥ 2 crests | **2**, at along 0.292 and 0.525 (spacing 0.233 ≈ 1/`DIAMOND_N`) |
| `look.diamonds_move_with_time` > 0.02 | **0.125** in half a cycle |
| `look.grounded_mech_has_only_an_ember` | brightest fragment 0.300, all of it inside the 0.045 ember |
| `scale.length_grows_with_thrust`, `scale.width_grows_with_thrust` | monotonic, and a 18× spread from the ground to the assault |
| the r9 root gate (0.30 m) | **0.011–0.031 m**, better than r9's 0.043 |
| `every measured nozzle has a plume` | 2 nozzles, 2 plumes |

#### 5. Two things worth writing down

* **`Basis.scaled()` scales the GLOBAL axes, not the mesh's own.** Scaling the plume by
  `(wide, reach, wide)` with `scaled()` sheared a plume whose axis is not a global one: the root sat
  **0.484 m** off its mouth at rest (gate 0.30) and the axis strayed 5.8°. Godot 4.7 has no
  `Basis.scale_local()`, so the fix is to build the basis from its own columns:
  `Basis(b.x * wide, b.y * reach, b.z * wide)`. Same trap as r8's `Basis.scaled(float)`.
* **A gate measured in linear space cannot see a blown-out highlight.** `white_is_a_core` passed at
  9.1 % while the offline render showed a solid white slab over the top quarter of the flame. It now
  measures saturation after a Reinhard tonemap — the shape the game's own tonemapper and bloom put on
  the frame — and reports 19.5 %.

The offline preview is `tmp/hero-v3/plume_preview.py`: it reads the constants straight out of
`hero3_plume.gd` (so it can never disagree with them), rasterises the shell from the side at a fixed
world scale and the cap from behind, and writes `tmp/hero-v3/plume.png`. It is how causes 2 and 3 were
found without a window, and it is the fastest way to judge a tuning change before asking for a capture.

### r9 — the user's two defects, and why the walk looked wrong (lead brief r9 + the item 3 add-on)

The user watched the game and named two things: **"角色和地面浮空"** (the hero floats above the
ground) and **"走路飞行 喷气口还是错位的"** (the nozzles are in the wrong place), then asked
**"高达跑步走路为什么动作这么怪"** (why do the run and the walk look so weird). All three are below,
each with the number that pins the cause and the number after the fix.

#### 1. The hero floated — four separate causes, each measured

The measure is `tests/probe_float.gd`: the LOWEST SKINNED FOOT/TOE VERTEX of each planted foot, in
world space, against two floors — the RENDERED one (`ArtSurfaces`-style trimesh index, the settle
pass's own view of the world) and the COLLISION one (the physics ray every other gate uses).
Headless, 11 scenarios, every tick.

| # | cause | evidence |
| --- | --- | --- |
| 1 | `MechBuild.instance_model` never hung the model half a capsule below the body origin, which CONTRACTS §5 requires. **That is the 7.5 m.** | idle sole **7.36–7.48 m** above both floors, on flat, on a ramp and on a kerb |
| 2 | The mesh's origin is not at the sole and the two feet are not symmetric about it (L **0.100 m**, R **0.010 m** below). `Hero3SoleTrim` measures both off the bind poses at load — never typed. | after cause 1: idle sole **−0.14 m** (L) and **−0.02 m** (R), i.e. one boot inside the floor |
| 3 | `MechContact.update_model` negated the stick's z, so the gait read every walk, run, strafe and backpedal as its **own mirror image**: plants laid behind the mech, heel-to-toe roll reversed, lower-body yaw reversed. At 9 m/s the planted foot ended **9.7 m behind its hip** — past the end of a 6.16 m leg — the pelvis solve saturated at `MAX_DROP` and the mech skated on one foot. | walk p50 gap **+0.81 m**, p90 **+1.51 m**, only **23 %** of planted frames on the floor |
| 4 | `Hero3Foot`'s one-pivot-per-half roll left up to 0.16 m of residual, and the gait planted both feet on the BODY's plane rather than the floor under each foot. `Hero3Ground` is one ray per foot per tick. | after cause 3: walk **93 %**, worst **+0.16 m** |

`--hero3-mirror` and `--hero3-notrim` reproduce the BEFORE in the same binary as the fix, the same
discipline as `--hero3-plain`.

**Gate, AFTER** (`tools/godot.sh test res://player/model/hero3/tests/probe_float.gd`). `near` is the
share of planted-foot frames within ±0.10 m of that floor; `above` / `below` are the worst float and
the worst burial, in metres.

| case | state | m/s | RENDERED near / above / below | COLLISION near / above / below |
| --- | --- | --- | --- | --- |
| idle, sandbox flat | idle | 0.0 | **100 %** / −0.01 / −0.05 | 100 % / −0.01 / −0.05 |
| walk, sandbox flat | walk | 9.0 | **100 %** / +0.02 / −0.00 | 100 % / +0.02 / −0.00 |
| run, sandbox flat | run | 16.0 | **100 %** / +0.01 / −0.00 | 100 % / +0.01 / −0.00 |
| strafe, sandbox flat | walk | 9.0 | **100 %** / +0.02 / −0.00 | 100 % / +0.02 / −0.00 |
| turn in place | idle | 0.0 | **100 %** / +0.01 / −0.00 | 100 % / +0.01 / −0.00 |
| boost slide | slide | 42.0 | **100 %** / −0.00 / −0.05 | 100 % / −0.00 / −0.05 |
| hop landing | idle | 0.0 | **100 %** / −0.01 / −0.05 | 100 % / −0.01 / −0.05 |
| heavy landing (90 m drop) | idle | 0.0 | **100 %** / −0.01 / −0.05 | 100 % / −0.01 / −0.05 |
| walk, 19 deg ramp | walk | 9.0 | **100 %** / +0.02 / −0.00 | 100 % / +0.02 / −0.00 |
| idle, on the 2 m kerb | idle | 0.0 | **100 %** / +0.01 / −0.00 | 100 % / +0.01 / −0.00 |
| **walk, over the 2 m kerb** | walk | 9.0 | **75 %** / **+0.91** / **−1.11** | 75 % / +0.91 / −1.11 |

**The kerb row is reported, not hidden.** p50 and p90 are both ±0.00 — the bulk of the walk is perfect
and the outliers are the ~0.6 s while the capsule climbs. Root cause, measured: the capsule is
**3.5 m in radius**, so it rides up the 2 m step while the trailing foot is still 4.9 m back and 5.6 m
down — **7.45 m from a hip a 6.16 m leg cannot reach**. The gait is doing the right thing (the ground
ray puts each foot on the surface actually under it); the body climbs before the feet do. That is
`MechStepping`'s capsule step-up, not the model's, and it is a Request below.

Before / after, the whole chain in one table (sandbox flat, rendered floor):

| stage | idle gap | walk p50 / p90 | walk near |
| --- | --- | --- | --- |
| shipping | **+7.36 … +7.48 m** | — | 0 % |
| + the model drop | −0.14 … −0.02 m | +0.81 / +1.51 | 23 % |
| + the measured sole trim | −0.04 … −0.01 m | +0.81 / +1.51 | 23 % |
| + the stick's sign | −0.04 … −0.01 m | +0.01 / +0.08 | 93 % |
| + the roll profile and the per-foot ground ray | −0.05 … −0.01 m | **+0.00 / +0.00** | **100 %** |

#### 1b. A shipped bug the gate found on the way: `ArtSurfaces` measures a sinking world

`PhysicsServer3D.body_create()` returns a **DYNAMIC** body in Godot 4.7.2 + Jolt, and
`game/world/art/settle/surface_query.gd` never sets a mode. Every support it indexes therefore falls
at 9.8 m/s² from the tick it is created. Measured (`tests/probe_surface_mode.gd`): a support whose top
face starts at y = 0 is at **y = −4.94 one second later**; the same body with
`body_set_mode(BODY_MODE_STATIC)` stays at 0.000. That is the index the city settle pass drops
dressing onto AND the index `tools/float_audit.gd` reports from, so both are measuring a world that is
sinking under them. `game/world/art/**` is city-art's, so this gate uses `tests/hero3_surfaces.gd`, a
local copy with the one missing line, and the fix is a Request.

#### 2. The thrusters were in the wrong place — three faults in `hero3_rig.gd`

| fault | what it did |
| --- | --- |
| `_bone_tail` returned a point in **skeleton** space and it was assigned to a `BoneAttachment3D` child's position, which is **bone** space | the plumes floated over the hero's head and shoulders |
| the cone's origin is its **centre**, and it was placed AT the mouth | every plume started 1.7 m inside the mech |
| the shader's `along` divided the vertex by the node's **Y scale** instead of the cone's height | `along` left [0,1] and the bright ROOT was drawn at the FAR end — the detached flame the lead saw |

The nozzles are now **measured**, never typed (`Hero3Nozzle`): the rearmost face of the backpack on
each side, its centroid as the mouth, its mean surface normal as the exhaust axis, both in the bone's
own frame. `tests/probe_nozzle.gd` prints the whole back as a depth map so the choice is checkable by
eye.

**What the mesh actually has, measured:** no modelled port anywhere. The backpack's rearmost surface
is broad armour (mean radius 1.1–2.1 m, normal within 5° of straight back) and a calf's rearmost
surface is the calf itself (radius 1.0–1.1 m at knee height). So there are **two** plumes, both on
`BackFrame`, and **the calf flames are gone** rather than floating beside the knees. The plumes are
also placed from the bone pose every tick instead of riding a `BoneAttachment3D`, which only refreshes
on a process frame — that alone put the root 1.7 m off in any gate that steps the model by hand.

**Gate** (`tests/test_hero3_thruster.gd`) reads the plume mesh's own **base ring** — the vertices at
the cone's −Y end, which is the end the shader calls `along = 0` — and transforms them to world:

| state | throttle | root off the mouth | axis off |
| --- | --- | --- | --- |
| rest | 0.00 | **0.043 m** | 0.0° |
| walk | 0.00 | **0.043 m** | 0.0° |
| boost | 0.80 | **0.043 m** | 0.0° |
| hover | 0.45 | **0.043 m** | 0.0° |
| flight 50 m/s | 0.85 | **0.043 m** | 0.0° |
| flight 84 m/s | 1.00 | **0.043 m** | 0.0° |

Gate 0.30 m. The 0.043 m is the base ring's centroid against the mouth — the ring is a circle of
finite radius, so it is not zero and should not be. Walking has **no flame at all**:
`MechContact.thruster_level` is 0.0 in `GROUND`, and the shader multiplies by the throttle.

#### 3. Why the run and the walk looked wrong — filmed, measured, fixed

**Filmed first**, in the sandbox, from a fixed side camera at 34 m: `tmp/hero-v3/r9/film/`
(`before_*` is `--hero3-mirror --hero3-notrim`, `after_*` is the fix, same binary, same camera).
Clips: walk 9 m/s, run 16 m/s, the 42 m/s boost skate, a hard stop from 16 m/s, a strafe and a 180°
turn in place. The sheet is `captures/hero3_r9_gait_before_after.jpg`.

**The honest list of what read wrong, frame by frame:**

1. **The torso stood bolt upright at every speed.** Measured: the chest's pitch off vertical was a
   constant **−1.8°** — leaning slightly *backward* — at 0, 9, 16 and 42 m/s. A 16 m machine at 16 m/s
   that does not lean reads as a mannequin on a treadmill.
2. **The arms never moved.** Measured: **0.00 m** of hand travel fore/aft through a whole walk cycle.
   They hung straight down like a shop dummy's.
3. **Strafing was a duck-walk.** Measured: the pelvis travelled **2.17 m** per step with the solve
   pinned at `MAX_DROP` (2.45 m) — the exact "crouched duck-walk when strafing" the original brief
   names as a root cause.
4. **The skate had no lean and no plume.** The 42 m/s boost was a flat glide with the chest still at
   −1.8° and the backpack nozzles in the wrong place (item 2).
5. Everything else measured clean: the feet were already world-locked.

**The fixes, all in `hero3_gait` / `stance` / `posture` / `timing` / `pelvis`, no new rig:**

* **A locomotion lean that grows with speed** (`Hero3Gait.LOCO_LEAN_DEG = 9` at the run speed, scaled
  linearly). The spine chain takes it too (`Hero3Posture.LEAN_SHARE`): the spine writes are ABSOLUTE,
  so a leaning pelvis under a bolt-upright chest is a bow, not a lean — that is why the first attempt
  measured no change at all.
* **A mechanical arm counter-swing** (`Hero3Posture.ARM_SWING`, 5° peak), opposite the leg on the same
  side, with a third of it on the forearm so the elbow absorbs it.
* **Side-steps are short and quick** (`Hero3Timing.stride_scale`, cut by the lower-body yaw). At the
  full walk stride the planted foot ended **5.45 m** from a hip a 6.16 m leg cannot reach; the reach
  floor answered by dropping the hips 2.45 m. Side-steps are now 4.52 m at 1.99 steps/s against a
  walk's 6.60 m at 1.36.

**Measurements, BEFORE → AFTER** (`tests/probe_gait.gd`, headless, 600 ticks per case). `slip` is the
metres a PLANTED foot travels along the ground per step; `arm` is the peak-to-peak fore/aft travel of
the right hand; `torso` is the peak-to-peak chest yaw against the pelvis.

| case | slip / step (gate 0.05) | cadence | step | pelvis / step | arm | torso | lean | pelvis drop |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| walk 9 m/s | **0.000** | 1.36 /s | 6.60 m | 0.62 m | **0.55 m** (was 0.00) | 12.0° | **3.2°** (was −1.8) | 0.28–0.90 |
| run 16 m/s | **0.000** | 1.82 /s | 8.80 m | 0.62 m | **0.55 m** (was 0.00) | 12.0° | **7.2°** (was −1.8) | 0.28–0.90 |
| skate 42 m/s | **0.000** | — (a glide, no steps) | — | 0.37 m | 1.43 m (the brace) | 0.0° | **7.4–10.2°** | 0.93–1.30 |
| strafe 9 m/s | **0.000** | **1.99 /s** (was 1.36) | **4.52 m** (was 6.60) | **0.62 m** (was 2.17) | 0.55 m | 12.0° | 3.2° | **0.28–0.90** (was 0.28–2.45) |
| back 9 m/s | **0.000** | 1.36 /s | 6.60 m | 1.02 m | 0.55 m | 12.0° | −6.9° (leans back) | 0.28–1.30 |
| turn in place | **0.000** | 1.82 /s | 2.40 m | 0.18 m | 0.00 m | 0.0° | −1.8° | 0.00–0.18 |

**Costs paid, recorded rather than hidden.** The pelvis takes only **22 %** of the lean
(`PELVIS_LEAN_SHARE`) and a skate keeps its own authored brace, because a fully leaning pelvis folds
the knee far enough to drive the calf plate **0.141 m** through the thigh (`test_hero3_pieces`). The
arm swing is 5° and not 7° for the same reason: at 0.12 rad the upperarm plate went 0.053 m into the
clavicle. Both are inside the 0.05 m gate now (walk crouch 0.000, slide skate 0.007).

### r7 — the hero must read (lead brief r7 + the lead's art note on the work in progress)
The lead's finding: the Tianshu is a **black silhouette in every trailer shot**. The cause was
material-level, and every number below is measured rather than asserted.

**1. The emission mask is derived from the atlas, not hand-painted.**
`blender/hero3/hero3_uv.py` rasterises every bone's UV islands off the exported `hero3.glb`, because
the atlas is one 4K sheet of unrelated islands and a colour rule alone picks up every bronze screw on
the mech. `blender/hero3/hero3_emissive.py` then writes `hero3_Emission.png` (4K) and
`hero3_lod1_Emission.png` (2K):
* **R** — the steady cyan seams. hue 168–206°, S ≥ 0.35, V ≥ 0.24, a 5 px close / 3 px open so a seam
  survives as one continuous line and speckle does not, then a 1.6 px blur for a falloff.
  **1.78 %** of the atlas; **8–10 %** of every drone blade's own island (drones 5–7 carry none, which
  is why their tips are modelled).
* **G** — the vents: the amber hue rule restricted to the Head / Neck / Spine01 / Spine02 islands.
* **B** — the gold trim, so the shader can push metallic to 1 on the trim alone. **3.84 %**.

One command, re-runnable: `python3 blender/hero3/hero3_emissive.py --preview`.

**2. `hero3_shell.gdshader` replaces the Tripo material on the armour surface.** It reads the atlas
the glTF import already resolved (nothing hardcodes the uuid filename but the mask). All of its
tuning lives in `Hero3Shade.SHELL_TUNING`, so it is one place to read, one place to A/B, and
answerable from a test.

**3. The openings are the concept's geometry, not orange rectangles.** `art/concept/hero/v3/a1-1.png`
has a **portcullis** at the sternum — vertical gold bars with a warm amber cavity glowing between
them, brightest in the middle — and a thin amber slit for a visor. `hero3_glow.gdshader` draws
feathered additive panels with `stripes` lit gaps, `duty` of each period lit, the bars themselves at
`bar_gain` in gold, and a centre envelope. The visor is the same panel with no bars and its own gain.
Both are placed on the MEASURED front face of the plate that carries them; nothing is hand-placed.
**Note for the lead:** the art note said "horizontal slats"; the concept sheet is unambiguously
**vertical**, so that is what this builds.

**4. The rim is off in first person** — `Events.camera_mode_changed` drives it, and
`test_hero3_shade.gd` asserts `0.350 -> 0.000 -> 0.350`.

**5. The accents pulse.** The lines are steady; the vents ride `max(thruster level, overdrive)` and go
to full on a `charge_r` / `charge_slash` clip. Measured: idle 0.34, boost 0.98, charge 1.00, rest 0.34.
The overdrive tint now reaches the body, the weapons AND the modelled glow — `_apply_tint` used to
only touch surfaces that already emitted.

**6. Weapons and drones carry the accent language.** Seven modelled cyan drone tips; the saber, rifle
and shield edges at 1.1 emission energy with the rim on them.

#### What changed after the lead's art note
| | first pass | now | why |
| --- | --- | --- | --- |
| vent / visor | one unshaded box each, traffic orange, hard edges | feathered additive panels, #FFB040, portcullis stripes | the lead: "flat orange rectangles" |
| armour linear floor | 0.052, blue-biased | **0.020**, neutral | the lead: "the plates now read as blue-grey metal"; a blue floor plus a blue sky fill is what did it |
| armour fill | (0.10, 0.12, 0.15) sky / (0.11, 0.075, 0.05) ground, gain 0.55 | (0.055, 0.058, 0.065) / (0.070, 0.052, 0.036), gain 0.45 | same |
| rim | (0.42, 0.62, 0.85) at 0.55 | (0.55, 0.66, 0.82) at 0.35 | same |
| trim albedo | the Tripo tan at metallic 0.51 | forced to hue 54° at metallic 1.0, plus a 0.13 gold-tinted emission | a metal's colour is its albedo times the environment, and the environment at dusk is a warm orange wall that dragged the measured trim hue down by ~20° |

Three real bugs were in the way, all found by measuring rather than looking:
* **The panels were centred on the midpoint of the plate's front patch.** The helm's bounding box runs
  x −1.18..1.48 because of the crest, so that put the visor 50 cm off the face. Both openings are on
  the body's midline, so they are centred on the BONE, and their depth is measured under their own
  footprint rather than at the frontmost point of the whole patch.
* **Godot's `unshaded` path outputs ALBEDO and ignores EMISSION**, so the first version of the glow
  shader drew nothing at all. A lit surface with a black albedo emits only EMISSION, which is what an
  additive glow panel wants.
* **The measurement hook could not see through the post stack.** The first palette pass wrote the mask
  to emission on the shipping frame and the bloom spread it: 3.9 M "trim" pixels out of a 5.7 M frame.
  It now renders the mask with the world hidden and takes `|mask − background|` as the silhouette.

### r6 — `hero3_gait.gd` split, behaviour-identical
`hero3_gait.gd` was 764 lines, the largest script in the game. It is now **399**, split along the
responsibilities it already had, and the split is its own commit.

| file | lines | what it owns |
| --- | --- | --- |
| `hero3_gait.gd` | 399 | the state machine (`set_state` / `reset` / `update`), the pelvis solve, and the whole public API |
| `hero3_stepper.gd` | 254 | the phase clock, the step triggers, the landing spot, the world-locked plants, the footstep |
| `hero3_stance.gd` | 174 | the non-stepping stances (skate, FULL clip feet) and the hand-over to and from the planner |
| `hero3_sole.gd` | 89 | where each sole and ankle IS this instant, and the heel-to-toe roll |
| `hero3_yaw.gd` | 67 | the lower body's heading toward the travel: the yaw target, the lead foot, the roll sign |
| `hero3_air.gd` | 175 -> 196 | gained `set_state` / `want`: whether the legs belong in the air pose is its own decision now |

Callers did not change. `Hero3Gait.WALK_SPEED` and `Hero3Gait.LEGS` are still on the gait
(`LEGS` re-exports `Hero3Stepper.LEGS`); every other public method is unchanged in name and meaning.

**Behaviour identity, measured not asserted.** `tests/probe_pose_dump.gd` drives the model through a
scripted timeline and writes EVERY bone's global pose (origin + quaternion) every tick, then compares
two dumps itself (`--cmp=`). 21 segments: walk, run, strafe both ways, back-pedal, turn in place,
accelerate, stop, coast, slide, dash, hover, a forward diagonal, a hop, a heavy landing, and six
authored clips (`death`, `hit_knockdown`, `ram_kick`, `execution`, `plunge_land`, `melee_l1`).

```
POSE wrote ... (4007 frames, 32 bones)
CMP 132233 lines, worst 0.000000000000 m / 0.000000000000 rad
PASS identical within 0.000010 m / 0.000010 rad
```

**Every segment is 0.000 m / 0.000 rad** -- the two dumps are byte-identical, so the gate is met by
eight orders of magnitude, not by 1e-5. The harness is deterministic: two runs of the same code
produce identical files.

**The harness is mutation-tested.** The first version of this split had a real bug -- `stance.clips`
was never wired, so a FULL clip's foot targets went missing -- and the first timeline did NOT catch
it, because it had no clips in it. Two things came out of that: the timeline now plays the clips, and
re-breaking the wiring on purpose makes the gate fail loudly (`worst 3.755 m / 1.539 rad`,
`clip_death`). The `test_hero3_pieces` interpenetration gate is what found it in the first place
(`R_Calf/R_Thigh +0.753 m` on death and knockdown); it passes again with the baseline's own numbers.

### r5 item 9 — the interpenetration gate PASSES (commit cb2aa05)
Every one of the seven poses is now at or under the 5 cm gate on what the ANIMATION adds over the
exported rest mesh. The numbers were swept with two probes that reuse the gate's own metric
(`tests/probe_pieces.gd`, `tests/probe_clear.gd`), not guessed:

| pose | was | now | what moved |
| --- | --- | --- | --- |
| knockdown deepest | R_Calf/R_Thigh +0.707 | **0.000** | the soles slide 3.4 m forward instead of 2.3 at the same 3.10 m pelvis drop, so the knee sits at 89 deg instead of 125 |
| melee_l1 follow | R_Forearm/R_Hand +0.198 | **0.000** | `_slash`'s across-yaw 1.90 -> 1.52 |
| slide skate | R_Calf/R_Thigh +0.301 | **0.000** | `Hero3Skate` slide stagger 2.4 -> 3.2 at the same 1.30 m drop |
| death last frame | L_Forearm/L_Upperarm +0.114 | **0.000** | the arms barely move and the forearms straighten |
| guard_up | L_Forearm/L_Upperarm +0.098 | **0.011** | a straighter left elbow, the right arm in tighter |

`Hero3Skate.stance()` gained an `override` so a sweep can set a stance without editing the table.

### r5 "weight" — the landing (commit 8ca4738)
Measured frame by frame with a scratch probe against the brief's own numbers:

| | brief | measured |
| --- | --- | --- |
| heavy: pelvis down | 2.0–2.5 m within 3 frames | **2.300 m by frame 2** |
| heavy: knees fold, feet planted through the IK | — | knee **118.5 deg**, both soles on their plants |
| heavy: torso forward | 10–15 deg | chest **+12.0 deg** |
| heavy: arms down and out | — | upperarm z 0.62 rad, forearm -1.25 |
| heavy: hold | ~6 frames | **7 frames** (frames 2–8) |
| heavy: recover | ~0.3 s ease-out | cubic ease-out, back to 0 by frame 27 |
| light: dip | ~0.8 m | **0.80 m** at 14 m/s, 1.04 m at 20 m/s |

Depth scales with `Events.landed`'s impact speed: `lerp(0.80, 2.30)` over 14 -> 52 m/s
(`mech_tuning.heavy_feel_speed`). `MAX_DROP` 1.60 -> 2.45, measured: the hip sits 8.60 m up with a
5.90 m hip-to-ankle span and the 135 deg knee clamp leaves 3.07 m.

Two bugs were behind the softness, both found by measuring:
* `set_locomotion` runs every tick, so `begin_landing` RE-ARMED itself for the first six frames and
  pinned the dip at full depth. It is idempotent now.
* the air pose was still blending out while the pelvis sank, so the legs stayed tucked and the knee
  never folded at all — **46 deg at the deepest**, against 118 deg once the legs are planted. The air
  pose is now released the instant the body reports a landing.

### r5 "weight" — falling and hits
`fall` is a compact brace (torso curled 0.20 rad, arms tucked low and close). Past 15 m/s down
`Hero3Air.brace` brings the legs out from under the body and reaches them at the ground
(`BRACE_KNEE_DEG` 12, `BRACE_SPLAY` 1.30). New optional HeroModel method `set_fall_speed(down)`,
fed by `PlayerMech` from `-velocity.y` — see Requests. Hit reactions blend in 2 frames
(`HIT_BLEND` 0.033) so the clips' frame-3 peak survives.

### r5 the switch (commits 01f7601, eb6f972, 5526977, f93c5e7)
1. `HERO_MODEL` -> `res://player/model/hero3/hero3_model.tscn`. Everything that reaches the model was
   grepped: `mech_contact` (set_locomotion / set_thrusters / set_wings), `weapon_context`
   (play_action / socket / stop_action), `melee_system` (set_saber_drawn, play_action),
   `saber_visual` (has_own_blade / blade_length / socket), `defense_system`, `skill_system`
   (set_overdrive), `cockpit_frame` (socket), `camera_rig` (model position), `Feel` (hit_pause).
   All of it is HeroModel API (CONTRACTS §5).
2. **Aim** every physics frame: `model.set_aim(ctx.aim_point(), w)`. `w` -> 1 while `ctx.ads` or for
   0.55 s after `Events.weapon_fired`, rising over 0.10 s and falling over 0.45 s.
3. `stop_action` at guard end (`defense_system._end_guard`) and the moment the gatling's `_spin`
   reaches 0 (`gatling._update_ready`, through the new `WeaponContext.stop_action`).
4. **Hits and death** in `_apply_damage`: `hit_light` / `hit_heavy` by `tuning.hurt_heavy_damage`,
   `hit_knockdown` at or above `KNOCKDOWN_IMPULSE` (18 m/s of impulse), `death` HELD at 0 hp.
5. **Perfect parry** plays `parry` at both `parry_perfect` sites.
6. **Sweep direction**: `MeleeTable.SWEEP` is GENERATED — `test_hero3_reach.gd` prints the block ready
   to paste. Measured off the animated model: l2, l3, charge_slash and air_l2 end on the mech's
   right, the rest on its left; `blade_dir` multiplies the arc angle by that sign.
7. **Footsteps**: `Hero3Model` forwards `Hero3Gait.footstep` to `Events.footstep` +
   `Feel.play(&"footstep_heavy")` at the planted sole, and answers `owns_footsteps()` so
   `MechContact.footsteps` stands its timer down for a model with a gait.
8. **Cockpit eye**: `camera_blend.cockpit_point` low-passes the step bob against a 0.30 s baseline,
   keeps 35 % of it, and takes anything over 0.60 m whole so a landing still reaches the cockpit.
9. **The old hero is gone**: `player/model/hero/` (63 MB), its tests and gallery, `blender/hero/`
   and `data/hero_anim_map.json`, in its own commit. The three melee harnesses were repointed at
   hero3 first so they did not silently fall back to the placeholder.

### Lead's note on 01f7601 — the revive (commit eed3a7b)
`PlayerMech._dead` latched at 0 hp and nothing cleared it. `heal()` is the one place every revive
passes through (`flow_progress.gd` `_restore_player` sets `hp` then calls it), so it now clears
`_dead`, resets the aim feed and calls `stop_action`. `Hero3Model.stop_action` also clears
`current_action`, so "is the model still playing death" is answerable through the API.

### r8 — close-up polish, the flight pose, the drone API (lead brief r8)

#### 1. The grille interior (item 1)
The cream blotches were **the shell, not the panel**. `hero3_shell.gdshader` declared `vent_color`
(amber) and then emitted **`accent_color`** (cyan) through it, so every vent on the mech threw a
1.19-gain CYAN; a cyan that far over white, added to a warm gold sternum and run through the
tonemapper, is exactly the cream the lead saw. Attributed, not guessed: the look scene now renders
the same camera with `vent_gain` forced to 0, and muting the vents drops the crop's share of pixels at
S < 0.25 / V > 0.8 from **1.42 % to 0.21 %**, with the brightest pixel going from (245,222,173)
s = 0.29 to (243,155,55) s = 0.77.

The panel was also rebuilt. It is now **MIX-blended, not additive**: it draws its own dark cavity and
its own gold bars, so the atlas behind the cavity can never show through at all.

| gate | measured |
| --- | --- |
| white blotches inside the grille mask, 4 tods × 3 angles | **0.00 %** in all 12 frames (gate ≤ 1 %) |
| brightest pixel inside the grille | v 0.77–1.00 at **s 0.50–0.89** — bright and still amber |

#### 2. The visor streak (item 2)
The r7 visor was a **flat quad at the frontmost point under its own footprint**. On a domed helm that
is a tangent plane: measured (`probe_panel.gd`), it touched the armour at the midline and floated
**0.40 m in front of it at both ends** — the rod through the side of the helmet.

`Hero3Surface` samples the real surface over a 10 cm bucket grid and `Hero3Panel` builds a 13×7 sheet
whose every vertex lies ON the armour, dilated by its own cell diagonal so it is *provably* in front
of the mesh (that dilation is what fixed the chest plate's ridges poking back through a 3 cm offset
and showing the atlas as blotches). The panel also shrinks until the plate underneath covers all four
corners.

| gate | measured |
| --- | --- |
| visor-panel pixels outside the helmet mask, front / 3-4 / side, 4 tods | **0** (the helmet mask is grown by 4 px, which is `PROUD` at the look cameras' scale) |

**Two engine facts cost a whole round and are worth writing down.** Godot rejects `return` inside
`fragment()` — the shader failed to compile and the panel silently fell back to the engine's default
material. And the skinning attributes are `BONE_INDICES` / `BONE_WEIGHTS`, not Godot 3's `BONES` /
`WEIGHTS`; the broken bone mask drew the WHOLE body, which made the visor gate pass for free.
`tmp/hero-v3/glow.py` now fails loudly on an empty panel mask, a head mask that covers the body, or a
beauty frame identical to the flat mask — all three fired on the runs they were written for.

#### 3. The flight pose (item 3)
Before: the hero flew as a standing hover. `test_hero3_flight` measures the r7 rig at **1.08 m** of
trail, a foot **1.67 m** outboard of its own hip and both knees locked straight at **175.9 deg**.

`hero3_flight.gd` is self-contained on purpose: it measures the mech's own motion off the model node
(a child of the body, so its global transform IS the body's) rather than asking `PlayerMech`, which
mech-move r7 is editing this round. It produces a lean from the measured 3D speed, a bank from the
measured yaw rate against `turn_run_deg`, and the world direction the plumes run.

The lean and the bank are applied to the **model node**, about a pivot at the hips, because every bone
write in this unit is an absolute skeleton-space pose (`Hero3LegIk.set_pose`) — a pelvis rotation
carries nothing above it, so it is the only place that leans the whole machine. The legs are handled
in `Hero3Air`: a `flight` channel brings them back and together, and a `pitch` channel rotates the leg
offset with the body's lean (without it the legs hang straight down under a mech that is leaning into
its own flight path — the opposite of trailing).

| | brief | measured (city drive, log `FLIGHT` lines) |
| --- | --- | --- |
| lean at the 50 m/s cruise | ~25 deg | **26.7 deg** at 53.4 m/s |
| lean under the 84 m/s boost | "more" | **38.0 deg** at 83.3 m/s |
| bank from yaw rate | into the turn | **-19.2 deg** at -94.9 deg/s, **+27.5 deg** at +110 deg/s |
| legs trailing | back and together | **5.56 m** behind the hips, **0.10 m** outboard of each hip |
| knees | inside the clamp | **144 deg** |
| plumes | along the thrust | both backpack plumes within 0.9 of the flight path |
| interpenetration, flight poses | ≤ 5 cm | **0.028 m** (cruise and boost-banked) |
| `test_hero3_states` and the air suites | pass | pass |

The drive also shows the pose blending out cleanly on `land_heavy` (0.82 → 0.29 → 0.00).

#### 3b. The dead-mech lock (lead, from the mech-move acceptance)
* `Basis.scaled(float)` at `hero3_rig.gd:411` is now `scaled(Vector3.ONE * s)`. A flight drive logs
  **0 SCRIPT ERROR, 0 SHADER ERROR, 0 NANWATCH, errors=0**.
* A death taken in flight held its thrust and lean for the full 0.55 s blend-out. The plumes now stop
  **on the tick** the death clip takes hold and the lean is gone in **0.10 s** (`DEATH_BLEND`).
* A dead mech powers down: `Hero3Shade.power` fades the seam lines, the vents, the gold anchor, the
  weapon edges, the modelled visor and the drone tips over **1 s** and brings them back on the revive.
  `Hero3Model` latches `_dying` from `play_action(&"death")` / `stop_action()` — the edge
  `PlayerMech.heal()` uses. `--hero3-nopower` holds them on for the A/B.
  Evidence: `captures/hero3_death_power_before_after.jpg`; the deterministic numbers are in
  `test_hero3_flight` (`line_gain`, `gold_glow`, `vent_pulse` and the panel gain all measure exactly
  0 on a wreck and come back at their old values).

#### 3c. A shipped defect the new gate found
`test_hero3_pieces` had never played an **air clip**. Adding the flight poses, and then `fall`, `fly`
and `hover`, exposed that the air clips' 28–36 deg upperarm abduction drove the shoulder **1.498 m**
through the pauldron — in the shipping game, on every hover and every fall. `probe_fall.gd` sweeps the
authored numbers against the gate's own metric; the values now in `hero3_clips_move.gd` are its
result, not taste. All **12** poses now pass, worst 0.028 m.

#### 4. The per-drone hide API (item 4)
`Hero3Drones` owns the seven back-frame blades: the fan, and a mask that collapses an individual
drone's bone so its blade leaves the back while a fin is out. On `Hero3Model`:

| signature | meaning |
| --- | --- |
| `set_drones_docked(mask: int) -> void` | bit `i` (0-based) SET = `Drone_{i+1}` is deployed, its copy on the back is hidden; `0` shows all seven |
| `drones_docked() -> int` | read-back of the same mask |
| `set_drone_deployed(index: int, deployed: bool) -> void` | one at a time, 0-based |
| `drone_deployed(index: int) -> bool` | read-back |
| `drone_tip(index: int) -> Vector3` | where that drone is mounted, WORLD space, so a fin leaves its own blade |

The modelled cyan tip in `Hero3Glow` hides with its blade. **The lead's mapping**, which
`test_hero3_drones` asserts: `Drone_1..4` ride `wing_l` and `Drone_5..7` ride `wing_r`; `fins_max` is 6,
so 3 fins a side and **`Drone_1` (bit 0) always stays docked** — the mapped mask is `0x7E`.

#### 5. city-art r16 — NOT LANDED, left to the lead
`status/city-art.md` still has r15 as its newest section ("in progress"); only r16 items 5 and 6 are
committed (`1f2dd83f`, `6d905c65`). Per the brief this is left to the lead: when r16 lands, re-shoot
`tmp/hero-v3/gates.sh look` and `read` and update the readability and palette tables. The trim's
measured hue is a metal reflecting the environment, so it moves whenever the environment does.


## In progress / next
* **r10: the plume has never been seen in the GAME.** Every number above is headless and the look was
  judged from an offline render of the shader's own maths — which is how causes 2 and 3 were found,
  but it is not the shipping frame. The commands are under **Captures needed**; the lead judges the
  pixels.
* **`hero3_rig.gd` is 542 lines.** Under the 600-line hard trigger but well over the 400-line "consider
  splitting" one, and the thruster block (~110 lines: build, aim, scale, level, dir) is self-contained
  enough to move into its own `Hero3Plumes` node child. Left this round on purpose — it is a pure
  refactor with no visual payoff and the round's budget went on the look — but it is the next
  structural debt to clear.
* **r9 item 1: the city surfaces are NOT measured.** `probe_float.gd` has a `--world=city` path (it
  builds the same `ArtSurfaces`-style index over `Tiles` and the kit's `detail` batches), but the whole
  r9 table above is the SANDBOX: flat, a 19 deg ramp and a 2 m kerb. The brief also asks for the A1
  container yard, a deck and a kit rooftop. Those need a headless load of `res://world/city.tscn`
  inside the test host, which is a heavier run than the sandbox and did not fit this round's budget.
  The physics is the same code path either way — `Hero3Ground` rays `Layers.WORLD` and
  `probe_float.gd` rays the rendered index — so the city numbers are a re-run, not a new mechanism.
* **r9 item 1: the 2 m kerb row is 75 %, and the cause is not mine.** See the kerb paragraph in the
  r9 section and the Request below. Standing ON the kerb is 100 %; only the ~0.6 s while the capsule
  climbs is out.
* **r9 item 3: no dust or sparks on the 42 m/s skate.** The brief asks for the run-to-skate change to
  be "sold with lean, sparks and dust". The LEAN is in (7.4-10.2 deg) and the backpack plumes now
  fire correctly, which is most of the read; the sparks and the dust are `game/fx/**` and
  `game/flow/**`, other units' files, so they are a Request rather than a change.
* **city-art r16 has NOT landed.** `status/city-art.md` still has r15 as its newest section; only r16
  items 5 and 6 are committed. The readability numbers, the palette table and both sheets have to be
  re-shot when it does — the trim's measured hue is a metal reflecting the environment, so it moves
  whenever the environment does. Left to the lead per the brief.
* **The `fall` brace is a weaker pose than it was.** The interpenetration gate forced the arms in
  (spread 0.62 -> 0.18 rad, elbow fold -1.35 -> -0.75 rad) and the chest curl from -0.20 to -0.12 rad.
  That is the price of not driving a plate 1.5 m through a pauldron, and `probe_fall.gd` says it is the
  best of the combinations swept — but a designer may want to re-author the arm silhouette with the
  mesh in view rather than accept the swept numbers.
* **The gate frames were shot on city-art r15 as accepted** (lead commit 79c69d3, "r15 accepted as a
  step; warmth, hatch, HDRI and tod 1.0 carried to r16"). When r16 lands, the readability numbers,
  the palette table and both sheets have to be re-shot: the trim's measured hue in particular is a
  metal reflecting the environment, so it moves whenever the environment does.
* The s04 combat camera in the readability probe is the game's own third-person rig, copied after a
  4 s settle (the rig lerps toward the player, so a 400 m teleport needs seconds before its arm is
  where the take would have it; at 0.5 s it was still 95 m out and framed a vista). It is the least
  stable of the three — the arm pushes out on collision — so treat its row as indicative.

## How to verify (exact commands)
```
# ---- r10: the plumes -----------------------------------------------------------------------
tools/godot.sh test res://player/model/hero3/tests/test_hero3_thruster.gd   # 23 checks, the whole table above
tools/suites.sh --only=hero3,hero3_pelvis,hero3_body,hero3_release,hero3_states,hero3_ground,\
hero3_aim,hero3_reach,hero3_casts,hero3_melee,hero3_fk,hero3_ik,hero3_pose,hero3_tree,hero3_skin,\
hero3_pieces,hero3_shade,hero3_drones,hero3_flight,hero3_thruster           # 20 rows, 20 green
python3 tmp/hero-v3/plume_preview.py --out=tmp/hero-v3/plume.png            # the offline look render
# ---- r9: the three gates, in one place -------------------------------------------------
tools/godot.sh check --only=res://player/                    # 153 files, 0 failed, 0 errors
# item 1 -- the float. 11 scenarios, headless, every tick, both floors.
tools/godot.sh test res://player/model/hero3/tests/probe_float.gd --timeout=1500
tools/godot.sh test res://player/model/hero3/tests/probe_float.gd -- --nofix=1 --hero3-mirror   # the BEFORE
tools/godot.sh test res://player/model/hero3/tests/probe_float.gd -- --world=city --timeout=1500
tools/godot.sh test res://player/model/hero3/tests/probe_surface_mode.gd   # the ArtSurfaces finding
# item 2 -- the nozzles. The measurement, then the gate.
tools/godot.sh test res://player/model/hero3/tests/probe_nozzle.gd -- --bone=BackFrame --mouth=0.35 --ywin=11.6,15.4 --nrm=0.55
tools/godot.sh test res://player/model/hero3/tests/probe_nozzle.gd -- --bone='*' --win=-4.5,4.5,10.0,17.5   # the depth map
tools/godot.sh test res://player/model/hero3/tests/probe_nozzle.gd -- --bone=R_Calf --mouth=0.3           # no calf port
tools/godot.sh test res://player/model/hero3/tests/test_hero3_thruster.gd
# item 3 -- the gait.
tools/godot.sh test res://player/model/hero3/tests/probe_gait.gd
tools/godot.sh test res://player/model/hero3/tests/probe_gait.gd -- --case="strafe 9 m/s" --debug=1   # the reach trace
# the films (windowed, corner window, ~1 min each). --hero3-mirror --hero3-notrim is the BEFORE.
tools/godot.sh movie --movie=$PWD/tmp/hero-v3/r9/film/after_side.avi \
    --timeline=res://player/model/hero3/tests/timeline_gait.json --side=90 \
    --scene=res://player/model/hero3/tests/hero3_city_shot.tscn --stub=camera,flow,hud --sandbox \
    --skip-menu --no-enemies --god --dist=34 --height=8 --look=8
#   ... the same line with --side=135 (the 3/4) and --hero3-mirror --hero3-notrim (the BEFORE), and
#   timeline_gait_turn.json at --side=180 for the strafe and the 180 deg turn.
# the foot-height and thruster captures
tools/godot.sh drive --scene=res://player/model/hero3/tests/hero3_city_shot.tscn \
    --timeline=res://player/model/hero3/tests/timeline_float_shots.json --shots=1.5,4.0,9.5,15.5 \
    --out=hero3_r9_foot_sandbox --shots-dir=$HOME/m/mecha-city/captures \
    --side=90 --dist=19 --height=4 --look=2 --stub=camera,flow,hud --sandbox --skip-menu --no-enemies --god
tools/godot.sh drive --scene=res://player/model/hero3/tests/hero3_city_shot.tscn \
    --timeline=res://player/mech/timelines/flight.json --shots=1.6,5.0,9.0 \
    --out=hero3_r9_thrust_side --shots-dir=$HOME/m/mecha-city/captures \
    --side=75 --dist=24 --height=6 --look=2 --stub=camera,flow,hud --sandbox --skip-menu --no-enemies --god
# ---- the standing suites ----------------------------------------------------------------
tools/godot.sh check                                                     # 727 files, 0 errors
tools/godot.sh test res://player/model/hero3/tests/test_hero3.gd          # gait + sockets + actions
tools/godot.sh test res://player/model/hero3/tests/test_hero3_shade.gd    # r7: the material layer
tools/godot.sh test res://player/model/hero3/tests/test_hero3_pelvis.gd    # A1
tools/godot.sh test res://player/model/hero3/tests/test_hero3_skin.gd      # A2 + A3 + A4 (slow)
tools/godot.sh test res://player/model/hero3/tests/test_hero3_body.gd      # A5 + A6
tools/godot.sh test res://player/model/hero3/tests/test_hero3_release.gd   # r4 items 1, 4, 5
tools/godot.sh test res://player/model/hero3/tests/test_hero3_states.gd    # r4 item 2
tools/godot.sh test res://player/model/hero3/tests/test_hero3_ground.gd    # r4 item 3
tools/godot.sh test res://player/model/hero3/tests/test_hero3_aim.gd       # r4 item 6
tools/godot.sh test res://player/model/hero3/tests/test_hero3_reach.gd     # r4 item 7 + r5 item 6
tools/godot.sh test res://player/model/hero3/tests/test_hero3_casts.gd     # r4 item 8
tools/godot.sh test res://player/model/hero3/tests/test_hero3_pieces.gd    # r4/r5 item 9 + r8 flight (slow)
tools/godot.sh test res://player/model/hero3/tests/test_hero3_drones.gd    # r8 item 4: the per-drone hide API
tools/godot.sh test res://player/model/hero3/tests/test_hero3_flight.gd    # r8 item 3: lean, bank, legs, death, power
tools/godot.sh test res://player/model/hero3/tests/test_hero3_melee.gd     # melee frames + sweep
tools/godot.sh test res://player/mech/tests/test_damage.gd                 # hits, death, revive
tools/godot.sh test res://combat/melee/tests/test_melee.gd
tools/godot.sh test res://combat/defense/tests/test_defense.gd
tools/godot.sh test res://combat/weapons/tests/test_weapons.gd
tools/godot.sh test res://player/camera/tests/test_camera.gd
tools/godot.sh test res://flow/tests/test_flow.gd -- --sandbox --flow --spawn=0,1,60   # 194 checks

# r7 — the mask, re-runnable from one command (the --uv rasters come from hero3_uv.py)
tools/blender.sh run blender/hero3/hero3_uv.py -- --res=1024
python3 blender/hero3/hero3_emissive.py --preview

# r8 items 1 and 2 — the close-up gates. The capture writes a beauty frame plus the panel, helmet and
# no-glow masks per camera; glow.py measures both gates off them and FAILS if a mask is not real.
tmp/hero-v3/retry.sh tmp/hero-v3/look_r8.log tools/godot.sh shot \
    --scene=res://player/model/hero3/tests/hero3_look.tscn --out=look --times=1800 \
    --look-tods=0,0.5,0.85,1.0 --look-warm=30 --look-tag=r8 --look-debug=glow \
    --look-angles=front,front34,side --skip-menu --no-enemies --god
python3 tmp/hero-v3/glow.py --tag=r8            # -> the two gate tables
python3 tmp/hero-v3/look.py --tag=r8            # -> captures/hero3_glow_vs_concept.jpg

# r8 item 3 — the flight pose, sandbox and city, with the lean/bank numbers in the log
tools/godot.sh drive --sandbox --skip-menu --no-enemies --nan-watch \
    --timeline=res://player/mech/timelines/flight.json --shots=1.6,2.6,3.8,5.0,6.0,8.0,10.5 \
    --out=hero3_flight_sandbox --shots-dir=$HOME/m/mecha-city/captures
tools/godot.sh drive --scene=res://player/model/hero3/tests/hero3_city_shot.tscn \
    --timeline=res://player/model/hero3/tests/timeline_flight_city.json \
    --stub=camera,flow,hud --no-enemies --god --spawn=-560,60,600,54 \
    --side=144 --dist=26 --height=2 --look=8 --shots=2.0,4.0,5.6,7.2,9.4,11.0 \
    --out=hero3_flight_city --shots-dir=$HOME/m/mecha-city/captures --nan-watch

# r8 item 3b — the death-pose A/B (--hero3-nopower is the BEFORE, in the same binary)
tools/godot.sh drive --scene=res://player/model/hero3/tests/hero3_city_shot.tscn \
    --timeline=res://player/model/hero3/tests/timeline_death.json --stub=camera,flow,hud \
    --no-enemies --spawn=-560,7.5,600,54 --side=200 --dist=30 --height=4 --look=6 \
    --shots=0.5,1.6,3.6 --out=hero3_death_after --shots-dir=$HOME/m/mecha-city/captures
#   ... the same line with --hero3-nopower and --out=hero3_death_before

# r8 item 3c — the fall-clip sweep that produced the authored numbers
tools/godot.sh test res://player/model/hero3/tests/probe_fall.gd

# r7 — every gate in one place. Each step retries until a machine-wide 'heavy' slot frees up.
tmp/hero-v3/gates.sh look        # the lit close-up sheet + the palette masks
tmp/hero-v3/gates.sh read        # the readability numbers, AFTER
tmp/hero-v3/gates.sh readplain   # the same probe with --hero3-plain: the BEFORE baseline
tmp/hero-v3/gates.sh perf        # the A1-spawn cost A/B
python3 tmp/hero-v3/look.py --tag=r7        # -> captures/hero3_look_vs_concept.jpg + hero3_glow_vs_concept.jpg
python3 tmp/hero-v3/palette.py --tag=r7     # -> the black-and-gold gate
python3 tmp/hero-v3/read.py --tag=r7after   # -> the readability gate
python3 tmp/hero-v3/read.py --tag=r7before

# r6: prove the gait still produces the SAME skeleton, bone by bone, over a scripted timeline.
tools/godot.sh test res://player/model/hero3/tests/probe_pose_dump.gd -- \
    --out=$HOME/m/mecha-city/tmp/hero-v3/pose.txt \
    --cmp=$HOME/m/mecha-city/tmp/hero-v3/pose_baseline.txt
# the side-view evidence harness (the real game under a fixed side camera)
tools/godot.sh drive --scene=res://player/model/hero3/tests/hero3_city_shot.tscn \
    --timeline=res://player/model/hero3/tests/timeline_drop.json \
    --stub=camera,flow,hud --no-enemies --spawn=-560,7.5,600,0 \
    --side=235 --dist=36 --height=2 --look=4
```

## Evidence
All in `captures/` (git-ignored, on disk).

### r10
| file | what |
| --- | --- |
| `tmp/hero-v3/plume.png` | **the look, rendered offline from the shader's own maths**: the plume from the side at throttle 0.00 / 0.45 / 0.80 / 1.00 at a fixed world scale, and from directly behind. Hot white head, cyan body, soft edges, visible shock-diamond banding, a soft-edged glowing disc from the rear. |
| `tmp/hero-v3/plume_preview.py` | the renderer. Reads its constants out of `hero3_plume.gd`, so it cannot disagree with the shader. |
| `tmp/hero-v3/r10_suites.log` | the 20 hero3 suite rows. |
| the test's own stdout | every number in the r10 gate table, printed as `PLUME …` / `THRUST …` lines. |

### r9
| file | what |
| --- | --- |
| `hero3_r9_gait_before_after.jpg` | item 3. Six rows: BEFORE / AFTER x walk, run, 42 m/s skate, same camera, same binary. BEFORE is `--hero3-mirror --hero3-notrim`. |
| `hero3_r9_thruster_states.jpg` | item 2. Walk from behind (NO flame), the 42 m/s skate from behind (two plumes on the back armour), and three flight frames from the side. |
| `hero3_r9_foot_surfaces.jpg` | item 1. Side views at foot height: sandbox flat idle, flat walk, the 19 deg ramp, the deck at the top of it. |
| `tmp/hero-v3/r9/film/{before,after}_{side,34,front}.avi` | the 26 s and 10.5 s films the sheets are cut from. `before_side` was re-shot at the matched camera; `before_34` and `before_front` are still at the older 46 m framing, so compare those two against each other and not across. |
| `tmp/hero-v3/r9/final.log` | the whole r9 regression in one file: the float table, the gait table, the thruster gate and the six mech-move suites. |

| file | what |
| --- | --- |
| `hero3_glow_vs_concept.jpg` | **r8 items 1+2**: 3x crops of the visor and the chest grille at 4 times of day, beside the same two regions of the concept. The grille reads as clean amber-lit bars over a dark cavity and the visor is a contained slit. |
| `hero3_flight_city_strip.jpg` | **r8 item 3**: the city flight from a fixed side camera — climb, cruise, bank, boost, descend, land, each cell labelled with its measured lean and speed |
| `hero3_flight_sandbox_t*.jpg` | **r8 item 3**: the sandbox `player/mech/timelines/flight.json` run, game camera |
| `hero3_death_power_before_after.jpg` | **r8 item 3b**: the death pose BEFORE (`--hero3-nopower`, lights held on) beside AFTER (powered down), two moments each |
| `hero3_read_before_after.jpg` | **r7 gate 2**: the three trailer cameras, BEFORE (`--hero3-plain`) left, AFTER right |
| `hero3_look_vs_concept.jpg` | **r7 gate 1**: the concept down the left, then 4 times of day × 4 angles in the city |
| `hero3_glow_vs_concept.jpg` | **r7, the lead's art note item 1**: 3× crops of the visor and the chest portcullis at 4 times of day, beside the same two regions of the concept |
| `hero3_emission_mask.jpg` | the atlas, the three mask channels and the mask laid over the atlas, per LOD |
| `hero3_r5_drop_before_after.jpg` | **the sheet for the user**: 20 m drop in the city, 8 frames, BEFORE (old hero) over AFTER (Tianshu) |
| `hero3_r5_drop_after.mp4` / `hero3_r5_drop_before.mp4` | the same drop as video, side view |
| `hero3_r5_hop_before_after.jpg` | a plain hop, same A/B |
| `hero3_r5_game_melee.jpg` | melee_l1 -> l2 -> l3 -> follow-through, game camera |
| `hero3_r5_game_fire.jpg` | aim, fire_r, rifle coming down, game camera |
| `hero3_r5_game_guard_parry.jpg` | guard_up, guard held, parry, guard released |
| `hero3_r5_game_dash_slide.jpg` | dash_f and the slide skate, game camera |
| `hero3_r5_first_person_walk.mp4` | 4 s of first-person running with the eye low-pass |
| `drive_t1_0.jpg` / `drive_t4_0.jpg` / `drive_t8_0.jpg` | r6: the 15 s combat drive re-run after the split |

### r8 gate numbers

**Close-ups** (`tmp/hero-v3/glow.py --tag=r8`, 4 times of day × front / front-3-4 / side = 12 frames):

| gate | measured |
| --- | --- |
| white blotches (S < 0.25, V > 0.8) inside the grille mask, ≤ 1 % | **0.00 %** in all 12 |
| visor-panel pixels outside the helmet mask, = 0 | **0** in all 12 (helmet mask grown by `PROUD` = 4 px) |
| brightest pixel inside the grille | v 0.77–1.00, **s 0.50–0.89** — bright and still amber |

**Flight** (`test_hero3_flight`, and the `FLIGHT` lines a city drive prints at 4 Hz):

| | r7 (before) | now |
| --- | --- | --- |
| feet behind the hips at the cruise | 1.08 m | **5.56 m** |
| a foot outboard of its own hip | 1.67 m | **0.10 m** |
| knee | 175.9 deg (locked straight) | **144 deg** |
| lean at 53 m/s | 0 | **26.7 deg** |
| lean at 83 m/s | 0 | **38.0 deg** |
| bank at 120 deg/s | 0 | **30.0 deg** |
| flight-pose interpenetration | not measured | **0.028 m** (gate 0.05) |
| a death in flight holds its thrust for | 0.55 s | **0 ticks** |
| a wreck's emissives | fully lit | **0.0** on `line_gain`, `gold_glow`, `vent_pulse` and the grille panel |

**The air clips' interpenetration**, which no pose in the gate had ever played:

| pose | r7 | now |
| --- | --- | --- |
| `fly` / `hover` standing | **1.498 m** (R_Clavicle/R_Upperarm) | 0.028 / 0.000 m |
| `fall` brace | 0.113 m | **0.000 m** |
| flight cruise / boost banked | not measured | 0.028 m |

**Suites:** every hero3 suite PASSES (`test_hero3`, `_shade`, `_drones`, `_flight`, `_pelvis`, `_body`,
`_release`, `_states`, `_ground`, `_aim`, `_reach`, `_casts`, `_melee`, `_fk`, `_tree`, `_skin`,
`_pieces`); `test_damage` **21/21**; `test_melee`, `test_defense`, `test_weapons`, `test_camera` no
failures; `tools/godot.sh check` **800 files, 0 errors**; a flight drive logs **0 SCRIPT ERROR,
0 SHADER ERROR, 0 NANWATCH, errors=0**.

### r7 gate numbers

**Readability at the trailer's own cameras** (`--tod 0.6`, the same binary both times; BEFORE is the
same run with `--hero3-plain`, i.e. the Blender materials exactly as exported):

| camera | dark BEFORE | dark AFTER | hero luma | ring luma | ratio | clip (outside the cores) |
| --- | --- | --- | --- | --- | --- | --- |
| s01 cold open | **49.1 %** | **7.9 %** | 0.056 -> 0.150 | 0.279 | 0.19 -> **0.54** | 0.01 % |
| s03 drop | **29.8 %** | **6.0 %** | 0.071 -> 0.163 | 0.307 | 0.23 -> **0.53** | 0.00 % |
| s04 combat | **31.1 %** | **5.3 %** | 0.076 -> 0.149 | 0.252 | 0.30 -> **0.59** | 0.11 % |

Gate `dark <= 40 %`: **PASS** (worst 7.9 %), and the SAME probe with `--hero3-plain` FAILS it at
**49.1 %** — which is the lead's original complaint, measured. Gate `clip <= 0.3 % outside the accent
cores`: **PASS** (worst 0.11 %; inside the cores it is 0.17 %, which the brief exempts).

`captures/hero3_read_before_after.jpg` is the A/B sheet: the three trailer cameras, BEFORE on the left
and AFTER on the right, from the same binary and the same light.

**Black-and-gold** (16 frames = 4 times of day × 4 angles, masks rendered with the world hidden so the
trim and the plates are identified exactly, measured on the beauty frame):

| metric | gate | measured |
| --- | --- | --- |
| trim hue | 35–55° | median **38.0°**, range 32.4–40.0°; **13 of 16 in band** |
| plates darker than the trim | yes | **16 of 16** (trim 0.23–0.39 luma, plates 0.09–0.21) |
| plates not blue-grey | B−R ≤ 0.02 | median **−0.010**; 13 of 16, worst +0.034 on the rear-34 camera at the two coolest times |

The three hue misses are the front-on cameras at tod 0.85 and 1.0, where the wall the mech stands in
front of is itself 25–30° orange and a metal reflects it. See "In progress / next".

**Shader cost at the A1 spawn** (`tools/godot.sh perf --spawn=-449,10,410,45 --warm=10`):
36 fps with `--hero3-plain`, **38 fps** with the shell. The gate is ≤ +0.2 ms and the measurement is
negative, i.e. inside the noise — note the world's primitive count differed by 3 % between the two
runs, so this is a "no measurable cost" result rather than a precise one.

**Other numbers:**
* `test_hero3_shade.gd`: shell bound to all four textures; lift **0.021 linear**, neutral to within
  0.001 (the test fails a blue bias on purpose); gold metallic **1.00**, roughness band (0.26, 0.40),
  gold albedo hue 0.151 turns = 54°; vents idle **0.34** -> boost **0.98** -> charge **1.00** ->
  rest **0.34**; overdrive tint **1.00** reaching the body, the edges and the drone tips; rim **0.350**
  third person -> **0.000** first person -> **0.350**; visor at (0.00, 14.56, −0.76), vent at
  (0.00, 12.00, −1.98), **7** bars, **7** drone tips, panel gain 0.32.
* r7 mask: lines **1.78 %** of the atlas, vents 0.15 %, gold **3.84 %**.
* r6 pose identity: **4007 frames × 32 bones × 21 segments, worst 0.000 m / 0.000 rad**.
* All hero3 suites PASS (`test_hero3`, `_shade`, `_pelvis`, `_body`, `_release`, `_states`, `_ground`,
  `_aim`, `_reach`, `_casts`, `_melee`, `_fk`, `_tree`, `_skin`, `_pieces`); `test_damage` **21/21**;
  `test_melee`, `test_defense`, `test_weapons`, `test_camera` no failures; `test_flow`
  **194 checks, 0 failed**; `tools/godot.sh check` **727 files, 0 errors**.
* `probe_eye.gd`: the gait's pelvis bob reaches the `cockpit` socket at FULL amplitude — pelvis
  7.700–8.249, head 12.950–13.499, cockpit 12.240–12.789, all a 0.549 m swing at walk AND at run.
* The first-person image measurement (`tmp/hero-v3/shake.py`): **1.42 px raw vs 1.08 px filtered**.

## Captures needed (the lead runs these in an approved window; `MC_WINDOW_OK=1`)

**r10 — the plume close-ups.** The lead asked for behind and side, at walk, boost, hover and flight
boost. `timeline_plume.json` is one 17 s run that does all four in order (walk, boost dash, hover,
assault), so the two cameras shoot the SAME take and the cells are comparable. The harness prints a
`PLUME state=… speed=… throttle=…` line at 4 Hz, so the log says which frame is which throttle — the
shot times below are a first guess and the timeline is mine if they need moving.

```
# from BEHIND (--side=0 is straight down the mech's back at spawn yaw 0)
tools/godot.sh drive --scene=res://player/model/hero3/tests/hero3_city_shot.tscn \
    --timeline=res://player/model/hero3/tests/timeline_plume.json \
    --shots=3.0,6.4,10.6,15.0 --out=hero3_r10_plume_behind --shots-dir=$HOME/m/mecha-city/captures \
    --side=0 --dist=15 --height=6 --look=5.5 --stub=camera,flow,hud --sandbox \
    --skip-menu --no-enemies --god --nan-watch

# from the SIDE
tools/godot.sh drive --scene=res://player/model/hero3/tests/hero3_city_shot.tscn \
    --timeline=res://player/model/hero3/tests/timeline_plume.json \
    --shots=3.0,6.4,10.6,15.0 --out=hero3_r10_plume_side --shots-dir=$HOME/m/mecha-city/captures \
    --side=90 --dist=15 --height=6 --look=5.5 --stub=camera,flow,hud --sandbox \
    --skip-menu --no-enemies --god --nan-watch
```

The nozzles sit ~5.5 m above the body origin (`Hero3Nozzle` measures the pack at y 11.6–15.4 in the
16 m model frame, and CONTRACTS §5 hangs the model 7.5 m below the body), so `--look=5.5 --height=6`
frames the backpack and `--dist=15` is a close-up. If the mech leaves frame, raise `--dist`.

**Still wanted from earlier rounds** (unchanged, listed in the sections above): the r9 gait
before/after films, the float surfaces sheet and the r8 flight/close-up sheets, all of which are
already on disk.

## Known issues
* **`test_last_stand` is 10/12 and is NOT mine.** Both failures are the director half ("the director
  plays the row on a crossing hit", "time_scale is 0.5x"), and `status/feel.md` documents the cause and
  the fix: `_test_pipeline()` runs five crossings after the director is in the tree and the first one
  already spends the row's 60 s cooldown, so `_test_director()`'s first play returns 0. Feel cannot
  edit mech-move's file. It fails identically before and after r9 — I touched `player/mech` only in
  `mech_build.gd` and `mech_contact.gd`, neither of which is on that path.
* **`probe_gait.gd`'s skate cadence column is meaningless.** A 42 m/s boost is a glide with no steps,
  so `report()["cadence"]` is reporting the timing module's leftover value, not a real cadence. The
  row's `pelvis`, `arm` and `lean` columns are real.
* **The pixel A/B of the power-down is noisy across two runs.** The two captures are separate drives,
  so the world lighting and the death animation's phase are not frame-identical and a whole-frame
  cyan/amber count moves by tens of percent on its own. The DETERMINISTIC evidence is
  `test_hero3_flight`, which measures every emissive gain at exactly 0 on a wreck and back at its old
  value on the revive; the sheet is there to be looked at, not counted.
* **The glow panel is lit, so it takes the helmet's shadow.** Measured: a flat 0.5-grey override on the
  visor renders at ~0.3 display under this light, i.e. the panel receives ambient only. That is fine
  for the grille (dark gaps are what the concept wants) and the visor's read comes from its emission,
  but a future pass that wants the gold BARS to catch the sun will have to move the panel off the
  shadow caster or give it its own light.
* **The eye low-pass buys less than the brief expected.** The pelvis bob does reach the cockpit
  socket at full amplitude (0.549 m, measured), but a pure vertical TRANSLATION of a first-person
  camera barely moves the image: the horizon does not shift and only near geometry parallaxes. The
  filter is in and measurably helps (1.42 -> 1.08 px), but the first-person view was never rattling
  the way the third-person one does.
* **The character fill is a cheat and is labelled as one.** At `--tod 0.6` the sun is behind the mech
  and the only light on the camera side is the ambient, so a black dielectric has no form at all
  (measured: 46 % of the hero's pixels under 0.03 display luma). `fill_gain` is a hemisphere term
  added to EMISSION, on the same third-person switch as the rim. It is a hemisphere rather than a
  constant so the plates still separate from each other instead of flattening into one grey mass, but
  it is not physical and the lead should know it is there.
* **The trim's hue is environment-dependent** because the trim is a metal. The 0.13 gold-tinted
  emission is what anchors it; if the lead would rather the trim not be self-lit at all, that number
  is the one to turn down, and the hue gate will follow the environment.
* **One engine error in the city drive, not mine**: `res://world/art/settle/settle.gd:193
  CitySettle.report(): Invalid access to property or key 'rays' on a base object of type 'Nil'`.
* The knockdown's arms now barely move (the pauldron crossed the upperarm by 0.92 m at the first
  pass's swing). The knockdown reads through the root drop, the torso throw and the feet sliding
  3.4 m forward instead.
* `data/hero_motions.json` is now unreferenced by anything in the tree. Left in place: it looks like
  a Tripo input manifest rather than something only the old hero used.

## Requests (to the lead / other units)
* **city-art — `ArtSurfaces` indexes a world that is FALLING.** One line, high value.
  `PhysicsServer3D.body_create()` returns a DYNAMIC body in Godot 4.7.2 + Jolt and
  `game/world/art/settle/surface_query.gd` never sets a mode, so every support it adds falls at
  9.8 m/s^2 from the tick it is created. Measured in `tests/probe_surface_mode.gd`: a support whose
  top face starts at y = 0 is at **y = -4.94 one second later**; the same body with
  `PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)` stays at 0.000 for the whole
  run. That index is what `CitySettle` drops the city's dressing onto AND what `tools/float_audit.gd`
  reports from, so both are measuring a world that sinks under them — the settle pass by up to a
  second of fall, the audit by however long it holds the index. The fix is one line in `add()`, right
  after `body_create()`. `tests/hero3_surfaces.gd` is my local copy with that line, used by
  `probe_float.gd` until it lands; it can be deleted the moment it does.
* **mech-move — the capsule climbs a 2 m step before the feet do.** Measured on the sandbox kerb
  (`probe_float.gd`, `walk_kerb`): for about 0.6 s the trailing foot is **7.45 m from its hip** on a
  **6.16 m** leg, because the 3.5 m-radius capsule has already ridden up the step while the foot is
  still 4.9 m back and 5.6 m down. The model's answer is right (each foot is planted on the surface
  actually under it, `Hero3Ground`), and standing on the kerb is 100 % inside the gate; it is the
  hand-over between `MechStepping`'s capsule step-up and the gait's plant that leaves the leg
  over-extended. A gait-side mitigation exists (force an early step for a foot whose plant is past
  `reach_max`), but it would break the phase-locked cycle, so it is a design call rather than a patch.
* **feel / fx — the 42 m/s skate wants sparks and dust.** r9 item 3 asks for the run-to-skate change
  to be sold with "lean, sparks and dust". The lean (7.4-10.2 deg) and the backpack plumes are in; the
  ground dust under a 42 m/s skid and the thruster sparks on each push-off are `game/fx/**`. A
  `Feel.play` id fired from `Hero3Gait`'s existing `footstep` signal at high speed would be the
  smallest hook.
* **skills r4 — the per-drone hide API is live (lead r8 item 4).** Exact signatures, all on
  `Hero3Model`, all callable behind `has_method`:
  `set_drones_docked(mask: int) -> void` (bit `i` 0-based SET = `Drone_{i+1}` is DEPLOYED and its copy
  on the back is hidden; `0` shows all seven), `drones_docked() -> int`,
  `set_drone_deployed(index: int, deployed: bool) -> void`, `drone_deployed(index: int) -> bool`,
  `drone_tip(index: int) -> Vector3` (that drone's mount in WORLD space, so a fin leaves its own
  blade). The modelled cyan tip hides with the blade. **The fin mapping the lead ruled:**
  `Drone_1..4` = `wing_l`, `Drone_5..7` = `wing_r`, `fins_max` 6, so **3 fins a side and `Drone_1`
  (bit 0) always docked** — the mask is `0x7E`, and `test_hero3_drones` asserts all of that.
* **camera-aim r7 request 0f — the cockpit weapon pose, PROPOSED not built.** The lead's optional
  item. What I would build, in my own files, with no camera edit: a `cockpit` branch in
  `Hero3Posture.apply_ready` that, while `Events.camera_mode_changed(true)`, drops the rifle arm to a
  low ready (upperarm x −0.20, forearm −1.30, hand rolled so the barrel runs down-forward and outboard)
  and pulls the left arm in against the ribs, and scales `Hero3Aim`'s weight to ~0.35 so the solve
  cannot put the barrel back across the lens. That gives camera-aim a chassis worth showing without
  touching `camera_hero_cull.gd`; the call on whether to retire the cull is theirs.
  **Not built this round**: the lead made it conditional on items 1–5, and item 5 is blocked on
  city-art r16.
* **CONTRACTS §5 — one optional addition.** `HeroModel.set_fall_speed(down_speed: float)`, called
  through `has_method` by `PlayerMech` every physics frame with `-velocity.y`. The `fall` pose braces
  only past ~15 m/s down, and `set_locomotion`'s `speed` is the FLAT speed. Optional on purpose: the
  placeholder does not implement it and nothing breaks.
* **CONTRACTS §5 — `HeroModel.set_powered(on: bool)`**, a third optional addition, called behind
  `has_method`. It is how a model with its own emissives powers down for a death and back up for a
  revive. `Hero3Model` already latches it from `play_action(&"death")` / `stop_action()`, which is the
  edge `PlayerMech.heal()` uses, so **nothing has to call it today** — it is here so a future model
  that is NOT driven through `play_action` still has a way to answer. Optional on purpose.
* `HeroModel.owns_footsteps() -> bool` is a second optional addition, for the same reason: it is how
  a model with a gait tells `MechContact` to stand its footstep timer down.
* `MeleeTable.SWEEP` needs re-pasting whenever the melee clips' arm sweep changes.
  `test_hero3_reach.gd` prints the block; it is generated, never typed.
* **city-art r16**: the gate frames in this file were shot on r15 as accepted. The trim's measured
  hue is a metal reflecting the environment, so the palette table has to be re-run when r16's warmth
  and HDRI land. Nothing in `game/world/art/**` was touched.
* The lead's "heavy fall" retune is still UNCOMMITTED in the working tree (`mech_tuning.gd`,
  `mech_locomotion.gd`, `land_*.tres`, `camera_shake.gd`, `docs/SPEC.md`, `docs/FEEL.md`). The r5
  landing numbers were tuned against those live values (fall gravity 80, `soft_speed` 46,
  `heavy_feel_speed` 52); if they move, `Hero3Air.LIGHT_IMPACT` / `HEAVY_IMPACT` should move with them.
