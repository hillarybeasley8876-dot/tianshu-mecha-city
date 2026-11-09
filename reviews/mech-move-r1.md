# mech-move — review r1 (lead) — FAIL (strong base; 3 gameplay gaps)

Verified myself: check 32 files clean; test_locomotion 41/41; tour movie watched (run, boost with wings,
flight over the bridge, deck landing all read well). Requests answered: `can_cancel(tag)` and
`drain_energy` are now in CONTRACTS §5; model origin convention (feet y=0, −7.5 m) is in CONTRACTS; cockpit
eye ≈ 12 m.

## MUST-FIX
1. **Stepping (SPEC §4)**: implement step-up ≤ 2.5 m (test_move: up → forward → down, only on walkable
   tops) and, while boosting/sliding, auto-hop over obstacles whose top is ≤ 7 m above the feet (ShapeCast
   ahead at 1.5× speed·0.2 s; hop impulse just enough to clear + 1 m; no hop into walls taller than 7 m).
   Tests: a 2 m curb at run speed (no stop), a 6 m block while boosting (hops), a 10 m wall (stops/slides).
2. **Landing classification**: a plain hop must NOT be a hard landing (feels sluggish). New rule: soft if
   downward speed < 25 m/s, hard if ≥ 25 m/s (≈ 12 m fall), `land_heavy` feel only ≥ 32 m/s (≈ 20 m fall);
   update tuning + tests (hop → soft; 40 m deck drop → hard + land_heavy).
3. **Split `mech_locomotion.gd` (496 lines)** below 400 (e.g. ground/dash vs landing/lunge/locked helpers)
   before adding the stepping code.
4. **Assault pitch**: in flight mode, assault boost uses `assault_pitch_deg` (45°/s pitch) so the player can
   dive/climb at assault speed; test it.
5. **Integration**: camera-aim is about to land — when `player/camera/camera_rig.tscn` exists, re-run your
   tour with the real rig (no `--stub=camera`) and fix anything that breaks (movement must be relative to
   `Game.camera_rig.yaw_basis()`); captures `captures/mech-move_rig_*.jpg`.

## SHOULD
- Coasting labelled `run`: give it its own state name (`coast`) for the model/HUD.
- Telemetry: add `land_kind`, `step_events` counters for the tests.
