# melee-defense — review r4 result (lead) — PASS, and a request for the hero-v3 hand-off

## Verdict: PASS
Reproduced: `test_melee.gd` → **TEST 233 checks, 0 failed**. Judged from `captures/melee_r4_strip_*` (enlarged
frame by frame): the blade sits in the right hand in every frame of the string, the lunge and the charged slash, and
sweeps with the forearm. No more 14 m blade spinning at the feet or flashing overhead — the worst defect the user
saw is gone. Thank you for proving that the suite is not vacuous (16 checks fail with the old arc path patched
back in). The trail's colour-energy fade and the per-quad alpha budget are good fixes, and so is the
lambda-capture fix in `defense_system`.

## What I still see (expected with the old clips, hero-v3 fixes it)
- The old model's clips swing 12–22 frames after the active window, and turn ~90° in 5 ticks — your table in
  Requests 1 is the hand-off. Gameplay must stay on the frame data, as you did.
- Two filmstrip frames show a small grey quad floating beside the mech (string front f7, string side f4,
  top edge): a trail fragment left behind after a ribbon restart (`MAX_SAMPLE_STEP`)? Find it and confirm. If it
  is the ribbon's first quad after a restart, do not draw a quad until two samples exist on the new lane.

## Next (small, before hero-v3 lands)
1. The trail fragment above.
2. **hero-v3 compatibility**: the new hero's saber is MODELLED and bound to `R_Hand` (`hero3_gear.py`, 9.4 m
   blade, cyan edge emissive), and hero-v3 exposes `saber_r`. When the model reports that it carries its own
   blade (agree a duck-typed `has_own_blade()` → true with hero-v3), `SaberVisual` must not draw a second 14 m
   blade over it. It keeps the trail (sampling the socket line with the model's blade length) and the
   ignite/extend glow as an overlay on the model's blade. Also make the hit volume use the real reach: if the
   drawn blade is 9.4 m, `BLADE_LENGTH` 14 m is a 4.6 m reach the player cannot see — agree with hero-v3 one
   number (I prefer the blade lengthened to ~12 m with an energy extension, so the reach stays generous and
   visible).
3. Keep `melee_clip_probe` ready: when hero-v3 lands its clips, run it on the new rig and post the table again.
