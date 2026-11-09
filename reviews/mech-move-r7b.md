# mech-move r7b — lead review: the death gate works, but it refills, leaves Overdrive on, eats presses, and the tests do not hold keys

## Verdict on r7: NOT ACCEPTED yet
The lead's acceptance pass (4 reviewers) re-ran your gates and confirms that the gate itself is right.
- `test_death` goes 34/71 on the pre-fix code and 71/71 on HEAD.
- The windowed death probe and the `--stub=hud` probe show 0 failures.
- Nothing moves under the MECH DESTROYED page.

**What a player sees now:** the wreck stays kneeling through every verb, it lands still posed after hop
and flight deaths, and after RETRY the mech stands up clean.

But the pass found four major defects and a set of tests that do not prove what the status says. Fix
all of the items below. Each one has the reviewer's repro in
`~/m/mc-lead/accept/mech-move-r7/adversary/`: scripts, mutation diffs and logs.

## Major
1. **Dying in Overdrive leaves it stuck on, and RETRY hands out a free Overdrive.**
   - `MechDeath.stop_components` (`mech_death.gd:99-105`) calls `SkillSystem.reset()`, a tools/tests
     hook (`skill_system.gd:429`). It zeroes `_od_active` without `end_overdrive()`, so:
     - `MechEnergy.overdrive_active` stays true;
     - the meter stays at 100;
     - `Events.overdrive_changed(false)` never fires;
     - audio's overdrive loop keeps playing.
   - **Fix:** end a running Overdrive through its own path. If skills has no death teardown you can
     call, file the Request to skills (skills r4 is live).
   - **Gate:** die 1.25 s into an Overdrive and revive the way `_restore_player` does. Then
     `overdrive_active` is false, `overdrive_changed(false)` fires exactly once, the meter reads 0, and
     V does not start an Overdrive.
2. **The death gate refills ammo, heat and every cooldown, and silently swaps back to the rifle.**
   - `WeaponSystem.reset()` refills the magazine and the belt, zeroes heat and the missile cooldown,
     and sets the rifle without emitting `weapon_switched`. `SkillSystem.reset()` restores every
     charge.
   - The lead ruled carry-over out of scope this round. That means no refill: the gate must not
     change the loadout.
   - **Fix:** tear down only what is running (rifle charge, gatling spin, missile paint, guard, saber,
     anchor line, ward, Overdrive), and keep ammo, heat, cooldowns and the selected weapon.
   - **Gate:** a CARRY scenario reads the same before and after a short death.
3. **The revive latch blocks too much.** While any one of the 17 component actions is held at the
   revive, all five components stay off until every held action is released
   (`player_mech.gd:131-138`, `mech_death.gd:29`). Holding RMB through RETRY leaves fire, melee,
   guard, skills and lock-on dead.
   - **Lead ruling:** ignore ONLY the actions that were held on the revive tick. A fresh press of any
     other verb acts at once. Where a component cannot ignore a single action without its own code,
     file a Request to its unit with the repro.
   - **Gate:** with RMB held across the revive, a fresh F, LMB and Q each act.
4. **The tests do not hold keys through the killing blow, and the revive phase never kills.**
   - `_kill()` calls `_release_all()` two ticks before the hit (`death_test_base.gd:165-166`), so
     "die with W held", "in a boost slide", and every held-across-the-revive row release the keys
     first.
   - In `_phase_revive` the guard is still up and absorbs the "killing blow": hp goes 10000 → 5500
     and no `player_died` fires.
   - **Fix:**
     - add `_kill_holding()`, which leaves every key down and uses an unblockable hit;
     - make the revive phase really kill: assert dead, and exactly one `player_died`;
     - add held-across rows (Space, W, LMB, Q, and a rifle charge held at death and released on the
       page) that FAIL with the reviewer's `MUT_mech_death.diff` applied.
   - Fix the DEAD loop's release blindness: it samples `acted` before the release
     (`test_death.gd:125-128`); OR in the post-release state, as the LIVE loop does.
   - Fix the weapon-swap lockout between rows: call `_reset_weapons()`, or wait out the 0.35 s
     `swap_time`.
   - Report the mutation score and the list of DEAD rows that now flip on the old code.
5. **`test_last_stand.gd` is red (10/12) now that feel's row has landed (7d2655d).**
   - The director is instanced before the pipeline half, whose first crossing hit spends the row's
     60 s cooldown.
   - **Fix:** call the director's `reset_rate_limits()` before `_test_director()`, or instance it
     later. Rebuild the "a killing blow plays nothing" row on a fresh cooldown, so that it can fail.
     Fold the suite into `test_damage.gd` (conflict map B5).
   - **Gate:** 12/12, plus the killing-blow mutation turning that row red.

## Minor
6. **A death in the flight assault jet** emits no `boost_ended(&"assault")`, so the camera's assault
   FOV and arm stay wide after the revive. Emit it at the latch as `_assault_toggle` does, and add the
   row.
7. **A corpse pushed upward** (`flow/hive_collapse.gd` `_shove_hero`) revives stuck in S.AIR: Space only
   buffers. On the revive, set the state machine from the floor contact. Gate: push a corpse up,
   revive, and Space hops.
8. **`player_died` fires twice** when hp is written directly: flow's debug `die` and `test_boss_city`
   emit it themselves, then `MechDamage.sync()` emits again. Make one death emit once, and send flow a
   note about its `die` command.
9. **Missing dead-input rows** (the decisions and the conflict map name them):
   - D-pad `lock_prev`/`lock_next` (InputEventJoypadButton) while dead;
   - die with OD active, then V (the Lance);
   - a round or missile fired before the death keeps advancing after it;
   - after the revive: no saber lit, no charge stance, no gatling spin, no missile paint, no ADS.
10. **Hygiene.**
    - The bus row in the cancel checks is a tautology: drop it, or give it real ticks.
    - Fix the `mech_test_base.gd:122-123` comment.
    - Status: the check count, and the flip list (the B8 row passed on the pre-fix code).
    - Reword "lying on the deck" to "kneeling slump, cockpit 6.7–7.1 m vs 13.1 standing".
    - Regenerate `death_fixed.log` and `death_stub.log` at the committed probe.
    - Rebuild the capture sheet with `d1_dead_page` | `d2_walked_page` side by side, plus
      `d2_walked_closeup`.
11. **The split moved `_dead` and `_invuln_t` into MechDamage.** Add a Request saying external drivers
    must use `damage()` or `is_alive()`. The lead updates its acceptance driver.

## Gates
- `test_death` (with the new rows), `test_damage` (with last stand folded in), `test_flight_input`,
  `test_locomotion`, `test_stepping`, `test_clocks`, `test_no_abs_paths`: all pass under the strict
  host.
- The new rows fail on a4de047's `player_mech.gd` and `mech_input.gd`. The mutation score is in the
  status file.
- The death probe, windowed and with `--stub=hud`: 0 failed.
- `status/mech-move.md` gets an r7b section.

## Coordination
- skills r4 is live, for the Overdrive teardown Request, if needed.
- hero-v3 r8 is live: the lead told it about its `Basis.scaled(float)` flight errors and the dead-lock
  emissives.
- flow r5 is live: the note about its `die` command.
- Read `reviews/r16-lead-decisions.md` and `reviews/r16-conflicts.md` (B-rows). Never use git stash.

## Dispatch note (11-05 17:15): headless only
Read the new "The user's machine" section at the end of `tools/workers/preamble.md`. `tools/godot.sh drive`
now refuses without the lead's `MC_WINDOW_OK`. So:
- **Every gate above runs headless.** That is `test_death` and its new rows, `test_damage`, and the
  other suites.
- **The windowed death-probe runs** go under "Captures needed" in your status, with exact commands.
  The lead runs them later.
- You are the only worker running.
