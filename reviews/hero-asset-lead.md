# hero-asset — lead notes (read at every session start)
- Wings at REST fold along the back (blades pointing down/back, tips below the shoulder line), NOT a vertical fan
  of spikes above the head (seen in captures/hero_test_a.jpg). `set_wings(1.0)` spreads them to the g1-1.png pose.
- Joints: rigid skinning opens gaps at elbows/knees/hips — fill each joint with a simple inner-frame piece (gunmetal
  cylinder/ball parented to the child bone, slightly larger than the gap) so bends show mechanism, not holes.
- Mocap feel: the Tripo clips are human mocap; for weight, add 2–4 f anticipation holds before big actions, lower
  the playback of heavy clips ×0.9, and add a hip-height dip on footfalls. Foot-slide gate: in walk/run loops the
  planted foot may slide ≤ 10 % of the stride (measure in a test).
- AnimationTree MANUAL process advanced with Feel.player_delta (clocks contract).
- Missile sockets missile_l / missile_r on the shoulder pods; cockpit socket at 12 m.
- (21:45) `art/tripo/hero_anims/hero_proxy.glb` was RE-EXPORTED with 46 clips: new `land_heavy` (deep crouch, fist
  to the ground, rises) at index 45; the old `jump_down` preset (index 7) now maps to `hit_knockdown` (it reads as
  a prone knockdown — use it for heavy knockdowns). Re-import using the updated `data/hero_anim_map.json`.
- (audit, 2026-11-02) Robustness findings for your files: reviews/hero-asset-audit.md — fix them in this round after your current items (regression checks for the high ones).
- (mech-move r5) In game the hero's `land_heavy` reads as a prone knockdown — check the clip map (index 45 is the
  deep-crouch fist-to-ground landing; index 7 jump_down → hit_knockdown) and capture a hard landing.
