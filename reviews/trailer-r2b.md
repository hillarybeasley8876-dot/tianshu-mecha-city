# trailer r2b — lead brief: a preview cut on today's look, rendered from a pinned worktree

## Why now
The user just asked whether the in-engine footage is ready. v2a (your part A) has the right camera
work on the old, mixed look. Since then the biggest visual rounds have landed and been accepted:
- city-art r15: a real sky, cool readable shadows;
- hero-v3 r7: the hero reads, with cyan seams, gold trim and the lit grille; r8's grille and visor
  fixes are committed as well;
- monster-assets r5: skins that no longer tear, a flash that brightens instead of whitening;
- city-kit r10: the crane and the props;
- feel r5: kills freeze the victim, not the world, and the dash and perfect dodge leave afterimages;
- camera-aim r7: first person and the flight camera;
- weapons r5: the FP muzzle flash;
- skills r4: the Lance reads as a beam.

A preview cut on this look is worth showing now. The final v2 still waits for city-art r16 (the
golden warmth), so make the preview re-renderable with one command.

## Do
1. **Render from a pinned git worktree, never from the live tree.** Seven workers are mid-edit there.
   - Pick HEAD at your start: `git worktree add ~/m/trailer-r2b <HEAD>`, then clone the import cache
     with `cp -c -R game/.godot`. Since tooling's ROOT fix, that worktree's `tools/godot.sh` imports
     and drives its own checkout.
   - Before recording, prove the pin is clean there: `tools/godot.sh check` gives 0 errors, and
     `tools/godot.sh run res://main.tscn 20` gives `errors=0`.
   - If the pin is not clean, step back to the newest lead commit (a `lead:` commit) that is clean.
     Write the pinned hash in status.
2. **Re-record every take of the part-B shot list** (`game/trailer/shots.json`), including the
   first-person (`c_fp`) and flight (`c_flight`) takes. Use the flags camera-aim r7 and mech-move r6
   gave in their status files; weapons r5 asked for `c_fp` to be re-recorded at or after 7774ff9.
   - Redo the `--tod` A/B per shot on the r15 sky.
   - Hero shots: the hero must not read as a silhouette. If one still does, choose another tod or
     bearing.
   - The spire collapse: try the un-stubbed flow, killing hive A5 at the pinned commit. If it does not
     film cleanly, leave it out and say why. flow r5 is still working on that camera.
3. **The A6 stage.** city-layout r8 moved `hive_a6` 27 m, but city-build has not rebuilt the city yet,
   so the pinned game still has the old A6. Keep your A6 stage for this preview, and re-scout it for
   the final v2.
4. **Cut** `captures/trailer/TIANSHU_trailer_v2_preview.mp4`, with the same pipeline and loudness
   targets, plus `_shots.jpg` and the 2 s sheet.
5. **Report:** the pinned hash, every take's errors and framing-gate result, and a short list of what
   still reads badly on screen. The lead routes those.

## Gates
- Every take: `DRIVE done … errors=0`, and the framing report shows 0 failed.
- ffprobe and loudness as in v1/v2a; no black and no frozen frames.
- `status/trailer.md` gets an r2b section.
- Remove the worktree when done: `git worktree remove --force ~/m/trailer-r2b`.

## Coordination
Nothing in the live tree is yours to edit except `game/trailer/**` and `tools/trailer/**`. Never use
git stash. Movie Maker renders take heavy slots shared with seven workers, so pass generous timeouts.
