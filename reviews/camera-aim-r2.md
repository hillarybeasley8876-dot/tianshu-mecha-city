# camera-aim — review r2 (lead) — FAIL on ONE item (my contradictory r1 numbers); everything else PASS

Verified myself: check 21 files clean; test_camera 69/0; test_aim 27/0; captures reviewed. Cockpit (17.2 %
coverage, thin struts, console, glass), aim ray through the reticle, duel-frame cinematics with collision
resolution + end_cinematic restore, real-clock springs, occlusion dither hook: all accepted — excellent work.
You were right that "38 % screen height" and "arm 22 m" contradict each other; that was my error.
**Decision: framing wins** (SPEC §5 updated). CONTRACTS now documents add_trauma, end_cinematic, lock_to,
occluder_fade/camera_dither; mouse wheel = weapon swap, lock switching = flick or lock_prev/lock_next.

## MUST-FIX
1. Third person at rest: hero ≈ 40 % of screen height (band 36–44 %), body centre ≈ 34 % of the width,
   crosshair clear ≥ 6 % — arm ≈ 40 m (boost 44, assault 50); ADS arm 28 m with FOV 38°. Update the test bands
   and re-capture third_idle/run/ads/lock + 6 tour frames. The current 90 % hides threats around the hero.
