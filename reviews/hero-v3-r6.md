# hero-v3 r6 — lead brief: split `hero3_gait.gd` (764 lines) without changing what it does

The project rule: a source file over 600 lines must be split the next time it is touched, and the split
is its own commit. `game/player/model/hero3/hero3_gait.gd` is 764 lines, the largest script in the game.
r5 grew it, and the next feel round will touch it again.

**Do:**
1. **Split it along the responsibilities it already has.** Your own helpers show the pattern:
   `Hero3Foot`, `Hero3Pelvis`, `Hero3Skate`, `Hero3Air`. Plausible new seams are the step planner (the
   phase clock, triggers, plant choice), the lower-body yaw, the heel-to-toe roll / replant, and the
   footstep emission.
2. **Size.** Every resulting file stays under about 400 lines, and `hero3_gait.gd` keeps the public API
   it has today. Callers do not change.
3. **Behaviour-identical.** Prove it, not just by the tests passing:
   - record the per-frame skeleton pose (every bone's global transform) over the same scripted
     timeline before and after the split: walk, run, strafe, back-pedal, turn in place, hop, heavy
     landing, slide;
   - they must be identical to 1e-5 m / 1e-5 rad.
4. **Tests.** Every `hero3/tests/` suite passes, plus `player/mech/tests/test_damage.gd` and
   `tools/godot.sh check`.
5. `hero3_clip.gd` (528 lines) is under the limit. Leave it.

One commit for the split, with an explicit path list. Report in `status/hero-v3.md` (an r6 section)
with the pose-diff numbers.
