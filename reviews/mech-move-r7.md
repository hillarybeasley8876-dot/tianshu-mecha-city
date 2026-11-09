# mech-move r7 — lead brief: a dead mech is dead

## Why
The acceptance pass found that a destroyed mech still obeys every input. At HP 0 (`_dead = true`) the MECH
DESTROYED page comes up, but it does not pause the tree (`ui/menus/menu_root.gd:96`). The keys a player
presses on that page walk, dash, shoot and swing the corpse; the left stick also drives the page's cursor.
So the wreck slides off under the page, or stands back up and fires. FEEL.md's last-stand slow-mo was never
built either. Both findings were made on a frozen copy at **b5d26d4**: `mech-move-dead-mech-walks-and-fires`
(verified) and `feel-last-stand-missing`, in `~/m/mc-lead/accept/findings_all.json`. Since then only r6
(567027e) and the trailer's `debug_perfect_dodge` (fd36986) have touched `game/player/mech/`, and neither is
on these paths. **Re-check each finding on HEAD first.** If one is already fixed, say so in your status
with the run that shows it.

## 1. [major] The corpse walks, dashes and gets back up
- **Defect.** `_dead` (`player_mech.gd:47`, latched at `:280-284`) only plays the held `death` clip.
  `_physics_process` (`:183-206`) still runs `_loco.tick`, `MechInput.poll` reads the stick every tick
  (`mech_input.gd:43`), and every state acts on it. Measured with real key events at the district `start`
  checkpoint: W for 1 s slides the corpse 13.2 m in the death pose, a Shift tap dashes it 36.2 m and spends
  EN, and dying with W held keeps it running (19.2 m in 1.2 s). It stands up because `hero3_model.gd:25-30`
  maps `dash_*`, `slide`, `hover`, `fly`, `fall` and `land_*` to clips, and `Hero3ClipPlayer.play`
  (`hero3_clip.gd:122`) replaces the held one. By the same path a mech killed in the air should get up when
  it lands (`fall` → `land_*`). That case was not measured: prove it either way.
- **Repro (live tree).** Copy the verifier's driver from
  `~/m/mc-accept/game/tmp_accept/verify-mech-move-dead-mech-walks-and-fires/` to
  `game/player/mech/tests/death_probe.{gd,tscn}` + `death_probe_end.json`. Take the output dir from
  `Game.flag("outdir")` and the file prefix from `Game.flag("out")`. Leave no home path in it:
  `world/art/tests/test_no_abs_paths.gd` fails any `/Users/` line under `game/`, comments included. Keep
  its log lines so the numbers compare 1:1. Before any change, run it on HEAD: use the `drive` line in
  Gates and pipe it to `tee tmp/mech-move/death_head.log`.
- **Done means: one gate, in PlayerMech.** The loader and the damage pipeline are yours (CONTRACTS §1). The
  death latch closes the gate and `_revive()` is its only release. It stops locomotion, and it tells every
  component PlayerMech instanced to stop (item 2). While dead:
  - move, jump, boost, dash, assault and descend are ignored. Gravity and `move_and_slide` keep running so
    the body settles. Horizontal speed dies, though the killing blow's own knockback may still carry it;
  - a death in flight, assault, a slide, a dash, a lunge or a lock leaves that state with its normal events
    (`flight_changed(false)`, `boost_ended`). The corpse burns no EN;
  - the model gets no move state that maps to a clip, so `death` holds at weight 1. SPEC §10 has no `dead`
    id, and a new one is a SPEC request. The aim feed (`_feed_model`, `:213`) drops to 0. Footsteps stop;
  - one predicate decides it all. `_dead` and `is_alive()` disagree whenever hp is written without
    `heal()`: `mech_test_base.gd:122` (`_reset`) does it, and so does `flow_progress.gd:248-249`
    (`_restore_player` at f39b168; flow r5 keeps moving it), which writes hp and then heals. Fix the harness.
- **Gate.** The probe prints `WHILE DEAD W 1.0 s … moved 0.0 m … footsteps 0`,
  `Shift tap: boost_started x0, moved 0.0 m` and `HELD W THROUGH DEATH` under 0.5 m. Every `POSE dead_*` line
  reads `clip=death weight=1.00` with `cockpit_h` < 8 m (13.1 standing). Every `VDEAD CHECK` is PASS.
  Add a hop death (at the apex) and a flight death (about +40 m) to the probe; both land still posed.

## 2. [major] …and it fires, swings, guards and casts
- **Defect.** `_load_components` (`player_mech.gd:167-180`) instances five components and keeps only
  `_aim` and `_weapons`. Each polls input in its own `_physics_process` with no alive check:
  `weapon_system.gd:115-134`, `melee_system.gd:96-111` → `melee_charge.gd:22`, `defense_system.gd:69-103`,
  `skill_system.gd:206-218` → `skill_input.gd:28`, and `aim_system.gd:36-43`. One LMB tap fires a shot and
  its `fire_r` clip stands the corpse up; F swings `melee_l1`. Only the skills ask your `can_cancel(&"skill")`
  (`skill_system.gd:271`).
- **Done means.**
  - **Input stops, the world does not.** The same gate stops every component from acting on input, without
    editing them, and `can_cancel()` is false for every tag. Rounds and missiles already in flight keep
    flying, and so do the pools under WeaponSystem (`weapon_system.gd:22-26`, children that run their own
    `_process` or `_physics_process`).
  - **No ghosts.** Whatever was running at death stays dead after the revive: guard up, saber lit, charge
    stance, gatling spin, missile paint, anchor line, ward, ADS.
  - **Nothing stale on the first live tick.** A rifle charge held at death and released on the page fires
    nothing. The RETRY press itself does nothing: Godot's default `ui_accept` probably includes Space and
    the pad's A, which are also `jump`; check `InputMap.action_get_events(&"ui_accept")`. W held through
    RETRY walks normally.
- **No exception (lead decision, `reviews/r16-lead-decisions.md`).** No guard line is granted in another
  unit's file: the pipeline reaches all five components. One it cannot reach goes in Requests, with the
  evidence. Edit nothing under `game/combat/**`; skills r4 (its item 6) adds an alive check to
  `skill_input.gd`, so leave that file alone.
- **Gate.** The probe prints `LMB tap (real mouse): 0 shots`, `F tap: melee_swing x0` and
  `CHECK PASS controls_after_retry`, and the pose holds after LMB, F and Shift. The new suite
  `player/mech/tests/test_death.gd` drives the real PlayerMech and its components with real
  `Input.parse_input_event` key/mouse events, as `test_flight_input.gd` does. It must FAIL on HEAD (record
  the score; for HEAD's code, copy your files aside and `git show HEAD:<path> > <path>`, never `git stash`)
  and PASS after:
  1. **Live first,** so a 0 means something: W, Space, Shift, LMB, F, Q and one skill key each work.
  2. **Dead, via `take_hit`:** the same events give 0 m flat; zero `jumped`, `boost_started`,
     `weapon_fired`, `melee_swing`, `skill_used`, `missiles_locked`, `weapon_switched`, `lock_changed`;
     the guard down; `can_cancel()` false; `death` at weight 1 after each verb. Also die with W held and
     in a slide, assault, dash, hop and flight.
  3. **The revive,** done exactly as `_restore_player` does it (`flow_progress.gd:246-249` at f39b168),
     with the three stale cases.

## 3. [minor] The last-stand slow-mo never fires
- **Defect.** FEEL.md's `hurt_heavy` row, slow-mo column: "last stand < 15 % HP: 0.5× 1.5 s (60 s CD)".
  `ref/research/juice-impact.md:266` adds that it fires "when HP first crosses 15 %", and aim and movement
  stay at 1×. It is built nowhere: `player_mech.gd:276` picks `hurt_heavy` or `hurt_light` by damage only,
  and `fx/events/hurt_heavy.tres` has no slow-mo.
- **Repro.** This prints nothing:
  `grep -rni --include='*.gd' --include='*.tres' --exclude-dir=.godot -e 'last.stand' -e 'last_stand' game`
- **Done means.** In `_apply_damage`, a hit that takes HP from ≥ 15 % to below it, with the mech still
  alive, calls `Feel.play(&"last_stand", global_position)` at strength 1 (`feel_director.gd:181` scales the
  slow-mo by strength); never on the killing blow, in god mode, or for a hit that starts below 15 %. The
  threshold comes from `MechTuning` (`od_low_hp`, `mech_tuning.gd:136`, is already 0.15). The 0.5×, 1.5 s
  and 60 s CD are the feel row's (`FeelEvent.slow_*`, `cooldown`), so add no second timer. You do not write
  `fx/**` or `docs/**`: feel r5 lands the FEEL.md `last_stand` row and `fx/events/last_stand.tres` in one
  commit (lead decision). Wire the `Feel.play` call only after that commit lands; watch `status/feel.md`.
- **Gate.** New `test_damage.gd` checks with `res://fx/feel_director.tscn` instanced: a crossing hit
  requests `last_stand` once; `Engine.time_scale` reads 0.5 ± 0.02 from 0.1 s to 1.3 s real and 1.0 by
  1.6 s; a second crossing within 60 s changes nothing; a killing blow from 20 % requests nothing. Until
  feel's `.tres` lands, the director checks FAIL (never SKIP); say so in your status.

## Gates
```
tools/godot.sh check                                             # whole project: 0 failed, 0 engine errors
tools/godot.sh test res://player/mech/tests/test_death.gd        -- --timeout=900  # new: FAIL at HEAD, PASS after
tools/godot.sh test res://player/mech/tests/test_damage.gd       -- --timeout=600  # + the last stand
tools/godot.sh test res://player/mech/tests/test_flight_input.gd -- --timeout=900
tools/godot.sh test res://player/mech/tests/test_locomotion.gd   -- --timeout=600
tools/godot.sh test res://player/mech/tests/test_stepping.gd     -- --timeout=600
tools/godot.sh test res://player/mech/tests/test_clocks.gd       -- --timeout=600
tools/godot.sh test res://world/art/tests/test_no_abs_paths.gd
tools/godot.sh drive --scene=res://player/mech/tests/death_probe.tscn \
  --timeline=res://player/mech/tests/death_probe_end.json --skip-menu --out=mech-move_death
```
- **Captures:** `captures/mech-move_death_*.jpg`, as a sheet in your status: close-ups with the menu layer
  hidden for that frame (dead; after W, LMB, F and Shift; the held-W death; the hop and flight deaths after
  touchdown; standing after RETRY), and the page before and after W, where the world must not pan.
- **The lead's own pass:** on a fresh acceptance copy at your commit, the checkpoint driver
  (`--acc-scenario=district`) prints `WHILE DEAD <cp>: move_forward 1 s -> 0.0 m, fire tap -> 0 shots` at
  `start` and spire1–3.
- **File size and hygiene.** `player_mech.gd` is 493 lines and `mech_locomotion.gd` 396: a file that would
  pass 600 is split first, in its own commit (the damage pipeline, `:234-307`, is the natural cut). One file
  per state family, no dead code, and never "fixed" without the re-run.

## Coordination
- **Lead decisions** (`reviews/r16-lead-decisions.md`: Shared, and mech-move r7) win where they differ
  from this brief.
- **Units you reach.** weapons, melee-defense and skills have acceptance items too, and AimSystem is
  camera-aim's: you stop their components from PlayerMech but never edit them.
- **hero-v3 r8 runs in parallel** (r7 accepted at a1c5bdc; r8, incl. the flight pose, works in
  `game/player/model/hero3/**`), so its files may sit uncommitted in the tree. Commit with an explicit
  path list, never `git add -A` or `commit -a`. Edit nothing under `game/player/model/**` except the
  placeholder, which is yours. If the model needs a "dead" lock, put it in Requests.
- **Routed elsewhere: do not fix, do not wait.**
  - **boss (flow r5 item 4, under flow's boss exception):** `BossDirector._on_player_died`
    (`boss_director.gd:345-361` at f39b168) heals the hero on the death frame, which releases your gate.
    Boss-phase deaths stay live until flow's fix lands, so gate on the district.
  - **flow:** r5 is fixing respawn in parallel. Tutorial deaths now have a start checkpoint (d670a58), and
    `_restore_player` moves with each flow commit: re-read it before your test mirrors it.
  - **hud (r6 has both, lead decision):** the page does not pause yet, and its footer "W / S 或 LS 选择"
    (W / S or LS to select) names W/S, which are not `ui_up` or `ui_down`. Once hud's GAME_OVER pause
    lands, the page freezes the whole tree, the hero model included.
- **Requests** go in `status/mech-move.md`, numbered from 9: feel, `fx/events/last_stand.tres` with
  `slow_scale` 0.5, `slow_seconds` 1.5, `cooldown` 60 and `slow_witch` false (the lead decided witch off;
  true would light the perfect-dodge tint, `screen_fx.gd:72`); weapons, if the pipeline cannot reach
  WeaponSystem; anything for melee-defense, skills or hero-v3.
- **Status.** Add an r7 section to `status/mech-move.md`: the root cause, the HEAD numbers next to the
  fixed ones, and the sheet. Add the new commands to How to verify.
