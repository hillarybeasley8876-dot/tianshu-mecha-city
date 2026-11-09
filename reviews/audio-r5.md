# audio r5 — lead brief: five sound ids the game asks for do not exist

The enemies call `Audio.play` with ids that `Audio.resolve()` cannot find. Each one logs a single warning
and then plays nothing, every time, for the whole game:

| call site | id | what the player should hear |
|---|---|---|
| `enemies/enemy_base.gd:208` | `enemy_telegraph` | the attack tell |
| `enemies/enemy_base.gd:230` | `enemy_stagger` | an enemy staggered |
| `enemies/enemy_base.gd:282` | `enemy_death` | an enemy dies |
| `enemies/juggernaut/juggernaut.gd:113` | `juggernaut_plate_break` | a juggernaut plate breaks off |
| `enemies/enemy_shockwave.gd:39` | `juggernaut_slam` | the juggernaut's slam shockwave lands |

Some of these moments are ALSO voiced by your router through a signal: `on_enemy_staggered` plays
`stagger_enemy`, and `on_enemy_telegraph` plays the telegraph sounds. Others have no sound at all today:
`juggernaut_plate_break` exists nowhere in `game/audio/`.

**Do:**
1. **Decide each row.** Either the router already voices it through a signal, in which case delete the
   direct call (the enemies unit is idle and you may edit those exact lines), or it needs a sound, in
   which case give it one: an alias in `table_aliases.gd` onto an existing event, or a new event from the
   existing library. Never let one moment play twice.
2. **Add a test so this cannot come back.** Scan every `.gd` under `game/` (outside `tests/` and
   `.godot/`) for `Audio.play(&"…")` and `Audio.play_loop(&"…")` literals, and FAIL on any id that
   `Audio.resolve()` returns null for. Print the list.
3. **Run your suites and the enemies' `test_ai.gd`.** Then a 30 s fight, `tools/godot.sh drive` with
   enemies on: zero `Audio: unknown or empty sound id` warnings.

Commit per step with an explicit path list. Report in `status/audio.md` (an r5 section).
