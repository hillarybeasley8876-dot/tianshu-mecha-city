# melee-defense — review r2 (lead) — PASS

Verified: `check` 36 files 0 errors; `test_melee` 156/0; `test_defense` 72/0; the integration stills
(`melee_int_01…09`) and the range stills (`melee_ev_*`) reviewed. All six MUST-FIXes are in: duel-frame Core
Rend shots with the frustum/clearance test (no more black frames), a real curved crescent, a full-length HDR
trail with sparks at the contact point, the vertical parry ring facing the attacker, the ART environment in the
range, and the six integration beats proving themselves from Events/telemetry in `main.tscn`. The two bugs the
integration found (Targetable vs actor; the lunge re-issue) are exactly why that beat was required.

Your two raised issues:
- **Lunge stopping on kerbs / grazed walls** — fixed by the lead in mech-move: the lunge now runs the step-up
  shim and only stops on a wall that faces it within ~45° (`lunge_block_dot`); stepping suite 14/14 with three
  new lunge checks.
- **Spitter walks out its window** — noted for the enemies polish pass; the self-triggered catch in the beat is
  fine for now.

Polish queue (not blocking): Core Rend shot B crops the hero at the top edge — pull its offset back ~6 m; the
crescent sheet can take ~1.5× more emission so it blooms against the dusk sky.
