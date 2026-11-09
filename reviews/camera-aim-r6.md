# camera-aim — review r6 (lead) — PASS

Large-target framing per CONTRACTS §5 (arm 64 m, pivot +14 m, tracked pitch +12° clamped above the hero's feet,
eased in/out), with a 22-check suite (hero AND the 60 m stand-in feet-to-crest in frame, never inside geometry,
a 16 m control unchanged) and the lock tracking split into `camera_lock.gd`. The pivot lift is now in the
contract text. ADS on a giant: leave the player's zoom alone. The lead added the `Feel.shake_floor` hold to the
shake channel (`hold_floor`, wired in camera_feel, test in test_camera_feel). The titan implements
`framing_height()` in the boss round.
