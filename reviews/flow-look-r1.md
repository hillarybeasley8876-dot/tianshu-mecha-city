# flow — look item 1 result (lead) — PASS, one polish

## Verdict: PASS
Reproduced: `test_flow.gd -- --sandbox --flow --spawn=0,1,60` → **TEST 173 checks, 0 failed**. In
`captures/look_flow_pods|burst|core.jpg` the four 9 m lime discs floating beside the trunk are gone. The pods are
seeded sac clusters sunk into the shell (gaps 3.54 / 1.94 / 0.95 / 0.69 m), with hull collision, and the burst
drives the model's per-pod glow (`set_pod_alive`). Skin for placement, hull for collision: that is the right split.
The two harness fixes (the bot steering by hand, the stand scorer seeing the trunk) are worth having.

## Polish (next time you are in these files)
1. **The exposed core reads as a sticker.** In `look_flow_core.jpg` (crop: `tmp/lead/flow_core_crops.jpg`) it is a
   flat, uniformly lit violet ellipse on the trunk's chest face: no sac structure, no depth, no glow falloff. Give it
   the pod treatment: 3–5 sacs merged, sunk into a torn opening in the shell (a dark rim ring, a few chitin shards
   folded back), an inner pulse (emission breathing 0.6–1.4 at ~1.2 Hz), and a soft violet light (OmniLight3D, small
   range, no shadow) so it lights the torn edges. It is the final target of the fight; it should look like the hive's
   heart, not a decal.
2. **Pod sockets moved** (monster-assets r4, Requests 7: pod_0 10.3 → 18.8 m, pod_1 24.0 → 27.8 m). You already read
   the sockets; make sure nothing in flow still assumes the old heights (burst VFX offsets, the stand scorer's
   target heights) and that `test_flow` pins the socket read rather than numbers.
