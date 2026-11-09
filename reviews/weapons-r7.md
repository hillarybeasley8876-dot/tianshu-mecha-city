# weapons r7 — lead brief (small): a public `stop_volley()`, so the death gate stops writing your private fields

## Why
mech-move's death gate (`player/mech/mech_teardown.gd`) must stop everything running, without
refilling, when the mech dies. `WeaponSystem.reset()` refills (`weapon_system.gd:202`), and
`HailstormLauncher` has no public cancel. So today the gate writes four of your PRIVATE fields itself:
- `hailstorm.painting`
- `locks`
- `_paint_time`
- `_lock_timer`

It also sets `ctx.ads` / `ctx.strafe_aim`. That breaks the moment you rename a field.

The full request is mech-move's Request 17 in `status/mech-move.md`.

## House rules
You are the ONLY worker. Headless only, one Godot process at a time. Never use git stash; commit with
explicit paths.

## Do
1. Add `func stop_volley() -> void` to `WeaponSystem`. It does exactly what the gate needs and nothing
   else:
   - cancel the rifle charge and the gatling spin;
   - clear the hailstorm's paint, locks and timers through a public `HailstormLauncher.cancel()`;
   - drop ADS and strafe-aim.
   It must NOT refill, reset heat or cooldowns, or change the selected weapon.
2. A unit test:
   - after `stop_volley()`, nothing is charging, spinning or painting;
   - the ammo, heat, cooldowns and current weapon are unchanged;
   - no `weapon_switched` is emitted.
3. mech-move's `MechTeardown` already calls `stop_volley()` "in preference" if it exists. Check that it
   now takes that path. Read its code, and run `player/mech/tests/test_death.gd` (its CARRY gate reads
   `rifle=6 gatling=226 burst=0 weapon=gatling` unchanged). Then file a Request to mech-move to delete
   the four private-field writes. Do not edit mech-move's files.

## Gates
- `test_weapons` passes with the new test; `test_death` 108/108; `tools/suites.sh --only=<weapons rows>,mech_death`
  is green.
- `status/weapons.md` gets an r7 section.
