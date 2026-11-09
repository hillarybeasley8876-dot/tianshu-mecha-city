# feel r5 — lead brief: kills hit hard without freezing the world

## Why
Acceptance found that every Ripper kill within 120 m of the camera freezes the whole game, and every large kill
freezes it and then slows it. A gatling burst through a pack stutters (12 kills, 8 world freezes), and each freeze
also stalls the gun's fire rate (`weapon_system.gd:120` runs on `Feel.player_delta`). Swarm fights should feel best
and hitch most: the biggest 爽感 regression in the demo. Kills must still land hard (victim holds and vibrates;
fireball, shake, flash, confirm all fire), but the world keeps running: global stops only where FEEL.md marks G. Also:
the dash and the perfect dodge never ghost, and the gallery's stills miss short effects. Findings were made on a
frozen copy at `b5d26d4`; re-check each against HEAD first (at 2e99e8d, `game/fx/**`, core's `feel.gd`,
`enemy_base.gd` and `docs/FEEL.md` are still identical to it; flow r5, weapons r5 and mech-move r7 have since moved
`game/flow/**`, `brood_titan.gd`, `weapon_system.gd` and `player_mech.gd`, and every line number here is 2e99e8d's).
If one is already fixed, say so, with evidence. Order: item 0 first (four rounds wait on its rows), then items 1–3;
the `enemy_base.gd` edit goes last, after enemies r11's commit (conflict map D1, D2, D4).

## 0. The FEEL rows other units wait on (do these first)
**Why first.** weapons r5's `combat/weapons/tests/test_feel_rows.gd` is committed red (25c0963: `TEST 13 checks,
9 failed`; tooling allow-lists it as KNOWN-ERROR `gatling-vent-good-unknown-feel-id` until your commit); mech-move r7
already calls `Feel.play(&"last_stand")` (`mech_damage.gd` `_last_stand()`, 15657b0), which warns "no FeelEvent" until the row
exists; flow r5 switches the boss death to `boss_kill` once it lands. FEEL.md is granted to you for these rows. Each
row lands in ONE commit with its `.tres`, so `test_feel`'s row count (`test_feel.gd:65`) stays green.
- **Do:**
  1. The three gatling rows, one commit: `gatling_vent_good`, `gatling_overheat`, `gatling_jam`, with the content in
     `status/weapons.md` Requests (first bullet, FEEL.md column order). The good vent's `audio` names a bank sound,
     e.g. `gatling_vent_hiss` (→ `gatling_vent`, `audio/tables/table_aliases.gd:29`), never `gatling_vent_perfect` or
     `ui_vent_chime` (weapons' constraint): the router has no `gatling_vent_good` sound until audio's `OVERRIDES`
     entry, so the row's own layer is what passes `vent.good_requests_a_sound` (`test_feel_rows.gd:66-68`).
  2. `last_stand`, one commit: a FEEL.md row (slow-mo 0.5× 1.5 s, 60 s CD, witch off), `last_stand.tres`
     (`slow_scale` 0.5, `slow_seconds` 1.5, `cooldown` 60, `slow_witch` false), and the slow-mo cell moved out of
     `hurt_heavy` (FEEL.md:40 → "—"). The trigger (a hit that crosses below 15 % HP and leaves the mech alive) is
     mech-move's.
  3. `boss_kill`, one commit: G 150 ms + the boss's 0.2×/1.2 s slow-mo, exempt from kill_large's budgets (item 1,
     Do 3). flow's switch replaces both boss-death calls (`brood_titan.gd:282-283`), so the row's other columns carry
     what kill_large gives that death today, unless the lead says otherwise.
  - Not yours: `audio/event_map.gd` (`FEEL_IDS` / `OVERRIDES` come in audio's next round). Until then the router
    warns once per new id ("unknown or empty sound id"); file `last_stand` and `boss_kill` for audio as Requests (the
    vent ids are already in `status/weapons.md`).
- **Gate:** `test_feel_rows.gd -- --audio-trace` → `TEST 13 checks, 0 failed` (HEAD: 9 failed); `test_feel.gd` PASS
  after each commit; two `test_swarm.gd` checks (item 1): `last_stand` holds 0.5× ± 0.02 from 0.1 s to 1.3 s real and
  is back to 1.0 by 1.6 s, and a second play inside 60 s changes nothing (mech-move r7's own gate runs on this row);
  `boss_kill` 0.5 s after a kill_large's global stop still gives one ~150 ms global stop and holds 0.2× to 1.2 s.
  Post each commit in `status/feel.md` the day it lands (mech-move, weapons and flow watch it) and tell tooling, which
  drops the KNOWN-ERROR entry.

## 1. Swarm kills freeze the world (major)
**Defect.** `kill_small.tres:8` still has `hitstop_kind = 2` (GLOBAL); the row (2b98f2d) predates the lead's change of
FEEL.md:42 to "local 40 ms (victim only)" (37e66d6). So `feel_director.gd:136-144` calls `Feel.hit_stop(0.04·f)` on
every small kill, capped only by core's limiter (`core/feel.gd:63-77`: 150 ms apart, 3 per second). kill_large
freezes 100 ms·f and slows to 0.35× for 0.35 s on every mantis/spitter/harrier/juggernaut kill (`enemy_base.gd:281`):
FEEL.md:43's budgets (≤ 1 global stop per 2 s, ≤ 1 slow-mo per 6 s) exist nowhere (only a 0.3 s row cooldown), the
slow-mo ignores distance (`feel_director.gd:79` passes `s`, not `s·f`), and nothing plays the wave-final "G 40 ms"
(deferred this round, see below).
- **No victim-local stop exists either:** no gameplay code calls `FeelDirector.hitstop_seconds()`; gunfire kills get
  no pause (`enemies/damage.gd:41-50` returns 0 for BALLISTIC/BEAM); a dead enemy never counts `_pause_left` down or
  ticks its vibration (`enemy_base.gd:288-291` goes straight to `_tick_wreck`, :334-354); and the 0.05 s row cooldown
  (`feel_director.gd:68`) drops 5 of 6 plays when a salvo kills 6 in one frame.
- **Found while writing this brief** (code reading; reproduce it first): `Feel.slow_mo()` (`core/feel.gd:88-96`)
  replaces the running slow-mo, so a kill_large in witch time ends witch time, and the boss death's own 0.2×/1.2 s
  slow-mo (`brood_titan.gd:282`) is cut to 0.35 s by the kill_large it plays next (:283).
- **Repro (live tree):** the `acc_swarm.gd` lines of the acceptance block under Gates; at b5d26d4 they printed 4 FAIL
  lines and `SWARM FAIL` (verifier logs: `~/m/mc-accept/tmp/acc/verify-feel-swarm-kills-global-freeze/`).
- **Granted to you this round** (lead decisions, "feel r5"; core's `feel.gd` stays the lead's file otherwise):
  (a) `Feel.play(id, at, strength, actors: Array = [])` with a 4-argument signal the director connects to instead of
  `event_requested`, which core keeps emitting (3 arguments) for audio's router (`audio/audio.gd:137-138`) and
  enemies' near_miss; (b) `Feel.slow_mo` combines instead of replacing (each request keeps its own clock, scale = the
  min, a non-witch request never ends witch time). Post the final `play()` signature in Requests: CONTRACTS §3 is the
  lead's to update. `wave_clear` is deferred (lead decision): build no wave-final stop; FEEL.md:42 already says local,
  so the `.tres` flip needs no FEEL.md edit. `boss_kill` is item 0.
- **Do (= what done means):**
  1. `kill_small.tres` → LOCAL. The verifier flipped only this field: 12 gatling-pace kills, 8 freezes → 0.
  2. The director runs a LOCAL row's stop, `Feel.local_hit_stop(actors, s)`, on the play's actors, even when the row
     cooldown drops the visuals; distance never shortens it. `_die` (`enemy_base.gd:281`) passes `[self]`: the
     victim only, no hero stop on a ranged kill (FEEL.md:6, "gunfire never freezes"). While `_pause_left` runs, the
     dead branch holds the collapse and death action and ticks the vibration ("frozen + vibrating", FEEL.md:7).
     Melee kills keep the attacker-and-victim stops their rows already have (`melee_strike.gd:44`).
  3. kill_large budgets, in the director: a global stop only if none was accepted (`Feel.hit_stop` returned true; the
     director is its only caller) in the last 2 s of `Feel.real_now()`, else the victim's 100 ms goes local; slow-mo
     at most once per 6 s; past half the falloff (f < 0.5, beyond 100 m), local stop only. flow's plays
     (`hive_spire.gd:207`, `hive_collapse.gd:106`) take the same budgets.
  4. `boss_kill` (item 0) is exempt from these budgets; flow r5 makes its call (Coordination).
- **Gate — new headless suite `game/fx/tests/test_swarm.gd`,** set up like the verifier's `acc_vfy_probe.gd`: core
  sandbox, real FeelDirector, `EnemySpawner` (`auto_spawn = false`), `enemies/tests/dummy_player.gd`, a Camera3D
  14 m behind and 7 m above it. Kill through `EnemyBase.take_hit(HitInfo.make(hp_max * 3, HitInfo.BALLISTIC, …))`,
  the gatling's own path (`projectile_manager.gd:162`); sample `Engine.time_scale` every rendered frame.
  - Rippers, 12 one per 0.20 s, two 6-in-a-frame salvos 0.30 s apart, 8 one per 0.45 s: no frame below 0.9; every
    victim (the salvos' too) holds its wreck and vibrates 40 ms ± 1 tick, then collapses.
  - 4 mantis one per 0.6 s: ≤ 1 global stop and ≤ 1 slow-mo, the other 3 victims hold 100 ms locally; 3 juggernauts
    2.5 s apart: ≤ 1 slow-mo; a kill_large 150 m away: neither. A mantis killed in witch time leaves
    `Feel.is_witch_time()` true to its natural end; a 0.2×/1.2 s slow-mo then a kill_large still lasts 1.2 s.
  - Item 0's `last_stand` and `boss_kill` checks.
  - It FAILS before your fix and PASSES after it; paste both outputs in your status file.
- **The movie the lead watches:** `fx/tests/swarm_feel.tscn` (+ script, + a `swarm_timeline.json` that only ends the
  run): the real `main.tscn` in the sandbox with the real camera rig (built as `acc_vfy_ingame.gd` does); the
  suite's rounds 25–55 m ahead (gatling string, salvo, 4 mantis); on screen the round, the
  live `Engine.time_scale` and a 3 s strip chart. Film it before and after your fix (commands under Gates).

## 2. The dash and the perfect dodge never leave afterimages (minor)
**Defect.** FEEL.md:31-32 gives dash "plume + 3 afterimages" and perfect_dodge "afterimage ×3"; neither row spawns
any. `dash.tres:18` lists only `thruster_burst`, `perfect_dodge.tres` has no vfx, and only skills ghost
(`zenith_overdrive.gd:107`; Rift Step `rift_step.gd:180,263` via `skill_fx.gd:76-80`).
**Repro:** `grep -n vfx game/fx/events/{dash,perfect_dodge}.tres; grep -rn --include='*.gd' -e '\.afterimage(' game | grep -v /tests/`
- **Do:** an afterimage count (+ spacing, lifetime) on FeelEvent; dash = 3, perfect_dodge = 3. The director ghosts
  `Game.player.model()` (`player_mech.gd:288`) through `vfx.afterimage()` (`vfx_library.gd:192`), spread along the
  motion (a dash lasts 0.25 s): three on one pose is the Overdrive r2 blob (`zenith_overdrive.gd:98-101`). No player
  or model: nothing, silently. Ghosts copy their source's `layers` (`afterimage_pool.gd:43-58` does not): first
  person hides the hero's body by layer (`camera_hero_cull.gd:39,53`), so a default-layer ghost would draw it over
  the cockpit view. The gallery's placeholder mech stands in as the player, so its dash and dodge rows ghost too.
- **Gate:** a `test_feel.gd` check with a stand-in player whose model moves between spawns: dash and perfect_dodge each
  leave 3 live ghosts at 3 distinct positions, each with its source's `layers` (FAILS on HEAD: 0 ghosts). Stills of a
  dash and a perfect dodge in third person, and a dash in first person with no ghost on the lens: e.g. take `c_dodge`
  (`trailer/tl_c_dodge.json`: dash 1.2 s, `debug_perfect_dodge` 1.5 s; flags in `shots.json`, minus the rig) via `drive --shots=…`.

## 3. The gallery's stills land late and miss the short effects (minor)
**Defect.** Two clocks: `feel_gallery.gd:55,66` schedules rows on wall time (`Time.get_ticks_usec()`), while
`game/tools/capture.gd:74-75` counts scaled frame time and starts only after the world wait and `--warm` frames
(:53-66). The fixed `FX_LEAD = 2.0` (`feel_gallery.gd:25`) measured 1.24 s at the start and 1.68 s at t≈46 (the rows'
own slow-mos stretch the capture clock): stills land 0.4–0.6 s late and miss every effect under 0.3 s, and the wall
clock also breaks the gallery movie and CONTRACTS §3 (clocks). Evidence: in
`~/m/mc-accept/captures/acc_suites_feelgallery_t1_15.jpg` the label reads `t 2.39` at capture t 1.15, nothing fired;
`~/m/mc-accept/game/tmp_accept/suites/acc_feel_frames.gd` (frame-locked) shows they do: `…/acc_suites_feel2_zoom_rows01-08.jpg`.
**Repro:** `tools/godot.sh shot --scene=res://fx/tests/feel_gallery.tscn --out=feel_r5_drift --fx=missile_hit@1.0,kill_large@3.0 --times=1.0,1.15,3.0,3.15`
→ in `captures/feel_r5_drift_t1_0.jpg` the `t …` label reads well past 1.0 and there is no blast yet.
- **Do:** the schedule runs on `Feel.real_now()`; the gallery takes its own stills as `acc_feel_frames.gd` does (reset
  rate limits, set the label, `Feel.play`, save after `frame_post_draw` 1 and 4 rendered frames later, as
  `<nn>_<id>`), run windowed through `tools/godot.sh drive` on the gallery scene with `fx/tests/gallery_timeline.json`
  (put the exact command in your status's How to verify); `FX_LEAD`, `--fx-lead` and whatever else this makes dead
  are deleted.
- **Gate:** a still per row at frame 4 plus frame 1 (1–2 f flashes, B/W frames), label = file name, the row's
  particles/ring/flash visible: 49 rows (44 + item 0's five), on sheets of 8 rows. A `test_clocks.gd` check that the
  gallery clock reads 2.0 s after 240 frames at `--fixed-fps 120` (fails on the wall clock). The gallery movie fires
  a row every 1.5 s of movie time (`sheet.py --every 1.5`).

## Gates
Each new test FAILS on HEAD and PASSES on your change (both outputs in the status file, beside the test host's commit:
the stricter host, which fails a suite on any SCRIPT or engine ERROR, is live since 317d03c; file any deliberate
`push_error` with its exact message as a Request to tooling). For the HEAD run, copy your
file aside, then `git show HEAD:<path> > <path>`; never `git stash` (the stash stack is shared by every worker).
```
tools/godot.sh test res://fx/tests/test_swarm.gd     # new: TEST feel swarm: PASS
tools/godot.sh test res://fx/tests/test_feel.gd      # + the afterimage checks
tools/godot.sh test res://fx/tests/test_clocks.gd    # + the gallery clock check
tools/godot.sh test res://combat/weapons/tests/test_feel_rows.gd -- --audio-trace   # TEST 13 checks, 0 failed
tools/suites.sh --only=enemies_status,enemies_projectile,enemies_audit,enemies_spawner_mix,enemies_spawner_none,main_spawn_r6,main_spawn_none,main_spawn_stub,enemies_fight,enemies_ai,boss,boss_city
tools/godot.sh check --only=res://fx/,res://enemies/  # 0 errors, 0 warnings
```
The `suites.sh` line runs every enemies row of `tools/suites.txt` with its flags (`test_ai` and `test_fight` need
`--timeout=400`, `test_main_spawn` needs `--sandbox`), plus the boss rows (`brood_titan.gd:197` runs EnemyBase's
dead branch); add any row enemies r11 adds. Judge it by the rows: an `UNLISTED` line (your own `test_swarm.gd`
until tooling adds its row) fails the exit code but is not a red. Run it after enemies' r11
commits (D2): a red that appears without your change is its owner's, and so is a `check` error from
`enemies/boss/**` (flow) or `enemies/models/**` (monster-assets); attribute those in Requests.
The lead re-runs the acceptance probes on the live tree (`game/tmp/` is git-ignored). They call the director's `event()`,
`falloff_factor()` and `reset_rate_limits()`, so keep those:
```
mkdir -p game/tmp/acc && cp ~/m/mc-accept/game/tmp_accept/suites/acc_swarm.gd game/tmp/acc/
tools/godot.sh test res://tmp/acc/acc_swarm.gd                       # SWARM PASS
cp ~/m/mc-accept/game/tmp_accept/verify-feel-swarm-kills-global-freeze/acc_vfy_{probe,ingame}.gd game/tmp/acc/
tools/godot.sh test res://tmp/acc/acc_vfy_probe.gd -- --timeout=280  # A freezes=0, C <=1/<=1, D slow<=1, E 0
tools/godot.sh test res://tmp/acc/acc_vfy_ingame.gd -- --timeout=280 --sandbox --skip-menu --no-enemies --god --stub=hud,boss,post
rm -rf game/tmp/acc                                                  # acc_vfy_ingame prints INGAME PASS
```
**Captures** (paths in `status/feel.md`): the swarm movie before and after, with a sheet; the real gun after the fix
(before: `captures/trailer/shots/c_gatling.avi`); the swarm scene under `drive --frametimes` is the real-time watch.
```
tools/godot.sh movie --movie=$PWD/captures/feel_r5_swarm.avi --movie-size=1600x900 --scene=res://fx/tests/swarm_feel.tscn \
  --timeline=res://fx/tests/swarm_timeline.json --sandbox --skip-menu --no-enemies --god   # before the fix: feel_r5_swarm_before.avi
TRAILER_SIZE=1600x900 tools/trailer/record.sh $PWD/captures/feel_r5_c_gatling.avi res://trailer/tl_c_gatling.json \
  --scene=res://trailer/shot.tscn --trailer-rig=res://trailer/rig_c_low.json --skip-menu --god --tod=0.6 \
  --stub=flow --spawn=-60,155,450,225 --trailer-pack=22,ripper:5,mantis:1 --trailer-hud=1
python3 tools/trailer/sheet.py captures/feel_r5_swarm.avi -o captures/feel_r5_swarm_sheet.jpg --every 0.25
```
Also the item 2 and 3 stills and sheets. House rules: split a file over 600 lines first (own commit); no dead code;
explicit-path commits, with `git diff -- <file>` first on `docs/FEEL.md` and `enemy_base.gd` (another unit's hunk
there: wait or ask); post `test_swarm.gd`'s suites row (path, flags) to tooling the day it lands; no `/Users/` path
under `game/` (`acc_feel_frames.gd:10` has one: do not copy it); a probe that runs another unit's live code names
that unit's commit and dirty files; an r5 section in `status/feel.md` (causes, FAIL→PASS lines, captures); no
"fixed" without a rerun.

## Coordination
- **flow** (r5) fixes blockers in parallel; do not edit `game/flow/**` or `enemies/boss/**`. `wave_clear` is deferred
  (lead decision), so no wave-final call goes to flow this round.
- **The boss death** is flow's to switch (its decision 6, under its boss/** exception): once your `boss_kill` commit
  lands, `brood_titan.gd:282-283` (the 0.2×/1.2 s `Feel.slow_mo` and the `kill_large` play) become
  `Feel.play(&"boss_kill")`. Until then the boss death takes kill_large's budget.
- **enemies** r11 edits `enemy_base.gd` in parallel (`_ready` :57-87, `recycle` :410-413). Your exception covers only
  `_die` (:281) and the dead branch (:288-291, `_tick_wreck` :334-354): do that edit last, after enemies' r11 commit
  is in, so neither of you commits the other's hunks; record it in `status/feel.md` and tell enemies in Requests. If
  enemies split the file first, the lead re-points these lines (D1). If the file would pass 600 lines, stop and file
  a Request (the split is enemies'). Every enemies suite must still pass.
- **Rows other units need from you this round** are item 0: `last_stand` (mech-move r7), `gatling_jam`,
  `gatling_overheat`, `gatling_vent_good` (weapons r5) and `boss_kill` (flow r5). You write each FEEL.md row, in the
  same commit as its `.tres`.
- **skills:** the `layers` fix also changes the Overdrive and Rift Step ghosts; tell them in Requests. **trailer:** its
  takes and `tools/trailer/**` are read-only for you; never write into `captures/trailer/`. Requests: `status/feel.md`.

## Lead decisions (read first)
`reviews/r16-lead-decisions.md` holds the lead's dispatch decisions. Read its "Shared" section, and every section that names this unit, including those under "Round 2". Where a decision and this brief differ, the decision wins.
