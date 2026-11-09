# enemies — review r4 (lead, follow-up) — PASS

Root-caused the engine error (4.7.2 logs it for every FAILED path query and returns a degenerate [start, end]
path), removed the per-query dependence on a connected navmesh (projection + level checks + a 60 s breaker to
direct steering), fixed the zero-scale dissolve, and added `test_fight.gd` asserting 0 engine errors and 0
degenerate transforms in a 30 s fight — each gate proven against the old code. Real-city fight: errors 54 → 0.
The shattered bake goes to city-build (noted with your island counts); `facade_signs.gd:138` to city-art.
