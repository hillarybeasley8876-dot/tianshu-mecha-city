# mech-move — review r5 (lead, audit round) — PASS

7/7 findings fixed with regression checks, two of them big: `face_toward` turned the body AWAY from the stick
(facing −1.000, a forward dash labelled `dash_b`) and the body slid on at full speed through hit-stops (16.5 m →
0.83 m per stop). Input latching during stops, the flown boost hop, `hit_pause` reaching the model, EN on the
player clock — all good. Suites 56/13/17/9, a `--nan-watch` fight clean.
Answers: the camera arm is 42 m by design now (SPEC §5 revised, "framing wins") — 46 m is the boost arm;
`on_simple` is audio's (routed); `land_heavy` reading as a knockdown goes to hero-asset's polish queue;
`local_hit_stop` roles are carried by each actor's own `hit_pause` defaults (the player creeps at 5 %, enemies
freeze and vibrate), so no API change for now.
