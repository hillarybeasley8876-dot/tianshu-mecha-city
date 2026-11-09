# feel status

## Done

### r5b (11-06) — the saved WIP, the boss row, and the skate sparks

Five commits. Nothing under `game/fx` was at risk; the lead's `tmp/lead/wip/feel` patch applied clean
and is committed.

| commit | what |
|---|---|
| `87d341c` | **r5 item 3, the gallery stills.** `tracked.patch` re-applied (`git apply --check` was clean): the schedule moved from `Time.get_ticks_usec()` to `Feel.real_now()`, the gallery photographs itself (`--fx-stills`: reset the rate limits, fire the row, save 1 and 4 rendered frames later as `<nn>_<id>_f1/_f4`), and `FX_LEAD` / `--fx-lead` / `--fx=<id>@<t>` are deleted with it. `stand_in_player.model()` now answers with itself when it has no `MeshInstance3D` child, so the placeholder mech ghosts on the dash rows. Plus the untracked `swarm_feel.tscn` + `swarm_timeline.json` (r5 item 1's movie scene). |
| `fab57d3` | **r5b item 4, the skate sparks and dust.** `FxSkateTrail` (`fx/vfx/skate_trail.gd`), built once by `VfxLibrary`: a spark shower and a dust plume per foot, parked on each boot's ground contact while the mech skates or slides on the floor. |
| `5fc5832` | **r5b item 3, the confirmation.** `fx/tests/test_boss_kill.gd`. |
| `d30b322` | the trail reads the real rig's feet, with a stance-width fallback for a skeleton-less model. |
| `9d53239` | stills mode owns the gallery schedule (it used to double-fire every row), and the timeline safety net went 90 s → 150 s. |

**Item 2 (the `enemy_base.gd` victim-local stop) needed no work**: it is already committed in
`aeb8234` and intact at HEAD after enemies r11 (`_die` passes `[self]` at `enemy_base.gd:285`, the
dead branch holds the wreck and ticks the vibration at `:294-300`, `_pause_left` is cleared in
`recycle` `:415`). No line of `enemy_base.gd` moved this round.

**Item 3 (the boss row) needed no edit either**: `brood_titan.gd:282` already plays
`Feel.play(&"boss_kill", …)` (flow r5 decision 6). Line 285's `Audio.play(&"kill_large")` is the
sound and is audio's; untouched. Confirmed instead — see below.

#### Item 4 in detail — the skate trail

`FxSkateTrail` is a child of `VfxLibrary` (so it is `PROCESS_MODE_PAUSABLE`, like every other world
VFX) and reads `Game.player` itself.

- **When**: `move_state` in `{slide, assault}` (the 42 m/s ground boost and the 84 m/s assault) or
  `{dash_f, dash_b, dash_l, dash_r, lunge}` (the ground slides), `is_grounded()`, and ≥ 18 m/s of
  horizontal speed — a 16 m/s run and a 9 m/s walk do not scrape. It also stands down while
  `Engine.time_scale < 0.5`, so a frozen skate does not sit there pumping sparks.
- **Where**: the model's own `R_Foot` / `L_Foot` bones (`skeleton.get_bone_global_pose()`), each
  dropped onto the floor by one downward `Layers.WORLD` ray per foot per tick. **Not**
  `Hero3Sole.contacts()` — that solver owns a smoothed per-foot floor height and asking it from a
  second place would advance the smoothing twice per tick and move the hero's feet. A model with no
  skeleton (the placeholder box) gets the two emitters one 1.6 m stance width either side instead of
  both on the mech's centre.
- **Budget**: four `GPUParticles3D`, 128 particles total (2 × 40 sparks @ 0.32 s + 2 × 24 dust @
  0.9 s), `amount_ratio` scaled 0.3–1.0 by speed, and **nothing** goes through the shared pools — a
  42 m/s skate cannot steal a kill's blast. `particle_budget()`, `emitter_count()`, `contacts()` and
  `active()` are the read-back the test gates on.

#### Gates (all headless, all after the last commit)

| command | result |
|---|---|
| `tools/godot.sh check --only=res://fx/` | `CHECK 87 files, 0 failed, 0 engine errors, 0 warnings` |
| `tools/godot.sh check --only=res://fx/,res://enemies/` | `CHECK 194 files, 0 failed, 0 engine errors, 0 warnings` |
| `tools/godot.sh test res://fx/tests/test_feel.gd` | `TEST feel: PASS (0 failures)`, `TEST ERRORS 0` |
| `tools/godot.sh test res://fx/tests/test_clocks.gd` | `TEST feel clocks: PASS (0 failures)`, `TEST ERRORS 0` (33 checks, the gallery clock is the new one) |
| `tools/godot.sh test res://fx/tests/test_skate.gd` | `TEST feel skate: PASS (0 failures)` — **24 checks**, `TEST ERRORS 0` |
| `tools/godot.sh test res://fx/tests/test_boss_kill.gd` | `TEST feel boss_kill: PASS (0 failures)` — 3 checks, `TEST ERRORS 0` |
| `tools/godot.sh test res://fx/tests/test_swarm.gd` | `TEST feel swarm: PASS (28 checks, 0 failures)`, `TEST ERRORS 0` |
| `tools/godot.sh test res://combat/weapons/tests/test_feel_rows.gd -- --audio-trace` | `TEST 13 checks, 0 failed` |
| `tools/godot.sh test res://enemies/boss/tests/test_boss.gd` | `BOSS TEST 135 checks, 0 failed` |

**New tests fail on the pre-fix code** (method: copy the file aside, `git show <pre-fix>:<path> > <path>`,
never `git stash`):

- `test_clocks.gd` against `87d341c^`'s wall-clock gallery →
  `FAIL the gallery clock reads 2.0 s after 240 frames at 120 fps (-1.0000 s)` /
  `TEST feel clocks: FAIL (1 failures)`; on the fixed tree `PASS … (2.0000 s)`.
- `test_skate.gd` with `skate_trail.gd` moved out and `87d341c`'s `vfx_library.gd` restored →
  `TEST ERROR res://fx/tests/test_skate.gd:91 … Parse Error: Identifier "FxSkateTrail" not declared`
  (`TEST ERRORS 16`). There is no skate trail on HEAD at all, so this is the honest form of the check.
- `test_boss_kill.gd` **passes on HEAD too** — by design: `boss_kill` was already switched by flow, so
  the test is a confirmation gate, not a regression gate. It fails if anyone puts `kill_large` back on
  that death path.

### r5 item 0 — the FEEL rows four rounds were waiting on (11-05)

Three commits, each with its FEEL.md row and its `.tres` in the same commit, so `test_feel`'s row
count stays green (44 → 47 → 48 → 49).

| commit | row | content |
|---|---|---|
| `dcda081` | `gatling_vent_good`, `gatling_overheat`, `gatling_jam` | weapons r5's columns, verbatim. The good vent's only sound layer is `gatling_vent_hiss` (→ `gatling_vent`); it names neither `gatling_vent_perfect` nor `ui_vent_chime`. |
| `7d2655d` | `last_stand` | 0.5× / 1.5 s / 60 s cooldown / witch off, plus the FEEL.md edit that moves the slow-mo cell out of `hurt_heavy`. |
| `408a14e` | `boss_kill` | G 150 ms + the boss's 0.2× / 1.2 s; every other column is `kill_large`'s. Exempt from the kill budgets (lead Round 3). `brood_titan.gd:282-283` switched to `Feel.play(&"boss_kill")` in the same commit (granted under `boss/**`). |

**Gates run**

- `tools/godot.sh test res://combat/weapons/tests/test_feel_rows.gd -- --audio-trace` →
  **`TEST 13 checks, 0 failed`** (HEAD before `dcda081`: 9 failed). **tooling: the KNOWN-ERROR entry
  `gatling-vent-good-unknown-feel-id` can be dropped.**
- `tools/godot.sh test res://fx/tests/test_feel.gd` → `TEST feel: PASS (0 failures)`,
  `FEEL.md table parsed (49 ids)` / `loaded 49 resources for 49 table rows` after all three commits.
- `tools/godot.sh test res://enemies/boss/tests/test_boss.gd` → `BOSS TEST 135 checks, 0 failed`
  after the `brood_titan.gd` switch.
- `last_stand` measured directly (probe, since mech-move's suite has a cross-unit problem — see
  Requests): `hold 0.500..0.500` over 0.1–1.3 s real, `scale 1.000` at 1.6 s, and a second play
  inside 60 s is refused.

### r3 — robustness round (reviews/feel-audit.md, all 18 findings) + packaging

Every finding is fixed; the high ones have a regression check in the new `fx/tests/test_clocks.gd`
(32 checks) and each check was **shown to fail on the pre-fix code** (method below).

| # | file | fix |
|---|------|-----|
| 1 high | `screen_fx.gd` | dt from `Feel.real_now()` (difference, clamped 0.1 s), not `Time.get_ticks_usec` |
| 2 high | `afterimage_pool.gd` | per-slot age on `Feel.real_delta(delta)` (unscaled game time) |
| 3 high | `debris_pool.gd` | per-slot `_age` fed the plain physics delta the chunks are simulated on |
| 4 high | `fireball_fx.gd` | `_t += (Feel.real_now() - _last_real) * time_scale` |
| 5 high | `shockwave_fx.gd` + `vfx_library._clock()` | same pattern; ring slots free on the same clock |
| 6 med | `core/feel.gd` | already fixed by the lead (`_frame_scale`), so `Feel.real_delta(delta)` is now correct in `_process` — that is what findings 2/7 are written against |
| 7 med | `decal_pool.gd` | glows fade on unscaled game time, not wall time |
| 8 med | `feel_director.gd` | `_clock()` = `Feel.real_now()`; row cooldowns are real seconds |
| 9 med | `feel_director._hitstop` | returns when `hitstop_seconds * f <= 0`; core also rejects a 0 s request before it spends the 150 ms / 3-per-second budget |
| 10 med | `screen_fx.gd` | `_apply()` + `visible` first, `_advance(dt)` after: an N-frame pulse is drawn N times |
| 11 med | `screen_fx.gd` | flash limiter compares `Feel.real_now()` |
| 12 med | `flash_lights.gd` | deadline in rendered frames (`Engine.get_process_frames() + frames`) |
| 13 med | `flash_pop.gd` | same accumulation as the fireball |
| 14 med | `spark_process.gdshader` | `mat3(EMISSION_TRANSFORM) * emit_direction` — the cone finally follows the hit normal; `FxBlast`'s embers get `emit_direction = UP` (they sit on an identity basis) |
| 15 med | `spark_process.gdshader` | cosine-space sampling (`ct = mix(1, cos(h), r2)`) instead of `tan(half_spread)` at its 180° pole: a real hemisphere, finite on every math mode |
| 16 med | `spark_process.gdshader` | streak basis built from `VELOCITY` (with an up fallback), not pinned to world +Y |
| 17 med | `vfx_library.gd`, `decal_pool.gd`, `flash_lights.gd` | world VFX are `PROCESS_MODE_PAUSABLE`; the explicit `ALWAYS` is gone from the two pools |
| 18 low | `spark_process.gdshader`, `impact_fx.gd`, `vfx_library.gd`, `blast_fx.gd` | the duplicate `TRANSFORM[3] += VELOCITY * DELTA` is deleted, and size now goes through the `size_mul` uniform instead of `node.scale` (with `local_coords = false` the node scale only shrank the culling box) |

**Packaging (lead, 01:15)**: `FeelDirector._load_events()` lists `fx/events/` with
`ResourceLoader.list_directory()` instead of `DirAccess`. In an exported .app every row is
`*.tres.remap`, so `DirAccess.get_files()` matched nothing and the shipped game had **zero** feel
events. `test_feel.gd` now asserts `ResourceLoader` lists ≥ 44 rows and the director loaded ≥ 44.

**New APIs other units may use**: `DebrisPool.oldest_age()`, `DebrisPool.clear()`,
`FxFireball.is_running()`, `VfxPresets.set_size_mul()`, `VfxPresets.build_sparks(..., dir)`.

### r2 review fixes (all 6 MUST-FIX + the SHOULD)


1. **Missile blast reads at 150 m** (`fx/vfx/blast_fx.gd`, `fireball_fx.gd`, `fireball.gdshader`).
   The ball now expands on an **absolute** clock - `0.055 s + 0.009 s/m`, so an 8 m missile ball is
   full size in **0.13 s** and a 28 m kill in 0.31 s (it used to be a fraction of the burn time, so a
   long-burning blast expanded slowly). Core heat is 6.0 HDR at rest with a **+35 % pop decaying over
   50 ms**, i.e. ~8 HDR at t = 0 (the brief's "6-8 at t=0"). Behind it: 20 dark smoke puffs over 2.0 s
   at `soot = 0.12` (the plume used to catch half the sun and read as a pale smudge), 40 embers on
   ballistic arcs, the row's 3-frame OmniLight, and a **ground dust ring** fired from a physics ray in
   `_physics_process` whenever the fireball comes within 5 m of the floor.
2. **Fireball detail** (`fireball.gdshader` rewritten). Domain-warped fbm (the noise field is displaced
   by itself twice and rises with time), a noisy silhouette that erodes faster as it ages, a
   white-yellow core -> orange body -> deep red -> **sooty near-black rim**, and per-layer noise
   frequency derived from the radius (`noise_scale = r * 0.95`) so flame cells stay about a metre at
   8 m and at 28 m. Three shells at ratios 1.0 / 0.86 / 0.62 with 0 / 35 / 70 ms delays, different
   seeds and counter-rotating spins. HDR heat is applied to the core only, so the rim stays near 1 and
   the ball blooms from the middle instead of turning into a lamp.
3. **Sparks at range** (`spark.gdshader`, `impact_fx.gd`, `flash_pop.gd/.gdshader`, `decal_pool.gd`).
   Streaks now carry a **screen-space floor of 2.5 px wide / 25 px long** (the length floor shrinks
   with age), counts are 20 (bullet) and 18 (beam), every burst is the composite `FxImpact` = streaks
   + a **camera-facing contact flash** (`FxFlashPop`, 1.4 m, 75 ms, itself floored at 4 px), and every
   spark kind also stamps a **short-lived `impact_glow` decal** (its own 32-slot ring, fading over
   0.25 s of real time, so it never eats a permanent scorch slot).
4. **Chromatic** - the shader already split R/B along the screen radius; the dash still that read as a
   pink "damage hit" was **not** the vignette (dash.tres has none). It was the blown-up spark streaks
   (see the pixel-scale bug below) tinting the whole frame. The dash capture is clean now; the
   vignette colour is also finally plumbed through (`ScreenFx.set_vignette_color`, called by the
   director per row), so `overdrive_ignite`'s rim is gold **#F2C14E** and a damage vignette is blood
   red, as the lead asked.
5. **Shockwave scale** - `ShockwaveFx.radius_at()` is now the single source of truth for the growth
   curve and the test asserts `shockcore` = 32 m in 0.18 s and `collapse` = **20 m** (the row had 8 m;
   the lead's number wins) against both the curve and a ring actually driven to its peak on the real
   clock. Captured at the peak frame via the new `--fx-slow=<factor>` capture aid.
6. **Settings keys honoured** (`screen_fx.gd`). `fx_chromatic`, `fx_radial_blur`, `fx_speed_lines` and
   `fx_flash` scale their own channel; `photosensitive` **drops `impact_bw` entirely** and caps
   full-screen flashes at **0.1 alpha and 1 per second** (vs 0.25 alpha / 2 per second normally). Speed
   lines are read straight from `Game.player.velocity` every frame - no locomotion call needed.

- **SHOULD - impact star**: `FxFlashPop` has a `star` mode (4-point cross flare) pooled as the
  `impact_star` kind and added to `melee_heavy`, `charge_slash` and `finisher`.
- **Lead note - afterimages**: `afterimage_pool.gd` used the Godot 3 property `skeleton_path`
  (~1,500 errors per drive run). It is `skeleton` in Godot 4, and a skinned mech part is now re-based
  onto the *source's* Skeleton3D so the ghost holds the pose instead of snapping to bind pose.

### The bug behind three of the six points
`VIEWPORT_SIZE` reads **0** in an offscreen capture, so the new screen-space size floors computed
`px = dist / (0 * ...) = dist` and turned every spark into a **kilometres-long additive streak**.
That is what washed the horizon white on `missile_hit` and tinted the whole `dash` frame pink - it was
never the bloom and never the vignette. Both floors now use the global **`fx_pixel_scale`**
(world metres per pixel per metre of depth), which `VfxLibrary._update_pixel_scale()` refreshes from
the active camera every frame. The gallery also drops `glow_bloom` and mip levels 5-7 so the sandbox
is judged the way ART.md §3 asks ("no full-screen bloom wash").

### Carried over from r1 (unchanged)
FeelEvent fields = FEEL columns; 44 `fx/events/<id>.tres` parsed from the doc by `fx/feel_table.gd`;
FeelDirector falloff / rate limits / first-person scaling / `hitstop_seconds()`; VfxLibrary pools
(`spawn`, `queue`, `spawn_ring`, `flash_light`, `spawn_debris`, `afterimage`, `emitter`); decal ring
buffer of 96; RumbleMixer = **max** of the live envelopes, never the sum; `&"feel_director"` and
`&"vfx_library"` groups.

## In progress / next
- Nothing open. The pixel gates below are the lead's to run (they need a window).

## How to verify (exact commands)
```
tools/godot.sh check --only=res://fx/                     # 87 files, 0 errors, 0 warnings
tools/godot.sh check --only=res://fx/,res://enemies/      # 194 files, 0 errors, 0 warnings
tools/godot.sh test res://fx/tests/test_feel.gd           # TEST feel: PASS (0 failures)
tools/godot.sh test res://fx/tests/test_clocks.gd         # TEST feel clocks: PASS (0 failures)
tools/godot.sh test res://fx/tests/test_skate.gd          # TEST feel skate: PASS (24 checks)
tools/godot.sh test res://fx/tests/test_boss_kill.gd      # TEST feel boss_kill: PASS (3 checks)
tools/godot.sh test res://fx/tests/test_swarm.gd          # TEST feel swarm: PASS (28 checks)
tools/godot.sh test res://combat/weapons/tests/test_feel_rows.gd -- --audio-trace   # 13 checks, 0 failed
tools/godot.sh test res://enemies/boss/tests/test_boss.gd # BOSS TEST 135 checks, 0 failed
tools/godot.sh drive --scene=res://enemies/tests/fight_probe.tscn \
  --timeline=res://enemies/tests/fight_timeline.json --nan-watch --frametimes
```

## Captures needed (windowed — refused without the lead's `MC_WINDOW_OK=1`)
Run in this order; the gallery writes its own stills, so nothing here needs a hand-made sheet script.
```
# 1. the 49-row gallery movie (one row every 1.5 s of movie time)
tools/godot.sh movie --movie=/Users/minimax/m/mecha-city/captures/feel_gallery.avi \
  --movie-size=1600x900 --scene=res://fx/tests/feel_gallery.tscn \
  --timeline=res://fx/tests/gallery_timeline.json

# 2. the 49-row gallery stills: frame 1 and frame 4 of every row, labelled with the file name
#    (98 jpgs, ~95 s; default output is the repo's captures/, --fx-out=<dir> to move it)
tools/godot.sh drive --scene=res://fx/tests/feel_gallery.tscn \
  --timeline=res://fx/tests/gallery_timeline.json --fx-stills=1
python3 tools/trailer/sheet.py --help   # sheets of 8 rows from captures/<nn>_<id>_f{1,4}.jpg

# 3. the swarm movie (r5 item 1): the real main.tscn, the suite's rounds 25-55 m ahead,
#    the live Engine.time_scale and a 3 s strip chart on screen
tools/godot.sh movie --movie=$PWD/captures/feel_r5_swarm.avi --movie-size=1600x900 \
  --scene=res://fx/tests/swarm_feel.tscn --timeline=res://fx/tests/swarm_timeline.json \
  --sandbox --skip-menu --no-enemies --god
python3 tools/trailer/sheet.py captures/feel_r5_swarm.avi -o captures/feel_r5_swarm_sheet.jpg --every 0.25

# 4. NEW, item 4 — the skate sparks and dust. A 42 m/s boost skate and a ground dash slide,
#    third person, from the side and from behind; the trail is only visible while the mech is on
#    the floor, so the take has to hold the boost for ~2 s.
TRAILER_SIZE=1600x900 tools/trailer/record.sh $PWD/captures/feel_r5b_skate.avi \
  res://trailer/tl_c_gatling.json --scene=res://trailer/shot.tscn \
  --trailer-rig=res://trailer/rig_c_low.json --skip-menu --god --tod=0.6 --stub=flow
```
Until (4) is filmed the trail is verified by numbers only (`test_skate.gd`): the emitters fire, park
on the real rig's `R_Foot` / `L_Foot` bones and stop in the air, but nobody has looked at the sparks.

## Evidence (paths, numbers)
- r5b: the gate table above. `test_skate.gd` prints 24 PASS lines, including
  `the contacts track the R/L foot bones (13.60, 10.40)`, `both foot bones exist (R_Foot=8 L_Foot=4)`
  (the real `hero3_model.tscn`), `the trail stops the moment the mech leaves the floor`,
  `128 particles is the whole budget` and `the skate used no pooled VFX slot (0 live)`.
- r5b pre-fix proof: `FAIL the gallery clock reads 2.0 s after 240 frames at 120 fps (-1.0000 s)` /
  `TEST feel clocks: FAIL (1 failures)` on `87d341c^`'s gallery; `TEST ERRORS 16 … Identifier
  "FxSkateTrail" not declared` for `test_skate.gd` on `87d341c`'s library.
- `captures/feel_r3_blast_t1_1/_t1_3/_t1_7.jpg` — missile blast at 40 m: fireball + dark plume, and
  the **embers now leave upward on ballistic arcs** (F14/F15/F16 — they used to fly as a flat disc
  toward world -Z). `captures/feel_r3_sparks_t1_06/_t1_14/_t1_25.jpg` — a rifle hit whose streaks
  are **radial, aligned with their own velocity**, dying inside their 0.35 s life (F16/F18).
- Scripted fight, 36 s, `fight_probe.tscn` + `enemies/tests/fight_timeline.json` with `--nan-watch`:
  `DRIVE done t=36.0 errors=0 warnings=1`, **no NANWATCH lines**, 2096 frames,
  p50 16.8 ms / p95 18.8 ms.
- Regression proof (the new checks on the pre-fix code, restored afterwards):
  F1 FAIL, F10 FAIL (alpha 0.000), F2/F3/F4/F5/F7/F8 FAIL (7 failures), F12/F17 FAIL (5 failures),
  F14/F15/F16/F18 FAIL (4 failures). `tools/godot.sh test res://fx/tests/test_clocks.gd` prints
  `TEST feel clocks: FAIL` in each case and `PASS (0 failures)` on the fixed tree.
- `test_feel.gd`: `ResourceLoader lists 44 rows and the director loaded 44 (export-safe)`.

## Known issues
- **r5b: the skate trail has never been looked at.** `test_skate.gd` proves the emitters fire, track
  the real rig's foot bones and stop in the air, but the spark colour (white-hot → blast orange), the
  0.16 m streak width and the 34° dust cone are unjudged numbers. Capture 4 above is the gate.
- **r5b: the gallery's `--fx-stills` path is unrun.** It needs a window (`frame_post_draw`), so only
  the clock it schedules on is tested headless (`test_clocks.gd`). Two bugs were found by reading it
  rather than running it (the double-fired schedule, the 90 s timeline); there may be more.
- `world/city.gd` does not parse at the moment (`city_nav.gd`, another unit's uncommitted work), so
  a fight on `res://main.tscn` drops the mech through the floor; the r3 fight was run on
  `enemies/tests/fight_probe.tscn` instead.
- Non-spark emitters (`build_smoke`, `build_dust`, `build_steam`) are still sized with `node.scale`,
  which `local_coords = false` ignores — same class of bug as audit 18, not in the audit's scope and
  the r2 captures were tuned around the current look. Worth a pass with the art director.
- The contact flash and the impact star are additive and HDR; on the bright grey sandbox they read as
  white. In the night city they will read hotter than these stills suggest.
- The beam streaks read thin on the bright sandbox floor - additive white on light grey has little
  contrast. Judged against the night city, where the background is dark.
- `lance_fire` is modelled as the release burst; the sustained beam has to be re-played by the
  weapons unit. `kill_large`'s 30 s burning wreck is available as `VfxLibrary.emitter(&"fire_loop")`
  but the enemies unit owns when it is placed.
- The debris dust trail is one shared emitter following the centroid of the live chunks.

## Requests (to the lead / other units)
0. **r5b, 11-06.**
   - **tooling**: two new suites need rows in `tools/suites.txt` (they print `UNLISTED` until then):
     `res://fx/tests/test_skate.gd` (no flags) and `res://fx/tests/test_boss_kill.gd` (no flags,
     ~35 s — it builds the boss harness). `test_swarm.gd`'s row is still missing too.
   - **hero-v3 / mech-move**: the ground half of r9 item 3 is in (`fab57d3`, `d30b322`). The trail
     reads `move_state()` / `is_grounded()` / `model()` / `velocity` off `PlayerMech` and the
     `R_Foot` / `L_Foot` bones off `Hero3Model.skeleton`; if the rig's bone names or the skate state
     names ever change, `FxSkateTrail.FEET` / `.SKATE` / `.SLIDE` are the three lists to update.
     It deliberately does **not** touch `Hero3Sole` (see the item 4 note). If you want a `Feel` row
     on the skate as well (a rumble layer, a light chromatic), say so and I will add the row — it
     needs a `docs/FEEL.md` line, which is a lead grant.
   - **CONTRACTS §3/§4 (lead)**: `VfxLibrary.skate` is a new public field on the library, and
     `FxSkateTrail` is a new global `class_name` (fx-prefixed, unique).
1. **r5, 11-05 — the rows landed, act on them.**
   - **weapons r5**: `gatling_vent_good`, `gatling_overheat` and `gatling_jam` exist as of `dcda081`;
     `test_feel_rows.gd -- --audio-trace` is `13 checks, 0 failed`. The good vent plays
     `gatling_vent_hiss` (→ `gatling_vent`), nothing else.
   - **mech-move r7**: `last_stand` exists as of `7d2655d` — wire `Feel.play(&"last_stand")`.
     **One thing you have to change in `test_last_stand.gd`:** `_test_pipeline()` runs five crossings
     *after* the director is in the tree, and the first one already spends the row's 60 s cooldown, so
     `_test_director()`'s first `_director_play()` returns 0 and the 0.5× check reads 1.000 (10/12
     checks pass). Add `_dir.call(&"reset_rate_limits")` as the first line of `_test_director()`, or
     move `_dir = DIRECTOR.instantiate()` to after `await _test_pipeline()`. I cannot edit your file;
     with the reset the row measures `0.500..0.500` over 0.1–1.3 s and `1.000` at 1.6 s.
   - **flow r5**: `boss_kill` landed in `408a14e`, which also made the one-line switch at
     `brood_titan.gd:282-283` for you (lead Round 3 grant). Nothing left for you there.
   - **audio r7**: `FEEL_IDS` / `OVERRIDES` still needed for `last_stand`, `boss_kill`,
     `gatling_vent_good` (→ `gatling_vent`), `gatling_overheat`, `gatling_jam`. Until then the router
     prints one `Audio: unknown or empty sound id '<id>'` warning per new id. `last_stand`'s own
     layer is `cockpit_alarm`; a dedicated bank sound would be better.
   - **tooling**: drop the `gatling-vent-good-unknown-feel-id` KNOWN-ERROR entry.
1. **`fx_pixel_scale`** is a new global shader parameter registered by `VfxLibrary`. If another unit
   renders VFX through its own scene without a `VfxLibrary` in the tree, the sparks fall back to their
   natural world size (no crash, just no screen-space floor). Worth a line in CONTRACTS §3.
2. `Feel.post()` ids used by the table: `chromatic`, `radial_blur`, `vignette`, `speed_lines`,
   `desaturate`, `impact_bw` (already listed) - plus the new vfx kinds `impact_star` and the
   `impact_glow` decal, which other units may now put in their own rows.
3. Any unit that lists a resource directory at runtime must use `ResourceLoader.list_directory()`,
   not `DirAccess` — the exported build only ships `*.remap` + .pck.
4. Please keep global `class_name`s unique across units; the fx unit prefixes everything with `Fx`
   (`FxBlast`, `FxFireball`, `FxImpact`, `FxFlashPop`, `ShockwaveFx`).
