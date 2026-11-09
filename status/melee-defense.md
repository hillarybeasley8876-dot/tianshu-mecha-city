# melee-defense status

## Scope
`game/combat/melee/**`, `game/combat/defense/**` — Dawn Edge saber (曦刃): L1–L3 with cancels, homing
lunge, charged slash + crescent wave, air string, Return Cut, Ram Kick, Core Rend executions; and
Mirror Guard (镜返盾): perfect parry, held block, catch field.

## Done — r7 (the Mirror Guard reads as an energy shield, not a mint-green tile)

### 0. What the old look actually was, from the r6 stills
`captures/melee_int_05_catch_hold.jpg` and `captures/melee_int_07_parry_return.jpg` (read this round)
show exactly what the lead described and give the three causes:

* **One alpha everywhere.** `shield_visual.gd` built the panel out of a 6-sided `CylinderMesh` and
  gave it `CombatMesh.hdr(SHIELD_COLOR, 1.15, 0.35)` — an additive material with a SINGLE alpha, so
  the middle of the plate was exactly as bright as its edge. No fresnel, no rim, no interior.
* **13 m across.** `DefenseTable.PANEL_RADIUS` was 6.5, i.e. wider than the hero's own chest.
* **Washed to near-white, not cyan.** `#4fe6ff × 1.15` added on top of ART.md's bright dusk city
  pushes green and blue over 1.0 together; the r6 still shows a pale mint card, not the hero's cyan.
* And in `melee_int_07_parry_return.jpg`, the perfect-parry ring is a **screen-filling white donut**:
  `PERFECT_COLOR × 2.2` clips every channel under AgX, so the white-gold never arrives.

### 1. New surface — `combat/defense/shaders/mirror_shield.gdshader` (74 lines)
One shader for both Mirror Guard surfaces. `blend_add` + `depth_draw_never`, so it never occludes
anything: **ALPHA is the contribution, and the hero and the target are visible straight through it.**
* interior = `core_alpha * (1.0 + hex_gain * cells)` — a flat wash plus hex cell walls;
* rim = `max(fresnel, radial band)` — two terms that agree, so the panel reads edge-on AND face-on,
  and the hard silhouette of the old plate became a soft glowing edge;
* `ripple` = a ring travelling out of the UV the hit landed on; `flash` = the perfect parry;
* `hex_spin` turns the cells (the catch dome only).

### 2. `MirrorShieldProfile` (`shield_profile.gd`, 128 lines) — one source of truth
Every number the pixels depend on lives here, is pushed into the material, and is what the tests
measure. The colour is **`Color(0.30, 0.90, 1.00)` = `Hero3Shade.ACCENT`**, and a test reads that
constant out of `player/model/hero3/hero3_shade.gd` and fails if the two ever drift apart.

| | old (r6) | new (r7) |
|---|---|---|
| panel size | 13.0 m across (`PANEL_RADIUS` 6.5) | **9.2 m** (`PANEL_RADIUS` 4.6) — the mech's chest and head |
| panel form | flat hexagonal cylinder | **curved hexagonal cap**, `PANEL_BULGE` 1.1 m proud of its rim |
| interior alpha | 0.35 everywhere | **0.12**, worst interior pixel **0.156** (lead's ceiling 0.25) |
| rim alpha | — | **0.95** (lead's floor 0.8) |
| colour | `#4fe6ff` at energy 1.15 → mint | hero accent, rim `#b8faff` |
| in / out | visibility pop | **0.08 s in, 0.15 s out** (`fade` uniform) |
| block reaction | none | **ripple from the hit point**, gone in 0.45 s |
| parry reaction | white donut | panel flash + **18 hex shards**, plus a ring that keeps its gold |
| catch field | no surface of its own | **translucent dome**, turning hex cells, rim visible |

### 3. New files
* `combat/defense/shaders/mirror_shield.gdshader` — the surface.
* `combat/defense/shield_profile.gd` — the numbers, the material builders, the CPU mirror of the
  shader's alpha maths.
* `combat/defense/parry_shards.gd` — the 18-shard pool, built once in `_ready()`; a parry only moves
  and re-fades them, so it allocates nothing mid-fight.
* `combat/defense/catch_dome.gd` — the catch field's dome. Built as a polar grid (not a `SphereMesh`)
  so the shader's `length(UV * 2 - 1)` rim term is the polar angle: 0 straight ahead, 1 on the rim.
* `combat/defense/tests/suite_visual.gd` — 52 checks, below.
* `combat/defense/tests/test_guard_capture.gd` — verifies the CAPTURE TIMELINE (see §5).
* `combat/melee/tests/timeline_guard_r7.json` — the capture beats.

### 4. The GLSL is compiled headless — and `check` does NOT do it
Measured, not assumed: `tools/godot.sh check` reports **`CHECK 0 failed`** on a `mirror_shield.gdshader`
with a deliberate syntax error. But the dummy renderer's material storage DOES parse shader code, and
logs `SHADER ERROR` + `Shader compilation failed` — it just needs a trigger. `Shader.new()` +
`code = <source>` + **`get_shader_uniform_list()`** is that trigger (the call answers an empty list
headless either way, but it runs the compiler). `mat.shader_compiles` does exactly that inside an
`ErrorCounter` window, and it is **not vacuous**: with `THIS_IS_NOT_GLSL;` injected it fails
`mat.shader_compiles 2 error(s): :46 (): Unknown identifier in expression: 'THIS_IS_NOT_GLSL'.`

### 5. The capture timeline is verified headless too
The lead runs the captures, so the shot times in §"Captures needed" have to mean something. 
`test_guard_capture.gd` boots the real `melee_range.tscn`, replays `timeline_guard_r7.json`'s own
guard presses at 120 Hz, and records the shield's state at the three `--shots=` instants:
1.82 s (panel up and faded in, **catch field not open yet**), 6.35 s (dome open, rounds orbiting),
8.88 s (parry landed, shards still in the air, panel still flashing). It found a real bug on its first
run — the first draft's catch shot at 5.20 s was 0.2 s before the spitter's arc reached the 12 m
hemisphere, so that still would have shown an empty dome. 27 checks, 0 failed.

### 6. Mutation-checked (none of the new checks are vacuous)
| mutation | check that failed |
|---|---|
| `CORE_ALPHA` 0.12 → 0.50 | `alpha.shield.center_alpha_at_most_0.25` — *worst interior pixel 0.650* |
| `RIM_ALPHA` 0.95 → 0.50 | `alpha.shield.rim_alpha_at_least_0.80` — *rim 0.500* |
| `FADE_IN` 0.08 → 0.50 | `fade.in_is_0_08_s` — *got 0.500 want 0.080* |
| `RIPPLE_TIME` 0.45 → 0.90 | `ripple.decays_to_zero_within_0_5_s` — *strength 0.426 after 0.50 s* |
| `SHARD_LIFE` 0.55 → 2.00 | `parry.shards_freed_within_1_s` — *got 18 want 0* |
| `RING_ENERGY` 1.30 → 2.20 | `parry.ring_blooms_without_clipping` — *peak channel 2.20* |
| `THIS_IS_NOT_GLSL;` in the shader | `mat.shader_compiles` — *2 error(s)* |

The ripple wait is the **lead's** 0.5 s, not `RIPPLE_TIME`, so raising `RIPPLE_TIME` moves nothing.

### 7. One judgement call to confirm
`ShieldVisual.RING_ENERGY` 2.2 → **1.30** and `RING_BAND` 0.16 → **0.10**. The lead did not ask for
this, but `melee_int_07_parry_return.jpg` shows the perfect parry arriving as a white donut with no
gold in it, which is the same "placeholder" read the round is about. The ring's radius (18 m) and
timing are unchanged. Revert both constants if the old punch is preferred — `parry.ring_blooms_without_clipping`
is the check to delete with them.

## Captures needed (r7)
All of these need `MC_WINDOW_OK=1`; every one is `tools/godot.sh`, never `godot` directly. The
**current look** to put beside them is `captures/melee_int_05_catch_hold.jpg` (block + catch) and
`captures/melee_int_07_parry_return.jpg` (parry), both from r6.

**A — the three beats, 3/4 front.** Block panel, catch dome, parry burst, one run:
```
tools/godot.sh drive --timeout=600 \
  --scene=res://combat/melee/tests/melee_range.tscn --nocam \
  --cam=22,14,-20,-2,11,-5,45 \
  --timeline=res://combat/melee/tests/timeline_guard_r7.json \
  --shots=1.82,6.35,8.88 --autoshot --out=melee_r7_front34
```
**B — the same three beats, side on** (swap only `--cam`):
```
tools/godot.sh drive --timeout=600 \
  --scene=res://combat/melee/tests/melee_range.tscn --nocam \
  --cam=28,13,-4,-3,11,-4,45 \
  --timeline=res://combat/melee/tests/timeline_guard_r7.json \
  --shots=1.82,6.35,8.88 --autoshot --out=melee_r7_side
```
**C — a tight shot of the shield itself** (the interior transparency is the thing to judge):
```
tools/godot.sh drive --timeout=600 \
  --scene=res://combat/melee/tests/melee_range.tscn --nocam \
  --cam=12,12,-14,-3,11,-5,38 \
  --timeline=res://combat/melee/tests/timeline_guard_r7.json \
  --shots=1.82,6.35,8.88 --autoshot --out=melee_r7_close
```
`--autoshot` adds an event-driven still on `Events.parry_success` (the exact parry frame, which the
timed `--shots` can only approximate). `--cam` is `px,py,pz,lx,ly,lz[,fov]`; the mech is at
`(0, 8, 0)` facing `-Z`, so the numbers above are front-right, pure right, and close front-right.
They are framing estimates — the socket is on `L_Forearm`, so if the shield sits off-frame, pan the
look-at point (`-2,11,-5`) a couple of metres.

**D — a real mantis, blocking and parrying** (the range's monsters are boxes; this is the enemies
unit's Mantis). Same drive as r6, it re-shoots all nine beats with the new surface:
```
tools/godot.sh drive --timeout=900 \
  --scene=res://combat/melee/tests/integration.tscn --sandbox \
  --enemies=mantis:2,ripper:6 \
  --timeline=res://combat/melee/tests/timeline_integration.json \
  --nan-watch --out=melee_r7_int
```
→ `captures/melee_int_05_catch_hold.jpg`, `_07_parry_return.jpg` overwrite the r6 pair, so the
before/after is the same filename. Copy the old two aside first if the comparison matters.

**E — the reel** (optional, if the segment is being recut):
```
tools/godot.sh movie --timeout=900 --movie=$PWD/captures/melee_r7_guard.avi \
  --scene=res://combat/melee/tests/melee_range.tscn --nocam --cam=22,14,-20,-2,11,-5,45 \
  --timeline=res://combat/melee/tests/timeline_guard_r7.json
```

## Done — r6 (hud_state() answers before the first physics tick)

### 1. The frame-1 SCRIPT ERROR pair — cause and fix
**Cause (two lines).** `charge`, `lunge` and `strike` are built in `_refresh()`, and `_refresh()` only
runs from `_physics_process` (`melee_system.gd:97`). The HUD polls from `_process`
(`ui/hud.gd:127` → `ui/hud_data.gd:75`), and a test-host boot of `main.tscn` adds main in a deferred
flush AFTER that frame's physics step — so the first poll reaches `charge_ratio()` / `lunge_ready()`
while `charge` and `lunge` are still `null`.

**Reproduced at HEAD (acc1e75) before touching anything** —
`tmp/melee-defense/r6_repro.log`, exactly 2 `SCRIPT ERROR`s, the documented chain
`hud_state ← HudData.poll ← Hud._process`, then `MAIN SPAWN TEST 6 checks, 0 failures` / `PASS`:
```
SCRIPT ERROR: Invalid call. Nonexistent function 'ratio' in base 'Nil'.
   at: MeleeSystem.charge_ratio (res://combat/melee/melee_system.gd:186)
SCRIPT ERROR: Invalid call. Nonexistent function 'ready' in base 'Nil'.
   at: MeleeSystem.lunge_ready (res://combat/melee/melee_system.gd:233)
```

**Fix — guard, not build-earlier.** `melee_system.gd` now has ONE rule for the whole file, the one it
already used at `last_hit_usec()` / `last_hit_kind()` / `reset()` / `hud_state`'s `executor` entries:

> A public accessor answers with the **idle-mech value** until `_refresh()` has built its part.

```gdscript
func charge_ratio() -> float:
	return charge.ratio() if charge != null else 0.0
func lunge_ready() -> bool:
	return lunge.ready() if lunge != null else false
```

**Why guard and not build earlier.** `_refresh()` is lazy on purpose (`melee_system.gd:61-62`): the
mech instances its components before the model/aim siblings are guaranteed ready, so `p.call("model")`
and `p.call("aim")` can return null on the first tick and only resolve later. Moving that work into
`_ready()` would also move `saber.attach()` and `executor.setup()` to a moment when `_model` is
usually still null, and `_aim` would be baked into `MeleeStrike` as null — the very state the lazy
refresh exists to avoid. The guard is two lines, changes no ordering, and leaves nothing dead: the new
test below proves `charge` and `lunge` really are null at that moment (`tick1.parts_built` is the
control).

**The whole public surface is now safe from the moment the node is in the tree** — audited method by
method: `charge_ratio` / `lunge_ready` guarded (above); `execution_available` → `_execution_target()`
already returns null while `_aim` is null; `cancel_open` → `_in_cancel_window()` returns false on
`move == &""`; `last_hit_usec` / `last_hit_kind` / `reset` already guarded; `hud_state`'s `jackpot`
and `executing` entries already guarded. `sweep` / `saber` / `executor` are built in `_ready()`, so
they are never null once the node is in the tree.

### 2. The regression test — `tests/test_hud_first_frame.gd` (42 checks)
Builds the real `melee_system.tscn` under `MeleeTestHarness.build()` and calls `hud_state()` in the
**same physics frame** as the `add_child` (the harness now records `built_frame`, and the test's first
check is `boot.same_physics_frame_as_add_child` — its own precondition). It attaches the host's
`res://tools/error_counter.gd` with `OS.add_logger` around the call, so the script errors the exit
code ignores are counted here. Then: 12 keys present, `charging` float 0.0, `lunge_ready` and
`execution_available` bool false; one system tick later (`h.ticks(2)` — `physics_frame` fires at the
START of a frame, before the nodes' `_physics_process`) the same 12 keys come back with the same
types, with `tick1.parts_built` as the control that `_refresh()` really ran.

**FAIL on the old code** (`git show HEAD:…melee_system.gd`, `tmp/melee-defense/r6_hud_old_fail.log`) —
FAIL lines, not a crash or a timeout:
```
FAIL boot.no_errors_logged 2 error(s): res://combat/melee/melee_system.gd:186 MeleeSystem.charge_ratio(): Invalid call. Nonexistent function 'ratio' in base 'Nil'.
TEST 42 checks, 1 failed
TEST FAIL boot.no_errors_logged — 2 error(s): res://combat/melee/melee_system.gd:186 MeleeSystem.charge_ratio(): Invalid call. Nonexistent function 'ratio' in base 'Nil'.
```
(The value assertions pass on the old code too: a failed call in a `-> float` / `-> bool` function
returns the type's zero value, so `charging` still reads 0.0 — the logged errors are the defect, and
that is what the test counts.)

**PASS on the new code** (`tmp/melee-defense/r6_hud_new_pass.log`, 0 `SCRIPT ERROR`):
```
PASS boot.same_physics_frame_as_add_child
PASS boot.no_errors_logged
PASS boot.charging_is_float_0
PASS boot.lunge_ready_is_bool_false
PASS boot.execution_available_is_bool_false
PASS tick1.parts_built
TEST 42 checks, 0 failed
```

### 3. `SCRIPT ERROR` count of every gate log — 0 everywhere
| log | `SCRIPT ERROR` | result |
|---|---|---|
| `r6_ms_ripper6.log` | 0 | `MAIN SPAWN TEST 6 checks, 0 failures` + `PASS` |
| `r6_ms_none.log` | 0 | `MAIN SPAWN TEST 2 checks, 0 failures` + `PASS` |
| `r6_ms_stub.log` | 0 | `MAIN SPAWN TEST 2 checks, 0 failures` + `PASS` |
| `r6_flow_perf.log` | 0 | `TEST 2 checks, 0 failed` |
| `r6_smoke.log` (`run res://main.tscn 20`) | 0 | `SMOKE seconds=20 fps_mean=45 fps_min=15 errors=0 warnings=1` |
| `r6_int.log` (integration drive) | 0 | `INT done shots=9 failed=0`, `DRIVE done t=55.0 errors=0 warnings=0` |
| `r6_melee.log` / `r6_defense.log` / `r6_hud_new_pass.log` | 0 | 252 / 90 / 42 checks, 0 failed |

Blade still in the hand: `captures/melee_int_01_string.jpg` and `_08_core_rend_a.jpg` show the cyan
blade held in the mech's right hand mid-string and mid-execution — the guard changed no ordering.

### 4. Housekeeping
- **Re-baselined at HEAD (acc1e75) before the change**: `check` 46 files 0 errors, melee 252 checks
  0 failed, defense 90 checks 0 failed — the r5 numbers still hold after 5526977 / 4d486e2 / e63e072.
- **Old Known issue 4 and Request 3 dropped** (the `aim_system.gd:68` flood after a freed target).
  The lead fixed it in 24f0021 and this round's drive confirms it: `DRIVE done t=55.0 errors=0`.
- **Old Request 4 dropped** (a dying monster scaled to 0). This round's `--nan-watch` drive reported
  nothing, so there is no fresh evidence for it.
- One transient false alarm worth recording: the first integration drive of this round failed the
  `lunge` and `core_rend` beats with `errors=6`, all of them
  `res://player/aim/aim_system.gd:176 Parse Error: Identifier "SWITCH_GRACE" not declared`. That was
  camera-aim's r8 edit caught mid-write in the shared tree (`git status` showed the file modified);
  `PlayerMech._load_components` could not load `AimSystem`, so `player.aim()` was null and no hard
  lock existed. Re-run after their write landed: all six beats pass, `errors=0`.

## Done — r5 (the stray quad, hero-v3's blade, the probe kept warm)

### 1. The stray grey quad — root-caused, not guessed
It is **the swing ribbon itself**, not a fragment: hiding `SaberVisual.trail()` removes it, and with
the trail forced to an opaque material the cell renders nothing there. Measured at the flagged frame
(`melee_strip`, string front f6): the ribbon's newest sample sat **~7–10 m from the blade tip on
screen** and every vertex colour was ~0.00–0.01 (99 % faded), i.e. an arc that had outlived its
attachment to the blade. Two things let that happen:

* **A single quad could span `MAX_SAMPLE_STEP` = 12 m.** A quad is `blade length × sample step`, so a
  12 m step is a 12 × 5 m sheet of paper — exactly the card the lead measured.
* **Nothing dropped the arc when the blade left it.** The shipped clips swing 12–22 frames AFTER the
  active window closes (Requests 1), so the arc stayed where the blade used to point for the rest of
  its 0.18 s fade.

Four fixes, all in the new `game/combat/melee/swing_trail.gd`:
- `MAX_STEP` 12.0 → **3.0 m**: the longest quad the ribbon can ever draw. Measured travel is
  0.2–0.6 m per tick in an active window and ~2.2 m per tick for the fastest clip swing, so a real
  swing is never cut; anything faster restarts the ribbon instead of stretching it.
- **`track()` + `DETACH_STEP` (3 m)**: the blade tip is fed to the ribbon every tick, and a ribbon
  the blade has run away from is dropped. Only applies BETWEEN swings — while a swing is sampling the
  newest sample *is* the blade.
- **Per-swing LANES**: the string chains L1→L2 through a cancel window shorter than `TRAIL_FADE`, so
  L1's samples were still alive when L2 opened. A quad never bridges two swings, and the frame a new
  active window opens draws **zero** quads in its lane (the lead's rule verbatim).
- **Per-sample timestamps**: each sample fades on its own clock. One shared timer was reset by every
  new sample and held the dead arc at full brightness.

The trail also moved out of `saber_visual.gd` (460 lines) into `swing_trail.gd` (217), and now
rebuilds on the PHYSICS tick, so it shows every sample at 120 Hz instead of every other one.

### 2. hero-v3 compatibility + the one agreed blade number
`SaberVisual.attach()` asks the model `has_own_blade()`. When it answers true:
- the white core and the hilt are **hidden** — no second blade through the mech's hand;
- the additive sheath is rebuilt as the **extension only**: it starts at the model's steel tip
  (`blade_length()`, default `MeleeTable.MODEL_BLADE_LENGTH`) and grows out to `BLADE_LENGTH` as the
  blade ignites, so ignition reads as energy running up the model's blade;
- `drawn_length()` lerps steel-tip → `BLADE_LENGTH`, so the trail samples the whole visible blade.

**The agreed number: 12 m of modelled steel + a 2 m energy extension = `MeleeTable.BLADE_LENGTH`
14 m** (`MODEL_BLADE_LENGTH = 12.0`). 14 m is not a guess — it is the length at which the DRAWN tip
covers the hit volume, now pinned by a test:
`hand.<move>_visible_reach_covers_the_hitbox` measures the drawn tip from the arc pivot against the
table's reach, every active tick. Measured on the shipped rig (drawn / hitbox, metres):
L1 19.7/18 · L2 19.2/18 · L3 22.6/20 · lunge 24.3/18 · charge_slash 22.0/22 · air_l1 19.2/16.
At 12 m total, charge_slash would fall to 20.0/22 and L1/L2 to 17.2/18 — which is why the number is
14 m of *visible* blade with the steel at 12 m.

### 3. `melee_clip_probe` kept ready
Re-run on the shipped rig; the table is unchanged (see Requests 1) and the hit-stop hold still
reports `STOP 0.083 s | held 8 ticks | move clock slipped 0 ticks | hand drifted 0.00 deg | OK`.

## In progress / next
**r7 is code-complete and every headless gate is green; the pixels are unverified.** The five capture
commands under "Captures needed (r7)" are waiting on `MC_WINDOW_OK=1` — until one of them runs, the
only claim this round can make is that the shader's inputs are right, not that the shield reads as
energy on screen. Nothing else is outstanding from the brief, review r1–r6, the audit or the lead notes.

## How to verify (exact commands)
```
tools/godot.sh check --only=res://combat/melee/,res://combat/defense/   # 148 files, 0 errors
tools/godot.sh test res://combat/melee/tests/test_melee.gd               # 252 checks, 0 failed
tools/godot.sh test res://combat/defense/tests/test_defense.gd           # 144 checks, 0 failed

# the frame-1 regression (hud_state() before the first physics tick)
tools/godot.sh test res://combat/melee/tests/test_hud_first_frame.gd     # 42 checks, 0 failed

# r7: the capture timeline's shot times, replayed headless
tools/godot.sh test res://combat/defense/tests/test_guard_capture.gd     # 27 checks, 0 failed

# the four test-host boots of res://main.tscn — 0 SCRIPT ERROR in every log
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --enemies=ripper:6 --timeout=300
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --no-enemies --timeout=300
tools/godot.sh test res://enemies/tests/test_main_spawn.gd -- --sandbox --enemies=ripper:4 --stub=enemies --timeout=300
tools/godot.sh test res://flow/tests/test_flow_perf.gd -- --skip-menu --no-enemies --spawn=-514.5,112,105.1,-66.4 --timeout=300

# the shipping boot
tools/godot.sh run res://main.tscn 20                                    # SMOKE ... errors=0

# the 60 fps filmstrips (front + side of the string, the lunge, the charged slash)
tools/godot.sh run res://combat/melee/tests/melee_strip.tscn 400

# the clip-vs-frame-data table + the hit-stop hold, on the real hero rig
tools/godot.sh run res://combat/melee/tests/melee_clip_probe.tscn 90

# the scripted fight in the real game, with the non-finite scan
tools/godot.sh drive --scene=res://combat/melee/tests/integration.tscn --sandbox \
  --enemies=mantis:2,ripper:6 --timeline=res://combat/melee/tests/timeline_integration.json \
  --nan-watch --out=melee_r6_int

# the demo range (on the shipped hero rig, so the blade rides the real hand)
tools/godot.sh drive --scene=res://combat/melee/tests/melee_range.tscn \
  --timeline=res://combat/melee/tests/timeline_showcase.json --nocam --autoshot --out=melee_r5
```

## Evidence
- **r7:** `tmp/melee-defense/r7_defense.log` (144 checks, 0 failed, `TEST ERRORS 0`),
  `r7_melee.log` (252/0), `r7_hud.log` (42/0), `r7_capture.log` (27/0), `r7_main_spawn.log`
  (6 checks 0 failures, **0 `SCRIPT ERROR` / `SHADER ERROR`**). The mutation table in "Done — r7" §6
  is the proof the new checks bite; `r7_mutation.log` is the run with four constants broken at once.
  `check --only=res://combat/` → `CHECK 148 files, 0 failed, 0 engine errors, 0 warnings`.
- **r7, what is NOT proven:** the pixels. Every number above is the shader's inputs and the CPU
  mirror of its maths; the only evidence that it READS as an energy shield is the capture set in
  "Captures needed", which the lead runs. The camera framings there are estimates.
- **r6:** `tmp/melee-defense/r6_*.log` — the table in "Done — r6" §3 carries every gate log with its
  `SCRIPT ERROR` count and result. The FAIL/PASS pair is in §2. `captures/melee_int_01_string.jpg`
  and `captures/melee_int_08_core_rend_a.jpg` show the blade still in the right hand.
- `captures/melee_r5_strip_string_front|side.jpg`, `_lunge_*`, `_charge_slash_*` — 8 frames per move
  at 60 fps, front and side, on the shipped hero. **No stray quad in any of the 48 cells** (the r4
  sheets had it in string front f7 and string side f4); the blade sits in the right hand and sweeps
  with the arm in every frame.
- `hand.*` (48 checks) in the melee suite, unchanged from r4, plus the new
  `hand.<move>_visible_reach_covers_the_hitbox` (8 checks) with the numbers in §2 above.
- `blade.*` (12 checks, new `MeleeBladeSuite`): the string chained through the CANCEL windows —
  `no_quad_bridges_two_swings` 0, `new_swing_starts_on_a_clean_lane` 3 of 3 active windows,
  `no_quad_longer_than_a_swing_step`, and the hero-v3 own-blade set (adopted, no second blade drawn,
  12 m of steel, tip at the steel before ignition, energy out to 14 m, trail still sampling).
  **Not vacuous**: with `_joins()` stubbed to `return true`, the suite fails
  `no_quad_bridges_two_swings got 2 want 0` and `new_swing_starts_on_a_clean_lane 2 of 3`.
- Integration: `INT done shots=9 failed=0` — all six beats (string, lunge, ram_kick, catch,
  parry_return, core_rend), `DRIVE done t=55.0 errors=0`, no non-finite report from `--nan-watch`.
- Range: `DRIVE done t=16.5 errors=0 warnings=0`, 14 shots in `captures/melee_ev_*.jpg` — L1 mid-swing,
  the crescent wave, the parry ring with the perfect window open, the Return Cut, the execution from
  the cinematic camera.
- `melee_clip_probe` table (see Requests 1) reproduced on this run.

## Known issues
1. **The shipped hero's melee clips are 12–22 frames late** (Requests 1). This is what made the stray
   quad look detached in the first place: the trail is drawn on the frame data and the arm arrives
   later. `DETACH_STEP` now drops the arc rather than letting it hang, but hero-v3 is what makes the
   trail beautiful.
2. The trail is a wide fan on those clips: they turn the blade ~90–100° in ~5 ticks, so a ribbon over
   a 14 m blade covers a large area. It reads as an arc now, not a card.
3. The range's dummy monsters are boxes, not the Tripo husks.
4. The lunge's stop distance varies with sandbox geometry; the beat asserts "crossed at least half
   the gap under power" and the continuous homing is pinned by the unit suite.
5. The melee string does not lock movement, so the mech can walk out of its own swing — deliberate,
   since locking it would kill the dash-cancel §4.3 requires.
6. **`combat/defense/defense_system.gd` is 474 lines** (the house rule says consider splitting over
   ~400; the hard limit is 600). It was 462 before r7 and r7 added 12. The clean seam is the damage
   pipeline — `_damage_filter` / `_perfect` / `_block` / `_reflect_incoming` / `_reflect` /
   `_reflectable` / `_hit_point`, ~160 lines that only need `state`, `_facing()` and `_origin()`.
   Not done in r7 because it is a behaviour-preserving refactor of the file every defence test
   drives, and it deserves its own commit and its own gate run.

## Requests (to the lead / other units)
1. **hero-v3** — every melee clip's swing is late against `melee_table.gd`. Measured on the shipped
   rig (`melee_clip_probe`), 60 fps frames from the start of the move:
   | clip | clip length | swing | active window | lead / tail |
   |------|-------------|-------|---------------|-------------|
   | melee_l1 | 0.47 s | f22–f28 (98°) | f10–f13 | +12 / +15 |
   | melee_l2 | 0.47 s | f20–f26 (77°) | f9–f12 | +12 / +14 |
   | melee_l3 | 0.90 s | f28–f34 (80°) | f15–f20 | +14 / +14 |
   | lunge | 1.10 s | f20–f30 (26°) | f7–f48 | +14 / −18 |
   | charge_slash | 0.90 s | f30–f34 (86°) | f11–f18 | +20 / +16 |
   | air_l1 | 0.40 s | f10–f24 (87°) | f9–f12 | +2 / +12 |
   | air_l2 | 0.40 s | f8–f22 (91°) | f9–f12 | −2 / +10 |
   | return_cut | 0.50 s | f8–f18 (43°) | f7–f12 | +2 / +6 |
   | ram_kick | 1.13 s | f28–f34 (34°) | f7–f12 | +22 / +22 |
   The clip LENGTHS are already close; it is the swing's position inside them that has to move, and
   the swing should be slower than 90° in 5 ticks so the trail reads as an arc.
2. **hero-v3 — the blade contract** (agreed, please confirm on your side):
   `has_own_blade() -> true`, `blade_length() -> 12.0`, socket `saber_r` on `R_Hand`, and
   `set_saber_drawn(bool)` as today. Melee then draws no blade of its own: the 12 m of steel is
   yours, the 2 m energy tip and the sheath are ours, and the hit volume is sized to the 14 m total.

*(r5's requests 3 and 4 — the `aim_system.gd:68` flood and the dying monster scaled to 0 — were
dropped in r6: the lead fixed the first in 24f0021 and this round's `--nan-watch` drive logged
`errors=0` with no non-finite report, so neither has fresh evidence.)*
