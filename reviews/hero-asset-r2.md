# hero-asset — review r2 (lead) — PASS (short polish round r3)

Verified: `check` 0 errors; `test_hero_model` 193/0 (slide 0–1 % walk, 0 % run, knees ≤ 171°); the walk/run
strips, before/after foot traces, rest front/rear, shield, thrusters; weapons integration and a `--nan-watch`
fight clean. The planted feet now hold their world point — exactly the art call. Narrow stance and the shield
are right. The audit fixes (bone-space jet directions, plates) and the `hero_rig.gd` split are good work.

## Answers
1. `PlayerMech.hit_pause` forwarding → mech-move (its round is queued; noted). The melee hold → melee-defense.
2. Cadence: yes, raise `MAX_PELVIS_DROP` to 1.0 m (the deeper, heavier gait suits a 16 m machine) and blend
   from the walk to the bound above ~6 m/s so the walk cadence never exceeds ~2×.
3. Joint fillers: they read as black bowling balls from the side. Make them ~20 % smaller, gunmetal (the inner
   frame colour) with a panel-line/ring normal so they catch light; never unlit black.
4. `blender/lib/export.py`: keep your local copy for now.

## r3 (polish)
Items 2 and 3 above; re-capture the walk/run strips and a side close-up of a knee and an elbow mid-stride;
keep the suite green.
