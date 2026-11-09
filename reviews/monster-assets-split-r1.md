# monster-assets — lead brief: split `game/enemies/models/monster_model.gd` (601 lines) without changing what it does

The project rule: a source file over 600 lines must be split the next time it is touched, and the split
is its own commit. `game/enemies/models/monster_model.gd` (`MonsterModel`) is 601 lines.

**Do:**
1. **Split along the responsibilities it already has.** For example gait / locomotion selection,
   action playback, hit flash / telegraph / stagger, sockets.
   - Every resulting file stays under about 400 lines.
   - The CONTRACTS §6 API on `MonsterModel` is unchanged, so `enemies/<type>/<type>.tscn` and its
     callers do not change.
2. **Behaviour-identical.**
   - `game/enemies/models/tests/test_models.gd` and `game/enemies/tests/test_ai.gd` pass with the same
     check counts.
   - Record one monster's per-frame skeleton pose through walk → run → attack → hit → death before and
     after: identical to 1e-5.
3. **`tools/godot.sh check` stays clean.**
4. Do not touch other units' files. city-art, city-kit and hero-v3 are running.

One commit for the split, with an explicit path list. Report in `status/monster-assets.md` (a short
section).
