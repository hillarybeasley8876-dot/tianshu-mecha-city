# mech-move r8 — lead brief: no floating on steps, monsters are not a moving floor

## Why
The user's first complaint about the hero was **"角色和地面浮空"** (the hero floats above the ground).
hero-v3 r9 fixed the model: planted feet sit within 0.10 m of the floor in 100 % of frames on flat,
ramp, turn, slide and landing. One case is left, and it is yours, from `status/hero-v3.md` (the kerb
paragraph):
- **Walking over a 2 m kerb is only 75 % grounded.** For about 0.6 s the 3.5 m-radius capsule rides up
  the step while the trailing foot is still 4.9 m back and 5.6 m down: 7.45 m from a hip that a 6.16 m
  leg cannot reach. The body climbs before the feet do. That is `MechStepping`'s capsule step-up.

There is a second, related defect, from `status/enemies.md` Request 19: **the hero treats monsters as a
moving floor.** Standing on a monster, it picks up the monster's motion as platform velocity (the
engine-default `platform_floor_layers`; `player_mech.gd` sets none). That is how a spawning or moving
monster flings the mech.

## House rules (the user's machine)
- You are the ONLY worker.
- Headless only, one Godot process at a time.
- Never use git stash. Commit with explicit paths.

## Do
1. **The step-up.** Make the body climb a step at a rate the legs can follow: ease the capsule's
   step-up over the time the trailing foot needs to replant, or let the leg IK lead. The visual lift
   may lag the collision lift, but neither may snap.
   - Keep SPEC §4 stepping: step-up 2.5 m, auto-hop ≤ 7 m while boosting, and no stall at run speed.
   - **Gate:** hero-v3's `res://player/model/hero3/tests/probe_float.gd` `walk_kerb` row goes from 75 %
     to ≥ 95 % near, and is never more than 0.25 m above. `test_stepping` and `test_locomotion` pass.
     Run a 2 m step and a 1 m step, up and down, at walk and at run.
2. **Monsters are not floor.** Set the mech's platform layers so that only world and static geometry
   carry it. Standing on a monster must neither carry nor fling the hero.
   - **Gate:** a headless test where the hero stands on a moving monster's back for 2 s. Its horizontal
     velocity stays under 1 m/s from the platform, and standing on a deck or a moving world platform, if
     any exists, still works.
3. **Requests 16 and 17 to skills and weapons** (the OD teardown fold and `stop_volley`): check whether
   they landed. If not, leave them as Requests. Do not edit those units' files.

## Gates
- The new tests fail on HEAD and pass after.
- The mech suites, `probe_float` and `tools/suites.sh --only=<mech rows>,<hero3 rows>` are green.
- `status/mech-move.md` gets an r8 section.
