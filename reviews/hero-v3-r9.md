# hero-v3 r9 — lead brief: the user's two defects. The hero floats above the ground, and the thrusters are in the wrong place

## Why
The user watched the game and named exactly two things: **"角色和地面浮空"** (the hero floats above the
ground) and **"走路飞行 喷气口还是错位的"** (when walking and flying, the jet nozzles are out of place).

The lead checked `captures/hero3_flight_sandbox_t1_6.jpg`, `t5_0.jpg` and `t10_5.jpg`; the sheet is
`tmp/lead/r16/hero_now.jpg`:
- the two big white thruster flames float **above the hero's head and shoulders**, detached from the
  back;
- the calf flames sit **beside the knees**, not on any nozzle.

This round is only these two defects. Your r8 work stands: the flight pose, the drone API and the dead
power-down. It is still to be accepted, and the lead will look at it with this round.

## House rules for this round (the user's machine)
The user works on this Mac and was furious that tool windows took it over. You are the ONLY worker
running.
- **Measure headless first.** Skin the mesh on the CPU, as your r3 leg probes did.
- **Keep windowed runs few and short.** They now open as a small, unfocused corner window
  (`MC_TOOL_WINDOW`, dc678f3). Never fullscreen, and nothing longer than about 3 minutes.

## 1. The hero floats above the ground
1. **Measure it.** Report the gap between the lowest sole vertex of each planted foot and the floor
   under it, per frame, two ways:
   - against the **collision** floor (the physics ray);
   - against the **rendered** floor. Ray against the visible mesh: kit tiles, decks, props. See
     `game/tools/float_audit.gd` for the render-surface ray method.

   Cover idle, walk, run, strafe, turn in place, slide, a hop landing and a heavy landing. Do it on the
   sandbox floor, on a ramp, and on a kerb or step edge. Do it in the city: the A1 container yard (where
   the player starts), a deck and a kit rooftop.
2. **Find the root cause.** Report the numbers that pin it. Candidates:
   - the model origin vs the PlayerMech capsule bottom;
   - your ground lock or sole offset;
   - foot roll about the ankle;
   - the IK planting on the collision surface while the visible floor is lower (render vs collision);
   - the pelvis solve holding the feet up.
3. **Fix it at the cause.** If the cause is in `game/player/mech/**` (the capsule, floor snap), you may
   make the minimal change there, because you are the only worker this round. Record it in your status
   and in `status/mech-move.md`.
4. **Gate:**
   - planted feet within **±0.10 m** of the rendered floor in ≥ 95 % of planted frames, and never more
     than 0.25 m above it;
   - the same against the collision floor;
   - every case above, before and after, in a table;
   - side-view captures at foot height: sandbox flat, ramp, kerb, A1 yard, rooftop, idle and walk.

## 2. The thrusters are misplaced
1. **Find the real nozzles on the mesh.** Locate the back thruster ports, and the calf or foot ports
   if the concept and mesh have them (`art/concept/hero/v3/a1-1.png`, `art/tripo/hero3_a1p` parts).
   - Measure each nozzle's mouth position and axis in the bone's frame. Do not hand-place them.
   - Replace `hero3_rig.gd` THRUSTERS' guessed bone offsets (`BackFrame ±1.5`, the calves) with the
     measured ones.
   - If the mesh has no calf nozzle, remove the calf flames rather than float them in the air.
2. **The states.**
   - **Walking:** no flame, or at most a small nozzle glow at the mouth, unless boosting.
   - **Boost, dash, hover and flight:** the flames grow from the nozzle mouth along the nozzle axis,
     and follow the flight lean you built in r8.
3. **Gate:**
   - each flame's root is within **0.3 m** of its nozzle mouth, projected and measured, at rest, in a
     walk, in a boost, in hover and in a 50 m/s and 84 m/s flight;
   - close-up captures from behind and from the side for each state, beside the concept;
   - walk captures with no floating flames.

## Gates (all)
- `tools/godot.sh check --only=res://player/` is clean, every hero3 suite passes, and `test_damage` and
  the mech suites pass if you touched `player/mech`.
- The before/after tables and captures for items 1 and 2 are in an r9 section of `status/hero-v3.md`.
- Commit with explicit paths. Never use git stash.
