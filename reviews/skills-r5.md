# skills r5 — lead brief (small): the Overdrive ends inside your own death hook

## Why
mech-move's death gate (`player/mech/mech_teardown.gd`) ends a running Overdrive by calling
`SkillSystem.end_overdrive()` itself, next to your `on_player_died()`. Your r4 hook only detaches the
anchor and drops the ward. Request 16 in `status/mech-move.md` asks that `on_player_died()` own the whole
skills teardown, Overdrive included, so the mech calls one hook and never reaches into skills' state.

## House rules
You are the ONLY worker. Headless only, one Godot process at a time. Never use git stash; commit with
explicit paths.

## Do
1. `on_player_died()` ends a running Overdrive through its own path, the same as `end_overdrive()`:
   - the meter goes to 0;
   - `overdrive_changed(false)` fires exactly once;
   - the model is told.
   It changes nothing else: charges, cooldowns and the aftermath rules stay as `end_overdrive` has them.
2. **A unit test:** die 1.25 s into an Overdrive with only `on_player_died()` called. Overdrive is off,
   `overdrive_changed(false)` fires once, and V does not restart it while dead.
3. **The handover to mech-move.** File a Request to mech-move: drop its direct `end_overdrive()` call
   and the dead private-field writes in `MechTeardown._weapons()` (weapons r7 landed `stop_volley`).
   Do not edit mech-move's files.

## Gates
- `test_skills` passes with the new test.
- `test_death` 108/108 still passes, because mech-move's call still exists.
- `tools/suites.sh --only=<skills rows>,mech_death` is green.
- `status/skills.md` gets an r5 section.
