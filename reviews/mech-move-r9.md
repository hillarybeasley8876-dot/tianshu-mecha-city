# mech-move r9 — lead brief (tiny): `MechTeardown` calls the owners' hooks only

skills r5 (b1beb5a, 2b651f1) made `SkillSystem.on_player_died()` own the whole skills teardown,
Overdrive included, with no aftermath. weapons r7 (ba5ada7) added `WeaponSystem.stop_volley()`. Two
blocks in `game/player/mech/mech_teardown.gd` are therefore dead or redundant:
- `_skills()`: the `if is_overdrive_active() … end_overdrive()` block;
- `_weapons()`: the fallback branch with the private `ctx.ads` / `ctx.strafe_aim` writes and the
  hailstorm field writes (`_unpaint()`).

See skills Request 8 and the weapons Requests.

House rules: you are the only worker. Headless only, one Godot process at a time. Never use git stash;
commit with explicit paths.

**Do:** delete both blocks, so the teardown calls `on_player_died()` and `stop_volley()` and nothing
else for those two components. Leave no dead code. Keep a guard only if a stand-in in your own tests
lacks a hook, and then fix the stand-in instead.

**Gates:**
- `test_death` 108/108, with the CARRY and Overdrive rows unchanged;
- `tools/suites.sh --only=<mech rows>,skills,weapons` is green;
- `check --only=res://player/` is clean;
- a short r9 note in `status/mech-move.md`.
