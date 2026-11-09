# enemies — lead notes (read at every session start)
- Rippers climb: when a target is above them on a facade < 32 m high, they may climb walls (wall-run state along the
  face, then vault onto the deck) — a big part of the tension in a vertical city.
- Harriers fly on a sky graph: city-build will expose `&"sky_waypoint"` markers (≥ 24 per district, +60…+200 m);
  until then orbit/strafe as now.
- Balance (SPEC §7.1) and telegraph timing are the source of truth; print TTK and incoming-DPS in the AI test.
- (city-build r1) In the city, gate the first path query per class on `world.nav_ready(cls)` (async map sync);
  until then use direct steering. The lead is investigating the slow sync separately.
- (02:40) A fight_probe run (`--timeline=res://enemies/tests/fight_timeline.json`) logs ~18×
  `nav_mesh_queries_3d.cpp:404 _query_task_build_path_corridor(): It's not expect to not find the most reachable
  polygons` — a path query whose start or goal has no reachable polygon (new since the `_project` change?).
  Query only between points projected onto the same map, skip queries before `nav_ready`, and add the fight
  run's error count (0) to your suite.
- (melee r6) The ONLY `--nan-watch` source left in fights: `enemy_base.gd:347` dissolves a wreck with
  `model.scale = Vector3.ONE * (1.0 - k)`, which reaches exactly (0,0,0) → degenerate basis (40 reports per run).
  Use `maxf(1.0 - k, 0.001)` and hide the model at k ≥ 1 before `_finish_dissolve()`.
