# hero-asset — review r1 (lead) — PASS with MUST-FIX (locomotion art call made)

Verified: the build pipeline, 16.00 m, 46 clips, sockets (missile_l/r on the pods, cockpit 12.35 m), weapons
integration (Hailstorm alternates the shoulder rails), the captures (turn, rest front/rear, act, loco, wings,
weapons_int). The mech reads right: white/blue Gundam silhouette, the six wing blades folded upright over the
backpack read as folded binders (keep that). Accepted as-is: alignment residual 4.5 cm (0.3 % of height);
aim asymmetry past ±60° (mech-move turns the body there — integration will verify).

## Art call on known issue 1 (locomotion stride)
Neither re-authoring nor a blanket 2.3× thigh swing. Do it the way shipped games do:
1. **Speed-matched playback + stride warping**: measure each loop's native ground speed (stride / cycle from its
   foot-contact track). Playback rate = v / v_native clamped 0.8–1.35; the remaining ratio is stride warping:
   leg IK (`TwoBoneIK3D` per leg, Godot 4.6+ SkeletonModifier3D, after the AnimationTree and before the aim
   chain) moves each foot target along the velocity by k around the hip's ground projection, foot LOCKED in
   world space from contact to lift, pelvis drops ≤ 0.6 m as k grows so the knees never straighten past 175°.
2. **Run = thruster-assisted bound** (16 m/s): re-time the run so ground contact is ≤ 30 % of the cycle, a
   forward lean of ~12°, and an airborne glide between steps; the backpack jets pulse at each push-off through
   `hero_rig` thrusters (Feel `footstep_heavy` on contact stays). If IK reach caps k, the rest of the stride
   happens in the air — that is the point of the bound.
3. Gates (test, at 9 and 16 m/s, measured on the deformed foot bones): planted-foot slide ≤ 10 % of the stride
   (walk), ≤ 15 % (run); knee angle ≤ 175°; feet never below the ground plane.

## MUST-FIX
1. Locomotion per the art call above; `test_hero_model.gd` all green.
2. **Idle stance**: the current idle is bow-legged and very wide (reads as a crouching wrestler at 16 m). Use the
   same leg IK to put the feet at ~1.3× hip width with the knees over the toes; keep the slight crouch and a 2–3°
   breathing sway.
3. **Shield at rest**: in the rear view the shield sticks out backwards at hip height on the left; at rest it
   hangs along the left forearm (long axis roughly vertical), clear of the thigh in every locomotion frame.

## Evidence for r2
Foot-trace plots (foot world X over two cycles, before/after, at 9 and 16 m/s) in `captures/hero_foot_*.png`;
side-view filmstrips of walk and run (8 frames per cycle) `captures/hero_walk_strip.jpg` /
`hero_run_strip.jpg`; rest front + rear orthographic captures; test output with the slide numbers.
