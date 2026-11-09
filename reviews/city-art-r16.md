# city-art r16 — lead brief: warm light back, a clean frame, a settle bake any checkout can trust

## Why
r15 is accepted as a step (`reviews/r15-acceptance.md`): the sky has structure, and the shade is cool and off black.
But the frame swung cool, so golden hour reads as an overcast evening, and a diagonal hatch runs across every frame.
A player sees those first. The acceptance pass adds four more: a settle bake every clean clone reads as stale, the
659-line `material_library.gd`, two stale suites and a floating antenna. Items 5–9 come from the findings in
`~/m/mc-lead/accept/findings_all.json` (ids per item), made on the frozen copy `b5d26d4`. HEAD `a1c5bdc` has not
touched the files behind 5, 8 and 9 (`git diff --stat b5d26d4 HEAD -- game/world/art/settle{,_cache.json}
game/world/kit game/world/city game/world/art/occlusion.gd` is empty). Re-check each on HEAD first; if fixed, show it.

## 1. Golden hour must stay golden — major (lead review)
- **Defect.** r15 swung the frame cool. `captures/sheets/art_r15_V1.jpg` has a blue-grey overcast sky; the key art
  (`art/concept/keyart/v1_pier-1.png`) has a warm gold one, with sunlit cloud edges. `gate.json` meets `skylo_hue`
  65–85 on 1 of 13 frames at tod 0 (33–66) and on 0 of 14 at 0.5 (3–64), and `lit_hue` 45–75 on 4 of 17 at 0.5.
- **Done.** Keep the cool shadows and the readable toe; make the horizon band, the sunlit cloud undersides and edges
  and the sunlit faces warm gold again. Pointers, not the fix: cloud warmth held to ~25° of the sun over a violet-grey
  body (`mc_sky.gdshader:20`, `:143-145`); `SKY_MID` #8a7a86 (`art_palette.gd:20`) vs ART.md §2's warm #B8A49C; the
  ramp done by ~17° (`mc_sky.gdshader:90-91`); a red horizon at 0.5 (`time_of_day.gd:191`, `:199-202`). Pick inputs
  by where the tonemap probe says they land. "Looks wrong in look-dev" (r15 §5.1) and V1's bearing are no stop rule.
- **Gate.** The colour table against `r15f2` (`cams_r15.json`, 18 cameras, tod 0/0.5/0.6/1.0, tag `r16`): `skylo_hue`
  and `lit_hue` met at tod 0 and 0.5 on every frame with the band; a miss needs a cause, and V1–V3 may not miss;
  `skylo_chroma`/`lit_chroma` lose no frame; no frame that met `shd_chroma`, `db`, `shd_p50` or `clip` misses it.

## 2. A diagonal hatch runs across the whole frame — major (lead review)
- **Defect.** A fine diagonal stripe covers sky and buildings (`art_r15_S02city.jpg`, the sky of `art_r15_V8.jpg`).
  Lead's quick read, a pointer only: a 512² sky FFT of `tmp/city-art/r15/frames/` peaks at ≈ 17.3 px, stripes ≈ 28°
  below horizontal; the same on S02city and V8, as strong in the bare-sky (B) and sun-off (C) frames, so screen-locked;
  already in the r14 baseline (`r15_p06_*`); 3×–700× the median from run to run, so test animated sources first.
- **Suspects**, one A/B each: the lens grain (`world/post/effects/post_lens.gd:32,71`, a `fract(sin(·)·43758)` hash
  of pixel coordinates in the thousands, plus time); MetalFX temporal at high's 0.60 (`quality.gd:34`, `:157-168`),
  against `--render-scale=1` (native + TAA); TAA; engine debanding (`project.godot`: ask); `--no-post`; the sky probe.
- **Done / gate.** Name the source, then remove it, or keep it intentional and subtle with a reason. Measure stripe
  energy as a `values.py` number, over ≥ 5 captures per arm and a `drive` still. Show the A/B table and
  `art_r16_hatch_{S02city,V8}.jpg` (1:1 crops of one sky region, r15 | r16). Shipping matches the source-off arm.

## 3. The HDRI plates ship at blend 0 — minor (lead review)
- **Defect.** The dome won r15's A/B, so `sky/index.json` ships `"blend": 0.0`. Yet git tracks two 4k plates,
  `kloppenheim_06` and `belfast_sunset` (34 MB), and the export packs them. `SkyPano`, the `pano*` uniforms and branch
  (`mc_sky.gdshader:35-47`, `:155`), `--pano` / `--pano-blend` and `test_sky_pano.gd` serve a branch that never runs.
- **Done / gate.** Re-A/B after item 1. Either use the plates where they win (e.g. the cloud field for the warm edges),
  at a blend a sheet, the table and a budget arm justify; or delete files, manifest, README, code, flags and test in one
  commit, after which `git grep -n -i pano -- game/world/art ':!*/probe_cams.gd'` prints nothing.

## 4. The `--tod=1.0` emissive budget is still over — major (r14 §7, lead review)
- **Defect.** Six of r15's seven clip-gate failures are at tod 1.0, the boss's time. Against the 1.5 % gate: A3st
  11.95 %, V7 7.61, V8 6.42, S04fight 3.40, V4 2.67, T1fac 1.90. All five frames r14 measured got worse (A3st from
  11.36, V7 from 6.70). Every source r15 names is yours: the storm crown and its strike (`storm_crown.gd`,
  `time_of_day.gd:151-168`), the Spire tether (`world/props/prop_scatter.gd:189-197`, its emission `:260`), and the neon.
- **Done.** Attribute each frame's clipped pixels by source, one `--value-hide=` arm each. Make the strike
  deterministic (none, then one at its peak), so a random flash does not set the number. Then reach ≤ 1.5 % per frame,
  or justify the rest per source with numbers (v8_crown itself clips 7.99 %, r15 §1). Per
  `reviews/r16-lead-decisions.md`: sky, facades and decks stay ≤ 1.5 % at every tod; at tod 1.0 only true emitters (the
  strike at its peak, the tether, the neon) may clip up to ~8 %, attributed per source. A3st's sign is a white field:
  11.95 % is never acceptable.
- **Gate.** The tod 1.0 clip table, one column per source, r15 | r16. S04fight at tod 0 (2.15 %) gets the same.

## 5. The settle stamp hashes file times, so no fresh checkout exports — packaging blocker, minor for players
- **Defect** (`pkg-settle-cache-mtime-stamp` + `settle-cache-mtime-false-stale`). `SettleCache._stamp_dir`
  (`world/art/settle/cache.gd:60-69`) hashes each glb as path:size:mtime (`:66-67`); git keeps no mtimes. In the
  byte-identical acceptance worktree the stamp is `9274b4e8` against the baked `98dd44ec`: `test_settle_cache` FAILs
  (your r14 status says PASS), `load()` returns null, every boot recomputes with a warning (`city_art.gd:172-180`,
  +1.5 s headless), and `export` refuses (`tools/godot.sh:112-115`). Template builds skip the check (`cache.gd:87`).
- **Done.** The committed stamp depends on content only; keep the export refusal. The glbs are 318 MB (tiles 53, kit
  265), not the comments' "400 + 300 MB" (`cache.gd:10-11`, `:58-59`); `get_md5` over all of them took 0.8 s; the
  import cache's `source_md5` (`.godot/imported/<glb>-<hash>.md5`) matches for 229 of 229. A (path, size, mtime) memo
  may live in `.godot/` or `user://`, never in git. Not the JSON chunk alone: a BIN edit would read fresh.
- **Gate.** (1) `test_settle_cache` PASSes in the main tree, with the fingerprint's load cost in ms. (2) In `git
  worktree add --detach ~/m/mc-r16-wt <final>`, run godot directly (`tools/godot_import.sh:7` imports the main tree),
  from the main tree with the paths spelled out: `python3 tools/slots.py import 1 --timeout 2400 --
  /opt/homebrew/bin/godot --headless --path ~/m/mc-r16-wt/game --import`, then `python3 tools/slots.py light 5 --
  /opt/homebrew/bin/godot --headless --fixed-fps 120 --path ~/m/mc-r16-wt/game -s res://tools/test_host.gd --
  --test=res://world/art/tests/test_settle_cache.gd --quality=high` PASSes with no re-bake (at HEAD it FAILs: the
  repro); as `test_float.gd` it logs `ART settle replaying`, no "missing or stale". Remove the worktree. (3) A new
  check on scratch copies of a tile and a kit glb (never tracked files): the same bytes rewritten (new mtime) keep the
  per-file stamp, which FAILs on today's rule; one flipped byte in the BIN chunk changes it.

## 6. Split `material_library.gd` first — minor (`hygiene-split-rule-material-library`)
- **Defect.** It is 659 lines at HEAD: r14 took it 599 → 632 and r15 → 659, editing instead of splitting. It is the
  only source file over 600, with 39 functions; only `SURFACES` (`:30-53`) and `GLOBALS` (`:93-102`) are data.
- **Done.** Split it along its seams in its own commit, before any other edit, with identical behaviour: e.g. the
  pushes and their state (`set_facade_mask` … `registered`, `:225-332`; the state `:55-87`) apart from the builders
  (`_build` … `apply_skyline`, `:431-659`). Keep `McMaterials`' API: `world/kit/kit_placer.gd:424` calls `kit()` and
  `world/city*` relies on `apply_to()` and the role names; none of them is yours.
- **Gate.** The commit touches only `material_library.gd` and new files, each under 400 lines; `check
  --only=res://world/art/` is clean; `test_art` PASSes; the boot line from `city_art.gd:86` is unchanged.

## 7. Fold the post rows back; `test_post` checks what ships — minor (`test-post-exposure-stale`)
- **Defect.** `world/post/tests/test_post.gd:48` pins `exposure` at 0.72, but the presets read 0.66 since r15
  (`post_presets.gd:22,34,43`; 0.56 at r14): `POST TEST FAIL (3 failures)`. `_check_grade` (`:64-89`) runs the cube at
  contrast 1.32 / saturation 1.06, post-render's first row, not the shipped 1.06 / 1.10 at pivot 0.42
  (`post_grade.gd:40`). `status/post-render.md` (`:104`, `:159-161`) and the `post_presets.gd` header are stale.
- **Done.** The rows live in `world/post` with their r14/r15 reasons. The test reads the shipped rows (pinned, with a
  rationale, never a looser check) and asserts the grade's properties at the shipped contrast, saturation and pivot;
  report any that fail. A new check keeps a lifted black off zero, and FAILs at r14's pivot 0.52 / contrast 1.22. If
  item 1 moves a row, the test and both docs move in the same commit.
- **Gate.** `test_post.gd` prints `POST TEST PASS`, and status shows the new toe check failing at r14's pair.

## 8. `test_occlusion` fails by construction, and one core is infinitely tall — minor (`test-occlusion-stale-premise`)
- **Defect.** `test_occlusion.gd:109` wants `stacked > 0` (design rows with no kit model). Since city-kit r9 all 358
  stand on one: `OCCLUSION 69 checks, 1 failed`. The same run prints `tallest inf m`. `KitRoofMap._core_blocks` seeds
  each block at INF (`settle/roof_map.gd:161`) and lowers it only when a map cell lands inside (`:186-189`); `top -
  base < min_h` (`:193`) is false for INF, so the block ships, and `CityOcclusion` builds its box to y = INF
  (`occlusion.gd:69-70`, `:217-218`). The winding check misses it, as a NaN volume is not `<= 0` (test `:48`).
- **Done.** (1) Replace the premise with the property at `:98`, that a covered row is never also a blockout box,
  checked on what the builder emits plus a synthetic uncovered row, as `_decks` does. (2) Say what the INF block is,
  whether it shipped as an occluder, and what it hid now that flight lifts the camera; fix it; assert finite cores.
- **Gate.** `test_occlusion.gd` prints `0 failed` and a finite `tallest`, and the finite-core assert FAILs on HEAD.

## 9. One antenna floats 0.8 m — minor (`float-antenna-array`)
- **Defect.** `test_float` fails on `prop:antenna_array` at (−128.9, 11.7, −10.6), 0.8 m above its roof, on both the
  recompute path and the replayed bake, so it ships. r13 traced it (status r13 Known issues): since city-kit r9 the
  roof map there sits 0.8 m above the shipped mesh, inside `VERIFY_M` 1.0 (`settle/settle.gd:50`, `:188-203`).
- **Done.** The antenna stands on its roof, or is dropped with a logged reason, by a rule that would catch the next one
  too. `FLOAT_GATE` 0.5 and `VERIFY_M` stay; r13 found that 0.45 m overrules the map on ~10 % of units. A wrong map
  cell goes to city-kit in Requests (model, cell, offset); the gate stays yours.
- **Gate.** One re-bake, after item 5 (`SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600`), prints
  `FLOAT 0 instances floating more than 0.5 m`. Then `test_float.gd` logs `ART settle replaying` and `FLOAT TEST PASS`.

## Gates
- `tools/godot.sh check --only=res://world/art/,res://world/props/,res://world/post/`: 0 failed, 0 errors. Every
  `test_*.gd` in `world/art/tests/` and `world/props/tests/`, and `test_post.gd`, PASSes under `tools/godot.sh test`.
  Each new check FAILs on HEAD and PASSes on yours (both summaries in status); nothing is "fixed" without the re-run.
- The probe: re-run the r15 §0/§5 commands with `--value-tag=r16` at tod 0/0.5/0.6/1.0, then `gate_table.py` and
  `clip_gate.py` (`tmp/city-art/r15/`) against `r15f2`: that baseline is r15's `gate.json` (write yours to a new file),
  and `clip_gate.py`'s built-in baseline is r14's. Look at `captures/sheets/art_r16_{V1,V2,V3,V8}.jpg` (r14 | r15 |
  r16 | key art), `art_r16_hatch_*.jpg`, S02city / S04fight at tod 0.6 (r15 | r16), and item 3's A/B sheet if any.
- Budget: what ships from items 1–4 costs ≤ +1.0 ms per camera at `cams_budget5`, paired as in r13, with the load
  average printed; re-run a contaminated run (r15 §5.4). No source file is over 600 lines: `git ls-files | grep -E
  '\.(gd|py|sh|gdshader|gdshaderinc)$' | xargs wc -l | awk '$1>600 && $2!="total"'` is empty. No dead code.
- `status/city-art.md`: mark r15 done; r16 goes on top with evidence, How to verify, Known issues and Requests.

## Coordination
- **In parallel:** hud r6, flow r5, feel r5, mech-move r7, skills r4, camera-aim r8, weapons r5, enemies r11,
  monster-assets r5, city-kit r10 (props), city-layout r8, city-build r11, traversal r1, tooling r1, and hero-v3 r8.
- **city-build r11** rebuilds the city after city-layout r8 and re-bakes the settle cache after each rebuild;
  **city-kit r10** re-bakes it if a prop's footprint changes, and whoever lands second re-bakes
  (`reviews/city-kit-r10.md` §3). Land item 5 early so their bakes carry the new stamp; make your one re-bake after the
  last of them, and re-run items 8–9 on that tree. city-build's Spire notch shows in every vista, so take each colour
  table and sheet on one tree and name the commit.
- **hero-v3** tunes its rim and emissives against your light. Put whatever items 1, 2 and 4 change in it in Requests,
  with the S04 cameras' shaded-side luma before and after. The Environment's public API does not change.
- **hud r6** credits the sky plates only if item 3 keeps them (it reads `status/city-art.md`): put item 3's outcome
  and any credit line in Requests early. The trailer films this look later: keep `--tod`, `--render-scale`, `--stub`,
  `--no-enemies` and `--trailer-*` as they are.
- **Yours** from r16 (`reviews/r16-lead-decisions.md`): `game/world/post/**` (item 7's rows and test, and
  `effects/post_lens.gd` if item 2's A/B lands there). Record each change in `status/post-render.md` too.
- **Not yours:** `game/project.godot`, `tools/**`, `data/**`, `docs/**`, `game/world/{kit,city}/**`, `game/trailer/`,
  and this round `blender/props/**` and `game/world/props/meshes/**` (city-kit r10's exception);
  no tile or kit rebuild. Commit per item, explicit paths (`git commit -m … -- <paths>`), never `-a`. Requests: status.
