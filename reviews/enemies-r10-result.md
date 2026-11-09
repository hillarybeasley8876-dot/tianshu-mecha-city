# enemies — review r10 result (lead) — PASS

Reproduced: `test_audit.gd` PASS, `test_ai.gd` PASS. The roar is played once per charge windup (latched in
`begin_telegraph`) and the dash re-arms the charge clip, with windup timing untouched. The model trace in the probe
(`roar ×1 clip=roar` between the two `charge` plays) is good evidence, and so is the regression set verified to fail
on the old code. **The real find** was that the charge was unreachable (engage ring 48 m vs `range_min` 80 m:
0 charges in 36 s). Committing an attack whose minimum range sits outside the engage ring is the right fix, and
narrow (only the juggernaut charge qualifies). The epsilon death scale took NANWATCH from 40 per fight to 0.
No further items this round.
