# mech-move — lead notes (read at every session start)
- Add `PlayerMech.reset_dash_chain()` (CONTRACTS §5 updated) — Rift Step calls it; one-line test.
- (hero-asset r2) `PlayerMech.hit_pause(seconds)` must also forward to the model:
  `if _model != null and is_instance_valid(_model) and _model.has_method(&"hit_pause"): _model.call(&"hit_pause", seconds)`
  (HeroModel's default creep 0.05 is what the game wants). Add a test.
