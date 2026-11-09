# r16 — lead decisions at dispatch (11-05)

The brief writers and critics asked for these decisions. Each unit reads its own section, and the
Shared section applies to every unit. A decision here overrides the brief where the two differ.

## Shared
- **Tooling lands first.** The tooling unit commits the ROOT fixes (`tools/godot_import.sh`,
  `tools/blender.sh`, and the ROOT one-liners in `tools/city/*.sh` and `tools/citykit/*`) and the
  `tools/godot.sh drive --timeout=` passthrough as its first commit, and announces them in
  `status/tooling.md`.
  - **Until then, for drives longer than 600 s:** run `tools/godot.sh import`, then the raw line
    `python3 tools/slots.py heavy 3 --timeout 3600 -- <the godot.sh drive command line>`.
- **The stricter test host** (script and engine errors fail a suite) lands with an allow-list. Each
  entry is tagged with its finding id, prints `TEST KNOWN-ERROR`, and is removed when its fix lands. A
  red that is not on the list is a real failure.
- **Never `git stash`.** The stash stack is shared by every worker in this tree. To get an old version
  back, copy your file aside, then `git show HEAD:<path> > <path>`.
- **`world/post/**` belongs to city-art** from now on. The lead adds the CONTRACTS row.

## Shared (addition, 11-05 08:55): the conflict map
`reviews/r16-conflicts.md` maps every file or artefact that two r16 units touch, and says who goes
first. Read the rows that name your unit; where a row and your brief differ, the row wins. Two rules
apply to everyone:
- **Shared files.** Before `git commit -- <file>` on a file another unit may touch (`settle_cache.json`,
  `CONTRACTS.md`, `project.godot`, `FEEL.md`, `main.gd`, `enemy_base.gd`, `player_mech.gd`), run
  `git diff -- <file>`. If it holds someone else's hunk, wait or ask.
- **Other units' live code.** A probe that runs another unit's live code names that unit's commit and
  dirty files in its status line.

Also:
- **New test files.** The day a new `test_*.gd` lands, post its suites row (path, flags, any expected
  red) as a Request to tooling.
- **Home paths.** Never land a file with a `/Users/` path under `game/`: `test_no_abs_paths` walks the
  disk.
- **Swap big splits in whole.** Split `player_mech.gd`, `material_library.gd` or `enemy_base.gd` off-tree,
  swap the result in whole, and run `check` on the folder straight away.

## flow r5 (running; sent as a nudge)
1. **The B1 landing.** Land on a probed fighting-floor point on the S4 side (r ≈ 50–80 m, y ≈ 241.5),
   the same point `boss_p1` saves. Lowering by 20 m alone ends the arc inside the Ø80 m core.
2. **The catapult arc.** Route it outward, past r 150 from the Spire axis. There will be no hole in the
   boss fighting floor. city-build notches Crown rib j=2 over the S4 pad.
3. **Quit vs abort.** hud r6 adds a distinct `abort_to_title` signal for PAUSE → ABORT; flow listens to
   it and returns to the title. `quit_game` always quits the app. Until hud's signal lands, flow acts on
   `quit_game` only while the menus page is PAUSE.
4. **The boss restore** is the duck-typed hook from `FlowProgress.respawn`. No new Events signal.
5. **Two passes.** Commit items 1–6 first and write an interim status section; then do items 7–9.
6. **The boss death feel.** When feel r5 lands the `boss_kill` row, switch `brood_titan.gd:282-283` (they
   were :239-240 before your 5129b4c) from `kill_large` to `boss_kill`. That is a one-line change under
   your boss/** exception. If you finish before feel's row lands, feel makes the switch instead.
7. **hud's half of your Requests** is in hud r6: the PAUSE RETRY row, GAME_OVER RETRY closing the page
   before the respawn, and pad B on GAME_OVER.
8. `wave_clear` (a feel suggestion) is deferred, so it is not in this round.

## mech-move r7
- **The last-stand row** lands as a pair: feel r5 adds the FEEL.md row `last_stand` (0.5× for 1.5 s,
  60 s cooldown, witch off) and `fx/events/last_stand.tres` in ONE commit, and moves the slow-mo cell out
  of `hurt_heavy`. feel is granted that FEEL.md edit.
  - Wire `Feel.play(&"last_stand")` only after feel's commit lands. Watch `status/feel.md`.
  - The trigger is any hit that crosses below 15 % HP and leaves the mech alive.
- **The death gate.** It must reach all five components through the PlayerMech pipeline; no guard lines
  are pre-granted in other units. If a component cannot be reached, file a Request with evidence.
  **Do not touch `skill_input.gd`:** skills r4 adds the alive check there (its item 6).
- **Respawn carry-over** (refilling ammo, heat and cooldowns on RETRY) is out of scope this round.
- **The two feel choices stand:**
  - the RETRY confirm press must not act after the revive (check the InputMap for ui_accept and
    jump);
  - horizontal speed dies at death.
- **The platform-velocity fling** comes from enemies r11's trace and arrives as a Request. Act on it
  only if the trace shows a trigger other than spawning.

## feel r5
- **The core API is granted for two changes.** `game/core/feel.gd` is the lead's file; feel may make
  these two:
  1. `Feel.play(id, at, strength, actors: Array = [])`, plus a new 4-argument signal that the director
     connects to. Keep emitting the 3-argument `event_requested`: audio's router and enemies' near_miss
     use it.
  2. `slow_mo` combines requests instead of replacing them. Each request keeps its own clock, the scale
     is the minimum of the running requests, and a non-witch request never ends witch time.
- **FEEL.md is granted for this round's rows:** the `kill_small` change, `last_stand` (see mech-move)
  and `boss_kill` (G 150 ms plus the boss's 0.2×/1.2 s slow-mo, exempt from the kill_large budgets).
  Each row lands in the same commit as its `.tres`, so `test_feel`'s row count stays green.
- **The distance rule.** A kill_large beyond half its falloff (more than 100 m away) gets the local
  stop only: no global stop and no slow-mo.
- **Ranged vs melee.** Ranged kills stop the victim only, so gunfire never freezes (FEEL.md:6). Melee
  kills keep the attacker-and-victim stops their rows already have.
- **`enemy_base.gd`.** Your narrow exception covers `_die`, the dead branch and `_tick_wreck`. Make
  those edits last, after enemies r11's commit to that file lands.
- `wave_clear` is deferred.

## skills r4
- **One shared press buffer** (6 frames of `can_act()`) for every press-edge skill: rift, anchor,
  burst, well and lance.
- **The Hero3 per-drone hide API.** Write the request with the exact signature you need; the lead
  forwards it to hero-v3. skills r4 is accepted with the Hero3 check showing PENDING.
- **The fin mapping.** `fins_max` stays 6, with 3 fins per side, and one wing_l blade always stays
  docked.
- **Item 6 (new): the alive check in `skill_input.gd`.** From the dead-mech finding: a dead mech's
  skill inputs do nothing. mech-move stays out of this file.
- **The Lance.** While you are in the Lance code, switch its shake top-up (`zenith_lance.gd:23-27`) to
  `Feel.shake_floor`.

## hud r6
- **The licence files ship.** The lead adds `ui/licenses/*` to `include_filter` in
  `game/export_presets.cfg` before dispatch. hud ships the composer plus a headless writer
  (`--out=`). The tooling unit wires that writer into `tools/godot.sh export`, so that
  `THIRD_PARTY_LICENSES.txt` lands next to the .app, never inside it.
- **Added items** (Requests routed from other units):
  - PAUSE gets a RETRY row (unpause, then `retry_game`);
  - GAME_OVER RETRY must not close its page before flow respawns (`menu_root.gd:295-297`);
  - pad B on GAME_OVER (`:252-262`);
  - the new `abort_to_title` signal for PAUSE → ABORT (see flow), while `quit_game` always quits;
  - GAME_OVER pauses the tree (`:96`), and the "W / S" footer hint (`menu_screen.gd:251`), from
    mech-move;
  - the lock_prev / lock_next glyphs (`hud_glyphs.gd:32`), from camera-aim.
- **The title path probe** is yours, under `ui/tests/`. A `{"key": …}` event for autoplay comes later
  from tooling.
- **The final audio credit strings** are in `status/audio.md`, Request 8 (audio r6, accepted). Use them
  verbatim.
- **The Poly Haven credit** is a textures-only row, unless city-art r16 item 3 keeps the sky plates.
  Check `status/city-art.md` before you finalise it.

## city-art r16
- **The tod 1.0 clip standard.** Sky, facades and decks stay ≤ 1.5 % at every time of day. At tod 1.0,
  true emitters (the strike at its peak, the tether, the neon) may clip up to the key art's ~8 %, but
  only when the clip is attributed per source. The A3st sign at 11.95 % is never acceptable.
- **Item 1's strictness stands.** A miss needs a stated cause, and V1–V3 may not miss.
- **The `post_lens.gd` grant stands.** If item 2's A/B pins the hatch on the lens grain, fix it there.

## city-layout r8
- **A6's third inbound route:** one runtime-free edge (stairs, ramp or edgejump) from a node the player
  can already reach. Pick it and justify it from the graph.
- **The connector runtime belongs to the new traversal unit**, not to city-build. Make the vent and
  vcat columns geometrically right.
- **Fold in the layout half of map-up-connectors-inert now:**
  - realign the 5 mid-air lift and vent endpoints vertically, or add landing decks;
  - give the A5_W5 vent its own pad;
  - declare deck holes for the sealed shafts;
  - turn the column check's NOTE into a FAIL.
- **Parapet openings.** Add an additive deck field `openings`, and add its schema line to `docs/MAP.md`
  §3 (granted).
- **The Knot.** Keep the datums: K3 stays at +32. The layout's decks and connectors become the Knot's
  collision, and city-build's `landmarks.knot` keeps only dressing.
- **The rng rule.** Every 3D fix is a cut or a filter that draws no random number. If one cannot be,
  stop and ask. Ship a per-key layout diff against r7.

## city-build r11
- **Notch Crown rib j=2** over the S4 pad and the S3n shaft, and dress the gap as the catapult well.
- **Adopt the movers format** you proposed: `layout.json["movers"]` rows plus `Mover_<id>` Area3D
  nodes. The lead adds the CONTRACTS entry; traversal reads it.
- **The gates.**
  - C17's VOID count is a hard gate at 0; the off-navmesh share stays informational.
  - C12 becomes hard for lifts, vcats, vents, lcats and stairs after item 6; edgejump and drop stay
    informational.
- **A connector that cannot be made to work** gets `usable: false` and a Request, and city-layout
  re-routes or drops its edge. `con_B1_A3_lift` is unusable this round.
- **No Crown opening over S4.** flow routes the arc outward.
- **A stairs flight steeper than 40° fails the build.** It must never become an invisible wall.
- **Leave `tools/city/*.sh`'s ROOT lines to tooling.**

## traversal r1 (new unit)
- **main.gd.** Add your one PARTS line, `["traversal", "res://world/traversal/traversal.tscn"]`, to
  `game/main.gd`, together with its header and `--stub=` entry, in the same commit as the scene
  (granted).
- **The movers format** is city-build's (see above).
- **The lcat control model:** a scripted arc, with boost refused for the first 1.5 s; after that a
  boost press breaks out with the arc's velocity. The F5→S4 lcat may fly a planned curved path round
  the trunk into the bay, if the sweep is clear within 6 s; city-build re-aims the rail.
- **The r1 bar:**
  - the runtime;
  - the three S4 routes, once city-build's rib commit and flow r5's pad commit land;
  - every other connector REACHED, or BLOCKED by a named blocker you have routed.

## tooling r1 (new unit)
- **Ownership grants:**
  - `game/core/{input_setup,pad_input,input_quad}.gd`;
  - the ROOT one-liners in `tools/city/*.sh` and `tools/citykit/*` (only those lines);
  - the autoload line for `input_quad` in `game/project.godot` (one line);
  - the THIRD_PARTY_LICENSES writer call in `tools/godot.sh export` (see hud).
- **The capture-tool clocks** (camera-aim r8, Request 6): `tools/godot.sh shot` times `--pulse` and
  `--times` on different clocks, about 1.1 s apart. Put both on one clock in `game/tools/capture.gd`,
  and add a test.
- **App identity:** copyright "© 2026 erapi0neer", bundle id `xyz.erapi0neer.tianshu`, version 0.1, no
  icon.
- **The scrub.** Fix only the files you own or were granted. List every other hit by owner. Leave the
  process docs (briefs/, reviews/, ref/) alone.

# Round 2 decisions (after the brief critics, 11-05 08:38)

## mech-move r7
- **Gates must not be masked by the GAME_OVER pause.** hud r6 makes GAME_OVER pause the tree. Your
  "a dead mech does not move or fire" gates must still prove something once it does, so measure the
  corpse with the menus out of the way:
  - the headless pipeline test (no HUD);
  - drives with `--stub=hud`;
  - at least one windowed drive run before hud r6 lands.
- **The dead-input list must match the live baseline.** The live baseline must press every input the
  dead list checks: `1`/MOUSE4, the wheel, Tab/MMB, and V held 0.25 s (overdrive). Add a Targetable to
  the test scene so `lock_changed` can fire while alive. Also check a corpse's air-melee hold (plunge),
  V and the Lance.
- **The weapons guard line is revoked** in weapons r5 too; the lead tells the weapons worker.

## enemies r11
- **"Full attack tokens" = the pool at capacity:** every slot is held, or shut by the re-grant delay,
  while another monster of that kind is asking. The lead updates the wording in SPEC §7.1.
- **Foreign check errors do not block you.** Errors from `enemies/boss/**` (flow is editing it) or
  `enemies/models/**` (monster-assets) in your `check --only=res://enemies/` run go in Requests with
  their attribution.
- **A round the catch field has held never counts as a near miss.**
- **NEAR_MISS_RADIUS** stays 6 m from the hurtbox.

## hud r6 — gates for the added items (each needs a probe run or a test)
1. **The PAUSE RETRY row:** PAUSE → RETRY → flow respawns at the checkpoint, and the HUD is back
   within 1 s.
2. **GAME_OVER RETRY** keeps the page until the respawn has happened. A RETRY with no checkpoint never
   closes the page.
3. **Pad B on GAME_OVER** never closes the page without a respawn.
4. **`abort_to_title`:** PAUSE → ABORT reaches the title, and `quit_game` from every other screen still
   quits.
5. **GAME_OVER pauses the tree:** enemies and projectiles freeze behind the page.
6. **The W/S footer** reads right.
7. **The lock_prev/next glyphs** read right: show them on a contact sheet.

Also:
- **hud r6 takes the CONTROLS page** (flight, the Lance, pause, F11 are missing): same file, separate
  commit.
- **When your test_hud engine error is fixed**, say so in Requests. tooling removes the matching
  KNOWN-ERROR entry.
- **A new run after ABORT → START** resets the HUD's tutorial retired set, so it is a fresh tutorial.

## traversal r1
- **Read city-build's movers export:** `layout.json["movers"]` rows plus `Mover_<id>` Area3D nodes in
  group `&"mover"`. Until city-build lands it, build against a stub with the same schema, generated from
  `city_layout.json` connectors.
- **Your gates must boot `main.tscn` with traversal in PARTS** (granted). Loading `city.tscn` alone
  does not count.
- **The 3 m lift pad lip:** city-build r11 lowers it to ≤ 2.0 m. Until then a ride may log
  `board=hop` and still count as REACHED.
- **Connector tops with no floor** (S5_S3n, F3_F6, M6b_M4, M1_M5, A5_W5) are BLOCKED by a named
  blocker this round.
- **New suites:** post a Request to tooling, which owns `tools/suites.sh`, to add your rows.

## city-art r16
- **The settle stamp covers the props too:** add `game/world/props/meshes/*.glb` to the content stamp.
- **The re-bake rule:** re-bake right after your fingerprint commit, so the shared tree is never left
  stale. After that, whoever changes a settle input (city-kit props, city-build geometry) re-bakes.
- **The fresh-checkout gate.** Do not run a full import in a fresh worktree: it holds the only import
  slot for up to 40 minutes. Prove the stamp with a unit test instead: touched mtimes leave the stamp
  unchanged, and changed content changes it. The lead runs the clean-checkout export gate at the end of
  the round.

## skills r4 — item 6, the alive check in `skill_input.gd`
- **The defect:** a dead mech's skill inputs act. Plunge (an air melee hold), overdrive (V held), the
  Lance and every press-edge skill skip `can_act()`.
- **Done:** while dead, none of them changes skill state, EN or cooldowns, or emits an event.
- **The gate:** a test with the mech dead that presses every skill input. It fails on HEAD and passes
  after.

## skills r4 — the Lance during ignition
A Lance press during the 0.45 s overdrive ignition (LOCKED) is held and fires when the ignition ends.

## tooling r1
- **App Nap:** a per-process route is preferred. If that cannot work, a persistent
  `defaults write org.godotengine.godot NSAppSleepDisabled -bool YES` is acceptable on this dev Mac.
- **Always-on-top windows** are a last resort, only for slot-held capture runs, at a small corner size.
  The user works on this Mac.
- **The capture clocks** pair with item 2: same file, `capture.gd`.
- **Add a `{"key": …}` autoplay step** this round.
- **The input quad** gets an explicit CONTRACTS §3 exception: it may read raw input. The lead adds the
  line.
- **Gate 7:** keep the full `check`, and attribute any foreign in-flight errors.

## city-layout r8
- **A6's third inbound edge:** `con_F3_F4_vcat`, from the Tower Lift Lobby F3 (-120,-360,0) onto the
  Sky Garden F4. It is a vcat with Δz 144, and traversal builds its runtime. The A6 in-engine gate
  accepts it as PENDING-RUNTIME until traversal lands.
- **The H3 crane cab collider:** city-build r11 moves it under the deck (z 40–48). Your sweep exempts
  `con_A1_H3_stairs` with a pointer to that fix.
- **`kit_assign.json`:** city-kit r11 re-runs `assign.py` after layout r8 lands, so do not wait for it.

## city-build r11 (additions)
- **Lower the 3 m lift pad lips** to ≤ 2.0 m, or give them a ramp. The mech's step height is 2.5 m.
- **Move the H3 crane cab collider** under the deck (z 40–48).

## feel r5 (addition, 11-05 08:51): the gatling vent rows from weapons r5
weapons r5 committed `combat/weapons/tests/test_feel_rows.gd`. It is red (9 of 13 checks fail) until
three FEEL rows exist. Their content is in the Requests section of `status/weapons.md`.
- Add the three rows to FEEL.md and their `.tres` files in one commit, under your FEEL.md grant, so that
  `test_feel` and `test_feel_rows` both go green.
- audio adds the matching `FEEL_IDS` / `OVERRIDES` entries in its next round.
- tooling allow-lists `test_feel_rows` as KNOWN-ERROR `gatling-vent-good-unknown-feel-id` until your
  commit lands.

# Round 3 decisions (the feel r5 critic, 11-05 09:15)
## feel r5
- **`boss_kill`'s other columns** (shake, flash, VFX, sound, rumble) are `kill_large`'s.
  `boss_kill`'s global stop does not count against the kill_large 2 s window: the boss death is the
  climax.
- **The `kill_small` row.** No FEEL.md edit is needed: FEEL.md:42 already reads "local 40 ms (victim
  only)". Mark the "G 40 ms for the LAST enemy of a wave" clause as deferred (wave_clear).
- **The boss switch.** If flow r5 has finished before your `boss_kill` commit lands, make the one-line
  switch at `brood_titan.gd:282-283` yourself. That single line is granted under boss/**.
- **mech-move's early `Feel.play(&"last_stand")`** (15657b0) is accepted. It warns until your item 0
  lands, so land item 0 first.
- **CONTRACTS §3.** Post the final `Feel.play(id, at, strength, actors)` signature in Requests; the lead
  updates CONTRACTS.
- **Dispatch now.** Do the rows (item 0) first. Hold the `enemy_base.gd` edit and the enemies-suite gate
  until enemies r11's commits land.
## audio r7 (later)
- Add the `FEEL_IDS` / `OVERRIDES` entries for `last_stand`, `boss_kill` and the three gatling vent ids,
  and `gatling_vent_good → gatling_vent` in `event_map.gd`.
