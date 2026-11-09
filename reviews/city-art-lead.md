- (23:10) **Shader globals are declared in `game/project.godot` [shader_globals]** by the lead: mc_time,
  mc_lit_fraction, mc_infection, mc_hive0..3, mc_hive_levels (types/defaults as in your ensure_globals). Runtime
  `global_shader_parameter_add` errors on an existing name and a shader compiled before your registration
  fails — so drop the `_add` path and only `global_shader_parameter_set`. Need another global? Put it in your
  status (name, type, default) and the lead adds it.
- (enemies r9) `world/art/detail/facade_signs.gd:138` logs an engine error in every real-city fight run — fix it
  (0 errors is a gate for every scripted run).
- (boss r2) The Spire tether must start at the top of the Crown's central core (Ø 80 m), never stand on the
  open deck where the fight happens. (lead, from boss_flow_t30) Lit window cells alias into noise at distance
  (the city below the Crown reads as static) — fade/mip the window cells past ~400 m to a lit-fraction glow.
- (r4 start, 04:15) All eight vista cameras are adopted in `data/vistas.json`. city-build r3 fixed the HLOD
  curtain (no more flat wall) and exported `podium_walls` for your mask. Mid-distance towers (300–900 m) still
  read as a coarse checkerboard of window squares (`city_V5_proposed.jpg`): fade the cell pattern into a
  lit-fraction glow with subtle per-building variation well before the cells shrink to a few pixels.
  Perf: the V2 slowdown (15 fps) is flow's per-frame cost, not yours (60 fps with `--stub=flow`) — but measure
  your own cost at every vista with `--stub=flow` and keep ≤ 16.6 ms.
- (12:10, PRIORITY — user feedback) New unit **city-kit** brings Tripo-made buildings. Provide
  `McMaterials.kit(src: StandardMaterial3D) -> Material`: your haze include + window-mask emission (lit fraction,
  warm/cool hash) applied to a glTF texture set, so kit buildings sit in the same atmosphere. Document it in your
  status; city-kit calls it.
- (12:25, user feedback "后处理 渲染 滤镜要加强") New unit **post-render** owns the cinematic grade/lens stack (Compositor)
  and A/B-tests renderer settings. Expose `CityEnvironment.compositor` (a Compositor on the WorldEnvironment/
  Camera they can append to) and apply their measured patch lists to environment.gd / quality.gd / materials
  (wetness + puddle masks on mc_road / mc_deck for SSR). Coordinate via status files.
