# city-build — navigation verdict (lead investigation, 2 independent probes + synthesis, 2026-11-02)

**There is no engine limit.** Two things combined:
1. The "15 / 35–40 / 65 s" and "never syncs" were FRAME COUNTS: `tools/godot.sh test` runs `--headless
   --fixed-fps 120` and the headless loop does thousands of frames per wall second; `checks.gd` prints
   `waited/120`. Real wall time to a usable map: large ~41 ms, medium ~100 ms, small ~150 ms (in parallel). The
   "never" cases took 0.24–0.5 s and simply ran past the harness's frame cap.
2. Builds took ~0.1 s (not ms) because `NavMapBuilder3D::_build_step_edge_connection_margin_connections` tests
   every PAIR of free edges (11,205 / 8,605 / 4,571 free edges → O(F²), 89 % of the build). With one region per
   map it joins nothing.

## Do (city_nav.gd, bake_nav.gd, checks.gd)
1. In `build()`, before `map_set_active`: `NavigationServer3D.map_set_use_edge_connections(map, false)` (comment
   why). Measured: builds 126/80/26 ms → 13/10/6 ms; all three maps usable ~20 ms after the first physics frame;
   identical paths. Keep the async iterations ON (off = a 250 ms main-thread hitch).
2. `is_synced()`: per class, true once `map_get_iteration_id(map) > 0` AND `map_get_closest_point(map, p)` is
   within 0.5 m of a sample polygon centre `p` (tested: fires on the first real-path frame in 7/7 variants).
3. `checks.gd` (and any wait loop): time with `Time.get_ticks_msec()`, never frames/120.
4. Remove the "engine limit" claims (city_nav.gd header + is_synced comment, bake_nav.gd, status known issues).
5. Free the three map RIDs in `_exit_tree()` (`NavigationServer3D.free_rid`).
6. **Now the REAL navigation problems** — measure and fix:
   - The bakes are fragmented: 2,218 / 1,599 / 732 islands; the largest covers only 8–17 % of the area.
   - Only 2 / 19 / 12 of the 48 NavigationLink3Ds attach to the navmesh at both ends (within link_r).
   - `bake_nav.gd:91` uses `Z_HI`, so small's `z_hi = 96` is never applied (379 islands above it).
   - Drop 1–2-triangle unreachable islands; re-bake at the godot-tech §3.1 cell sizes (small 0.5, medium 1.0,
     large 1.5) now that sync is linear; snap link endpoints onto the baked navmesh (closest point) and report
     how many attach; for each class report the share of gameplay pairs (spawn zone → arena centre, arena →
     arena) whose path ends within 1 m of the target. Target ≥ 95 % for medium/large between connected arenas.
