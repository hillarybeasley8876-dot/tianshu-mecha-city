# camera-aim — review r1 (lead) — FAIL (systems solid; framing + cockpit look)

Verified myself: check 17 files clean; test_camera 49/0 and test_aim 25/0; captures reviewed. Spring arm,
collision, lock-on, soft lock, cinematic hooks and Feel.kick are exactly what we need. Settings defaults are
now fov_third 55 / fov_first 62 (core). Lock switching = flick only (mouse wheel = weapon swap) — agreed.

## MUST-FIX
1. **Hero framing** (third person): today the mech is small (~25 % of screen height) and centred, covering
   the crosshair. Target: mech feet-to-crest ≈ 38 % of screen height at rest, its body centred at ≈ 34 %
   of screen width (left of centre) and in the lower half, crosshair clear by ≥ 6 % of width. Get there
   with arm 22 m (boost 26, assault 30), pivot 12.5 m, shoulder offset that actually shifts the framing
   (camera-space right offset ~6 m), default pitch −6°. Add a test that projects the model AABB and the
   crosshair and asserts the clearance + size bands. Re-capture third_idle/run/ads/lock.
2. **Cockpit** (first person): frame coverage ≤ 18 % of the screen (measure with a mask test). Replace
   the heavy dark slabs with a refined canopy: thin bevelled struts (dark gunmetal #2A2F38, roughness 0.4)
   with cyan #4FE6FF emissive trim lines 2–3 cm, a slim dashboard at the bottom 8–10 % with a few lit
   screens, a subtle glass layer (fresnel edge reflection + faint dust, alpha ≤ 0.08). It should look
   expensive, like key art, not a block-out. Re-capture first_forward/up/side.
3. **Integration**: mech-move r2 is running — when its new player lands, run a combined tour (its
   `tour.json` or yours) through main.tscn with your rig: run, dash, boost, flight, landing — capture 6
   frames and confirm no jitter (camera follows at 120 Hz physics with the 60 fps cap) and that
   `yaw_basis()` makes WASD camera-relative.
4. Ask mech-move (status Requests) to put the placeholder `cockpit` socket at 12 m; keep your clamp.

## SHOULD
- Building occlusion dither: expose `occluder_fade(amount)` hook + group `&"camera_dither"`; city-art will
  supply the shader.
