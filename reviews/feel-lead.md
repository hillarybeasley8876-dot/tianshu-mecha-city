# feel — lead notes (read at every session start)
- fx/vfx/afterimage_pool.gd:46 uses the Godot 3 property `skeleton_path` (Godot 4: `skeleton`) → ~1,554 errors per
  drive; fix it (Overdrive afterimages and the Rift Step streak depend on it).
- `overdrive_ignite`'s vignette must be GOLD (#F2C14E), not red.
- Clocks contract (CONTRACTS §3): Feel/screen effects/rumble timing on the real clock (`Feel.real_now`).
- (from mech-move r3 captures) the `assault_boost` shock cone / radial effect whites out half the screen when it
  spawns near the camera: keep VFX ≥ 12 m from the camera or fade by camera distance; cap any full-screen-ish
  additive layer at 0.25 alpha.
- (packaging, 01:15) `FeelDirector` enumerates `fx/events/` with `DirAccess` and keeps only `.tres/.res` — in the
  exported .app those files are `*.tres.remap`, so the shipped game loads ZERO feel events (no juice at all).
  Use `ResourceLoader.list_directory(EVENTS_DIR)` (Godot 4.4+, export-safe) and add a test that ≥ 44 events load.
