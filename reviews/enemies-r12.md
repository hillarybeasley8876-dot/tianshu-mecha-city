# enemies r12 — lead brief: a monster that loses sight of the player must not park forever

## Why
Your r11 report found a real gameplay defect (Request 21). **A monster that loses sight of the player
parks blind forever.** A spitter in the sandbox trench stayed silent for the rest of the run. In the
demo, that is an enemy standing still behind a wall while the player wonders where the fight went. It
breaks the arenas' tension and can stall an objective that waits for an arena to be cleared.

The lead also saw `test_ai` fail 1 of 5 runs under load, and the failing line was not captured. An
"engaged" or "stuck" check failing intermittently is consistent with the same defect.

## House rules (the user's machine)
- You are the ONLY worker.
- Headless only, one Godot process at a time.
- Never use git stash. Commit with explicit paths.

## Do
1. **Reproduce headless.** A test where a monster loses line of sight: the player moves behind cover,
   or onto another level, or leaves the leash radius and comes back. Assert that within N seconds
   (pick N from SPEC/AI and say it) the monster does one of:
   - investigates the last known position;
   - re-paths toward the player along the navmesh;
   - flanks;
   - returns to its arena anchor.
   It must never be idle for more than 6 s while the player is alive and inside its arena or leash.
   Cover every archetype's brain: ripper, mantis, spitter, harrier, juggernaut.
2. **Fix it in the AI**, not in the test: a last-known-position memory, a search behaviour, and a
   give-up path that never ends in permanent idle.
3. **The flake.** Run `test_ai` 10× sequentially and capture every failing line, if any. If one fails,
   find out why.

## Gates
- The new LOS-loss test fails on HEAD and passes after, for all 5 archetypes.
- `test_ai` passes 10/10 sequential runs, with the logs kept.
- `tools/suites.sh --only=<every enemies row>,boss,boss_city,flow` is green.
- `status/enemies.md` gets an r12 section. The windowed fight capture goes under Captures needed.
