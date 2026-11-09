# monster-assets r6 — lead brief: no monster sinks into the floor (the juggernaut's charge, the rest of the floor table)

## Why
The user's top complaint has been **"浮空"**: things not standing on the ground. The hero is fixed (hero-v3
r9, mech-move r8: every planted foot within 0.10 m), and so is the city dressing (city-art r16a). Your r5
fixed the mantis hover. Left from your own r5 report:
- **the juggernaut's `charge_run` still sinks 0.70 m** (it was −1.11 m). It is its signature attack, so
  players watch it closely. The build's round-trip measurement says 0.09 m while Godot says 0.70 m, and
  you could not find why;
- any other grounded clip whose lowest point is below −0.15 m, or that hovers above +0.3 m, in your
  `probe_floor` table.

## House rules (the user's machine)
You are the ONLY worker. Godot headless only (`tools/godot.sh test`), and Blender in background mode
only (`tools/blender.sh`). No Tripo web runs this round: the browser driver opens a window on the user's
screen. One heavy process at a time. Never use git stash; commit with explicit paths.

## Do
1. **Find why Godot and the build disagree for `charge_run`.** Candidates:
   - the clip's root motion or a root-bone offset the build strips but Godot keeps;
   - an animation track Godot plays that the build does not (scale tracks, or the import's
     `root_motion` setting);
   - LOD1 against LOD0;
   - the playback speed scale in `monster_playback.gd`;
   - EnemyBase's model offset while charging.
   Measure it in the shipped game path (`probe_floor` already does), and print the per-frame lowest
   vertex with its bone.
2. **Fix it at the cause.** If the cause is in EnemyBase (an enemies file), put a Request in your status
   with the measurement instead of editing it.
3. **The whole table.** Re-run `probe_floor` for every type and every grounded clip. Nothing lower than
   −0.15 m, and nothing hovering above +0.3 m, for more than 3 consecutive frames.

## Gates
- `probe_floor`: every grounded clip of every type inside the band, as a table, before and after.
- `test_models` passes, and so do `tools/suites.sh --only=<monster rows>` and `enemies_*`.
- `status/monster-assets.md` gets an r6 section. The windowed clip strips go under Captures needed.
