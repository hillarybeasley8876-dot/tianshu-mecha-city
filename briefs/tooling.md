# tooling r1 — lead brief: tools that drive their own checkout and fail on errors; README, export, pad, input quad

A new unit: the lead hands you its tooling (wrappers, test host, autoplay, pad tests, packaging). Your 13 findings are
in `~/m/mc-lead/accept/findings_all.json` (ids per item; `check` corrections win), made on the frozen copy at `b5d26d4`.
HEAD has moved on: re-check each against HEAD first; if one is already fixed, say so with the evidence. Work in order.
Lead decisions (`reviews/r16-lead-decisions.md`: Shared, and tooling r1) win where they differ; tooling r1 there also
adds the capture-tool clocks (`game/tools/capture.gd`, with a test).

## Why
From a worktree, `tools/godot.sh` imports and "heals" the LIVE tree; `drive` dies at 600 s, so the E2E (850–1,950 s)
cannot finish; a windowed run whose window is hidden stalls and keeps its heavy slot; suites print PASS over SCRIPT
ERRORs (melee's Nil pair hid in four runs). The app has no README and its pack ships the harness: ACCEPTANCE §5 fails.
Nothing drives the pad path, 13 SPEC §3 pad rows are untested, a reload holds the left thumb off the stick 0.4 s (§2
allows 0.3), and press-to-photon has no instrument to film.

## 1. Tools drive the checkout they live in; long runs take `--timeout=` — minor, do it first
`tooling-worktree-imports-live-tree`, `godot-import-hardcoded-live-root`, `lead-drive-slot-cap-and-worktree-import`
- **Defect:** 3e50961 made only `godot.sh` checkout-relative (`:19-21`). Its import step (`:29`) runs `godot_import.sh`,
  whose `ROOT="$HOME/m/mecha-city"` (`:7-9`) aims the doctor (it unlinks `.import` files, `import_doctor.py:26-30`),
  the stamp and `godot --import` at the live `game/`, and never imports the caller's. The same hard-code is in
  `blender.sh:10`, `tools/city/*.sh:6-8`, `tools/citykit/{qa,process_all}.sh` and eight `tools/citykit/*.py`. `drive`
  (`godot.sh:71`) gets the heavy slot's 600 s (`slots.py:17`), `test` (`:54-57`) light's 300 s, whatever the `--timeout=`.
  **Repro** (scratch worktree): `BASH_ENV=<a set -x file> tools/godot.sh import; grep ROOT= tmp/last_import.log`.
- **Fix:** ROOT from the script's own path in all of them (the stamp follows); `godot_import.sh` logs `[import] project
  <PROJ>`. Leave `SLOT_DIR` (`slots.py:19`) in place: workers hold its locks, and a moved pool lets two imports of one
  tree overlap. `--timeout=<s>` sets each subcommand's slot timeout; `test` adds a margin to the suite's `--timeout=`
  so the host's own TIMEOUT report prints first. Defaults stay; `GODOT=`/`BLENDER=` may override the binaries.
- **Done:** Gates 1–3. Prove the worktree case in a scratch `git worktree add` under `tmp/tooling/` with the live cache
  cloned in (`cp -c -R game/.godot <wt>/game/`, APFS: instant) so its import is incremental; remove it after. Add a
  `--timeout=` line to the preamble's wrapper section. Commit this first and log it under Done: flow r5 waits on it.

## 2. Windowed runs keep going when their window is hidden — minor (lead note, no finding id)
- **Defect:** a heavy-slot window (`shot`, `run`, `drive`, `movie`, `perf`) that is not visible stops drawing and sits at
  0 % CPU, holding its slot until the slot timeout: Stage Manager tucks away every app that is not in front, and a
  full-screen movie over the screen does the same. Acceptance lost two runs to it:
  `~/m/mc-accept/tmp/acc/checkpoints/run_district_try1_stalled.log` (waited on `frame_post_draw` until its driver fell
  back to `RenderingServer.force_draw`) and `~/m/mc-accept/tmp/acc/suites/logs/feel_frames2.log` (72 `ACCFEEL no frame
  drawn` once its window was covered).
- **Do:** find a robust fix in `tools/godot.sh` (plus `slots.py` or `game/tools/**` if it needs them): e.g.
  `--always-on-top` or a window placement that keeps every heavy-slot window visible, App Nap off for the Godot process
  (`NSAppSleepDisabled`), or a stall detector that names the run and frees its slot. Measure each option (CPU from `ps`,
  frames drawn, wall time) on a covered and an uncovered run. Never change the user's Stage Manager or display
  settings. Gate 8.

## 3. The test host fails on errors — minor (`test-host-ignores-script-errors`)
- **Defect:** `game/tools/test_host.gd:42-50` shows the ErrorCounter only on TEST TIMEOUT: a suite that logs SCRIPT or
  engine ERRORs and quits 0 exits 0 (`:7` says the default is 120 s, `:12` 300). **Repro:** `tools/godot.sh test
  res://enemies/tests/test_main_spawn.gd -- --sandbox --no-enemies` exited 0 with 2 `SCRIPT ERROR` lines at b5d26d4
  (melee-defense r6 fixed that pair, 7cf4abe); at HEAD, until hud r6 item 6 lands, `tools/godot.sh test
  res://ui/tests/test_hud.gd` exits 0 over the engine ERROR from `ui/tests/suite_widgets.gd:187`.
- **First the list:** `tools/suites.sh` + a list of every `game/**/tests/test_*.gd` (71 tracked at `25c0963`, more
  landing), flags as each unit's status documents (`~/m/mc-accept/tmp/acc/suites/lane_{a,b}.txt` = b5d26d4's 66 runs);
  an unlisted test fails it. Per run: exit, checks line, SCRIPT ERRORs, other ERRORs (not exit-time leak lines). Today's
  host, table in status; at b5d26d4 it flags melee's pair (`test_main_spawn` ×3, `test_flow_perf`), `test_hud`,
  `test_spawner` and `test_art`.
- **Then the host:** at quit `TEST ERRORS <n>` + the first lines; exit 1 on a SCRIPT ERROR or an engine ERROR (push_error
  too), not on warnings or exit-time lines. One host-side allow-list keyed by suite + exact message, a reason each, no
  wildcard: deliberate negatives (confirm `test_spawner`'s `dragon` and `test_art`'s `huge`) and this round's routed
  red (hud r6 item 6; melee-defense r6's pair is already fixed, so no entry), tagged with the finding id, printed
  `TEST KNOWN-ERROR`, removed when the fix lands. Fix harness causes; other reds go to Requests per owner. The export's
  pre-checks (`godot.sh:112,119`) use the host too. Fixtures `game/tools/tests/fixture_*.gd` (Gate 4); a preamble line.
- **Order:** the table is committed in status BEFORE the host changes in the live tree. Every worker's suites run
  `game/tools/test_host.gd` the moment it is saved, so build and test the new host in a scratch worktree (item 1) and
  copy it into the live tree only after the table is in.

## 4. README.md with both control schemes — major (`pkg-readme-missing`)
- **Defect:** no README in any commit (`git log --all --oneline -- README.md`), in `build/` or the bundle; the in-game
  CONTROLS page omits double-tap flight and the Lance. **Content** (English, in-game verb names): every SPEC §3 row,
  KB+M and pad, with its tap/hold meaning; pause (Esc / Menu), F11, RB = shift layer; first opening of the ad-hoc,
  un-notarized app (Privacy & Security › Open Anyway, or `xattr -dr com.apple.quarantine TIANSHU.app`); macOS 11+,
  universal, Metal; from source (`tools/godot.sh play`, Godot 4.7.2, `GODOT=`); the credits, hud r6's 开源许可 LICENCES
  page and `build/THIRD_PARTY_LICENSES.txt`. **The code is the truth:** `core/input_setup.gd:21-68`, `pad_input.gd:19-27`,
  double tap 0.30 s (`player/mech/mech_input.gd:22`), catch field 0.3 s (`combat/defense/defense_table.gd:32`), the
  Lance = a second hold during Overdrive, ward 0.35 s (`combat/skills/skill_input.gd:108-126`,
  `combat/skills/tuning/skill_tuning.gd:62,137`). Where SPEC differs (a plain "V" for the Lance), follow the code and
  put the mismatch in Requests. Gate 7.

## 5. The export ships the game, not the harness — minor (`pkg-export-preset-polish`)
- **Defect:** `game/export_presets.cfg:10` drops only `*/tests/*, */demo/*`: the 11-04 pack holds 19 `tools/` entries
  (test_host, autoplay …), `world/city/tools/**`, `trailer/**`, and would take scratch in `game/tmp/` (camera-aim r8's
  probe) or `tmp_*/`. No icon exists; `NSHumanReadableCopyright` is empty. **Do:** exclude `tools/`, `world/city/tools/`,
  `trailer/`, `tmp/`, `tmp_*/` (no `*probe*` glob: `world/art/detail/arena_probes.gd` is runtime); show nothing else
  loads them (today one message string, `world/art/city_art.gd:180`). `application/copyright="© 2026 erapi0neer"`,
  version 0.1, no icon; keep universal + ad-hoc (`:20`, `:27-28`). hud r6's licence glob is already in `include_filter`
  (`:9`, `ui/licenses/*`, the lead's 24deec4): keep it. The export case (`godot.sh:108-130`) copies the README and,
  once hud's writer lands, writes `build/THIRD_PARTY_LICENSES.txt`, as a post-export step that also runs alone into a
  scratch dir.
- **Never run `tools/godot.sh export`** (it holds the machine's one import slot; the lead exports). Check the globs
  statically (Godot matches `res://path` and `path`); promote `~/m/mc-accept/tmp/acc/packaging/scripts/pck_list.py` to
  `tools/` and run it on today's `build/TIANSHU.app` for the before numbers. Gate 6.

## 6. Hygiene — minor (`hygiene-tracked-pyc`, `hygiene-ownership-table-stale`, `public-release-scrub`)
- **.pyc:** `tools/tripo/__pycache__/{api,pipeline}.cpython-312.pyc` are tracked (3cb66cf; `.gitignore:16-17` covers
  them) and hold the home path: `git rm --cached`, own commit. **Ownership:** 2,334 of 4,780 tracked files had no §1
  owner at b5d26d4 (the finding lists them: seven units missing, city-blockout now city-build, a dead `hero/**` row,
  boss inside enemies, `kit_assign.json` inside `data/map/**`). Draft §1 from the briefs and status files
  (`reviews/r16-lead-decisions.md` wins: `world/post/**` is city-art's), one stated precedence (the most specific row
  wins); promote `~/m/mc-accept/tmp/acc/packaging/scripts/owners.py` to `tools/`, reading the table from
  `docs/CONTRACTS.md`. Mark owners you cannot tell; nothing else in `docs/`; commit it alone.
- **Scrub** (no secrets found): ys-api's internal endpoint (`git grep -n -I xaminim`) is in `tools/concept/ys.py:16`
  (yours: an env var, a readable error when unset), `tools/sfx/voice.py:28` (audio's), two lead docs; `/Users/minimax`
  in 13 tracked docs and status files; `~/m/mecha-city` in ~120 `blender/**` lines (`blender/lib/common.py:16` and
  `export.py:17,39` are shared). A checker lists hits by owner: fix yours, the rest go to Requests with file:line.

## 7. The pad path, driven and tested — minor
`pad-only-combat-atom-missing`, `input-pad-bindings-untested`, `pad-reload-hold-threshold`
- **Autoplay** only calls `Input.action_press` (`game/tools/autoplay.gd:106-120`), so PadInput (`core/pad_input.gd:42-48`)
  never sees a scripted run: add raw pad button and axis steps (via `Input.parse_input_event`) and document them.
- **Bindings:** `core/tests/test_core_input.gd` (24 checks) covers A, RB+X, RB+RT, RT, L3, L3+R3, D↑ tap. Add one per
  remaining row: B, X, Y, LB, LT → aim, sticks → move/look, R3 after the chord window, RB+Y/B/A with the latch, D↑ hold
  → reload, D↓ and View → camera_toggle, D←/→ → lock_prev/next (camera-aim r8 owns the consumer), Menu → pause.
- **Reload:** `RELOAD_HOLD := 0.4` (`pad_input.gd:17`); SPEC §3's 0.25 s wins (a clash inside SPEC → Requests). Keep tap
  = weapon_next on release (`:102-112`). Check: no reload at 0.20 s, reload by 0.27 s, no weapon_next; FAILS at 0.4.
- **The atom:** promote `~/m/mc-accept/game/tmp_accept/suites/acc_pad_atom.gd` (real `main.tscn`; last run: R3 saw no
  target in view, the fins tap fell inside the ward) to `core/tests/`, targets in front of the hero. One sequence of
  raw pad events, shared by the headless test and a windowed `drive`; the D-pad switch uses camera-aim r8's consumer
  (landed in a8c8a50).

## 8. The F3 input quad — minor (`press-to-photon-blocked`)
- **Defect:** `debug_toggle` (F3, `core/input_setup.gd:44`) has no consumer (`grep -rn --exclude-dir=.godot debug_toggle
  game`), so ACCEPTANCE §2's 240 fps press-to-photon film has nothing to score. **Build** `game/core/input_quad.gd`: F3
  toggles a corner quad (off by default) that flips black↔white on the first frame drawn after a key, mouse-button or
  pad-button press. It never consumes input, runs on the title and under pause, draws above HUD and post, is ≥ 96 px
  square at 1600×900, ships in the .app; add its one autoload line to `game/project.godot` (granted in
  `reviews/r16-lead-decisions.md`). The lead films: put the procedure in status (what to press, what to count; 50 ms =
  12 frames at 240 fps). Gate 7.

## Gates
1. `git grep -nE 'HOME/m/mecha-city|expanduser\("~/m/mecha-city|cd ~/m/mecha-city' -- tools` lists only `slots.py:19`,
   `tripo/cdp.py:35` (the lead's), `workers/lead-watch.sh:4` and comments (a citykit file with city-kit's uncommitted
   edits, e.g. r10's new `props_swap.sh:8`, goes to Requests instead).
2. From the item-1 scratch worktree (the lead repeats it from `~/m/mc-accept`): `tools/godot.sh import` logs and stamps
   that tree, a new `game/tmp/tooling/x.png` gets an `.import`, and `tools/blender.sh preview <glb> t` writes under its
   `captures/`.
3. A 60 s fixture: `tools/godot.sh drive --sandbox --timeline=res://tools/tests/<it>.json --timeout=30` ends `[slots]
   TIMEOUT after 30 s`, `--timeout=300` ends `DRIVE done`; flow's district drive (`status/flow.md`, with your own
   `--out=` and `--log=`) with `--timeout=1500` ends `DRIVE done` too.
4. `tools/godot.sh test` on the fixtures (SCRIPT ERROR + quit 0, push_error + quit 0, allow-listed, clean): 1 1 0 0, and
   0 0 0 0 on HEAD's host. `tools/suites.sh` prints the table; every red in it is in status with its owner.
5. `tools/godot.sh test res://core/tests/test_core_input.gd`: ≥ 37 checks, 0 failures. The atom passes three times with
   the same numbers, longest left-stick release ≤ 0.30 s (fails with the 0.4 s reload); a contact sheet of the drive.
6. The post-export step run alone writes `<scratch>/README.md`. After the lead's export, `python3 -I tools/pck_list.py
   build/TIANSHU.app/Contents/Resources/*.pck` lists nothing under `tools/`, `trailer/`, `world/city/tools/`, `tmp*/`,
   `*/tests/`, `*/demo/`, and still lists `world/art/detail/arena_probes.*`; `codesign -dv` adhoc; `lipo -archs`
   x86_64 arm64; the plist's copyright; `build/README.md`; the app boots to the title.
7. The README test (every binding in the real InputMap/PadInput tables is on its action's README row, none extra;
   FAILS on a copy missing a row) and the quad test (one flip per injected key, mouse and pad press by the next frame;
   FAILS on HEAD) pass; two windowed quad frames, dark and lit; `tools/owners.py` 0 uncovered, 0 ambiguous; the scrub
   checker 0 hits in your files; `git ls-files '*.pyc'` empty; `tools/godot.sh check` 0 errors.
8. With a full-screen movie over the screen (and again with Stage Manager on and another app in front), Gate 3's 60 s
   fixture drive with `--shots=` ends `DRIVE done` with every shot written, in about the wall time of an uncovered run;
   the same covered run before your change stalls (paste both, with `ps` CPU samples); a contact sheet of the covered
   run's shots. If only detection proves possible, the stall is reported and the slot freed within 60 s, and status says
   why the run cannot be kept going.
- New tests drive the real path, FAIL on the old code and PASS on the new (paste both; for the old code copy your file
  aside, `git show HEAD:<path> > <path>`, re-run, copy it back; never `git stash`); no file over 600 lines (split
  commit first); no dead code; explicit-path commits; no "fixed" without the re-run; an r1 section per item in status.

## Coordination
- **Yours** (the preamble's "lead's files" rule does not apply): `tools/*.sh`, `tools/*.py`, `tools/workers/**` except
  `m78.py`, `watchdog.py`, `lead-watch.sh` (never touch the runner), `game/tools/**`, `game/core/tests/**`,
  `game/core/{input_setup,pad_input,input_quad}.gd`, `README.md`, `game/export_presets.cfg`, `.gitignore`, your status.
  **One change each:** the ROOT lines in `tools/city/*.sh` (city-build's), `tools/citykit/*` (city-kit's), `blender/lib/`;
  `tools/concept/ys.py:16`; the two .pyc; the §1 table of `docs/CONTRACTS.md`; the `input_quad` autoload line in
  `game/project.godot`. `git status -- <file>` first: a file with someone's uncommitted edits goes to Requests. Not
  yours: the rest of `game/project.godot`, `game/main.*`, the rest of `game/core/**` and `docs/**`, other units' files.
- **Live scripts:** workers run `godot.sh`, `godot_import.sh`, `slots.py` and `blender.sh` all the time, and bash reads
  a script as it runs it: never edit them in place; write the new file beside the old one and `mv` it over.
- **In parallel:** flow r5 waits on `--timeout=`; hud r6 item 6 fixes the routed red (melee-defense r6 fixed its pair:
  7cf4abe); hud r6 item 3 needs your export call (the include_filter line is in: 24deec4); enemies r11 gates on
  `test_main_spawn`; camera-aim r8 landed the D-pad consumer (a8c8a50); audio owns `tools/sfx/**` (r6 accepted), and
  its `credits_check` counts shipped files by the preset's excludes (the new list goes in Requests); skills r4 asks
  before touching `pad_input.gd`; the export refuses while city-art's `test_settle_cache` fails; city-kit r10,
  monster-assets r5 and hero-v3 (uncommitted `hero3/**`) run Blender via `blender.sh`. The CONTROLS page
  (`ui/menus/menu_root.gd:38`) lacks flight, the Lance, pause and F11: hud's, so note it in Requests.
- **Requests** go in the Requests section of `status/tooling.md`; the lead forwards them.
