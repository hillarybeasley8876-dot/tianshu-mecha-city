# weapons r6 — lead brief: the orange slabs in the first-person view, and a broken shader that `check` cannot see

## Why
Every first-person gatling take still shows **large flat ORANGE slabs** flying across the right side
of the frame:
- `captures/weapons_r5_fp_sheet.jpg`, before and after your r5 fix;
- the trailer v2 `c_fp` take;
- the showcase g10_fp segment (`captures/trailer/sheets/TIANSHU_showcase_segments.jpg`).

They are about the size of a car door, at 3–10 m from the lens. The likely source is the spent casings
(`game/combat/projectiles/casing_pool.gd`: one MultiMesh, ejected at `gatling.gd:193` with a 14 m/s
sideways kick) drawn at a third-person scale next to the first-person lens. It could also be sparks or
debris. **Find it, do not guess.**

## House rules (the user's machine)
You are the ONLY worker. `tools/godot.sh shot|run|drive|movie|perf` refuse without the lead's
`MC_WINDOW_OK`. Diagnose and gate headless, and list the exact windowed capture commands under
**"Captures needed"** in your status. Never use git stash; commit with explicit paths.

## Do
1. **Identify the slabs, headless.** Drive a first-person gatling burst in a headless test, as your r5
   `suite_fp` does. Every few ticks, list each visible quad or mesh within 15 m of the FP lens: its
   owner node, its size and its colour. The slabs are whatever is large, orange and inside that
   radius.
2. **Fix them by camera mode**, as r5 did for the muzzle flash:
   - in first person, casings (or whatever it is) eject away from the lens and are scaled for a 16 m
     mech seen from its own cockpit, or are hidden while inside a near radius;
   - in third person nothing changes.
3. **Gate:** in the headless FP burst, no orange-dominant quad larger than 0.5 m is within 8 m of the
   lens on any tick, and the third-person numbers are unchanged. The test must fail on HEAD.
4. **Captures needed:** an FP gatling burst before/after (3 frames), plus a third-person control.

## Also
melee-defense r7 found that `tools/godot.sh check` does not catch a broken `.gdshader`. Look at your
shaders (`combat/weapons/**`, `combat/projectiles/**`): if any is built from code, compile it in a test
the way melee-defense's `mat.shader_compiles` does, so a broken shader fails your suite.

## Gates
- `test_weapons` passes with the new FP check, and `suite_fp` passes; `check --only=res://combat/` is
  clean.
- `status/weapons.md` gets an r6 section with the identification table, the before/after numbers and
  Captures needed.
