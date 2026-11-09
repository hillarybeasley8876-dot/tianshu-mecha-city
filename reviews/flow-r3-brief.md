# flow — r3 (lead): the end-to-end demo run in the real city

The city is built (city-build r2: tiles, markers, nav maps that sync in ~40 ms, the Crown with rim segments,
the art environment), the boss is in its r2. Your unit is the spine of the demo, so you own the E2E harness.

1. **E2E drive in the city**: `game/flow/tests/e2e_city.json` (+ `flow_debug` commands as needed) that runs
   with `--skip-menu --god --frametimes --nan-watch` and goes: drop-in on H0 → tutorial fight at A1 (real
   enemies) → district → each of the 3 Hive Spires in their real arenas (A2 Knot, A5 Foundry, A6 Sky Garden):
   travel there (teleport between beats is fine), fight the pods and the core with real weapons/skills
   (god mode on), see the collapse beat → `boss_gate` → the Ascension Catapult at S4 → land on the Crown →
   hand-over to the boss director (its intro roar). Stop there until boss r2 lands, then extend to victory.
   Every state transition and objective asserted from Events; 0 engine/script errors.
2. **Checkpoints in the city**: die (debug) after spire 1 → respawn at that checkpoint with full HP/EN, the
   fallen spire stays down, the standing ones restored.
3. **Pacing report**: wall time per phase in the scripted run and an estimate for real play (target 20–25 min).
4. Evidence: `captures/e2e_*.jpg` at each beat (drop-in over the canal, A1 fight, each spire's pods, each
   collapse, the catapult launch, landing on the Crown) and `captures/e2e_city.mp4`; frametimes p50/p95/p99
   per phase; the error count.
Report every cross-unit problem you hit with file:line — do not edit other units' files.
