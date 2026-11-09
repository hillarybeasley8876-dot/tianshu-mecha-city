# weapons status

## Plan (files I own)
```
game/combat/weapons/
  weapon_system.tscn      component scene (root Node3D, script weapon_system.gd)
  weapon_system.gd        swap / reload / routing / strafe-aim / hud_state
  weapon_context.gd       the only bridge to PlayerMech / AimSystem / HeroModel (null-tolerant)
  rifle.gd                P1 Pierce-Light (hitscan, 2-stage charge, pierce, blast)
  gatling.gd              P2 Thunder Spindle (spin-up, heat, active vent, superheated)
  hailstorm.gd            S3 Hailstorm (paint locks, salvo ripple, guided)
  shot_query.gd           pierce rays, HitInfo delivery, blasts, marks/primes, LOS
  tuning/*.gd             RifleTuning / GatlingTuning / MissileTuning (Resource classes)
  tests/                  test_weapons.gd + harness + 8 suites (rifle/clocks/robust/gatling/fp/missiles/perf/teardown) + rig/dummy stand-ins
  tests/test_feel_rows.gd FEEL-row audit (r5 item 2); runs on its own, fails until the rows land
  tests/timeline_fp_kit.json  first-person kit timeline (rifle tap, stage 2, gatling ADS, salvo)
  tests/weapons_range.*   demo range for the oblique captures (ART.md environment)
  tests/integration.*     main.tscn + sandbox + real PlayerMech, plus a dummy target field
game/combat/projectiles/
  projectile_manager.gd   600 pooled gatling rounds (arrays, ray-stepped) + MultiMesh tracers
  missile_manager.gd      24 pooled missiles (arrays), one simulation loop
  beam_pool.gd            pooled 3-layer beam cylinders + muzzle/shock rings + flash lights
  casing_pool.gd          MultiMesh shell casings
  spark_pool.gd           impacts / blasts / launch puffs; routes to the fx VfxLibrary when it exists
  missile_visuals.gd      4 MultiMeshes: hulls, engine flares, tapered core ribbons, lingering smoke
  fx_bridge.gd            the one lookup into the fx unit's VfxLibrary (+ soft-disc texture helper)
```

## Done
- WeaponSystem component (`weapon_system.tscn`): rifle/gatling swap (0.35 s, `Events.weapon_switched`),
  reload, `set_strafe_aim(true)` while firing/ADS and for 0.6 s after, model actions
  (`fire_r charge_r gatling_spin reload missile_launch`), `hud_state()` with every briefed key.
- P1 rifle: 240 rpm cap, 9-round cell, 1.6/1.2 s reload, 230/70, falloff 100 % ≤200 m → 60 % at 350 m,
  cut-off 500 m, charge 0.6 s (700/350, pierce 1, 3 rds + 120 EN) and 1.2 s (1,400/800, pierce all,
  8 m blast, detonates primes, 5 rds + 200 EN), auto-fire at 3 s, pooled 0.06 s beam + muzzle ring.
  A stage the cell or the EN gauge cannot pay for falls back to the highest affordable one.
- P2 gatling: 0.3 s spin-up, 15 rds/s, 900 m/s ray-stepped rounds, spread 2.6°/1.1° + 1.2° bloom,
  heat +0.85/shot and −30/s after 0.35 s, overheat at 118 rounds → 0.9 s needle with
  perfect/good/miss windows, Superheated 4 s (+30 % dmg, +50 % impact), casings every round,
  tracer every 3rd round (42 m long so the stream reads at 60 fps).
- S3 Hailstorm: 0.10 s locks in a 24°×16° box, ≤4 per target, 12 max, 300 m + LOS, auto-fire at 3 s,
  12 missiles in 0.5 s from `missile_l/r`, bloom → ignite 120→200 m/s, turn 300→600°/s, 5 m fuse,
  6 s life, 280/140 + 6 m blast, 6 free missiles without locks, guided while `aim` is held, chaff eats
  4, CD 14 s, `Events.missiles_locked`.
- Test suite: `tests/test_weapons.gd` — 148 checks, all passing.
- Demo/capture rig `tests/weapons_range.tscn` (placeholder mech + target walls at 100/300/500 m +
  12-dummy missile field + `hud_state()` debug readout) with three drive timelines.

## Lead update 18:35 (SPEC §2/§4/§5/§6 revised) — applied
- rifle ranges → full ≤ 200 m, 60 % at 350 m, cut-off 500 m (was 280/440/600).
- missile lock range → 300 m (was 320 m).
- chest/socket fallback height → 11.5 m (was 11.0); casing gravity → 25.5 m/s² (was 56).
- gatling cut-off → 350 m, the city's longest sightline (SPEC §5), instead of an invented 400 m.
- Unchanged: times, damage, EN costs, percentages and ×2 reach/radius/projectile-speed scaling.

## Lead review r1 — all five MUST-FIX and both SHOULD items applied
1. **Beam look**: three coaxial layers per shot (core / glow / afterglow) with HDR albedo
   (`CORE_ENERGY 1.9` clears the 1.2 Glow threshold). Per-stage radii in `RifleTuning`:
   0.5/1.6 m plain, 1.0/3.5 m stage 1, 2.2/7.0 m stage 2; stage 2 adds a 0->12 m shock ring in
   0.12 s and a 0.4 s afterglow. Every beam fades over the last 0.12 s (no pop). Cyan muzzle
   OmniLight3D for 3 frames through the fx unit's `FlashLightPool` when present. The range scene now
   uses the ART.md environment (AgX, exposure 1.0, Glow on at HDR 1.2).
2. **Itano circus** (`projectiles/missile_visuals.gd`, 4 MultiMeshes): billboard engine flare with a
   soft-disc texture at each head, tapered additive core ribbon (wide at the missile -> thin, gone
   0.6 s after the missile dies), and soft grey-white smoke that lingers 1.5 s and widens x3.
   Staggered launch puffs at the rails. Impacts go to `VfxLibrary`
   (`missile_blast` + `scorch` + shockwave ring); with no library the fallback is a real blast
   (fireball, flash light, smoke puff), never a small orb. New `projectiles/fx_bridge.gd` is the
   single lookup into the fx unit (class search, cached, retried).
3. **No debug geometry by default**: captures have none. The range scene draws an aim ray only with
   `--debug`; the integration scene traces the crosshair and every shot with `--debug`.
4. **API alignment (CONTRACTS §4)**: `enemy.status.add_mark_hit(n)` (with a fallback for actors that
   carry the method themselves), COLLAPSE via
   `get_tree().call_group(&"prime_detonators", &"detonate_primes", center, radius, source)`
   (`deliver()` now takes a detonation radius), and `hud_state()` carries `last_hit_usec` /
   `last_hit_kind` (`normal|weak|stagger|kill`, resolved from the hurtbox and the status component).
5. **Real player integration**: `tests/integration.tscn` instances `main.tscn` verbatim (sandbox
   world, real PlayerMech + hero model + AimSystem + camera rig + feel director) and only adds a
   dummy target field, because the sandbox has no `Targetable`s. `timeline_integration.json` fires
   the rifle at the 120 m wall, charges stage 2, swaps, runs a gatling burst, paints and launches a
   salvo. Two real bugs surfaced there and are fixed: the shoulder launch arc was rotated the wrong
   way (missiles left the rails 22 deg *downward*), and a dead missile's core ribbon stayed frozen in
   the air (segments now expire with their samples).
6. Gatling tracers 0.35 m thick, HDR 5.0, per-round `spark_bullet` on every surface.
7. Sizes: largest file is `missile_manager.gd` at 236 lines, `missile_visuals.gd` 210; none over 400.

## Lead review r3 — clock contract (CONTRACTS §3) + PadInput, applied
1. **Player clock for every weapon timer.** `WeaponSystem._physics_process` now derives
   `var dt := Feel.player_delta(delta)` once and hands it to the swap timer, the strafe-aim release,
   `rifle.update`, `gatling.update` and `hailstorm.update` (parameters renamed `player_dt` at every use
   site). On that clock: rifle rate cap / reload / charge accumulator, gatling spin / rate / heat /
   cooling / Superheated / jam / vent sweep, Hailstorm cooldown / lock rate / paint time / salvo ripple.
   Witch time no longer slows the guns; a global hit-stop freezes them with the player.
2. **World clock untouched where it belongs.** `projectile_manager`, `missile_manager`,
   `missile_visuals`, `beam_pool`, `casing_pool`, `spark_pool` still run on plain `delta` — a round or
   missile in the air crawls with the world in witch time while the launcher keeps rippling at speed.
   Both manager headers now say so.
3. **Deviation, deliberate:** the charge tap/hold accumulator and the vent needle + its press windows
   run on `player_delta`, not `real_delta`. In witch time the two clocks are identical
   (`player_time_comp()` == 1/scale), so the needle keeps real-time speed and the 6/12-frame windows
   stay the 6/12 real frames the HUD promises — the case the contract is about. They differ only inside
   a global hit-stop, where `real_delta` would let the needle sweep on and jam a player who is frozen
   and cannot press; freezing it (as melee does with the parry window) is the fair reading. See Requests.
4. **Pad (RB+RT missiles)**: no code change and none needed — the component and every test drive
   *actions only* (`Input.is_action_pressed` / `Input.action_press`), never joypad buttons or key
   events; `grep -rn "JOY_BUTTON\|InputEventKey\|InputEventJoypad" game/combat/{weapons,projectiles}`
   returns nothing. PadInput holds `missiles` for as long as RB+RT is down, so paint-on-hold /
   fire-on-release still works.

## Lead review r4 — numeric-robustness audit (reviews/weapons-audit.md), all 7 findings fixed
Each fix was proved by reverting it alone and re-running the suite: the named check fails without
the fix and passes with it (counts from those runs are in Evidence).
1. **[high] world-space pools (#1)**: `Beams/Sparks/Casings/Bullets/Missiles` are `top_level` in
   `weapon_system.tscn`, and each pool's `_ready()` sets `top_level` + `global_transform = IDENTITY`
   if it is instanced bare (tests, tools). Without it every MultiMesh instance transform — a world
   position — was drawn at `player_xf * world_pos`, i.e. 60 m behind the sandbox spawn.
2. **[high] Hailstorm lock debt (#2)**: `_paint()` zeroes `_lock_timer` when `_add_lock()` fails, so
   1.2 s of painting at nothing no longer pays out as 12 locks + an instant salvo in one tick.
3. **[high] gatling timers while holstered (#3)**: `WeaponSystem._swap()` calls the new
   `gatling.tick_holstered(player_dt)` whenever the gatling is not the ticking weapon (rifle out or
   mid-swap). Heat cools, Superheated/jam/reload run, and a VENT nobody can answer resolves into a
   jam — silently, because the mech is not holding the gun (`_jam(silent)`), so no Feel row plays at
   a stowed muzzle. `update()` and `tick_holstered()` share one `_tick(...)`.
4. **[low] zero-life ring (#4/#5)**: `BeamPool.ring()` returns -1 before making the slot visible, so
   `shock_ring_time = 0` disables the ring instead of freezing a bright torus on screen.
5. **[low] afterglow cut short (#6)**: the After layer is a child of the core, so the core is now
   hidden only when both `_beam_left` and `_after_left` are done (its alpha is already 0 by then),
   and `beam()` takes a slot only via `_free_beam()` (both timers <= 0). A charged shot's 0.4 s
   afterglow survives its 0.14 s beam.
6. **[low] unwritten trail samples (#7)**: `MissileVisuals._ready()` fills `_times` with -1e9 (and
   `clear()` re-fills), so a fresh missile's 19 unwritten history slots cannot age in as smoke puffs
   at the pool origin while `_now < SMOKE_LIFE`. `live_samples(i)` exposes the count to the suite.
- New suite `tests/suite_robust.gd` (28 checks) runs between the clock and gatling suites. Two older
  checks were counting cumulative state and are now deltas: `gatling.tracer_every_third` and
  `missiles.released_fires`.

## Look round 2026-11-02 — the dead trigger on an empty cell (reviews/look/weapons.md item 1)
The one item routed to weapons. Fix 1 is mine; fixes 2 and 3 are `game/ui/widgets/weapon_panel.gd`
and the reticle — the hud unit's files (see Requests).
1. **Dry trigger reloads** (`rifle.gd` `update()`): `if ammo <= 0` is now handled before the charge
   path — a press calls `reload()` and returns, and an idle empty cell reloads itself after
   `RifleTuning.auto_reload_delay` (0.25 s, the AC6 beat) on the player clock. Before, `pressed and
   ammo > 0` swallowed the press, `_release()` never ran and the only reload was the R key.
   `_empty_left` is reset by `reset_state()`, `reload()` and any frame with rounds in the cell.
2. The amber count at 0 ammo (`weapon_panel.gd:58-60`) was already in the build — that half of fix 2
   was done by the hud unit; the 'RELOAD [R]' label and the reticle tag were not and are not mine.
3. New checks in `tests/suite_rifle.gd::_dry` (7): `rifle.dry_trigger_{starts_reload,fires_nothing}`,
   `rifle.dry_reload_refills`, `rifle.last_round_empties`, `rifle.auto_reload_{waits,kicks_in,refills}`.
   New capture timeline `tests/timeline_dry.json` (9 taps empty the cell, a 10th press at 4.0 s).

## Lead review r5 — the cockpit gatling flash, and vent results that play nothing
Commits `36c0499` (item 1 core), `25c0963` (item 2 audit + the duplicate chime), `7774ff9` (item 1,
the Hailstorm rails). Both findings reproduced on HEAD first; the repro output is in Evidence.

### 1. [major] In first person the gatling's muzzle flash covered a third of the frame — fixed
**Cause.** Every round drew `SparkPool.impact(muzzle, dir, …, 2.2, 0.07)` — the pool's own 0.5 m
sphere grown to 2.2 m — and nothing under `combat/` read the camera mode. The lens sits 6.0 m from
`muzzle_r` (camera-aim r7), so 2.2 m at 6 m under the 62 deg FOV is ~30 % of the frame height.
**Fix — one camera-mode path in `WeaponContext`, used by every muzzle/rail-anchored visual.**
- `WeaponContext.is_first_person()` reads `AimSystem.is_first_person()` live through `ctx.aim`, and
  falls back to `fp_hint`, which `WeaponSystem._on_camera_mode` sets from
  `Events.camera_mode_changed` (`weapon_system.gd:69-70`, `:73-79`). Live read means the size is right
  from the first round after a toggle, in both directions, and for a mech already in the cockpit
  when the component readies. camera-aim's public API only; nothing else of its is touched.
- `fp_size()` (x0.27), `fp_alpha()` (x0.6, FEEL.md:9), `fp_light_energy()`, `fp_light_range()` (x0.5)
  and `fp_beam_from()` (the beam starts 24 m down range, so the lens never looks into the open end
  of the glow cylinder). Gatling flash 2.2 m -> **0.594 m** = 8 % of the frame; unchanged at 2.2 m in
  third person. Impact sparks, tracers and casings are NOT scaled — `fp.impacts_stay_full_size_*`
  proves it.
- Call sites: `gatling.gd:190-191` (`sparks.muzzle_flash`), `rifle.gd:_visuals` (beam radii + start,
  both rings, flash light), `hailstorm.gd:_launch` (dust puff, flash light).
- **The kit check found two more failures the stills alone missed.** The rifle tap drew a 3.2 m ring
  over the lower-right third and a stage-2 release whited the whole canopy out (the lens was looking
  straight into the 7 m glow tube). And the **movie** caught the Hailstorm: `rig_probe
  --probe-dump-at=8.8` put `dust_puff6@Vfx` and `Flash6/Flash7@FlashLights` **3.6 m** from the lens —
  the shoulder rails are closer to the cockpit eye than `muzzle_r` is — so a salvo flooded the
  canopy orange-white. Both now go through the same path. The stills at 8.8/9.1 had missed it; the
  60 fps movie did not.

### 2. [minor] The good vent, the overheat and the jam are not FEEL rows — Request filed, audit added
**Cause.** `gatling_overheat`, `gatling_vent_good` and `gatling_jam` have no FEEL.md row and no
`fx/events/<id>.tres`, so the FeelDirector warns once and plays nothing; the good vent additionally
has no bank sound, so it is silent. Rows are the lead's, `.tres` feel's, `event_map.gd` audio's —
**the Request is in Requests below, with all three rows' content.**
- Mine, and landed: the duplicate `Audio.play(&"gatling_vent_perfect")` that sat under
  `Feel.play(&"gatling_vent_perfect", …)` at `gatling.gd:120` is **deleted**. `--audio-trace` showed
  3 `gatling_vent_perfect` requests per perfect vent — the row's
  `ui_vent_chime` layer, the audio router's id mapping, and that direct call. Now 2, and the chime
  still sounds (`vent.perfect_sound_has_one_source` pins it at exactly 2). The good vent never had a
  direct `Audio.play` and still has none.
- `combat/weapons/tests/test_feel_rows.gd` is the new audit. It runs **on its own**, not inside
  `test_weapons.gd`, so the main suite stays green until the rows land. It instances the real
  `res://fx/feel_director.tscn` (so the perf suite still measures what it did), drives the real
  WeaponSystem through an overheat and the perfect/good/miss windows, and scans every literal
  `Feel.play(&"…")` under `combat/weapons` + `combat/projectiles` against `FeelTable.ids()` and
  `fx/events/<id>.tres`.

## Lead review r6 — the orange slabs in the first-person view, identified and gated
Commits `8dc64bf` (the fix), `557410e` (the test rig), `fb2e41a` (scan + gates + shader gate).

### 1. Identification — it was the spent casings, and it was also the missile flares
`FpNearScan` (`tests/fp_near_scan.gd`) lists **every drawn primitive within 15 m of the first-person
lens** — owner node, shape, distance, size in metres, how wide it reads across the 62° view, and its
colour. `FpNearSuite` drives a real first-person gatling burst (144 physics ticks, scanned on **every
tick**) and a real Hailstorm salvo (192 ticks) and prints the worst frame each pool drew.

**Before (only `CasingPool.FP_SCALE` / `MissileVisuals.FP_SCALE` set back to 1.0 — the pre-r6 build):**

| pool / effect | shape | distance | size | reads | colour |
|---|---|---|---|---|---|
| `Casings/Casings` | box | **5.0–5.2 m** | **1.25 × 0.42 m** | 5° wide | **#FFB333** |
| `Sparks/Spark0` (muzzle flash) | sphere | 5.4 m | 0.59 × 0.58 m | 6° wide | #FFFFFF (HDR orange) |
| `Bullets/Tracers` | box (needle) | 11.0 m | 42.00 × 0.35 m | 2° wide | #FFFFFF |
| `Visuals/Flares` (salvo) | soft quad | **3.2 m** | **3.52 × 3.52 m** | **58° wide** | **#FFFFFF (orange)** |
| `Visuals/SmokeTrails` (salvo) | soft quad | **0.0 m** | **12.60 × 12.60 m** | 180° wide | #B8C0D3 |
| `Visuals/Bodies` (salvo) | cylinder | 3.5 m | 5.00 × 0.55 m | 9° wide | #E5DCDA |
| `Visuals/CoreTrails` (salvo) | box | 5.2 m | 7.73 × 0.91 m | 10° wide | #62FFFF |

**The slabs are `CasingPool`** — a 1.25 × 0.42 m hard-edged orange box, 5 m from the lens, tumbling
(spin ±14 rad/s) so each face reads as a flat polygon. That is "about the size of a car door, at
3–10 m from the lens", and it is ejected to the **right** (`facing × UP`), which is the side of the
frame the lead reported. The missile **engine flare** (3.5 m orange billboard 3.2 m from the lens,
58° of the frame) is the same defect at the shoulder rails and is fixed the same way.
Not the cause: the tracers (0.35 m needles that recede from the lens) and the muzzle flash (already
scaled in r5).

**After:**

| pool / effect | shape | distance | size | reads | colour |
|---|---|---|---|---|---|
| `Casings/Casings` | box | 5.8 m | **0.34 × 0.11 m** | 1° wide | #FFB333 |
| `Sparks/Spark0` (muzzle flash) | sphere | 5.4 m | 0.59 × 0.58 m | 6° wide | #FFFFFF |
| `Bullets/Tracers` | box (needle) | 11.1 m | 42.00 × 0.35 m | 2° wide | #FFFFFF |
| `Visuals/Flares` (salvo) | soft quad | 4.4 m | **0.97 × 0.97 m** | **13° wide** | #FFFFFF |
| `Visuals/SmokeTrails` (salvo) | soft quad | 3.6 m | **3.40 × 3.40 m** | 51° wide | #B8C0D3 |
| `Visuals/Bodies` (salvo) | cylinder | 4.5 m | 1.35 × 0.15 m | 2° wide | #E5DCDA |
| `Visuals/CoreTrails` (salvo) | box | 5.1 m | 7.73 × 0.25 m | 3° wide | #62FFFF |

### 2. The fix, by camera mode (one rule, in the pool, driven from the component)
- **`CasingPool`** (`FP_SCALE 0.27`, `FP_SPEED 1.8`, `FP_HIDE 4.0`, `FP_THROW`): in the cockpit the
  casing is drawn at 0.34 m, thrown along the **lens → ejection-port ray** plus a downward bias
  instead of the third-person side-and-up kick, at 25 m/s instead of 14 (it leaves the 8 m canopy
  zone in ~0.1 s), and is not drawn at all inside 4 m of the eye. Third person takes none of those
  branches and is byte-identical to r5 — the RNG call order is untouched.
- **`MissileVisuals`** (`FP_SCALE 0.27`, `FP_HIDE 5.0`, `FP_NEAR 14`, `FP_FAR 40`): the same rule as
  a **distance ramp**, applied to all four MultiMeshes — hulls, engine flares, core ribbons and
  smoke. A salvo leaves the rails at FP_SCALE, nothing at all inside 5 m, and is back to full size by
  40 m, so the circus still reads as a circus once it is out over the street. This also closes the
  r5 known issue ("a salvo still throws flares and smoke past the canopy"): the smoke went from
  12.6 m to 3.4 m at the canopy.
- **`WeaponContext.lens()`** reads camera-aim's own public API (`AimSystem.camera()`), falling back
  to the `cockpit` socket at the SPEC §5 eye band — the same rule as `cockpit_frame.gd:54`.
- **`WeaponSystem._publish_camera_mode()`** pushes the mode and the lens into both pools **every
  tick**, because they are world-clock pools: a casing ejected the frame before a cockpit toggle is
  still on screen after it.

### 3. The gates (`tests/suite_fp_near.gd`, 20 checks)
Three gates per pass, over the scan, on every physics tick:
- `fp_near.<pass>_no_orange_slab_within_8m` — **the lead's rule**: no orange-dominant hard-edged
  flat primitive (box/quad, not a needle) longer than 0.5 m within 8 m.
- `fp_near.<pass>_no_hard_orange_primitive_over_0_6m` — shape-agnostic backstop; 0.6 m is the r5
  muzzle flash the lead already accepted, so it is the ceiling for anything hard-edged.
- `fp_near.<pass>_no_orange_primitive_over_16deg_wide` — nothing orange may read more than 16° across
  the 62° frame. This is the bound soft sprites (flares, smoke, dust — alpha discs with no edges)
  cannot dodge by not being a box.

Supporting checks: `fp_near.lens_is_about_6m_from_the_muzzle` (the gate radius is not vacuous),
`fp_near.lens_follows_the_aim_camera`, `fp_near.casings_are_cockpit_sized`,
`fp_near.casings_never_need_the_near_hide`, `fp_near.scan_saw_geometry`, `fp_near.burst_really_fired`,
`fp_near.salvo_really_launched`, and `fp_near.fp_scale_agrees_with_the_context` /
`…missile_fp_scale…` (the two pools restate `WeaponContext.FP_SCALE` rather than importing it across
a cyclic class reference; these fail if they drift).

### 4. Shader gate (`tests/suite_shaders.gd`, 8 checks) — the "Also"
`tools/godot.sh check` does not compile GLSL at all. **The weapons own no shader**: every material
under `combat/weapons/**` and `combat/projectiles/**` is a `StandardMaterial3D`, and
`shader.weapons_own_no_gdshader` fails the moment a `.gdshader` appears there without being compiled
in the suite. What the weapons *reach* is the fx unit's `VfxLibrary`, through `FxBridge`, for
`spark_bullet` / `spark_beam` / `dust_puff` / `missile_blast` / `scorch` / `spawn_ring` — six shaders,
all compiled here the way melee-defense r7 does it (`Shader.code = source` +
`get_shader_uniform_list()` under an `ErrorCounter`).

## Lead review r7 — a public `stop_volley()`, so the death gate stops writing private fields
Commit `weapons r7` (this round). mech-move's Request 17.

### 1. `WeaponSystem.stop_volley()` — the corpse path, and `reset()`'s opposite
`reset()` is the respawn path: it refills the cell and the belt, zeroes the heat and the missile
cooldown and selects the rifle. The death gate must stop what is **running** and hand nothing back,
so `stop_volley()` (weapon_system.gd) does exactly four things and nothing else:
- `rifle.cancel()` — the charge is lost, the cell keeps its rounds;
- `gatling.cancel()` — the barrel spins down, the heat / jam / Superheated clocks keep running;
- `hailstorm.cancel()` — the new public hook below;
- `ctx.ads = false` + `_apply_strafe(false)` (which also tells the mech `set_strafe_aim(false)`),
  because `WeaponSystem` assigns both from the input every tick it runs and a corpse's
  `_physics_process` is off, so the last value would otherwise stick.

`_apply_strafe()` is the extraction of the one place `ctx.strafe_aim` was already written, so the
mech is told once per change from both callers. It does **not** refill, reset heat or cooldowns,
change `current`, emit anything, or touch `HeroModel.stop_action()` — that last one is deliberate:
`stop_action()` clears `Hero3Model._dying`, so calling it in the death path would kill the death
clip.

### 2. `HailstormLauncher.cancel()` — public, and the four private fields it owns
`painting = false`, `locks.clear()`, `_paint_time = 0.0`, `_lock_timer = 0.0`. It fires nothing, it
leaves `cooldown` alone (carry-over) and it announces nothing, so a corpse reaches no bus.
`reset_state()` stays the respawn path (it also clears the salvo queue and the cooldown).

### 3. The gate takes the path — proven, not inferred
`MechTeardown._weapons()` (`player/mech/mech_teardown.gd:44`) already preferred `stop_volley()` behind
`has_method`, and `WeaponSystem` now answers to it. A scratch test (run, then deleted — it was never
committed) fed `MechTeardown.quiet()` a stub that has `current_weapon()` + `stop_volley()` and a
`HailstormLauncher`-shaped child with `painting`/`locks`/`_paint_time`/`_lock_timer` set:
`PASS stop_volley called once (1)`, `PASS private painting untouched (true)`,
`PASS locks untouched (3)`, `PASS ctx.ads untouched (true)` — the dispatch is the hook, and the four
private writes are now dead code on mech-move's side (see the Request below).

### 4. Test (`tests/suite_teardown.gd`, 17 checks, wired into `test_weapons.gd`)
Two phases, each the state a firefight actually leaves behind:
- **rifle + paint** — two rounds spent, `fire` held (charging), `missiles` held (painting locks on 3
  dummies at 60 m), `aim` held (ADS + strafe-aim up). After `stop_volley()`: `rifle.is_firing()`
  false and `charge_ratio() == 0`, `hud_state()` `charge_stage 0` / `charge 0`, `painting` false with
  an empty `locks` and `missile_painting` false, `ctx.ads` / `ctx.strafe_aim` / the mech's
  `strafe_aim` all false, and no `weapon_switched` on the bus (a listener is connected across the
  whole suite).
- **gatling** — swapped to the gatling, 0.6 s burst (spin 1.0, heat > 0, belt spent). After
  `stop_volley()`: `spin() == 0` and `is_firing()` false.
- **carry**, in both phases: one snapshot dictionary (rifle ammo/reloading, gatling ammo/heat/state/
  superheated, missile cooldown, salvos, `current`, `current_weapon()`) compared across the call —
  `teardown.rifle_carry_unchanged` / `teardown.gatling_carry_unchanged`.
- **stays quiet**: 0.3 s of ticks with every button up must not re-arm the charge, the spin or the
  paint.

## In progress / next
- Nothing outstanding. Remaining nice-to-have: an oblique third-person capture of the integration
  scene (the over-the-shoulder camera foreshortens every beam by construction).

## How to verify (exact commands)
- `tools/godot.sh check --only=res://combat/` -> `CHECK 152 files, 0 failed, 0 engine errors,
  0 warnings` (the lead's r6 gate); `--only=res://combat/weapons/,res://combat/projectiles/` ->
  `CHECK 40 files, 0 failed`.
- `tools/godot.sh test res://combat/weapons/tests/test_weapons.gd` -> **`TEST 189 checks, 0 failed`**
  (172 at the end of r6 + 17 `teardown.*`). Perf line in the same run:
  `PERF idle 0.107 ms/frame, loaded 2.069, weapons cost 1.962 ms/frame`.
- r7 gate: `tools/suites.sh --only=weapons,weapons_feel_rows,mech_death` ->
  `SUITES 3 rows, 3 green, 0 known, 0 red`, with `mech_death` at **108/108** (its DEAD gate still
  stops the charge, the spin, the paint and ADS, and its CARRY gate still reads
  `rifle=6 gatling=226 burst=0 weapon=gatling` unchanged).
- **The gate fails on HEAD.** Revert only the two scale constants and re-run:
  `CasingPool.FP_SCALE := 1.0` (+ `FP_SPEED 1.0`, `FP_HIDE 0.0`) and `MissileVisuals.FP_SCALE := 1.0`
  (+ `FP_HIDE 0.0`) -> `TEST 164 checks, 6 failed`, and the scan prints the identification table
  above. Restore -> 0 failed.
- **The shader gate bites:**
  `tools/godot.sh test res://combat/weapons/tests/test_weapons.gd -- --shader-selftest`
  -> `SELFTEST broken shader produced 2 engine error(s)`, `PASS shader.a_broken_shader_is_caught`,
  then `TEST ERRORS 2` with `Shader compilation failed` and exit 1 — which is the point: a broken
  shader is loud here and silent in `check`.
- FEEL-row audit (r5 item 2) — **the Request landed, this is green**:
  `tools/godot.sh test res://combat/weapons/tests/test_feel_rows.gd -- --audio-trace`
  -> `TEST 13 checks, 0 failed` (all three rows — `gatling_overheat`, `gatling_vent_good`,
  `gatling_jam` — plus the `event_map` entry are in the tree). Without `-- --audio-trace` it reports
  `TEST 13 checks, 2 failed`: the two sound checks need the trace, which is what the flag is for.
- **Captures needed** — see the section below; the lead runs these in a window the user approves.

- First-person gatling, the reported take (before/after are the same command on the same commit):
  `tools/godot.sh drive --scene=res://trailer/shot.tscn --timeline=res://trailer/tl_c_fp.json \
   --skip-menu --god --tod=0.6 --stub=flow --spawn=-540,10,570,45 \
   --trailer-pack=30,ripper:4,mantis:1 --trailer-hud=1 --out=weapons_r5_fp \
   --shots=3.4,3.8,4.4,5.0,5.6`
- First-person kit (rifle tap, stage-2 release, gatling ADS, Hailstorm salvo) — new
  `tests/timeline_fp_kit.json` on the `c_fp` flags:
  same command with `--timeline=res://combat/weapons/tests/timeline_fp_kit.json
  --out=weapons_r5_kit --shots=2.7,4.75,6.2,8.75,9.1`
- First-person movie of the kit (this is what caught the Hailstorm flood):
  `tools/godot.sh movie --movie=<abs>/weapons_r5_fp.avi --scene=res://trailer/shot.tscn \
   --timeline=res://combat/weapons/tests/timeline_fp_kit.json --skip-menu --god --tod=0.6 \
   --stub=flow --spawn=-540,10,570,45 --trailer-pack=30,ripper:4,mantis:1 --trailer-hud=1`
- Third-person before/after at the same spot (`tl_c_gatling.json` on the `c_fp` flags):
  `tools/godot.sh drive --scene=res://trailer/shot.tscn --timeline=res://trailer/tl_c_gatling.json \
   --skip-menu --god --tod=0.6 --stub=flow --spawn=-540,10,570,45 \
   --trailer-pack=30,ripper:4,mantis:1 --trailer-hud=1 --out=weapons_r5_tp \
   --shots=2.2,2.6,3.0,3.4`
- Which draw call is the disc (camera-aim's probe, `--fp-hide=Sparks` blanks it):
  `tools/godot.sh drive --scene=res://player/camera/demo/rig_probe.tscn \
   --timeline=res://trailer/tl_c_fp.json --skip-menu --god --tod=0.6 --stub=flow \
   --spawn=-540,10,570,45 --probe-log=<abs>/probe.csv --probe-dump-at=4.4 --probe-dump-radius=10 \
   --out=weapons_r5_fp_probe --shots=4.4`   (add `--fp-hide=Sparks` for the vanishing-disc frame)
- Audit A/B (per finding): revert that one fix, re-run the suite, see the named check fail, restore.
  `--nan-watch` fight: add `--nan-watch` to the integration drive below.
- Range captures (oblique camera, ART.md environment):
  `tools/godot.sh drive --scene=res://combat/weapons/tests/weapons_range.tscn \
   --timeline=res://combat/weapons/tests/timeline_rifle.json --aim=0,14,-300 \
   --cam=26,22,40,0,13,-150,55 --out=weapons_r2_rifle --shots=1.35,3.55`
  (same with `timeline_gatling.json --aim=0,12,-100 --cam=30,20,36,0,12,-140,55 --shots=2.6,9.95`
   and `timeline_missiles.json --aim=4,16,-90 --cam=95,42,35,0,16,-95,58 --shots=2.85,3.15`)
- Real-player integration (main.tscn + sandbox + real camera rig):
  `tools/godot.sh drive --scene=res://combat/weapons/tests/integration.tscn \
   --timeline=res://combat/weapons/tests/timeline_integration.json --sandbox \
   --out=weapons_r2_int --shots=1.75,3.85,6.0,9.15,9.6` (add `--debug` for the aim/shot trace)
- Movies:
  `tools/godot.sh movie --movie=<abs>/weapons_r2_demo.avi --scene=res://combat/weapons/tests/weapons_range.tscn \
   --timeline=res://combat/weapons/tests/timeline_all.json --cam=58,36,54,0,15,-120,58`
  `tools/godot.sh movie --movie=<abs>/weapons_r2_int.avi --scene=res://combat/weapons/tests/integration.tscn \
   --timeline=res://combat/weapons/tests/timeline_integration.json --sandbox`

## Captures needed (the lead runs these; `tools/godot.sh shot|drive|movie` refuse without MC_WINDOW_OK)
The r6 numbers above are all headless. The pixels need one window the user approves. **Before/after
means the same command on `557410e~1` (pre-r6) and on `fb2e41a` (post-r6).**

1. **First-person gatling burst, before/after, 3 frames each** — the take the lead reported:
```
tools/godot.sh drive --scene=res://trailer/shot.tscn --timeline=res://trailer/tl_c_fp.json \
  --skip-menu --god --tod=0.6 --stub=flow --spawn=-540,10,570,45 \
  --trailer-pack=30,ripper:4,mantis:1 --trailer-hud=1 --out=weapons_r6_fp \
  --shots=3.4,3.8,4.4,5.0,5.6
```
   Expect: no flat orange polygon on the right of the frame; the casings read as small tumbling
   specks leaving down-and-right, gone inside ~0.2 s.
2. **Third-person control at the same spot** (nothing may have changed):
```
tools/godot.sh drive --scene=res://trailer/shot.tscn --timeline=res://trailer/tl_c_gatling.json \
  --skip-menu --god --tod=0.6 --stub=flow --spawn=-540,10,570,45 \
  --trailer-pack=30,ripper:4,mantis:1 --trailer-hud=1 --out=weapons_r6_tp \
  --shots=2.2,2.6,3.0,3.4
```
   Expect: the 1.25 m casing arc and the 2.2 m muzzle flash exactly as in
   `captures/weapons_r5_tp_sheet.jpg`.
3. **First-person Hailstorm salvo** (the second slab source — flares and smoke off the rails):
```
tools/godot.sh drive --scene=res://trailer/shot.tscn \
  --timeline=res://combat/weapons/tests/timeline_fp_kit.json \
  --skip-menu --god --tod=0.6 --stub=flow --spawn=-540,10,570,45 \
  --trailer-pack=30,ripper:4,mantis:1 --trailer-hud=1 --out=weapons_r6_kit \
  --shots=2.7,4.75,6.2,8.75,9.1
```
   Expect: the canopy is not whited out at 8.8–9.1 s; the swarm still reads as a circus by ~9.3 s.
4. **The movie** (the 60 fps take is what caught the r5 Hailstorm flood, and stills miss motion):
```
tools/godot.sh movie --movie=<abs>/weapons_r6_fp.avi --scene=res://trailer/shot.tscn \
  --timeline=res://combat/weapons/tests/timeline_fp_kit.json --skip-menu --god --tod=0.6 \
  --stub=flow --spawn=-540,10,570,45 --trailer-pack=30,ripper:4,mantis:1 --trailer-hud=1
```

## Evidence
- **r6 identification, on the pre-fix build** (`CasingPool.FP_SCALE 1.0`, `MissileVisuals.FP_SCALE
  1.0`; everything else at `fb2e41a`): `tools/godot.sh test
  res://combat/weapons/tests/test_weapons.gd` -> `TEST 164 checks, 6 failed`:
  `fp_near.gatling_no_orange_slab_within_8m` — `Casings/Casings [box] 5.2 m away, 1.25 x 0.42 m,
  5 deg wide, #FFB333`; `fp_near.gatling_no_hard_orange_primitive_over_0_6m` — the same row;
  `fp_near.casings_are_cockpit_sized` "got 1.250 want 0.338"; `fp_near.salvo_no_orange_primitive_over_16deg_wide`
  — `Visuals/Flares [soft quad] 3.9 m away, 3.60 x 3.60 m, 50 deg wide, #FFFFFF`; plus the two
  `fp_scale_agrees_with_the_context` checks. Full log: the tables in §1 above.
- **r6 after the fix:** `TEST 172 checks, 0 failed`, `TEST ERRORS 0 (known 0, warnings 1)`.
  Casing 1.25 m -> **0.34 m**; flare 3.60 m -> **0.97 m** (50° -> 13° wide); missile smoke 12.60 m ->
  **3.40 m**; missile hull 5.00 m -> 1.35 m. Third-person values are pinned by the r5 checks
  (`fp.flash_third_person_2_2m`, `fp.rifle_ring_third_person`, `fp.launch_puff_third_person`) and by
  `fp_near.casing_box_is_1_25m_in_third_person`, all still green.
- **r6 shader gate:** normal run `TEST ERRORS 0`; `-- --shader-selftest` ->
  `SELFTEST broken shader produced 2 engine error(s): :2 (): Expected a ';'.` and
  `TEST ERROR servers/rendering/dummy/storage/material_storage.cpp:192 shader_set_code():
  [Condition "err != OK" is true.] Shader compilation failed.` The six reached shaders
  (`spark_process`, `spark`, `puff`, `fireball`, `flash_pop`, `shockwave_ring`) all compile.
- **r6 check:** `tools/godot.sh check --only=res://combat/` -> `CHECK 152 files, 0 failed,
  0 engine errors, 0 warnings`.
- **r6 perf:** `PERF idle 0.077 ms/frame, loaded 2.199, weapons cost 2.122 ms/frame` (budget 4 ms).
  Higher than r5's 1.692 in absolute terms, but idle went 0.058 -> 0.077 over the same runs — the
  machine is busier (the user is on it). Weapons cost per unit of idle is unchanged (r5 29x, r6 28x).
  The pools' recording is a single `if` per write and is off outside the near-lens suite.
- **r5 repro on HEAD, before any change.** `tools/godot.sh test
  res://combat/weapons/tests/test_weapons.gd` printed
  `WARNING: Audio: unknown or empty sound id 'gatling_vent_good'` with the backtrace
  `[3] _resolve_vent (res://combat/weapons/gatling.gd:122)`. The `NO ROW` one-liner from `game/`
  printed `NO ROW gatling_jam`, `NO ROW gatling_overheat`, `NO ROW gatling_vent_good`. The `c_fp`
  drive produced `captures/weapons_r5_fp_before_t4_4.jpg`: a flat pale disc ~30 % of the frame tall,
  under the weapon readout. `rig_probe --probe-dump-at=4.4` listed `Spark1@Sparks:6.0` — 6.0 m from
  the lens, matching `muzzle_r` — and `--fp-hide=Sparks` made the disc vanish
  (`captures/weapons_r5_fp_nosparks_t4_4.jpg`).
- **r5 A/B, item 1 (each fix reverted alone, the suite re-run, the fix restored):**
  - gatling call site back to the unscaled `FLASH_SIZE` -> 2 failed:
    `fp.flash_first_person_0_6m` "got 2.200 want 0.594", `fp.flash_first_person_under_0_6m` "2.200 m".
  - `rifle.gd:_visuals` back to the unscaled sizes -> 5 failed: `fp.rifle_ring_first_person`
    "got 3.200 want 0.864", `fp.rifle_glow_first_person` "got 1.600 want 0.432",
    `fp.rifle_beam_starts_down_range_in_first_person` "0.00 m from the muzzle",
    `fp.rifle_stage2_ring_first_person` "got 12.000 want 3.240", `fp.rifle_stage2_glow_first_person`
    "got 7.000 want 1.890".
  - `hailstorm.gd:_launch` back to the unscaled puff/light -> 2 failed:
    `fp.launch_puff_first_person` "got 6.800 want 1.836", `fp.launch_light_first_person`
    "got 2.600 want 1.560".
  - All three restored -> `TEST 148 checks, 0 failed`.
- **r5 A/B, item 2.** `test_feel_rows.gd -- --audio-trace` **without** the three rows:
  `TEST 13 checks, 9 failed` — `vent.overheat_fires_its_row`, `vent.miss_fires_its_row`,
  `vent.good_fires_its_row`, `vent.good_requests_a_sound`, `vent.no_unknown_rows` ("3 unknown ids
  warned"), `vent.row_loaded_gatling_{overheat,vent_good,jam}`, and
  `call_sites.every_id_has_a_row` ("3 unresolved: gatling_jam / gatling_vent_good / gatling_overheat:
  not a FEEL.md row"). The log carries `FeelDirector: no FeelEvent for id 'gatling_overheat'` and
  `Audio: unknown or empty sound id 'gatling_vent_good'`.
  **With** the three rows staged locally (the `.tres` written to `tmp`, the FEEL.md rows and the
  `event_map` entry added, all reverted immediately afterwards — `git status` for `docs/`,
  `game/fx/**`, `game/audio/**` is clean): `TEST 13 checks, 0 failed`, and in the same state
  `test_weapons.gd -- --audio-trace` -> `TEST 148 checks, 0 failed` with **nothing** matching
  `gatling_vent_good|no FeelEvent|unknown or empty sound id`, `test_feel.gd` -> `TEST feel: PASS
  (0 failures)`, `test_audio.gd` -> `TEST audio: PASS (0 failures)`. That is the proof the Request
  below is sufficient; the files themselves are not mine to land.
- **r5 captures** (`captures/`, git-ignored), one sheet each:
  - `weapons_r5_fp_sheet.jpg` — first person before (top row) / after (bottom row) at t=3.4/4.4/5.0;
    the disc becomes a flash at the gun. Stills: `weapons_r5_fp_before_t*`, `weapons_r5_fp_t*`.
  - `weapons_r5_kit_sheet.jpg` — the first-person kit, before on top, after below: rifle tap,
    stage-2 release, gatling ADS, then the Hailstorm frames and the `--fp-hide=Sparks` frame.
    Stills: `weapons_r5_kit_before_t{2_7,4_8,6_2}`, `weapons_r5_kit_t{2_7,4_8,6_2,8_8,9_1}`,
    `weapons_r5_fp_nosparks_t4_4`.
  - `weapons_r5_tp_sheet.jpg` — third person before/after at the same spot
    (`weapons_r5_tp_before_t*`, `weapons_r5_tp_t*`): the flash at the gun, the casing arc and the
    tracers are unchanged. The drive is not frame-deterministic (the enemy pack nudges the mech), so
    the framing drifts a little between the pair; the exact third-person numbers are pinned by
    `fp.flash_third_person_2_2m` / `fp.rifle_ring_third_person` / `fp.launch_puff_third_person`.
  - `weapons_r5_fp.mp4` (10.5 s, 631 frames) + `weapons_r5_fp_movie_sheet.jpg` — the whole kit in
    motion; this is the take that exposed the Hailstorm flood at 8.8 s.
- **r5 perf, unchanged:** `PERF idle 0.058 ms/frame, loaded 1.749 ms/frame, weapons cost
  1.692 ms/frame` (budget 4 ms).
- **r5 integration drive:** `DRIVE done t=12.0 errors=0 warnings=6`, no `NANWATCH` line, at
  `36c0499`. Re-run at HEAD (`7774ff9`) it reports `errors=2907` — **not from `combat/`**: 0 of the
  20 unique `DRIVE ERROR` sources are under `combat/`. They are all
  `res://player/model/hero3/hero3_glow.gd:250` / `:294` `Parse Error: Identifier "radius" not
  declared in the current scope`, cascading into `hero3_drones.gd`, `hero3_rig.gd` and
  `hero3_model.gd` failing to compile — hero-v3's uncommitted work in the shared tree. See Requests.
  Captures from the clean run: `captures/weapons_r5_int_t{1_8,3_9,6_0,9_2,9_6}.jpg`;
  `weapons_r5_int_t3_9.jpg` shows the third-person stage-2 shot unchanged (12 m shock ring, the beam,
  1070/1400 damage numbers).
- look round: `tools/godot.sh check --only=res://combat/weapons/,res://combat/projectiles/` ->
  `CHECK 34 files, 0 failed, 0 engine errors, 0 warnings`; `test_weapons.gd` -> `TEST 121 checks,
  0 failed` (7 new `rifle.dry_*` / `rifle.auto_reload_*` checks).
- look round A/B (revert `rifle.gd` `update()` to `if pressed and ammo > 0`, re-run): 4 fail —
  `rifle.dry_trigger_starts_reload` "reloading false", `rifle.dry_reload_refills` "ammo 0 reloading
  false", `rifle.auto_reload_kicks_in` "still dry after the delay", `rifle.auto_reload_refills`
  "ammo 0". Fix restored -> 121 / 0.
- look round captures, same timeline `timeline_dry.json`, same scene `integration.tscn` (real HUD):
  `captures/look_weapons_before_t5_5.jpg` — panel reads `0 / 9` + dim `CHARGE`, permanently dead
  (the reported bug); `captures/look_weapons_after_t5_5.jpg` — the same frame reads `9 / 9`;
  `captures/look_weapons_after_t4_0.jpg` — the `RELOADING` amber sweep bar mid-reload.
  `look_weapons_{before,after}_t3_6.jpg` are the 0.25 s window before the auto-reload starts (both
  builds show `0 / 9` there — that is the delay, not a bug).
- look round perf, unchanged: `PERF idle 0.074 ms/frame, loaded 1.878, weapons cost 1.804 ms/frame`.
- r4: `tools/godot.sh check --only=res://combat/weapons/,res://combat/projectiles/` ->
  `CHECK 34 files, 0 failed, 0 engine errors, 0 warnings`; `test_weapons.gd` ->
  `TEST 114 checks, 0 failed` (24 new `robust.*` checks).
- r4: `tools/godot.sh drive --scene=res://combat/weapons/tests/integration.tscn
  --timeline=res://combat/weapons/tests/timeline_integration.json --sandbox --nan-watch
  --out=weapons_audit_fix --shots=1.75,3.85,6.0,9.15,9.6` -> `DRIVE done t=12.0 errors=0 warnings=0`,
  no `NANWATCH` line. Captures: `captures/weapons_audit_fix_t{1_8,3_9,6_0,9_2,9_6}.jpg` (mech at
  (0, 7.5, 60), i.e. the displaced case finding #1 is about: launch puffs, missile bodies, flares and
  smoke all sit on the shoulder rails).
- r4: revert-one-fix runs (suite output, only the relevant lines):
  #1 pools not top_level -> 7 failed (`robust.{beams,sparks,casings,bullets,missiles}_is_world_space`,
  `robust.all_pools_world_space`, `robust.tracer_multimesh_is_world_space`, pools reported at
  (140, 0, -60) with the mech's yaw); #2 no `_lock_timer = 0` -> 2 failed
  (`robust.locks_do_not_burst` "0 locks and 1 salvos in the first 2 ticks",
  `robust.locks_stay_paced` "0 locks 0.45 s later"); #3 no `tick_holstered` -> 5 failed
  (`robust.heat_cools_while_holstered` "28.1 -> 28.1", `robust.superheated_expires_while_holstered`
  "4.00", `robust.holstered_vent_{resolves,jams}`, `robust.holstered_jam_clears`);
  #4/#5 no ring guard -> `robust.zero_life_ring_refused` "slot 0" + `robust.no_ring_left_visible`
  "1 rings visible"; #6 old hide -> `robust.afterglow_outlives_the_beam` "beam visible false at
  0.22 s" + `robust.afterglow_slot_not_reused` "slot 0 handed out again"; #7 no `_times.fill` ->
  `robust.fresh_trail_draws_one_smoke_puff` "10 of 20 history slots", `robust.written_samples_age_in`,
  `robust.clear_ages_every_sample_out`.
- r3: `tools/godot.sh check --only=res://combat/weapons/,res://combat/projectiles/` ->
  `CHECK 33 files, 0 failed, 0 engine errors, 0 warnings`
- r3: `tools/godot.sh test res://combat/weapons/tests/test_weapons.gd` -> `TEST 86 checks, 0 failed`
  (13 new checks in `tests/suite_clocks.gd`, all measured with `Feel.real_now()`):
  `clocks.witch_time_opens`, `clocks.world_really_is_slow` (time_scale really is 0.3, so the checks
  below are not vacuous), `clocks.rifle_4_shots_per_real_second_in_witch_time` (4 shots in 0.90 real s
  under `Feel.slow_mo(0.3, 2.0, 0, 0, true)`), `clocks.rifle_burst_fits_one_real_second`,
  `clocks.witch_time_reopens`, `clocks.stage2_charge_takes_1.2_real_seconds` (1.20 real s),
  `clocks.stage2_damage_in_witch_time` (1400), `clocks.hit_stop_starts`,
  `clocks.hit_stop_freezes_the_charge` (a 0.25 s global hit-stop at scale 0.05 grows the charge by
  0.010 of a stage, not 0.208), `clocks.hit_stop_releases_the_shot`, 3x `clocks.time_scale_restored`.
- r2 baseline, unchanged by r3: `CHECK 32 files, 0 failed` and `TEST 73 checks, 0 failed`
  (3 checks: stage-2 COLLAPSE through `prime_detonators`, no detonation on a plain shot,
  `last_hit_usec` / `last_hit_kind` present in `hud_state()`).
- Perf (headless, uncapped frames, 30-frame mean): idle 0.039 ms/frame, 600 rounds + 24 missiles
  1.810 ms/frame -> **1.77 ms/frame** for the whole stack (budget 4 ms).
- Damage unchanged from r1 (rifle 230 @100 m -> 138 @480 m, none past 500 m; gatling 52/26/none past
  the 350 m cut-off; overheat at 118 rounds).
- Captures (`captures/`):
  `weapons_r2_rifle_t1_4.jpg` plain shot at the 300 m wall (0.5 m core / 1.6 m glow, cyan ring),
  `weapons_r2_rifle_t3_6.jpg` stage-2 shot (2.2/7.0 m + 12 m shock ring + sparks on the wall),
  `weapons_r2_gatling_t2_6.jpg` stream + 0.35 m tracers + casing arc,
  `weapons_r2_gatling_t10_0.jpg` overheat, needle readout `heat 100 %  needle 0.65 / mark 0.72`,
  `weapons_r2_missiles_t2_9.jpg` 12-missile bloom with engine flares + smoke,
  `weapons_r2_missiles_t3_2.jpg` curving tapered trails onto the painted dummies,
  `weapons_r2_int_t1_8/_t3_9/_t6_0/_t9_2/_t9_6.jpg` the same weapons on the real PlayerMech in
  `main.tscn --sandbox`.
- Movies: `captures/weapons_r2_demo.mp4` (range, oblique) and `captures/weapons_r2_int.mp4`
  (real player). The `.avi` raw captures are git-ignored.
- r3 note: at `Engine.time_scale == 1.0` (every capture and perf run) `Feel.player_delta(delta) ==
  delta`, so r3 is behaviour-identical to the r2 captures and perf numbers above; the only changed
  behaviour is under slow-mo / hit-stop, which is covered by the clock suite, not by a screenshot.

## Tuning choices (numbers the docs leave open — named fields in the tuning resources)
- First-person VFX (r5 item 1), `WeaponContext`: `FP_SCALE 0.27` (the gatling flash 2.2 m -> 0.594 m,
  the lead's "<= 0.6 m at 6 m" = 8 % of the 62 deg frame), `FP_OPACITY 0.6` (FEEL.md:9),
  `FP_LIGHT_RANGE 0.5` (an omni at the gun lights the whole street from inside the cockpit),
  `FP_BEAM_START 24.0` m (the lens must not look into the open end of the glow cylinder). Every one
  is a no-op in third person, so the third-person look is byte-identical to r4.
- Beam energies: core 1.9 (blooms at the ART.md 1.2 threshold), glow 0.55, afterglow 0.18, rings 1.6.
  The wide glow and afterglow stay under the threshold on purpose: at stage-2 width (7 m) an HDR glow
  layer washes the whole frame out from a 30 m camera.
- Missile visuals: core ribbon 0.9 m wide at the head over 8 samples (0.6 s), smoke 4.2 m growing to
  12.6 m over 1.5 s, flare 3.6 m, samples every 0.075 s.
- gatling belt 240 rounds, reload 3.2 s, cut-off 350 m (the city's longest sightline, SPEC §5),
  bloom +0.9 deg/s while firing and -2.4 deg/s after, vent marker at 0.72 of the sweep.
- rifle: `charge` in `hud_state()` is hold/1.2 s clamped to 1 (pips sit at the stage boundaries).
- missiles: launch interval `salvo_time / missile count`, shoulder launch arc 22 deg up,
  chaff cloud radius 14 m when the node does not declare its own, missile life 6 s (per the brief;
  the dossier's 3 s is the 8 m-hero figure).
- A blast never charges the directly hit actor twice: it is excluded from the radial query.

## Known issues
- **The integration drive gate is unblocked again**: hero-v3's `hero3_glow.gd` parse error is gone
  (`tools/godot.sh check --only=res://player/model/hero3/` -> `CHECK 85 files, 0 failed`). The
  windowed re-run is in Captures needed; the headless gates never depended on it.
- **The missile smoke trail is still 3.4 m at the canopy** (was 12.6 m). It is a soft grey alpha
  disc, not an orange slab, so it is outside the r6 gate, and a salvo *should* smoke up the cockpit —
  but at 3.4 m and ~6 m from the lens it covers roughly a third of the frame width for the first
  ~0.3 s. Say the word and I will take `MissileVisuals.FP_SCALE` down for the smoke alone.
- **`RigModel`'s placeholder mech moved** (r6): the gun is now held at chest height so `muzzle_r` is
  5.9 m from the cockpit eye instead of 12 m. That changes the silhouette in the third-person *range*
  captures (`weapons_range.tscn`), which are git-ignored and re-taken anyway. No weapon number moved.
- `tests/timeline_fp_kit.json` runs against the **trailer's** `shot.tscn` and `c_fp` flags, because
  that is the only scene with a cockpit and a HUD. It is my file; the trailer re-records `c_fp`
  itself. The commit the trailer unit needs for that is **`7774ff9`** (item 1 complete: the FP
  muzzle-flash size rule), on top of `36c0499` and `25c0963`.
- First person, ADS: the gatling flash is 0.594 m — the lead's number, 8 % of the frame at the 62 deg
  FOV. ADS is 45 deg, so it reads about 1.5x larger there (~12 %), which the brief anticipated. It
  also sits partly behind the cockpit rail. Judged acceptable from
  `captures/weapons_r5_kit_t6_2.jpg`; say the word and I will take `FP_SCALE` down further.
- A missile salvo still throws bright engine flares and smoke past the canopy in the first ~0.5 s
  (`weapons_r5_fp.mp4` at 8.6-9.1 s). **r6 measured and shrank it**: the flare is 0.97 m at the rails
  (was 3.6 m) and the smoke 3.4 m (was 12.6 m), ramping back to full size by 40 m. The flares are
  correct once the missiles are 30 m out, so they are scaled by distance, not by camera mode alone.
- The over-the-shoulder camera puts every shot almost parallel to the view axis, so beams are
  foreshortened in the integration captures; the beam look itself is judged from the range captures.
- The hero placeholder model has no `missile_l` / `missile_r` sockets, so the Hailstorm launches from
  the chest fallback (+/-1.6 m). Nothing breaks; it will read correctly once the rails exist.
- `Feel.play` rows only fire when the feel director is in the scene. The range scene instances the fx
  unit's `VfxLibrary` directly (not the whole director) so captures show the real pooled impacts.
- The rifle's ADS FOV change is the camera-aim unit's job; the component only reports `ads`.

## Requests (to the lead / other units)
- **mech-move (r7, your Request 17 — LANDED, please delete the adapter's field writes).**
  `WeaponSystem.stop_volley()` and `HailstormLauncher.cancel()` now exist and do exactly what your
  gate needed: the rifle's charge, the gatling's spin and the launcher's paint / locks / timers stop,
  ADS and strafe-aim drop (through the mech's own `set_strafe_aim(false)`, so the mech and the
  component agree), and nothing is refilled — ammo, heat, the jam, Superheated, the missile cooldown
  and the selected weapon all carry over, and no bus row is emitted. `MechTeardown._weapons()` takes
  the `has_method(&"stop_volley")` branch and returns, so **`_unpaint()` and the `ctx.set(&"ads", …)`
  / `ctx.set(&"strafe_aim", …)` lines in it are now dead code** — please delete them (and `_unpaint`
  itself if nothing else calls it); I verified with a scratch harness that `quiet()` reaches
  `stop_volley()` and leaves those fields alone. Your `test_death.gd` is 108/108 on this build, with
  the CARRY gate reading `rifle=6 gatling=226 burst=0 weapon=gatling` unchanged. One thing to know if
  you ever widen the hook: I deliberately do NOT call `ctx.stop_action()` — `Hero3Model.stop_action()`
  sets `_dying = false`, which would cancel the death clip.
- **camera-aim (r6)**: `WeaponContext.lens()` reads `AimSystem.camera()` — thank you, that public API
  is exactly what the near-lens rule needed, and it is the *real* lens rather than a mirror of
  `cockpit_frame.gd`. One ask: the cockpit camera is what the rule wants, but `camera()` also answers
  in third person, where the lens is 42 m behind the mech. I only read it while
  `is_first_person()` is true, so nothing is wrong today — but if you ever cache or reuse the
  Camera3D node across modes, please keep `global_position` honest at all times, or give me an
  explicit `lens()` and I will switch to it.
- **fx (r6)**: `combat/weapons/tests/suite_shaders.gd` compiles the six shaders behind the pooled
  kinds the weapons spawn (`spark_bullet`, `spark_beam`, `dust_puff`, `missile_blast`, `scorch`,
  `spawn_ring` -> `spark_process`, `spark`, `puff`, `fireball`, `flash_pop`, `shockwave_ring`). If a
  new kind is added to that set, or one of those presets starts using another shader, please ping me
  — the list is hand-maintained and `tools/godot.sh check` will not notice it going stale.
- **lead / feel / audio (r5 item 2) — LANDED, thank you.** All three FEEL.md rows
  (`gatling_overheat`, `gatling_vent_good`, `gatling_jam`), their `fx/events/<id>.tres` and the
  `audio/event_map.gd` entries are in the tree; `test_feel_rows.gd -- --audio-trace` is
  `13 checks, 0 failed` and a perfect vent still requests exactly 2 `gatling_vent_perfect` sounds.
  Nothing outstanding on my side.
- **hero-v3 (was blocking my integration gate) — resolved.** `hero3_glow.gd` compiles again
  (`CHECK 85 files, 0 failed` on `res://player/model/hero3/`), so the `integration.tscn` drive can be
  re-run. Nothing was needed from you; closing the note.
- **hud (look round item 1, fixes 2 and 3)**: `game/ui/widgets/weapon_panel.gd` already draws the ammo
  count amber at 0, but `_draw_state()` still falls through to the `CHARGE` pips when the rifle is
  empty and not reloading, so the panel still reads `0 / 9 CHARGE`. Please replace that label with
  `RELOAD [R]` (16 px amber, outlined), and add the 14 px amber `RELOAD` tag ~40 px right of the
  reticle (Daemon X Machina, ref image 17). My side now reloads on a dry trigger and 0.25 s after the
  last round, so the state is brief — but it is still reachable when the player swaps to the gatling
  on an empty cell, because a holstered rifle does not tick.
- **lead (r3, decision to confirm)**: the charge tap/hold accumulator and the vent needle + press
  windows run on `Feel.player_delta`, not `real_delta`. In witch time the two are identical
  (`player_time_comp()` == 1/scale), so the needle keeps real-time speed and the windows stay the real
  6/12 frames the HUD promises — that is the case the clock contract exists for, and your test #3
  passes on it. They differ only inside a global hit-stop: on `real_delta` the needle would keep
  sweeping while the player is frozen and cannot press, turning an unavoidable hit-stop into a jam.
  I froze it with the player instead (same call melee made for the parry window). Say the word if you
  want the literal `real_delta` reading and I will switch it — it is three accumulators.
- **mech-move / hero model**: please add `missile_l` and `missile_r` sockets (S3 launches from both
  shoulders); until then the launcher falls back to the chest at +/-1.6 m.
- **camera-aim**: at rest in third person the crosshair sits ~9 deg below the horizon (the aim ray
  hits the ground ~120 m ahead), so a level shot needs a `look` correction of about -120 px. If that
  rest pitch is intended, ignore this — it only cost a capture iteration.
- **fx/feel**: `res://fx/screen_fx/post.gdshader` failed to compile earlier today
  (`Redefinition of 'TAU'`); it is fixed now, but `tools/godot.sh check` does not compile shaders, so
  a windowed run was the only way to see it. Also: `VfxLibrary` is in no group, so I find it by class
  (`find_children("*", "VfxLibrary")`) once per tree — a group would be cheaper and more obvious.
- **enemies / skills**: marks go to `enemy.status.add_mark_hit(n)` and primes to the
  `prime_detonators` group call, both per CONTRACTS §4. I pass the blast radius as the detonation
  radius (8 m rifle stage 2, 6 m missiles) — tell me if COLLAPSE wants its own number.
