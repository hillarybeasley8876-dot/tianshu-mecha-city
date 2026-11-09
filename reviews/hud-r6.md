# hud r6 — lead brief: honest credits and licences, the first tutorial prompt, a flight cue

The five findings (`~/m/mc-lead/accept/findings_all.json`, ids per item) were made on the frozen copy at `b5d26d4`.
Since then (checked at `a1c5bdc`) `git diff --stat b5d26d4 HEAD -- game/ui docs` is empty; `game/flow` has only flow
r5's commits (a `resume()` in `tutorial_director.gd`, `abort_to_title()`: see Coordination) and
`game/export_presets.cfg` only the lead's include_filter line (`24deec4`), so expect all five to reproduce. Re-check
each on HEAD first; if one is already fixed, say so with the evidence.

## Why
- From the title, `W 移动 MOVE` never shows and LOOK gets 5 s, for every real player; hud/flow runs use `--skip-menu`.
- The credits call the Tripo-built city "built in-house": a false AI disclosure is worse than a missing row.
- The app ships no Godot MIT notice, engine third-party notices or font OFL text; it cannot be shared yet.
- Flight works from every state now (mech-move r6), but nothing on screen says the mech is flying.

## 1. The first tutorial prompt is lost on the title path — major (`hud-first-tutorial-prompt-dropped-from-title`)
- **Defect:** `ui/widgets/tutorial.gd:114` adds to `age` every frame from HUD creation, with an empty queue
  and under the title too (`hud_widget.gd:40-50` runs `update_hud` even when suppressed); `prompt()`
  (`:62-71`) never resets it. The flow's first `prompt(&"move")` meets `age > LIFE` (`:115`, 12 s) on its
  first frame: popped AND retired, it never comes back. LOOK, queued 7 s later (`flow/tutorial_director.gd:15`),
  starts at age 7 and gets 5 s. The drop-in takes 5.4 s, so MOVE is lost whenever the title is up > ~6.6 s.
- **Done:** LIFE counts from when a prompt reaches the front of the queue; nothing ages an empty queue. The
  canopy copy runs the same script (`hud.gd:93-99` fans out), so both copies pass. LIFE stays a fallback
  longer than the flow's 7 s; the flow owns the timing — no edits to `game/flow/**`.
- **Repro = the new test** (fails on HEAD), in `suite_widgets.gd`: empty queue for 13 s (`update_hud(13.0)`
  or real frames), then `h.hud.prompt(&"move")`: a frame later `current_id() == &"move"` and visible, still
  after 7 s; then `dismiss_prompt(&"move")` + `prompt(&"look")`: look visible 7 s. Same on the canopy copy.
- **The real path:** stock `tools/autoplay.gd` cannot press keys (`tap` is `Input.action_press`, which never
  reaches `menu_root.gd:_input`). Ship a probe scene in `ui/tests/` that instances `main.tscn`, presses Enter
  (reveal + START) 10 s after the world is built via `Input.parse_input_event` (Esc is `pause`), and prints
  `front/age/queued/retired` on every change and every 0.5 s. Real flow: no `--skip-menu`, `--sandbox` or stubs.
  `tools/godot.sh drive --scene=res://ui/tests/<probe>.tscn --timeline=res://ui/tests/<probe>.json --god
  --out=hud_r6_title --shots=3,9,14,16,17.5,19,20.5,22,23.5,25,26.5,28,29.5,31 2>&1 | tee
  ~/m/mecha-city/tmp/hud/r6_title.log` (timeline: one `end` at 32 s)
- **Gate:** the test; in the drive `W 移动 MOVE` is up from landing (about 5.4 s after START) until the hero
  moves or 7 s pass, then `MOUSE 环视 LOOK` for its full 7 s, and the log never shows `retired=[move]` one
  frame after the prompt was queued. Control: START 0.5 s after the build shows MOVE the full 7 s (today 6.2).

## 2. The AI disclosure misattributes the city — major (`credits-ai-label-city-in-house`)
- **Defect:** `ui/menus/credits_data.gd:45-49` (AI_ROWS) dates from hud r3 (`ce73f7e`), before city-kit
  landed: the city "built in-house", the models "rigged + textured in-house". KitPlacer draws every skinned
  building (448 structures); props, HUSK and hero are Tripo image→model too, all from AI concept images, and
  no row mentions the concept art. **Repro:** the credits frame of the menu capture (Gates).
- **Facts, read-only — do not guess:** `art/tripo/jobs.json` (kit 67, prop 30, mon 7, hero 6 + hero3 4, all
  from `art/concept/**`), `briefs/city-kit.md:1,15`, `briefs/hero-v3.md`, and `status/monster-assets.md`
  (in-house `mon_rig.py`, `mon_custom_rigs.py`, `mon_clips*.py`) against `art/tripo/mon_*/rig.log` and
  `motions.log` (Tripo auto-rigs, motion clips). Poly Haven CC0: `game/assets/textures/manifest.json`.
- **Done:** every AI family has an AI label: city buildings, street props, HUSK models, the HUSK rigs and
  clips Tripo made, the hero, the MiniMax voice, and the AI concept images (Tripo's inputs, not shipped; name
  a generator only where a record does). "In-house" only for what is: the procedural blockout (collision,
  nav, the Spire), shaders and materials, VFX, and the rigs and clips built here. One Poly Haven CC0 row for the
  textures; the two sky plates join it only if city-art r16 item 3 keeps them (lead decision: check
  `status/city-art.md` before you finalise it; `game/world/art/sky/README.md` has city-art's line).
- **Gate:** a suite check that fails on today's rows (every family has an AI row; no row calls Tripo content
  in-house), and the credits frames read at full size.

## 3. No licence notices ship — major (`credits-no-engine-font-licences`, lead note b)
- **Defect:** no MIT text, engine notices or OFL text on any page or in the PCK: `git grep -n -E
  'get_license_text|get_copyright_info|get_license_info' -- game` finds nothing, and `LC_ALL=C grep -a -c
  'ui/fonts/OFL'` on the current PCK is 0. `ui/fonts/OFL.txt` lacks the copyright line OFL §2 requires
  (Noto Sans CJK SC: "© 2014-2021 Adobe"); `OFL-Rajdhani.txt:1` has its own.
- **Done:**
  - 引擎与字体 ENGINE & FONTS rows: Godot Engine 4.7 — MIT · godotengine.org/license; Noto Sans CJK SC —
    © 2014-2021 Adobe · SIL OFL 1.1; Rajdhani SemiBold — © 2014 Indian Type Foundry · SIL OFL 1.1.
  - a 开源许可 LICENCES page reached from CREDITS (title, pause, victory), scrolled by keys and pad, showing
    `Engine.get_license_text()`, each `Engine.get_copyright_info()` component with its `get_license_info()`
    text, and both OFL texts with their copyright lines; engine text read at runtime, never pasted in.
  - the licence files in `game/ui/licenses/` (granted): move both OFL files there, fix `hud_palette.gd:66,75-76`.
    A file that will not open is a `push_error` plus a visible row saying so, never a blank page.
  - one composer for the full notice text, used by the page and by a headless writer in `ui/licenses/`
    (`--out=`), so `tools/godot.sh export` (tooling r1 wires the call) writes `build/THIRD_PARTY_LICENSES.txt`
    from the same source.
- **The export trap:** `game/export_presets.cfg:9` was `include_filter="*.json"` (lead-owned); the lead's line has
  landed (`24deec4`: `"*.json, ui/licenses/*"`), so a `.txt` ships only from `ui/licenses/`, yet every dev run reads
  any path from disk and passes. Add a suite check that every file the page reads matches an include_filter glob in
  `res://export_presets.cfg` (ConfigFile, split on commas, + `String.match`); a file left in `ui/fonts/` must fail
  it: do not weaken it.
- **Gate:** suite: the LICENCES text holds "Juan Linietsky", "FreeType", "Indian Type Foundry" and "Adobe"
  (fails on the old code); the LICENCES frames show the MIT text and the OFL section.

## 4. Credits polish — minor (`credits-text-clipped-and-header`)
- **(a) Clipped values:** `menu_screen.gd:141-142` gives values 45 % of the list and `:233-234` cuts there,
  so the voice row reads "processed in-hous". Nothing may be cut on any page.
- **(b) MUSIC header:** `credits_data.gd:77-78` says "all CC0 1.0"; 7 of the 13 music files (metronome + 6
  stingers) are "own synthesis | ours" in `audio/audio_manifest.csv`. Derive it from the licence column.
- **(c) Victory never reaches the credits** (SPEC §8 step 5): FINISH (`menu_root.gd:173`) quits at
  `:298-301`. FINISH opens CREDITS; leaving them from there quits the app as FINISH does today (`quit_game`: see
  Coordination).
- **Layout, for 2–4 together:** 27 rows at 25 px, centred, no scrolling (`menu_screen.gd:135-137`; today's page:
  `~/m/mc-accept/tmp/acc/packaging/acc_packaging_menus_t8_3.jpg`). A 16:9 canvas (1920×1080) fits ~34 rows and
  items 2–3 add about a dozen: paginate or scroll, every row reachable by keys and pad and inside a 1920×1080
  canvas (a suite check). `menu_root.gd` is 374 lines: the licences page gets its own file.
- **Gate:** suite checks that fail on the old code — each value fits its column (measured with the draw's font
  and size), the header matches the manifest, FINISH opens CREDITS (via a seam: `get_tree().quit()` must not
  end the test host) — and the menu frames show every string whole.

## 5. Flight has no cue — lead item (`status/mech-move.md` Request 7, frame `captures/mech-move_flight_t3_6.jpg`)
- **Defect:** `hud_state()["state"]` is `"fly"` in flight (`player/mech/player_mech.gd:462`; set every flight
  tick at `mech_air.gd:96`, the in-flight assault too) and `hud_data.gd:75` merges it, but
  `grep -rn '"fly"' game/ui` finds no reader. `Events.flight_changed` (`core/events.gd:32`) is the edge signal.
- **Done:** in flight, a clear indicator: the state (one language, `HudLocale`) and an EN drain reading the
  player can act on, e.g. seconds of flight left, derived from what `hud_state()` publishes (do not copy
  `mech_tuning.gd:87-89`'s 80 / 120 EN/s into `ui/`). It shows on entry and goes on every exit (EN 0 → glide,
  landing, toggle), keeps the palette (cyan = self, amber only to warn) and the outlined type, clears the
  reticle cluster, and works on the canopy. A missing key is a Request to mech-move; never edit `player/**`.
- **Gate:** a suite case (forced `fly` shows the cue and its reading; `glide`, `fall`, `run` hide it; fails
  on the old code); a flight step in `hud_shots.gd --hud=combat` with one canopy frame; and the real strip
  `tools/godot.sh drive --sandbox --timeline=res://player/mech/timelines/flight.json --out=hud_r6_flight
  --shots=0.9,2.2,3.6,4.9,5.9,7.4,8.8,10.2,11.2 --log=$HOME/m/mecha-city/tmp/hud/r6_flight.csv`:
  the cue is in every frame whose CSV row says `flying=true` and in none where false (table in status).

## 6. test_hud logs an engine ERROR — minor (`hud-test-engine-error`)
- **Defect:** `ui/tests/suite_widgets.gd:187` hands the freed `doomed` to `TypedArray.has()`; test_host
  ignores engine errors, so 217/0 hides it. **Repro:** `tools/godot.sh test res://ui/tests/test_hud.gd 2>&1
  | grep -B1 -A5 'previously freed'`. **Done:** assert the prune without handing a freed object to the array.
- **Gate:** the suite log has no `ERROR:` line except the exit-time "resources still in use at exit".

## Gates
- `tools/godot.sh check --only=res://ui/` → 0 errors, 0 warnings.
- `tools/godot.sh test res://ui/tests/test_hud.gd 2>&1 | tee ~/m/mecha-city/tmp/hud/r6_test.log` →
  `TEST n checks, 0 failed`; `grep -n 'ERROR:'` on that log shows only the exit-time line.
- Every new check fails on the old code: copy each fixed file aside, `git show HEAD:<path> > <path>` (before you
  commit the fix), re-run, paste the FAIL lines, copy it back. Never `git stash`: the stash stack is shared by
  every worker in this tree.
- Menus: `tools/godot.sh shot --scene=res://ui/tests/hud_shots.tscn --out=hud_r6_menus --hud=menus --sandbox
  --skip-menu --god --no-enemies --times=<yours>`, with steps for every credits page or scroll position,
  LICENCES at the top (MIT) and at the OFL text, and victory → FINISH → credits. Say which frame is which.
- Combat (`--hud=combat`, How to verify) with the flight step; item 1's two drives; item 5's strip and table.
- `wc -l` on every file you touch: none over 600 (split commit first); `menu_root.gd` under 400.
- After the lead's export (not yours to run): `LC_ALL=C grep -a -o -E 'ui/licenses/[A-Za-z0-9_.-]+'
  build/TIANSHU.app/Contents/Resources/*.pck | sort -u` lists the files, `build/THIRD_PARTY_LICENSES.txt` holds
  item 3's four strings, and `codesign --verify --deep --strict build/TIANSHU.app` passes.
- `status/hud.md`: an r6 section (per item: HEAD re-check, cause, fix, re-run), the title run in How to
  verify, and the r3–r4-closed items (`hit.source_kind`, `heartbeat`) out of Known issues and Requests.
  Commit with an explicit path list (hero-v3 has uncommitted files); no dead code; no "fixed" without a re-run.

## Coordination
- **In parallel from the same pass.** **flow r5** item 5 has landed (`f39b168`): `game_flow.gd:129-130` connects a
  new `abort_to_title` signal that you add for PAUSE → ABORT (lead decision 3, `reviews/r16-lead-decisions.md`)
  and, until it ships, answers `quit_game` only while PAUSE is up and the tree is paused (`:302-306`); flow mirrors
  `Page.TITLE`/`PAUSE` as 1/2 (`:23-24`), so append new pages. Today every QUIT/ABORT/FINISH emits `quit_game`
  (`menu_root.gd:298-301`); from now on `quit_game` always quits the app, so leaving the victory credits emits it.
  **lead**: the ACCEPTANCE §5 licence clause (the include_filter line has landed). **tooling r1**: the README and
  the `THIRD_PARTY_LICENSES.txt` writer call in `tools/godot.sh export` (the README will point to 开源许可 LICENCES:
  keep the name). **audio** (r6, accepted): copy its final strings verbatim from `status/audio.md` Request 8 into
  `PACKS` (`credits_data.gd:12-23`) and the music keys of `OTHER` (`:37-42`); four `TRACKS` rows (`:26-33`) differ
  from that table too. **mech-move** answers flight-key requests; **hero-v3 r7** is in `hero3/**`.
- **Routed to hud by other briefs and added to this round by the lead** (`reviews/r16-lead-decisions.md`, hud r6):
  flow r5's PAUSE RETRY row (unpause, then `retry_game`), GAME_OVER RETRY closing early (`menu_root.gd:295-297`) and
  pad B (`:252-262`); mech-move r7's unpaused GAME_OVER (`:96`) and W/S footer (`menu_screen.gd:251`); camera-aim
  r8's lock glyphs (`hud_glyphs.gd:32`); the `abort_to_title` signal above. Same files: separate commits.
- Granted: `game/ui/licenses/` (new). Read-only: every source item 2 cites, and `game/audio/audio_manifest.csv`.
  Not yours: `game/export_presets.cfg`, `tools/*.sh`, `game/tools/**`, `docs/**`, `game/flow/**`, `game/player/**`.
- Requests go to the Requests section of `status/hud.md`: any `hud_state()` key.

## Dispatch note from the lead (11-06 18:10): one worker at a time, headless only
The user works on this Mac. `tools/godot.sh shot|run|drive|movie|perf` refuse without the lead's
`MC_WINDOW_OK` (see the end of `tools/workers/preamble.md`). So:
- **Menus and tutorial flows.** Drive them headless through the test host: build `main.tscn` or the
  menus scene in a `test_*.gd`, inject `InputEventKey` / `InputEventJoypadButton` with
  `Input.parse_input_event`, and assert the page, signals and widget states.
- **Visual checks** (the credits page, the CONTROLS page, glyph sheets, the flight cue) go under
  **"Captures needed"** in `status/hud.md`, with exact commands. The lead batches them.
- **What changed since this brief was written:**
  - flow r5 landed `abort_to_title` handling (f39b168, 3e1a807);
  - audio r6's final credit strings are in `status/audio.md`, Request 8;
  - city-art kept no sky plates (r16a), so the Poly Haven row is textures-only;
  - the export already ships `ui/licenses/*` (24deec4).
- **Order:** read `reviews/r16-lead-decisions.md`, both the hud r6 section and Round 2. They hold
  the gates for the seven added menu items.
