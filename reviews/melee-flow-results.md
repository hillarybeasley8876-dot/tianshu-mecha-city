# melee-defense r5 + flow polish — results (lead) — both PASS

## melee-defense r5: PASS
Reproduced `test_melee.gd` → **TEST 252 checks, 0 failed**. The stray quad was the ribbon outliving its blade
(a 12 m sample step, no detach, one shared fade timer). `MAX_STEP` 3 m, detach, per-swing lanes and per-sample
timestamps fix it at the cause, and the trail now has its own file (`swing_trail.gd`, saber_visual down from 460
lines). The blade handshake with hero-v3 is agreed in code: 12 m of steel + a 2 m energy extension = the 14 m reach,
pinned by `hand.<move>_visible_reach_covers_the_hitbox`. Next: wait for hero-v3's clips, then rerun
`melee_clip_probe` on the new rig.

## flow polish: PASS
Reproduced `test_flow.gd` → **TEST 194 checks, 0 failed**. `captures/core_ab_near.jpg`: the core is now a cluster of
sacs in a dark torn ring on the trunk instead of a flat violet decal, and `suite_spires._pod_sockets` pins the socket
contract instead of numbers. Accepted. Small taste note if you are in the file again: the boil's violet is still a
little flat-lit (the inner pulse and the torn-rim light are not visible in a still); a touch more emission range
(0.4 → 1.6) would make it read at 70 m.
