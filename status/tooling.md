# tooling status

Unit brief: `briefs/tooling.md` (tooling r1). Started 11-05. Round r1b: `reviews/tooling-r1b.md`.

## r1b — one green regression table before the next export

**The lead's command is `tools/suites.sh`.** No arguments: it runs every row in `tools/suites.txt`
sequentially (`--jobs=1`, the machine stays usable) and ends with ONE line —

```
SUITES <n> rows, <g> green, <k> known, <r> red
```

— exiting 0 only when `r = 0` and no tracked test is unlisted. `--list` runs nothing and prints the
coverage check; `--only=a,b` runs named rows; `--jobs=N` parallelises (never for a perf gate).

### r1b item 1 — the uncommitted r1 status is committed (`69a22956`)
The 63 lines were r1's own Done sections for items 4, 7, 8, 5 (rest) and the city-kit r10 add-on. Every
commit they name (`a625bae`, `451e2bd`, `93d03c7`, `2fad86f`, `ace8852`, `63db170`, `ce4c050`,
`317d03c`, `6de4500`) is in the log, so the file was committed as it stood.

### r1b item 2 — a row for every tracked test (`46c95edc`)
16 tests landed by the ten rounds since r1 had no row; `tools/suites.sh --list` now prints
`coverage: every tracked test has a row` (**89 tracked `test_*.gd`, 92 rows** — `main_spawn` ×3 and
`spawner` ×2 carry different flags). Flags are each owner's own, taken from their status file or the
suite's own header:

| row | suite | flags | why those |
|---|---|---|---|
| `core_input_quad` | `core/tests/test_input_quad.gd` | — | mine (item 8) |
| `core_pad_atom` | `core/tests/test_pad_atom.gd` | `--sandbox --god --no-enemies --timeout=300` | the suite header |
| `core_readme` | `core/tests/test_readme_controls.gd` | — | mine (item 4) |
| `fx_swarm` / `fx_skate` / `fx_boss_kill` | `fx/tests/…` | — | `status/feel.md` "How to verify" |
| `mech_death` | `player/mech/tests/test_death.gd` | `--timeout=1200` | `status/mech-move.md:248` |
| `defense_guard_capture` | `combat/defense/tests/test_guard_capture.gd` | — | `status/melee-defense.md:328` |
| `hud_title_tutorial` | `ui/tests/test_title_tutorial.gd` | `--timeout=900` | `status/hud.md:235` (the real title path, ~7 min) |
| `enemies_near_miss` | `enemies/tests/test_near_miss.gd` | `--timeout=300` | `status/enemies.md:136` |
| `enemies_spawn_safety` | `enemies/tests/test_spawn_safety.gd` | `--sandbox --no-enemies --timeout=400` | `status/enemies.md:135` |
| `flow_collapse_camera` / `flow_die_once` | `flow/tests/…` | — | `status/flow.md:50-51` |
| `hero3_flight` / `hero3_thruster` | `player/model/hero3/tests/…` | — | `status/hero-v3.md:504,539` |
| `tools_capture_clock` | `tools/tests/test_capture_clock.gd` | — | mine (item 8, camera-aim r8 Request 6) |

**The 16 new rows, run first on their own** (`tmp/tooling/r1b_new_rows_table.tsv`): **16 green, 0 red,
0 SCRIPT ERROR, 0 engine ERROR** — no flag or timeout had to be corrected.

| row | exit | checks |
|---|---|---|
| `core_input_quad` | 0 | `INPUT QUAD TEST 17 checks, 0 failures` |
| `core_pad_atom` | 0 | `PADATOM PASS: 23 checks, 0 failed, longest left-stick release 0.283 s` |
| `core_readme` | 0 | `README CONTROLS TEST 113 checks, 0 failures` |
| `fx_swarm` | 0 | `TEST feel swarm: PASS (28 checks, 0 failures)` |
| `fx_skate` | 0 | `TEST feel skate: PASS (0 failures)` — 24 checks |
| `fx_boss_kill` | 0 | `TEST feel boss_kill: PASS (0 failures)` — 3 checks |
| `mech_death` | 0 | `PASS mech-move death: 108/108 checks passed` |
| `defense_guard_capture` | 0 | `TEST 27 checks, 0 failed` |
| `hud_title_tutorial` | 0 | `TEST 6 checks, 0 failed` |
| `enemies_near_miss` | 0 | `NEAR MISS TEST 17 checks, 0 failures` |
| `enemies_spawn_safety` | 0 | `SPAWN SAFETY TEST 10 checks, 0 failures` |
| `flow_collapse_camera` | 0 | `TEST 62 checks, 0 failed` |
| `flow_die_once` | 0 | `TEST 9 checks, 0 failed` |
| `hero3_flight` | 0 | `PASS` |
| `hero3_thruster` | 0 | `PASS` |
| `tools_capture_clock` | 0 | `CAPTURE CLOCK TEST 16 checks, 0 failures` |

### r1b item 4 — the one-line wrapper (`46c95edc`)
`tools/suites.sh` ends a full run with `SUITES <n> rows, <g> green, <k> known, <r> red` and
`[ "$red" -eq 0 ] && [ "$missing" -eq 0 ]` — the old tail returned 0 **when** a row was red
(`[ "$red" -gt 0 ] || [ "$missing" != 0 ]` is true exactly when red > 0), so the runner's exit code
said the opposite of its own table. The `checks` column also now prefers any
`<n> checks, <n> failed` summary line over a trailing bare `PASS`, so `core_pad_atom` shows its 23
checks instead of the host's last word.

### r1b item 3 — the full table, `--jobs=1`, four passes
`tools/suites.sh` (no arguments), ~11 min wall each. **Passes 1, 2 and 4 are identical row for row**;
pass 3 is the same except for the audio flake below. Artifacts: `tmp/tooling/r1b_full_table_pass1.tsv`,
`…_pass3.log`, `…_pass4.log` and `tmp/tooling/r1b_full_table.tsv` (= pass 4, the tree as committed);
per-suite logs in `tmp/suites/<row>.log`. The verdict on the current tree:

```
SUITES 92 rows, 90 green, 1 known, 1 red
```

**Every red, with its owner — nothing in the table is mine:**

| row | exit | failing line | owner | verdict |
|---|---|---|---|---|
| `art_design_copy` | 1 | `FAIL res://world/city/design_layout.json was copied from a different …/data/map/city_layout.json (stamp 1567d61d, now 615d1f71) — run tools/blender.sh run blender/city/markers.py` (plus `358 buildings` vs `318`, `77 decks` vs `76`) | **city-layout** moved the layout, **city-build** owns the refresh | **RED, real defect** → Request 17. Not allow-listed: the runtime places art from the stale copy, so it must be seen before an export. |
| `art_occlusion` | 1 | `FAIL 0 design rows have no kit model (the blockout boxes)` — `OCCLUSION 69 checks, 1 failed` | **city-art** | **KNOWN-ERROR `test-occlusion-stale-premise`** — the lead's own routed red, `reviews/city-art-r16.md` item 8: the suite asserts at `test_occlusion.gd:109` that some design rows have no kit model, and since city-kit r9 all 358 stand on one, so it fails by construction. Allow-listed in `game/tools/known_issues.txt`; drop the row when that item lands. |

Two runs log an engine ERROR and still exit 0 — both are the deliberate negatives already in the
allow-list (`enemies_spawner_mix`'s `dragon`, `art`'s `huge`), and the host suppresses exactly those
two messages. **`script_err` is 0 in all 92 rows of all four passes.**

**The two flakes, measured.**

| row | result | what |
|---|---|---|
| `enemies_ai` | **green in all four passes** (`AI TEST 14 checks, 0 failures`) | the row that failed 1 of 5 runs under load in r1. At `--jobs=1` it never fired, so no re-run was needed. |
| `audio`, `audio_clocks` | **red in pass 3 only — 1 of 4 full passes; 4 of 4 green when run alone afterwards** | `FAIL the beat clock reaches the requested clip (110.0 BPM) once the wait is over` (`test_audio_clocks.gd:171`, the same check reached from both suites). Every green run prints **145.6 BPM**, which is `clip_bpm(&"boss")`; the failing one read **110.0**, i.e. the switch had not been adopted after `_settle_music()`'s 8 s of game time. **Not allow-listed** — a flake must stay visible. → Request 18 (audio). |

**The wrapper's exit code, proved on one row at a time** (`tools/suites.sh --only=<row>`):
`core_input` (green) → **0**, `art_occlusion` (known) → **0**, `art_design_copy` (red) → **1**.
The allow-list is not a blanket pass: with the expected count changed from 1 to 2 the same run prints
`RED (known list says 2 failed, this run had 1)` and exits 1.

**What the table's own tooling caught in MY code** (`0d8bb3d9`). `tools/godot.sh check` printed, after
`CHECK 829 files, 0 failed, 0 engine errors, 0 warnings`, an engine ERROR from my own autoload:
`The InputMap action "debug_toggle" doesn't exist.` at `core/input_quad.gd:55`. `InputQuad` ticks from
frame 0 and polled F3 before anything had called `InputSetup.register_actions()` (the tool hosts and
`camera_rig.gd` do; `check_all.gd` does not), and Godot logs an ERROR for every such poll. It never
showed in a suite because `test_host.gd` registers the map in `_initialize()`, before the first frame —
which is exactly why a whole-project `check` is worth running beside the table. Fixed with
`InputMap.has_action(&"debug_toggle") and …`; after the fix the same `check` prints
`CHECK 829 files, 0 failed, 0 engine errors, 0 warnings` with **no** `debug_toggle` line, and
`core_input_quad` is still `INPUT QUAD TEST 17 checks, 0 failures`, `TEST ERRORS 0`.


**The whole table** (row | exit | checks | script_err | other_err; artifact `tmp/tooling/r1b_full_table.tsv`, logs `tmp/suites/<row>.log`):

| row | exit | checks | script_err | other_err |
|---|---|---|---|---|
| `core_input` | 0 | CORE INPUT TEST 58 checks, 0 failures | 0 | 0 |
| `core_input_quad` | 0 | INPUT QUAD TEST 17 checks, 0 failures | 0 | 0 |
| `core_pad_atom` | 0 | PADATOM PASS: 23 checks, 0 failed, longest left-stick release 0.283 s | 0 | 0 |
| `core_readme` | 0 | README CONTROLS TEST 113 checks, 0 failures | 0 | 0 |
| `fx_feel` | 0 | TEST feel: PASS (0 failures) | 0 | 0 |
| `fx_clocks` | 0 | TEST feel clocks: PASS (0 failures) | 0 | 0 |
| `fx_swarm` | 0 | TEST feel swarm: PASS (28 checks, 0 failures | 0 | 0 |
| `fx_skate` | 0 | TEST feel skate: PASS (0 failures) | 0 | 0 |
| `fx_boss_kill` | 0 | TEST feel boss_kill: PASS (0 failures) | 0 | 0 |
| `mech_locomotion` | 0 | PASS mech-move locomotion: 56/56 checks passed | 0 | 0 |
| `mech_damage` | 0 | PASS mech-move damage: 33/33 checks passed | 0 | 0 |
| `mech_stepping` | 0 | PASS mech-move stepping: 17/17 checks passed | 0 | 0 |
| `mech_clocks` | 0 | PASS mech-move clocks: 9/9 checks passed | 0 | 0 |
| `mech_flight_input` | 0 | PASS mech-move flight input: 16/16 checks passed | 0 | 0 |
| `mech_death` | 0 | PASS mech-move death: 108/108 checks passed | 0 | 0 |
| `melee` | 0 | TEST 252 checks, 0 failed | 0 | 0 |
| `melee_hud_first_frame` | 0 | TEST 42 checks, 0 failed | 0 | 0 |
| `defense` | 0 | TEST 144 checks, 0 failed | 0 | 0 |
| `defense_guard_capture` | 0 | TEST 27 checks, 0 failed | 0 | 0 |
| `skills` | 0 | TEST 275 checks, 0 failed | 0 | 0 |
| `weapons` | 0 | TEST 172 checks, 0 failed | 0 | 0 |
| `weapons_feel_rows` | 0 | TEST 13 checks, 0 failed | 0 | 0 |
| `aim` | 0 | TEST PASSED (0 failures) | 0 | 0 |
| `camera` | 0 | TEST PASSED (0 failures) | 0 | 0 |
| `camera_audit` | 0 | TEST PASSED (0 failures) | 0 | 0 |
| `camera_cockpit` | 0 | TEST PASSED (0 failures) | 0 | 0 |
| `camera_feel` | 0 | TEST PASSED (0 failures) | 0 | 0 |
| `camera_flight` | 0 | TEST PASSED (0 failures) | 0 | 0 |
| `camera_flow` | 0 | TEST PASSED (0 failures) | 0 | 0 |
| `camera_large` | 0 | TEST PASSED (0 failures) | 0 | 0 |
| `hud` | 0 | TEST 371 checks, 0 failed | 0 | 0 |
| `hud_title_tutorial` | 0 | TEST 6 checks, 0 failed | 0 | 0 |
| `audio` | 0 | TEST audio: PASS (0 failures) | 0 | 0 |
| `audio_clocks` | 0 | TEST audio clocks: PASS (0 failures) | 0 | 0 |
| `audio_call_sites` | 0 | TEST audio call sites: PASS (0 failures) | 0 | 0 |
| `audio_enemies` | 0 | TEST audio enemies: PASS (0 failures) | 0 | 0 |
| `post` | 0 | POST TEST PASS (0 failures) | 0 | 0 |
| `kit_textures` | 0 | PASS 59 window masks: all FORMAT_L8 with mipmaps | 0 | 0 |
| `art_no_abs_paths` | 0 | ABS PATHS TEST PASS | 0 | 0 |
| `art_design_copy` | 1 | DESIGN COPY TEST FAIL | 0 | 0 |
| `art_roof_map` | 0 | ROOF MAP TEST PASS (0 failures) | 0 | 0 |
| `art_settle` | 0 | SETTLE TEST PASS (0 failures) | 0 | 0 |
| `art_surface_static` | 0 | SURFACE STATIC TEST PASS (0 failures) | 0 | 0 |
| `art_settle_cache` | 0 | SETTLE CACHE TEST PASS (0 failures) | 0 | 0 |
| `art_float` | 0 | FLOAT TEST PASS (0 failures, 0 floating) | 0 | 0 |
| `art` | 0 | ART TEST PASS (0 failures) | 0 | 1 |
| `art_occlusion` | 1 | OCCLUSION 69 checks, 1 failed | 0 | 0 |
| `art_shadows` | 0 | SHADOWS 13 checks, 0 failed | 0 | 0 |
| `art_sky_pano` | 0 | SKY PANO TEST PASS (0 failures) | 0 | 0 |
| `props` | 0 | PROPS TEST PASS (0 failures) | 0 | 0 |
| `city` | 0 | TEST PASS (111 checks, 0 failed | 0 | 0 |
| `enemies_status` | 0 | STATUS TEST 90 checks, 0 failures | 0 | 0 |
| `enemies_projectile` | 0 | PROJECTILE TEST 22 checks, 0 failures | 0 | 0 |
| `enemies_audit` | 0 | AUDIT TEST 25 checks, 0 failures | 0 | 0 |
| `enemies_spawner_mix` | 0 | SPAWNER TEST 9 checks, 0 failures | 0 | 1 |
| `enemies_spawner_none` | 0 | SPAWNER TEST 6 checks, 0 failures | 0 | 0 |
| `main_spawn_r6` | 0 | MAIN SPAWN TEST 6 checks, 0 failures | 0 | 0 |
| `main_spawn_none` | 0 | MAIN SPAWN TEST 2 checks, 0 failures | 0 | 0 |
| `main_spawn_stub` | 0 | MAIN SPAWN TEST 2 checks, 0 failures | 0 | 0 |
| `enemies_fight` | 0 | FIGHT TEST 13 checks, 0 failures | 0 | 0 |
| `enemies_ai` | 0 | AI TEST 14 checks, 0 failures | 0 | 0 |
| `enemies_near_miss` | 0 | NEAR MISS TEST 17 checks, 0 failures | 0 | 0 |
| `enemies_spawn_safety` | 0 | SPAWN SAFETY TEST 10 checks, 0 failures | 0 | 0 |
| `models` | 0 | TEST 722 checks, 0 failures | 0 | 0 |
| `boss` | 0 | BOSS TEST 135 checks, 0 failed | 0 | 0 |
| `boss_city` | 0 | BOSS CITY TEST 20 checks, 0 failed | 0 | 0 |
| `flow` | 0 | TEST 252 checks, 0 failed | 0 | 0 |
| `flow_idle` | 0 | TEST 8 checks, 0 failed | 0 | 0 |
| `flow_perf` | 0 | TEST 2 checks, 0 failed | 0 | 0 |
| `flow_collapse_camera` | 0 | TEST 62 checks, 0 failed | 0 | 0 |
| `flow_die_once` | 0 | TEST 9 checks, 0 failed | 0 | 0 |
| `hero3` | 0 | PASS | 0 | 0 |
| `hero3_pelvis` | 0 | PASS | 0 | 0 |
| `hero3_body` | 0 | PASS | 0 | 0 |
| `hero3_release` | 0 | PASS | 0 | 0 |
| `hero3_states` | 0 | PASS | 0 | 0 |
| `hero3_ground` | 0 | PASS | 0 | 0 |
| `hero3_aim` | 0 | PASS | 0 | 0 |
| `hero3_reach` | 0 | PASS | 0 | 0 |
| `hero3_casts` | 0 | PASS | 0 | 0 |
| `hero3_melee` | 0 | PASS | 0 | 0 |
| `hero3_fk` | 0 | PASS | 0 | 0 |
| `hero3_ik` | 0 | <no checks line> | 0 | 0 |
| `hero3_pose` | 0 | <no checks line> | 0 | 0 |
| `hero3_tree` | 0 | PASS | 0 | 0 |
| `hero3_skin` | 0 | PASS | 0 | 0 |
| `hero3_pieces` | 0 | PASS | 0 | 0 |
| `hero3_shade` | 0 | PASS | 0 | 0 |
| `hero3_drones` | 0 | PASS | 0 | 0 |
| `hero3_flight` | 0 | PASS | 0 | 0 |
| `hero3_thruster` | 0 | PASS | 0 | 0 |
| `tools_capture_clock` | 0 | CAPTURE CLOCK TEST 16 checks, 0 failures | 0 | 0 |

## Done

### >>> PAD INPUT COMMITS (conflict map A8) <<<
- **`a625bae`** — `RELOAD_HOLD` 0.4 → **0.25 s** (SPEC §3) and `test_core_input.gd` 24 → **58 checks**.
  **skills: re-run your pad cases (`suite_input`'s RB+B and L3+R3) after this commit.** `pad_input.gd`
  is tooling's from now on; input-map or PadInput needs come to tooling as Requests.

### >>> THE STRICTER TEST HOST IS LIVE AS OF COMMIT `317d03c` <<<
Every unit: **name the host commit beside your FAIL/PASS pairs from now on.** A suite that logs a
SCRIPT ERROR or an engine ERROR (`push_error` included) exits 1 whatever it printed; warnings and
Godot's exit-time leak lines do not count. Deliberate `push_error` negatives are allow-listed one by
one — **file each one as a Request to tooling the day you write it** (suite path + the exact message),
or your suite goes red. The table below was taken under the OLD host (`6de4500`); re-run your own
suite to see the new verdict.
Fixtures for the host itself: `game/tools/tests/fixture_{clean,push_error,script_error,known_error}.gd`.

### Item 4 — README.md with both control schemes (commit `451e2bd`)
`README.md` at the repo root: every SPEC §3 row for KB+M and for the pad with its tap/hold meaning, the
RB shift layer and its latch, pause (Esc / Menu), F11, first-open of the ad-hoc-signed app (Privacy &
Security › Open Anyway, or `xattr -dr com.apple.quarantine TIANSHU.app`), macOS 11+ / universal / Metal,
running from source (`tools/godot.sh play`, Godot 4.7.2, `GODOT=`), and the credits + hud r6's
开源许可 LICENCES page + `THIRD_PARTY_LICENSES.txt`. **The code is the truth** — the numbers come from
it: double-tap flight 0.30 s (`mech_input.gd:47`), reload 0.25 s (`pad_input.gd`), catch field 0.3 s
(`defense_table.gd CATCH_HOLD`), ward 0.35 s (`skill_tuning.gd`), the 4-frame L3+R3 chord, and the
Lance as a second `V` / `L3+R3` press while Overdrive runs (`skill_input.gd _overdrive_edge`).
`core/tests/test_readme_controls.gd`: **113 checks, 0 failures**; it requires every binding in
`InputSetup.KEYS/MOUSE/AXES` and `PadInput.NORMAL/SHIFTED` to sit on ONE row with the other half of its
action, and rejects invented bindings. Deleting the Undertow Well row → **2 failures**.

### Item 7 — the pad path, driven and tested (commits `a625bae`, `451e2bd`, `93d03c7`)
- **Autoplay pad steps.** `{"pad": {"button": "rb", "down": true}}` and `{"pad": {"axis": ["rt", 1.0]}}`
  go through `Input.parse_input_event`, plus `{"dpad": "right", "hold": …}` and
  `{"chord": "y", "hold": …}`. Verified with a drive (`game/tools/tests/timeline_pad.json`): the left
  stick moved the hero and RB+X spent 150 EN **through the shift layer**, `errors=0`.
- **Bindings.** `core/tests/test_core_input.gd` 24 → **58 checks, 0 failures** — one per remaining SPEC
  §3 pad row (B, X, Y, LB, LT, both sticks, R3 after the chord window, RB+Y/B/A with the latch,
  D-pad ←/→, D-pad ↓ *and* View, Menu), plus the reload timing.
- **Reload.** `RELOAD_HOLD` 0.4 → **0.25 s** (SPEC §3). Checks: no reload at 0.20 s, reload by 0.27 s,
  no `weapon_next` on release. With 0.4 restored the same suite reports **2 failures**.
- **The atom.** `core/tests/test_pad_atom.gd` + `core/tests/pad_atom.json` — the REAL `main.tscn`, ~40 s
  of combat, RAW joypad events only, one sequence **shared with the windowed drive**. 23 checks.
  **5 consecutive runs, all `PADATOM PASS: 23 checks, 0 failed, longest left-stick release 0.283 s`.**
  With `RELOAD_HOLD` back at 0.4 s: `FAIL D-pad up held 0.27 s reloads` (plus the lock pair in that run).
  Two acceptance failures fixed: targets are placed in front of the **camera** (and re-fronted on an arc
  at the lock beat — the hero turns during the opening beats, and a line of targets occludes itself),
  and the fins tap now runs 11 s before the ward instead of inside it (`fins_cd` is 10 s).

### Item 8 — the F3 input quad (commits `2fad86f`, `ace8852`)
`core/input_quad.gd` (autoload, one line in `project.godot`): a 128 px square, top-right, that flips
black↔white on the **first frame drawn** after a key, mouse-button or pad-button press. Raw `_input()`
(the one exception CONTRACTS §3 grants), never consumes input, `PROCESS_MODE_ALWAYS`, CanvasLayer 120
(above every HUD layer and the post stack), **off by default**. Presses are counted, not flagged, so
two presses in one frame flip twice. `core/tests/test_input_quad.gd`: **17 checks, 0 failures**; on
HEAD (no autoload) the same test prints `FAIL the InputQuad autoload exists`, 1 check, 1 failure.
**Two windowed frames**: `captures/tooling_quad_t2_0.jpg` (dark) and `captures/tooling_quad_t3_0.jpg`
(lit) — the quad flips above the HUD and the same Space press still jumps the mech.
The capture tool gained `--key=<name>@<t>` (a RAW key event; `Input.action_press` never reaches
`_input()`) and **one clock** for `--times`, `--pulse` and `--key` (camera-aim r8 Request 6):
`CAPTURE key F3 at t=0.52 / tooling_quad_t2_0 at t=2.02 / CAPTURE key Space at t=2.51 /
tooling_quad_t3_0 at t=3.01`, `errors=0`. `game/tools/tests/test_capture_clock.gd`: 16 checks, 0 failures.

### Item 5 (rest) — the post-export step (`package`)
`tools/godot.sh package --out=<dir>` writes the files that ship beside the .app and **runs on its own**;
`export` calls it after a successful export. Gate 6, run alone into a scratch dir:
`tmp/tooling/pkg_scratch/README.md`, byte-identical to the repo README. It says plainly that
`THIRD_PARTY_LICENSES.txt` is not written yet — hud r6 item 3 owns that writer (A6). The stale-settle
refusal in `export` is untouched.

### Lead add-on (city-kit r10) — both done
- `tools/godot.sh run <scene> <seconds>` now passes **every later argument** through as a game option.
- `game/tools/perf_probe.gd` walks **three** levels under World and through non-`Node3D` nodes: the art
  root `CityArt` is a plain `Node`, so the old Node3D-only walk stepped over it and never reached the
  props (`World/<CityArt>/Dressing`).

### Item 3, step 2 — the SAME table under the strict host (`317d03c`), and what it caught
`tools/suites.sh --jobs=3` → `tmp/tooling/suites_newhost_table.tsv`. **31 red.** Almost all of them are
other units' *live uncommitted work* in the shared tree at the moment of the run (conflict map rule G),
not regressions: at 09:0x mech-move, hero-v3, skills, flow and enemies all had dirty files.

| group | suites | cause | owner |
|---|---|---|---|
| 2 errors in every suite that loads the hero or the world | hero3 ×18, main_spawn ×3, flow_perf, skills, and part of mech_* | `hero3_glow.gdshader:56` has `return;` inside `fragment()` → `Using 'return' in the 'fragment' processor function is incorrect.` + `Shader compilation failed.` | **hero-v3** (the file is uncommitted) → Request 1 |
| `SCRIPT ERROR` ×23–207 | mech_locomotion, mech_damage, mech_stepping, mech_clocks, mech_flight_input | `Could not find type "MechDamage"` / `Identifier "MechBuild" not declared` | **mech-move** (`mech_damage.gd`, `mech_death.gd` are untracked and mid-edit) → Request 2 |
| 1 extra error | skills | `SkillRigModel: no CONTRACTS §5 socket named muzzle_l` | **skills / hero-v3** → Request 3 |
| unchanged reds | weapons_feel_rows (KNOWN), post, art_float, art_occlusion | as in the table above | weapons/feel, post-render, city-art |
| **artefact of my own run** | enemies_ai | `FAIL physics frame with 40 enemies: 21.9 ms (budget 6.0)` — measured with 3 suites in parallel. Re-run alone: **AI TEST 12 checks, 0 failures, exit 0** | mine; `suites.sh` now defaults to `--jobs=1` |

**This is the host working.** Under the old host all of those printed PASS and exited 0.

### Item 5 — the export ships the game, not the harness (commit `63db170`)
`exclude_filter` now also drops `*/tools/*`, `*/trailer/*`, `*/tmp/*`, `*/tmp_*/*`; `application/copyright`
is `© 2026 erapi0neer`. `include_filter` keeps `ui/licenses/*` **verbatim** (A5). Verified with Godot's
own `String.matchn`, through `ConfigFile` on the real preset:
`res://tools/autoplay.gd`, `res://world/city/tools/bake_nav.gd`, `res://trailer/boss_shot.gd`,
`res://tmp/tooling/x.png`, `res://tmp_probe/x.gd` and `res://world/art/tests/test_art.gd` are all
excluded; `res://world/art/detail/arena_probes.gd`, `res://core/pad_input.gd` and `res://ui/hud.gd` are
not. The copyright round-trips as `© 2026 erapi0neer`; bundle id `xyz.erapi0neer.tianshu`; no icon.
Nothing at runtime loads the excluded paths (see the commit message). `tools/pck_list.py` promoted from
the acceptance harness. **Before** numbers from today's `build/TIANSHU.app` (PCK v4, 3,631 files):
19 × `tools/`, 17 × `world/city/tools/`, 0 × `trailer/`, 0 × `tmp*`, 0 × `tests/`; `arena_probes.*`
present. The **after** numbers need the lead's export (I never run `tools/godot.sh export`).

### Item 6 — hygiene (commits `<pyc>`, `ce4c050`)
- `git ls-files '*.pyc'` → **0** (the two `tools/tripo/__pycache__` files, own commit; they stay on disk).
- `python3 tools/owners.py` → **5,008 tracked files, 20 units, 0 uncovered, 0 ambiguous.**
- `python3 tools/scrub_check.py --mine` → **0 hits** in tooling's files; 211 in eight other units
  (Requests 4–11). The one deliberate exception is `tools/slots.py`'s machine-wide slot pool, recorded
  with its reason inside the checker. `tools/concept/ys.py` now reads `YS_API_BASE` and fails with a
  readable message when unset.

### Item 3, step 1 — the suite table under TODAY's host (committed BEFORE the host changes)
`tools/suites.sh` + `tools/suites.txt` (75 runs over the 72 tracked `test_*.gd`; `main_spawn` ×3 and
`spawner` ×2 carry different flags). Coverage check: **every tracked test has a row**, 0 unlisted.
Run: `tools/suites.sh --jobs=3` → `tmp/tooling/suites_head_table.tsv`, logs in `tmp/suites/<name>.log`.
Host at this point: **`test_host.gd` as of `6de4500`** — errors are counted but never fail a run.

| suite | exit | checks | script_err | other_err |
|---|---|---|---|---|
| core_input | 0 | CORE INPUT TEST 24 checks, 0 failures | 0 | 0 |
| fx_feel | 0 | TEST feel: PASS (0 failures) | 0 | 0 |
| fx_clocks | 0 | TEST feel clocks: PASS (0 failures) | 0 | 0 |
| mech_locomotion | 0 | PASS mech-move locomotion: 56/56 | 0 | 0 |
| mech_damage | 0 | PASS mech-move damage: 21/21 | 0 | 0 |
| mech_stepping | 0 | PASS mech-move stepping: 17/17 | 0 | 0 |
| mech_clocks | 0 | PASS mech-move clocks: 9/9 | 0 | 0 |
| mech_flight_input | 0 | PASS mech-move flight input: 16/16 | 0 | 0 |
| melee | 0 | TEST 252 checks, 0 failed | 0 | 0 |
| melee_hud_first_frame | 0 | TEST 42 checks, 0 failed | 0 | 0 |
| defense | 0 | TEST 90 checks, 0 failed | 0 | 0 |
| skills | 0 | TEST 188 checks, 0 failed | 0 | 0 |
| weapons | 0 | TEST 148 checks, 0 failed | 0 | 0 |
| **weapons_feel_rows** | **1** | **TEST 13 checks, 9 failed** | 0 | 0 |
| aim | 0 | TEST PASSED (0 failures) | 0 | 0 |
| camera | 0 | TEST PASSED (0 failures) | 0 | 0 |
| camera_audit | 0 | TEST PASSED (0 failures) | 0 | 0 |
| camera_cockpit | 0 | TEST PASSED (0 failures) | 0 | 0 |
| camera_feel | 0 | TEST PASSED (0 failures) | 0 | 0 |
| camera_flight | 0 | TEST PASSED (0 failures) | 0 | 0 |
| camera_flow | 0 | TEST PASSED (0 failures) | 0 | 0 |
| camera_large | 0 | TEST PASSED (0 failures) | 0 | 0 |
| **hud** | 0 | TEST 217 checks, 0 failed | 0 | **2** |
| audio | 0 | TEST audio: PASS (0 failures) | 0 | 0 |
| audio_clocks | 0 | TEST audio clocks: PASS (0 failures) | 0 | 0 |
| audio_call_sites | 0 | TEST audio call sites: PASS (0 failures) | 0 | 0 |
| audio_enemies | 0 | TEST audio enemies: PASS (0 failures) | 0 | 0 |
| **post** | **1** | **POST TEST FAIL (3 failures)** | 0 | 0 |
| kit_textures | 0 | PASS 59 window masks | 0 | 0 |
| art_no_abs_paths | 0 | ABS PATHS TEST PASS | 0 | 0 |
| art_design_copy | 0 | DESIGN COPY TEST PASS | 0 | 0 |
| art_roof_map | 0 | ROOF MAP TEST PASS (0 failures) | 0 | 0 |
| art_settle | 0 | SETTLE TEST PASS (0 failures) | 0 | 0 |
| art_settle_cache | 0 | SETTLE CACHE TEST PASS (0 failures) | 0 | 0 |
| **art_float** | **1** | **FLOAT TEST FAIL (1 failures, 1 floating)** | 0 | 0 |
| **art** | 0 | ART TEST PASS (0 failures) | 0 | **1** |
| **art_occlusion** | **1** | **OCCLUSION 69 checks, 1 failed** | 0 | 0 |
| art_shadows | 0 | SHADOWS 13 checks, 0 failed | 0 | 0 |
| art_sky_pano | 0 | SKY PANO TEST PASS (0 failures) | 0 | 0 |
| props | 0 | PROPS TEST PASS (0 failures) | 0 | 0 |
| city | 0 | TEST PASS (111 checks, 0 failed) | 0 | 0 |
| enemies_status | 0 | STATUS TEST 90 checks, 0 failures | 0 | 0 |
| enemies_projectile | 0 | PROJECTILE TEST 22 checks, 0 failures | 0 | 0 |
| enemies_audit | 0 | AUDIT TEST 25 checks, 0 failures | 0 | 0 |
| **enemies_spawner_mix** | 0 | SPAWNER TEST 9 checks, 0 failures | 0 | **1** |
| enemies_spawner_none | 0 | SPAWNER TEST 6 checks, 0 failures | 0 | 0 |
| main_spawn_r6 | 0 | MAIN SPAWN TEST 6 checks, 0 failures | 0 | 0 |
| main_spawn_none | 0 | MAIN SPAWN TEST 2 checks, 0 failures | 0 | 0 |
| main_spawn_stub | 0 | MAIN SPAWN TEST 2 checks, 0 failures | 0 | 0 |
| enemies_fight | 0 | FIGHT TEST 13 checks, 0 failures | 0 | 0 |
| enemies_ai | 0 | AI TEST 12 checks, 0 failures | 0 | 0 |
| models | 0 | TEST 722 checks, 0 failures | 0 | 0 |
| boss | 0 | BOSS TEST 135 checks, 0 failed | 0 | 0 |
| boss_city | 0 | BOSS CITY TEST 20 checks, 0 failed | 0 | 0 |
| flow | 0 | TEST 240 checks, 0 failed | 0 | 0 |
| flow_idle | 0 | TEST 8 checks, 0 failed | 0 | 0 |
| flow_perf | 0 | TEST 2 checks, 0 failed | 0 | 0 |
| hero3 (×18: base, pelvis, body, release, states, ground, aim, reach, casts, melee, fk, ik, pose, tree, skin, pieces, shade, drones) | 0 | PASS | 0 | 0 |

**Every red, with its owner** (nothing here is mine):
| suite | owner | what |
|---|---|---|
| `weapons_feel_rows` | weapons → feel r5 | 9/13: `gatling_jam`, `gatling_vent_good`, `gatling_overheat` are not FEEL.md rows and have no `.tres` (lead add-on: KNOWN, tag `gatling-vent-good-unknown-feel-id`) |
| `post` | post-render | `FAIL low/medium/high exposure is 0.72` ×3 |
| `art_float` | city-art | 1 instance floats 0.8 m (`prop:antenna_array`) — already in `status/city-art.md` Known issues |
| `art_occlusion` | city-art | `FAIL 0 design rows have no kit model (the blockout boxes)` |

**The three exit-0 runs that log engine ERRORs** — these are what the stricter host must catch, and all
three are accounted for:
| suite | exact message | verdict |
|---|---|---|
| `enemies_spawner_mix` | `EnemySpawner: unknown enemy type 'dragon'` | deliberate negative → allow-list |
| `art` | `InfectionField: cannot register 'huge', only 4 hive slots exist` | deliberate negative → allow-list |
| `hud` | `Attempted to use 'has' an invalid (previously freed?) object instance into a 'TypedArray'.` + `Condition "!_p->typed.validate(value, "use 'has'")" is true. Returning: false` | hud r6 item 6, routed red → allow-list, removed when it lands |

`script_err` is **0 in every run**: melee-defense r6's Nil pair (7cf4abe) is fixed, as the brief said.
`hero3_ik` and `hero3_pose` print no PASS/checks line — they are hero-v3's diagnostic dumps, not
assertion suites; they exit 0 and log nothing.

### Item 1 — tools drive their own checkout; `--timeout=` reaches the slot (commit `6de4500`)
`godot_import.sh`, `blender.sh`, `tools/city/*.sh` and the ROOT one-liners in `tools/citykit/*` now take
ROOT from the script's own path; the import stamp follows it (the flock slots stay machine-wide —
`slots.py SLOT_DIR` — because a moved pool lets two imports of one tree overlap). `godot_import.sh`
logs `[import] project <PROJ>`. `tools/godot.sh` takes `--timeout=<s>` on **every** subcommand and hands
it to the slot; `test` passes it to the host as well and gives the slot `<s>+60`. `GODOT=`/`BLENDER=`
override the binaries. Preamble (`tools/workers/preamble.md`) has the `--timeout=` line. flow r5 is
unblocked.

## In progress / next

**r1b is done** (items 1–4, all three gates). What is left from r1 and r1b:

1. **`art_design_copy` is the one standing red** — Request 17. It is a one-command refresh owned by
   city-build; the moment it lands, `tools/suites.sh` should print
   `SUITES 92 rows, 91 green, 1 known, 0 red`.
2. **`audio` / `audio_clocks` flake** — Request 18, 1 of 4 passes. Until audio explains it, a table run
   can come back `88 green … 3 red` instead of `90 green … 1 red`; re-run those two rows alone to tell
   a flake from a regression (`tools/suites.sh --only=audio,audio_clocks`).
3. **The `art_occlusion` allow-list row** comes out when `reviews/city-art-r16.md` item 8 lands.
4. **Re-run the table before every export.** New tests land every round; `tools/suites.sh --list`
   says so the moment one has no row.

### GATE8 READY — asking the lead for a window (conflict map A4)
Item 2's covered arms need the machine to itself: a full-screen movie over the screen, and Stage
Manager with another app in front, cover **every** worker's window and stall them at 0 % CPU — the very
defect under test. I will not run either until the lead announces a window with no other windowed run
live. **Please announce one.** Until then I measure with a probe that hides only *my own* Godot process
(`System Events … set visible of process <my pid> to false`), which covers nobody else's window; say if
even that is too much and I will defer it too.

### Order of work (conflict map A1–A10 applied) — r1, all done
1. Item 3's **suite table** committed in this status BEFORE the stricter `test_host.gd` is copied in
   (A1). The host itself is built and tested in the scratch worktree `tmp/tooling/wt` first.
2. Item 5 (export preset) → then `tools/sfx/credits_check.py` + hud's include-filter check (A5).
3. Item 6 (hygiene), item 4 (README), item 7 (pad), item 8 (quad).
4. `blender/lib` ROOT lines: **separate commit**, proven with `tools/blender.sh preview` from the main
   tree *and* the worktree (A10).
5. `capture.gd` / `autoplay.gd` are built in the scratch worktree and `mv`'d in; new steps additive;
   `--times` stays relative to world-ready and `--pulse` moves onto that clock (A2).
6. Re-scan `game/**/tests/test_*.gd` immediately before the final table (A3).

### Lead add-ons
- (after items 1-2, city-kit r10) `game/tools/perf_probe.gd` never reports the props (two levels under
  World) — put them in the per-subsystem table; `tools/godot.sh run <scene> <seconds>` drops every
  argument after those two — pass them through. Gate both with a one-line run each, shown here.
- (item 3 KNOWN list) weapons r5's `combat/weapons/tests/test_feel_rows.gd` fails 9/13 on purpose until
  feel r5 lands three gatling-vent FEEL rows. Allow-list with tag `gatling-vent-good-unknown-feel-id`;
  drop it when `status/feel.md` reports the rows landed.

## How to verify (exact commands)

```bash
# r1b — the lead's one command before an export (headless, ~11 min, --jobs=1 by default)
tools/suites.sh --list        # coverage: every tracked test has a row   (0 UNLISTED)
tools/suites.sh               # … and ends: SUITES 92 rows, 90 green, 1 known, 1 red   (exit 1)
tools/suites.sh --only=art_design_copy    # the one red, on its own
```

## Evidence (paths, numbers)

### r1b
- `tools/suites.sh --list` → `coverage: every tracked test has a row`; **89 tracked `test_*.gd`,
  92 rows**, 0 UNLISTED (16 rows added this round).
- The 16 new rows alone: `tmp/tooling/r1b_new_rows_table.tsv` — `SUITES 16 rows, 16 green, 0 known,
  0 red`, no flag or timeout needed correcting.
- The full table: `tmp/tooling/r1b_full_table_pass1.tsv`, `tmp/tooling/r1b_full_table_pass3.log` and
  `tmp/tooling/r1b_full_table.tsv` (= pass 4, the committed tree) — passes 1, 2 and 4 **identical row
  for row**, ~11 min wall each, per-suite logs `tmp/suites/<row>.log`. Pass 3 differs only in the two
  audio rows (Request 18).
- Exit codes: green → 0, known → 0, red → 1 (`--only=core_input` / `--only=art_occlusion` /
  `--only=art_design_copy`). The allow-list refuses a wrong count: expected 2 vs an actual 1 →
  `RED (known list says 2 failed, this run had 1)`, exit 1.
- `tools/godot.sh check` → `CHECK 829 files, 0 failed, 0 engine errors, 0 warnings`, and no
  `debug_toggle` ERROR line (it was there before `0d8bb3d9` — `tmp/tooling/r1b_check.log` has the
  before, the re-run after the fix has none). `core_input_quad` re-run after the fix:
  `INPUT QUAD TEST 17 checks, 0 failures`, `TEST ERRORS 0`.

### Item 1
**Gate 1** — `git grep -nE` over `tools` for the three hard-coded repo-root shapes (an absolute `$HOME`
root, an `expanduser("~/m/…")` root and a bare `cd ~/m/…`) now lists exactly four lines:
`citykit/props_swap.sh:8` (city-kit's new untracked file → Requests), `slots.py:19` (the machine-wide
slot dir, deliberately kept), `tripo/cdp.py:35` and `workers/lead-watch.sh:4` (the lead's).

**Gate 2** — scratch worktree `tmp/tooling/wt` at `6de4500` with the live cache cloned in
(`cp -c -R game/.godot`, 1.3 GB in 0.7 s), a fresh `game/tmp/tooling/x.png` in the worktree only:
- `tmp/tooling/wt/tmp/last_import.log` line 1: `[import] project <the worktree>/game` (the worktree's own
  path, not the live tree's)
- `tmp/tooling/wt/jobs/.slots/import.stamp` written; `tmp/tooling/wt/game/tmp/tooling/x.png.import` created.
- Live tree untouched: `jobs/.slots/import.stamp` mtime `Nov 5 08:46:34` before **and** after, and
  `game/.godot/imported` mtime `Nov 5 08:46:37` before and after.
- `tools/blender.sh preview game/world/kit/b01/b01_far.glb t --views front34 --light studio` (run from the
  worktree) wrote `tmp/tooling/wt/captures/blender/t_studio{,_front34}.jpg`; the live
  `captures/blender/` gained no `t_*` file.
- **Before the fix** (same worktree at `10e8499`, i.e. HEAD's hard-coded ROOT): the run imported the LIVE
  tree — the live stamp moved `08:46:07 → 08:46:34`, `game/.godot/imported` was touched, the worktree got
  no stamp and `x.png` got no `.import`.

**Gate 3** — 60 s fixture `game/tools/tests/timeline_60s.json`, `tools/godot.sh drive --sandbox`:
- `--timeout=30` → `[slots] TIMEOUT after 30 s, killing: …` (exit 124, wall 30.3 s).
- `--timeout=300` → `DRIVE done t=60.0 errors=0 warnings=6`, all three `--shots=3,20,40` written, wall 68 s.
  Captures: `captures/tooling_gate3_to300_t{3_0,20_0,40_0}.jpg`.

## Known issues

## Requests (to the lead / other units)

**From the r1b table (11-06) — the only red in 92 rows, and it is a real defect:**
17. **(city-build, caused by city-layout)** `art_design_copy` is **RED**:
    ```
    FAIL res://world/city/design_layout.json has 358 `buildings` rows, data/map/city_layout.json has 318
    FAIL res://world/city/design_layout.json has 77 `decks` rows, data/map/city_layout.json has 76
    FAIL res://world/city/design_layout.json was copied from a different data/map/city_layout.json
         (stamp 1567d61d, now 615d1f71) — run tools/blender.sh run blender/city/markers.py
    ```
    `437e0b96` (city-layout r8, 11-05) rewrote `data/map/city_layout.json` (md5 `1567d61d` →
    `615d1f71`, 16,448 insertions) and nobody refreshed the `res://` copy the runtime actually reads —
    `world/art/repo_path.gd` places art from it, so the dressing is being placed on a layout that is
    40 buildings and 1 deck behind the city geometry. The refresh is
    **`tools/blender.sh run blender/city/markers.py`** (city-build's script, city-build's output file
    `game/world/city/design_layout.json`); tooling does not touch either. I did **not** allow-list it:
    it should be red until it is refreshed. After it lands, `tools/suites.sh` should read
    `SUITES 92 rows, 91 green, 1 known, 0 red`.
18. **(audio)** `audio` and `audio_clocks` fail **1 of 4 full table passes** on the same check and pass
    4 of 4 when run alone afterwards:
    ```
    FAIL the beat clock reaches the requested clip (110.0 BPM) once the wait is over
      test_audio_clocks.gd:171, in _metronome_follows_stream()
    ```
    Every green run prints **145.6 BPM** (`clip_bpm(&"boss")`); the failing one read **110.0**, so
    after `_settle_music()`'s 8 s of game time `music.playing_clip` was still not `&"boss"` (or the
    clock had not adopted it). `music_director.gd:230` adopts the pending clip once
    `AudioClock.since(_pending_since) > _switch_timeout_s(clip)` = 2 bars × 60/145.6 + 2 ≈ **5.3 s**,
    and `AudioClock` is `Feel.real_now()` — an idle-frame accumulator clamped at 0.1 s per frame
    (`core/feel.gd:209`). So either the 8 s wait and the 5.3 s timeout are measured on clocks that can
    drift apart under load, or `Feel._process` is not ticking every frame in this suite. I did not
    allow-list it: it is a flake, and a flake must stay red until it is understood. Both rows are
    otherwise green with `TEST ERRORS 0`, `script_err 0`.

**From the strict host (`317d03c`), r1 — ALL THREE ARE FIXED, kept here as the record:**
1. **(hero-v3) FIXED** (`93ccb69d`, hero-v3 r8) `game/player/model/hero3/hero3_glow.gdshader:56` has `return;` inside `fragment()`.
   Godot logs `Using 'return' in the 'fragment' processor function is incorrect.` followed by
   `Shader compilation failed.` It fires in **every** suite that loads the hero or the world — all 18
   hero3 suites, `main_spawn` ×3, `flow_perf`, `skills` — so it is the single biggest source of red in
   the table. The file is uncommitted in the shared tree at the time of writing.
2. **(mech-move) FIXED** (`c0ee30ed`/`394bd7da`, mech-move r7/r7b) `Could not find type "MechDamage"` and `Identifier "MechBuild" not declared` —
   23–207 `SCRIPT ERROR`s per suite in `test_locomotion`, `test_damage`, `test_stepping`, `test_clocks`
   and `test_flight_input`. `game/player/mech/mech_damage.gd` and `mech_death.gd` are untracked and
   mid-edit; the `class_name` is not registered yet.
3. **(skills / hero-v3) FIXED** (`4ea1aa22`, skills r4) `SkillRigModel: no CONTRACTS §5 socket named muzzle_l` in `test_skills`
   (which otherwise passes 270 checks). CONTRACTS §5 lists `muzzle_r`; either the rig model asks for
   the wrong name or the socket is missing.

**From the scrub (`python3 tools/scrub_check.py`, full list in `tmp/tooling/scrub_report.txt`):**
4. **(audio)** 1 hit — `tools/sfx/voice.py:28` hard-codes the internal ys-api endpoint. It needs the
   same treatment as `tools/concept/ys.py`: an env var plus a readable error when unset.
5. **(lead)** 86 hits, including `blender/lib/common.py:4,16` and `blender/lib/export.py:9,17,39`
   (shared by every Blender unit — tooling r1 fixes these in a **separate** commit per A10), the
   `xaminim` endpoint in `briefs/audio.md:28` and `ref/research/audio-music.md:688`, and
   `/Users/<name>` in `reviews/`, `ref/` and `briefs/`.
6. **(city-kit)** 47 hits, all `~/m/mecha-city` roots under `blender/citykit/**`. Also
   `tools/citykit/props_swap.sh:8` still hard-codes `ROOT="$HOME/m/mecha-city"` — it is city-kit's new
   file, so Gate 1 lists it and tooling does not touch it.
7. **(monster-assets)** 33 hits under `blender/monsters/**`.
8. **(hero-v3)** 30 hits under `blender/hero3/**`.
9. **(city-build)** 7 hits, e.g. `blender/city/layout.py:7`, `blender/city/build_city.py:19`.
10. **(city-art)** 6 hits, e.g. `blender/props/inspect_prop.py:8,14`.
11. **(boss)** 1 hit — `game/enemies/boss/tests/boss_showcase.gd:6`.

**Other:**
12. **(hud)** `ui/licenses/*` is kept verbatim in `include_filter` and `tools/sfx/credits_check.py`
    still passes after my preset commit (`problems: none`, 300 files). Your include-filter check does
    not exist yet, so I could not run it (A5) — ping me when it lands and I will re-run both.
13. **(hud)** Your licence writer (A6): post the exact invocation and I will wire it into
    `tools/godot.sh export` as a post-export step. The stale-settle refusal at `godot.sh:112-115` stays.
14. **(hud)** The CONTROLS page (`ui/menus/menu_root.gd:38`) still lacks double-tap flight, the Lance,
    pause and F11 — noted here as the brief asks; the README (item 4) will carry all of them.
15. **(lead)** Gate 8 needs a window — see "GATE8 READY" above.
16. **(camera-aim)** When `--pulse` moves onto the world-ready clock (A2), only your pulse lines shift
    by about 1.1 s; I will confirm the exact number in this status when the change lands.
