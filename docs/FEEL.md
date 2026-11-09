# FEEL table (lead-owned) — one row = one `Feel.play(&"id", pos, strength)` event

Sources: `ref/research/juice-impact.md` §13 (and §2–12 for the why), `ref/research/skills-catalog.md` §4.10.
The feel unit stores each row as a `FeelEvent` resource (`fx/events/<id>.tres`) and implements the columns.
Gameplay units call `Feel.play(id, world_pos, strength)` at the right moment and never hand-roll juice.
Rules: gunfire never freezes; melee uses LOCAL hit-stop (`Feel.local_hit_stop([attacker, victim], s)` —
victim frozen + vibrating, attacker at 5 % speed); global hit-stop only where marked G (rate-limited in
core) and NEVER for swarm fodder. Player locomotion is never frozen (CONTRACTS §3 clocks). Trauma is ADDED (clamp 1, shake = trauma², rotational noise, linear decay 1.2/s). Distance falloff
`clamp(1 − d/falloff, 0, 1)`. 1st person: shake ×0.6, FOV ×0.75, VFX opacity −40 %. Flash ≤ 2/s.
Sound layers: T transient, B body, S sub, M mechanical, Tl tail, D debris, UI. Rumble = weak/strong/ms.

| id | Hit-stop | Shake (+trauma) | Flash / post | FOV | Slow-mo | Particles / decals | Sound | Rumble |
|---|---|---|---|---|---|---|---|---|
| rifle_fire | — | kick 0.25° up | muzzle light 2 f | — | — | muzzle ring | T "tchew" + M | 0.15/0/40 |
| rifle_hit | — | 0.02 | enemy hit_flash 2 f | — | — | spark_beam 12 + scorch decal (world) | T tick + B | 0.15/0/30 |
| rifle_charge_1 / _2 | — | 0.05 / 0.1 at release | muzzle ring per stage | +2° / +4° release | — | charge sparks, ring | rising whine + stage click | 0.2/0.3/60 |
| rifle_stage2_hit | local 3 f | 0.12 | enemy flash 4 f | — | — | pierce burst, 8 m blast | T + B + S | 0.3/0.5/90 |
| gatling_fire (per 3 shots) | — | kick 0.15° | tracer | — | — | shell casings (MultiMesh) | loop T + spin M | 0.1/0.05 sustained |
| gatling_hit | — | 0.01 | hit_flash 1 f | — | — | spark_bullet 6 | tick | — |
| gatling_vent_perfect | — | 0.06 | white ring | +3° | — | steam burst | hiss + chime | 0.3/0.2/80 |
| gatling_vent_good | — | 0.03 | — | — | — | steam puff (short, no ring) | hiss | 0.2/0.1/60 |
| gatling_overheat | — | 0.12 + kick 0.4° up | white flash 2 f | — | — | steam burst at the barrel | alarm + heavy hiss | 0.4/0.5/140 |
| gatling_jam | — | 0.18 + kick 0.6° down | red flash 2 f, vignette 0.15 | — | — | smoke puff + jam sparks | clunk + grinding tail | 0.5/0.6/200 |
| missile_launch | — | 0.04/missile | hatch glow | — | — | bloom smoke | fwip ×n | 0.1/0.1/40 |
| missile_hit | local 50 ms (first of salvo) | 0.25 falloff 160 m | enemy flash 4 f, OmniLight 3 f | — | — | missile_blast + shockwave ring 0→20 m/180 ms | T + B + S 35–55 Hz + Tl + D | 0.35/0.6/180 |
| melee_light | local 5 f | 0.15 | enemy flash 3 f | +4° lunge | — | melee_light arc sparks | T clang + B + M servo | 0.4/0.2/80 |
| melee_heavy | local 9 f | 0.30 + kick 1° along swing | enemy flash 5 f | +4°, −2° on hit | — | melee_heavy + ring 0→8 m | T + B + S + M | 0.6/0.6/150 |
| lunge_hit | local 7 f | 0.25 | enemy flash 4 f | +8° travel | — | trail + impact | whoosh → T + B | 0.5/0.4/100 |
| charge_slash | local 10 f | 0.35 | white arc | −4° | — | crescent wave 90 m | T + B + S + Tl | 0.6/0.8/200 |
| finisher (Core Rend, Return Cut) | local 10 f | 0.55 | 1–2 f B/W impact frame + flash 6 f | −10° push, +6° release | 0.3× for 0.3 s | finisher burst | swell → T + B + S + Tl; world −9 dB 0.5 s | 0.8/1.0/250 |
| parry_perfect | local 8 f (both) | 0.10 | white-gold ring, chromatic 4 f | — | — | 40 sparks | bell "ting" + thump | 0.8/0.2/80 |
| block | — | 0.08 | blue hex panel | — | — | sparks on shield | muffled clank | 0.3/0.2/60 |
| catch_release | — | 0.12 | — | +3° | — | caught rounds burst | whoomp | 0.4/0.4/120 |
| perfect_dodge | — | — | desaturate + cyan edge 0.35 s | +6° | witch 0.3× 0.35 s | afterimage ×3 | reverse whoosh + heartbeat | 0.3/0.1/80 |
| dash | — | 0.06 + kick 0.6° opposite | chromatic 2 px 120 ms, radial blur 0.04 | +10° in 60 ms, back 250 ms | — | plume + 3 afterimages | T chuff + whoosh | 0.5/0.3/90 |
| boost_start | — | 0.08 | speed lines on | +6° hold | — | thruster burst + dust ring (< 10 m alt) | ignition + roar loop + S 40 Hz | 0.2/0.4/200 then 0.1/0.15 |
| assault_boost | — | 0.10 | radial blur 0.06 hold, speed lines | +10° hold | — | shock cone | sonic boom + roar | 0.3/0.5/250 |
| jump | — | 0.04 | — | — | — | dust ring | thrust T + servo | 0.2/0.2/60 |
| land_light | — | 0.16 + kick 1.2° down + dip (by impact, 0.35 m at a hop) | — | −1° 50 ms | — | dust puff | thud + hydraulics | 0.15/0.45/100 |
| land_heavy | — | 0.55 + kick 3° down + dip (by impact, to 1.2 m) | radial blur 0.03, 120 ms | −4° 90 ms | — | crater decal 8 m, debris, dust ring, shockwave ring 14 m / 0.25 s | T + B + S + D | 0.5/1.0/260 |
| footstep_heavy | — | 0.03 | — | — | — | dust | thump + clank | 0.05/0.15/50 |
| hurt_light | — | 0.18 | red vignette 0.25/150 ms | — | — | sparks on own armour | ping + B | 0.3/0.2/100 |
| hurt_heavy | G 83 ms | 0.50 + kick 1.5° away | red vignette 0.6/350 ms + chromatic 3 px | −3° | — | armour chunk + smoke 2 s | T + B + S + alarm; world LPF 400 ms | 0.6/0.8/300 |
| last_stand | — | 0.30 + kick 1° away | desaturate 0.5 + cyan edge 1.5 s, vignette 0.3 | −5° 250 ms | 0.5× 1.5 s (60 s CD, witch off) | thruster burst + steam vents | alarm + low sub | 0.5/0.8/400 |
| near_miss | — | 0.04 + yaw nudge 0.4° | edge blur if suppressed | — | — | — | doppler flyby | 0.25/0/60 |
| kill_small | local 40 ms (victim only; G 40 ms only for the LAST enemy of a wave) | 0.12 falloff 120 m | white 0.15 1 f (< 80 m, ≤ 2/s) | — | — | kill_small + wreck | B blast + D; UI confirm | 0.3/0.3/100 |
| kill_large | G 100 ms (≤ 1 per 2 s; local if another G fired < 2 s ago) | 0.45 | white 0.25 2 f | −3° → 0 in 0.4 s | 0.35× 0.35 s (≤ 1 per 6 s) | kill_large ×3 chained + burning wreck 30 s | T + B + S + Tl + D; world −6 dB | 0.5/0.9/350 |
| boss_kill | G 150 ms (exempt from the kill budgets) | 0.45 | white 0.25 2 f | −3° → 0 in 0.4 s | 0.2× 1.2 s | kill_large ×3 chained + burning wreck 30 s | T + B + S + Tl + D; world −6 dB | 0.5/0.9/350 |
| jackpot | — | 0.25 | B/W frame 1 f | −4° | 0.2× 0.5 s | — | JACKPOT callout | 1.0/1.0/200 |
| stagger_enemy | local 6 f | 0.20 | enemy amber flash, "STAGGER" | — | — | armour sparks | metal groan | 0.3/0.4/120 |
| boss_stagger | G 150 ms | 0.60 | B/W frame 1 f + white 0.4 2 f | −6° 120 ms | 0.5× 0.4 s | plates eject, arcs, steam | groan + S + stinger | 0.6/1.0/400 |
| shockcore | local 4 f (victims) | 0.30 | white 30 % 2 f, radial blur 6 f | — | — | fresnel shell 0→32 m in 0.18 s, scorch ring | inhale → crack-boom | 0.4/1.0/220 |
| collapse | local 4 f | 0.25 | violet flash | — | — | implosion → flash | reverse cymbal + boom | 0.4/0.7/180 |
| plunge_land | local 6 f | 0.40 | window-crack flash < 40 m | −3° | — | crater decal, radial debris, dust ring | whistle → boom + 60 Hz | 0.6/1.0/260 |
| rift_step | — | 0.05 | ripple + chromatic 2 f | +8° 4 f | — | ghost + implosion ring | reversed whoosh + thump | 0.3/0.2/60 |
| anchor_latch | — | 0.05 | — | speed lines > 70 m/s | — | latch sparks | twang + clank | 0.2/0.1/50 |
| fins_launch | — | 0.03 | — | — | — | fin trails | chime cascade | 0.1/0/40 |
| ward_hit | — | 0.02 | hex ripple | — | — | ripple | glass ring | 0.1/0/30 |
| overdrive_ignite | — | 0.20 | gold rim, vignette | −6° → +4° | 0.3× 0.25 s | vents + afterimages | synth swell + roar | 0.3/0.7/300 |
| lance_fire | — | 0.15 continuous (+0.8 at release) | B/W frame 2 f at release | −12° charge, +14° release | enemies 0.3× during the 0.8 s charge | beam layers, heat haze | riser → sustained roar + S | 0.3/0.6 every 250 ms |
| boss_roar | — | 0.15 global, 0.4 within 300 m | — | — | — | dust shake from buildings | roar (3D, 1.5 km audible) | 0.3/0.6/600 |
