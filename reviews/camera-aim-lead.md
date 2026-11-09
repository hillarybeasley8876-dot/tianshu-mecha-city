# camera-aim — lead notes (read at every session start)
- Mouse on macOS: set `Input.use_accumulated_input = false`, read `InputEventMouseMotion.screen_relative`, no
  smoothing; sensitivity in degrees per 1000 px; offer "invert Y" and a pad response-curve option.
- Third-person framing in streets: when the arm is pulled in by walls for > 0.5 s, raise the pivot +6 m and pitch
  down 8° (over-the-top compression) so the hero stays readable in 36–48 m streets; giant targets (juggernaut/titan)
  in hard lock widen the arm and FOV until both fit.
- (boss r1) CONTRACTS §5 "Large-target framing": actors with `framing_height() ≥ 30` (the titan: 60) → arm ≈ 64 m,
  default pitch +12°, keep hero + locked core in frame, ease back on release. Test with a 60 m stand-in.
- (skills r3) Implement `Feel.shake_floor_requested(trauma, seconds)`: while a floor is active the shake keeps
  `trauma = max(trauma, floor)` (real time, multiple floors → the max). Test it.
