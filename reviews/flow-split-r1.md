# flow — lead brief: split `game/flow/flow_debug_assault.gd` (624 lines) without changing what it does

The project rule: a source file over 600 lines must be split the next time it is touched, and the split
is its own commit. `game/flow/flow_debug_assault.gd` is 624 lines.

**Do:**
1. **Split along the responsibilities it already has.** For example the scripted assault's stages,
   the bot's combat driver, and the evidence/capture helpers; you know the seams. Every resulting file
   stays under about 400 lines, and callers do not change.
2. **Behaviour-identical.** Every `flow/tests/` suite passes:
   `tools/godot.sh test res://flow/tests/test_flow.gd -- --sandbox --flow --spawn=0,1,60`, and the E2E
   assault run if the suite has one. Print the check counts before and after; they must match.
3. **`tools/godot.sh check` stays clean.**
4. Do not touch other units' files. city-art, city-kit and hero-v3 are running.

One commit for the split, with an explicit path list. Report in `status/flow.md` (a short section).
