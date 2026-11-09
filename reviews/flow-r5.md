# flow r5 — lead brief: death, respawn and checkpoints are bullet-proof; the E2E bot plays for real

## Why
The acceptance pass (frozen copy at `b5d26d4`) found three ways to strand the player (die before the district opens, die
in boss phase 1, fall off an open tunnel end), a dead PAUSE → ABORT, respawns that re-arm cleared arenas and revive the
hero behind the boss's death page, and an E2E bot that never fires at a hive. The code is unchanged since `b5d26d4`, but
re-check each item at HEAD first; if one is already fixed, say so in your status with the run.

## Rules for this round
- Evidence: `~/m/mc-lead/accept/findings_all.json` by heading ids (its `check` block wins). Gates take the real path: a
  lethal hit via `PlayerMech.take_hit`, no `--god`, RETRY as a real `ui_accept` on the page (FlowDebug `die`/`respawn`,
  `flow_debug.gd:245-250`, are repros only). New tests FAIL on HEAD, PASS after; no "fixed" without the rerun. Split
  before a file (e.g. `flow_debug.gd`, 457) passes 600, own commit; explicit path lists; no dead code; r5 in `status/flow.md`.
- Fixture `<x>`: copy `<x>.json` + `<x>_drive.json` from `~/m/mc-accept/game/tmp_accept/flow-e2e/` to `game/flow/tests/`
  (JSON only: `check` loads every script in `res://`), then `tools/godot.sh drive --skip-menu --nan-watch
  --timeline=res://flow/tests/<x>_drive.json --flow-script=res://flow/tests/<x>.json --out=r5_<x>`. Order: 1–6, 7, 8, 9.

## 1. A death before the district opens soft-locks the run, and no respawn snaps the camera — blocker [flow-cp-tutorial-death-softlock, flow-tutorial-death-softlock; flow-cp-respawn-camera-not-snapped, minor]
The only `&"start"` save is in `_enter_district` (`game_flow.gd:224-225`); `respawn()` (`:307-311`) closes the page and
ignores `progress.respawn()` returning `&""` (`flow_progress.gd:176-179`); `_on_respawned` lifts any resume to DISTRICT
(`game_flow.gd:322`). A tutorial death leaves an HP-0 hero, no page, no HUD, `game_over` for good; `suite_states.gd:27`
asserts it. `_restore_player` (`flow_progress.gd:195-204`) never calls `snap_to_player()` (`camera_rig.gd:410`; it takes
the hero's yaw, `:422`), so the camera crosses the city. **Repro:** fixture `cp_tutorial` → `no checkpoint yet`.
- **Done:** a start checkpoint saved as the tutorial starts (landing or `--spawn`) resumes `tutorial`, A1 at wave 1; with
  none, `push_error` + `FlowWorld.player_start()`. Every respawn sets the saved facing, then snaps. **Gate:** die in A1,
  RETRY → within 1 s `tutorial`, HP/EN full, i-frames, HUD up, camera ≤ 60 m from the hero at once; clear A1 → `district`.

## 2. BOSS starts mid-catapult, boss_p1 is saved inside the Crown deck, the pad hint never clears — blocker [flow-boss-p1-checkpoint-midair-strands-hero; lead item b = refuted map-s4-catapult-pad-unreachable, verifier part 2; flow-cp-boss-respawn-stale-catapult-hint, flow-stale-catapult-hint-in-boss-fight, minor]
The S4 arc (`ascension_catapult.gd:174-191`) crosses deck tiles, where `is_on_floor()` is true, so `crown_gate.gd:75-83`
fires mid-flight and `_enter_boss` (`game_flow.gd:252-254`) saves the live transform, buried between the deck (224) and the
ring above (232). The pad never re-arms (`ascension_catapult.gd:141`, `:196-207`); p2/p3 also save live transforms
(`game_flow.gd:282-284`). Lead item (b): `_zone_or` (`crown_gate.gd:58-63`) uses zone nodes 20 m above their floors
(`city_markers.gd:145`), so the pad floats in a Crown rib, out of reach, and B1 lands the hero on the core top. The pad
`HINT` (`game_flow.gd:244`) never clears. **Repro:** fixture `cp_district_boss` → the phase-1 RETRY buries the hero.
- **Done:** BOSS starts on a real deck touchdown only (not `flying` or LOCKED, feet ray on the deck, no overlap), by
  catapult or flight, and clears the hint. Checkpoints save probed standable points, never mid-air or buried ones (boss:
  e.g. the director's `ring_point`, `boss_director.gd:189`). The swept arc hits nothing; the pad re-arms. Pad at the S4
  zone point −20 m (y 160–162); landing −20 m too, but B1 is the Ø80 m core's axis: end the arc over the fighting floor.
- **Gate:** a real step onto the pad launches grounded ≤ 12 m from its centre, landing on the deck. Die in each phase,
  RETRY → within 1 s no overlap, deck ≤ 1 m below, camera clear, titan in frame, then walk to 40 m of it (not via
  `assault_boss`: it teleports). Suite: no `reached_crown` mid-flight; boss_p1 on the deck; no hint in `boss`, ever.

## 3. The titan's own summon flings it 68–134 m in one tick; nothing bounds its height — blocker [boss-titan-leaves-crown-after-phase3-restore]
Not the restore: the `AddSpawner` is the titan's child (`brood_titan.gd:71-75`) and `EnemySpawner.spawn()` parents an add
before placing it (`enemies/spawner.gd:93-94`), so new adds become its floor and fling it as platform velocity;
`_stay_on_the_deck` (`brood_titan.gd:199-212`) clamps the radius, not the height. **Repro:** every fight's first summon
(≈14.8 s in `boss_check`), ≈1.2 s after a death (`:385-386`). Without `Layers.ENEMY` in `platform_floor_layers`, no fling.
- **Done:** in `game/enemies/boss/**`, adds spawn off its footprint and never become its floor; the clamp bounds the
  height; the `--boss-hp-scale` pool survives a restore (`:360`). **Gate:** a per-tick tracker in a boss test (model:
  acceptance `titan_track.gd`) over `boss_check`, a death per phase and 20 forced `titan.demand(&"titan_summon")`:
  ≤ 1 m per tick beyond its walk; |y − 239| < 20 m and r ≤ 132 for 30 s after each RETRY.

## 4. A boss-fight death gets two respawns, the first behind the page — major [boss-cp-double-respawn-behind-death-page; boss-cp-phase-restore-deck-and-adds, minor]
`BossDirector._on_player_died` (`boss_director.gd:317-333`) restores the titan with its AI on, moves the hero 127–179 m and
heals it under MECH DESTROYED; the mech fights on behind the page, then RETRY moves it again. Flow never restores the
titan (`boss_phase`, `checkpoint.gd:12`, is never read). Minor, unverified: the restore always mends the rim
(`boss_director.gd:322-323`): phases 2/3 run on a phase-1 deck, and adds survive. **Repro:** fixture `cp_district_boss`.
- **Done:** the boss leaves a dead hero where it fell; flow's RETRY is the one respawn, and a hook it calls (duck-typed
  like `roar`; an `Events` signal would be the lead's) restores phase N at `phase_start_hp(N)` with its rim and no adds;
  rewrite `test_boss_city.gd:128-141`. **Gate:** a lethal hit per phase → hp 0 for 8 s, 0.0 m moved, HUD hidden; RETRY
  by key moves the hero once, full HP/EN; titan at phase N and `phase_start_hp(N)`, rim broken for N ≥ 2, no adds.

## 5. Falling out of the world is permanent, and PAUSE has no way out — major [map-u5-tunnel-open-end-fall, flow's half; lead item a]
Off the open U4/U5/U6 tunnel ends (caps: city-build) the mech falls to −3,000 and nothing notices; the only catch is the
Crown's, in the fight (`boss_arena.gd:212-233`). PAUSE has no RETRY row (`menu_root.gd:117-124`), and ABORT emits
`quit_game` (`:298-301`), which nothing connects (`game_flow.gd:114-119`). **Repro:** flow script `wait_state tutorial`,
`teleport [0, -200, -330]`, `state` 5 s later → still falling; Esc → ABORT → Enter → still PAUSED.
- **Done:** feet below −120 (the lowest floor is the −40 tunnel deck) or past `bounds` (`world/city/layout.json`; log the
  margin) → the RETRY respawn within 2 s, the Crown's catch left alone. Flow connects `quit_game`, but only ABORT from
  PAUSE goes back to the title (unpaused): QUIT elsewhere still quits, and hud r6 is reworking those emits, so agree the
  meaning in Requests. `respawn()` works from any state, for hud's row. **Gate:** flow on, no `--god`: the teleport and a
  real boost off the open U5 pad each respawn within 2 s, HP/EN full; PAUSE → ABORT → title in 2 s; START → 0/3.

## 6. Every respawn re-arms the arenas the player already finished — major [flow-cp-cleared-arenas-rearm]
`FlowProgress.respawn` resets every arena (`flow_progress.gd:185-188` → `encounter_director.gd:336-350`), the checkpoint
keeps only `spires_down` (`checkpoint.gd:10`), and district checkpoints sit inside the arena just won (`game_flow.gd:225`,
`:231`): RETRY re-enters it and `_on_arena_entered` (`encounter_director.gd:215-217`) restarts wave 1 within 0.3 s.
**Repro:** fixture `cp_district_boss` → A1, cleared at step 3, dumps `done=false` after the RETRY.
- **Done/Gate:** the checkpoint stores the done arenas (`make`/`to_dict`/`from_dict`); they and every fallen hive's arena
  stay done and empty; the comment at `flow_progress.gd:172-175` goes. suite_states: clear the yard, die elsewhere,
  respawn → A1 done and quiet for 4 s; the same for a hive arena; once more by real-key RETRY in the city.

## 7. Three of every hive's four pods sit inside its own hull, so neither the player nor the bot hits them — major [flow-hive-pods-inside-collision-hull, flow-e2e-bot-never-uses-real-weapons]
The spire body is on `Layers.WORLD` (`hive_spire.gd:54`, in `MASK_PLAYER_ATTACK`) with `HiveCollision` (`:106`), a convex
hull (`blender/monsters/mon_hive.py:123-135`), while the pods sit 1 m inside the skin (`hive_surface.gd:20`), 8.5–11.8 m
deep in the hull at Pod1–3 and the core. One-hit shots (`rifle.gd:162-163`, `projectile_manager.gd:148`) and missiles
reach only Pod0, yet hull hits show a marker and a number (`shot_query.gd:79-88`, `damage_numbers.gd:31`); the suite
(`suite_spires.gd:76-81`) excludes the spire; the bot's `sees()` (`flow_assault_targets.gd:125-132`) needs the first
MASK_SIGHT hit within 2 m of the pod, so it never fires. **Repro:** six taps on A6 Pod1 → six '230's, HP unchanged.
- **Done:** from the open side each pod and the open core is the first hit for taps, gatling and missile locks, through
  a trunk collision that follows the skin (your own decimated trimesh: monster-assets r5 does not carry your Request 4),
  not Hurtboxes pushed out; `Layers` changes are the lead's; trunk hits show nothing; `_pod_look` excludes
  nothing. Then the bot judges lines by the shot it fires (`ShotQuery.ray_hits` from the muzzle, `MASK_PLAYER_ATTACK`,
  areas, real pierce) from stands that frame the hive (closer or higher at A2), tapping too; `kill_spire` (`:203`, `:428`
  in `flow_debug.gd`) and A1's scripted `clear_arena` are fallbacks; `status/flow.md` 35/91/113/388/396/401 are corrected.
- **Gate:** a ray fan through `ctx.query.ray_hits` (24 bearings × 4 elevations, 30–80 m) meets each of the 12 pods and the
  open core first on ≥ 50 % of rays; six real taps each on A6 Pod1, Pod2 and the core deal 6 × 230; one hive dies to taps
  and gatling alone; `e2e_city` ends `bot_kills=3 debug_fallbacks=0`, `assault_city` `spires=1` (0 today), hives in frame.

## 8. Captures miss their beats; the hive collapse has never been filmed — minor + lead item c [flow-e2e-captures-duplicate-and-miss-beats; trailer Request 5]
- **Captures:** `_capture` (`flow_debug_view.gd:330-348`) waits in `_settle()` (`:351-362`) for the lens within 60 m of the
  hero, never true in a cinematic, while the script moves on after `SHOT_HOLD` (`flow_debug.gd:23`), so frames fire
  together (`e_spire0_collapse` = `f_game_over`; `k_spire2_collapse` = `l_boss_gate_vista` = `m_catapult_pad`). Done: a
  `shot` blocks until saved and shows its beat; the report flags duplicates and frames missing their subject.
- **Collapse:** `hive_collapse.gd:67-77` holds a 2 s duel-frame shot from ≈117 m after `hive_spire.gd:287-296` locks the
  aim on the core; camera-aim r7 fixed the hand-back. Check it un-stubbed at all three hives, by a real kill and by
  `kill_spire` (with no hard target the frame falls back to world −Z, `camera_cinematic.gd:49`, `:118-122`). Done: for 2 s
  the trunk stays in frame, topples, three blasts climb it, the wreck swaps in, the hero reads small; the camera is back
  within 1 s. **Gate:** 17 distinct md5s from `e2e_city` (`md5 -r captures/e2e_*.jpg | sort`), each its beat; per hive
  a contact sheet of the 2 s collapse (8 frames, 0.25 s apart) in the status, with the flags, for the trailer.

## 9. The flow-cost gate cannot fail; the title is not SPEC §8.1's shot — minor [flow-perf-test-vacuous, flow-title-vista-not-spec]
- **Perf:** `test_flow_perf.gd:126-136` averages stale `Performance` monitors, so both arms always match (0.000 ms): time
  flow's own bodies or sample ≥ 2 s of wall time per arm. Gate: the arms differ; a 2 ms busy-loop arm FAILS.
- **Title:** `_title()` (`game_flow.gd:170-173`) frames the hero parked at the landing, dark, behind the logo: put it on a
  lit platform, skyline behind (city-art for a light). Repro/gate: copy `title_menu.json`; `tools/godot.sh drive
  --timeline=res://flow/tests/title_menu.json --shots=4,9 --nan-watch --out=r5_title` → hero ≥ 10 % of frame height, lit.

## Gates
- `tools/godot.sh check` clean; no file over 600 lines; `test_flow.gd`, `test_flow_idle.gd`, `test_flow_perf.gd` as in
  `status/flow.md` "How to verify"; `tools/godot.sh test res://enemies/boss/tests/test_boss.gd` and `…/test_boss_city.gd`.
- **Checkpoint matrix:** one real-path run (its command in your status) dying by `take_hit` and retrying by key at the
  tutorial start, district start, each spire, boss p1/p2/p3 and a fall-out, with a respawn frame each (HUD up, camera
  behind, right objective) and the boss death frames (HUD hidden); plus the S4 pad, the A6 taps and the title frames.
- Drives, as in "How to verify": `boss_check`, `assault_city`, and the district E2E switched to `--boss-hp-scale=0.02
  --flow-script=res://flow/tests/e2e_city.json --out=e2e_city`. That run needs up to 1,950 s; until the lead's `drive
  --timeout=` lands, run `tools/godot.sh import`, then its `drive)` line under `python3 tools/slots.py heavy 3 --timeout
  3600 -- …`. The lead re-runs the acceptance drivers (`~/m/mc-accept/game/tmp_accept/`) on your final commit.

## Coordination
- **Ownership exception:** for items 3–4 flow may edit `game/enemies/boss/**` (death, respawn, restore and summon code in
  `boss_director.gd`, `brood_titan.gd`, `boss_arena.gd`, the boss tests); the boss unit is idle this round. Log each boss
  change in `status/flow.md` and as a dated note in `status/boss.md`. Not yours: `enemies/spawner.gd` (enemies' own
  enemies-spawn-at-origin-flings-player; your fix must hold without it), `game/ui/**`, `game/player/**`, `game/core/**`,
  `blender/**`. In parallel: enemies r11 (that spawner line), mech-move r7 (a dead mech stops moving and firing), hud r6
  (menus); city-build owns the tunnel caps and the S4 rib but has no brief in this batch, so do not wait for them.
- **Requests** (status Requests section) — hud: a PAUSE RETRY row (unpause, then `retry_game`); GAME_OVER RETRY closes the
  page before flow respawns (`menu_root.gd:295-297`); pad B on GAME_OVER closes it with no respawn (`:252-262`,
  unverified); 0-damage hits get numbers. weapons: `ShotQuery.deliver` reports 0-damage hits. lead: each pod hit emits
  `hit_landed` twice. If your route needs them: monster-assets, a skin-following `HiveCollision`; city-build, an S4 opening.
