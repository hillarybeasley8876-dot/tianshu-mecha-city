# city-build — review r2 (lead) — PASS for this round; r3 below

Verified: `check` 0 errors, `test_city` 105/0, nav sync 19–41 ms (the investigation holds), the export-safe
tile listing, the art environment instanced, 16 rim segments, perf 482–1,383 draws at 60 fps, and the captures.
Finding the ground crust 80 % missing was the find of the round. The lead adopted V1/V2/V3/V6/V8 from your
solver into `data/vistas.json`; V4/V5/V7 framed a ceiling or clutter and go back to you.

## Decisions
- **C15 accepted at 48 %** (L2+ 59 %): the compass carries the canyons. New requirement instead: every arena
  centre at its top tier sees the Spire top or the tether.
- C12/C13: informational (the player flies; the arena tiers under 32 m are the dossier's datums).

## r3
1. **Spire — still a disc on a stick** from mid-distance (S2/S4). Make the 10 brackets massive, visible ribs that
   sweep from the shaft at ~+120 m out to the Crown rim (lit edges along each rib), flare the shaft toward the
   top (a trumpet, not a cylinder), and light the Crown's underside (panels/strips, never a black disc).
   Also find the **black blob under the Crown** in S2/S4 (a plume or fog volume? coordinate with city-art).
2. **Vistas V4, V5, V7** — re-solve with stricter metrics: rays in the upper half of the frame hitting geometry
   within 120 m ≤ 15 % (no ceilings), subject ≥ 4 % of the frame and unobstructed, camera may rise up to +60 m
   and move up to 150 m. Hints: V4 from high in the canyon (Blender ≈ (420, 520, 110)) at Block 9 + koi; V5 from
   a high deck (≈ (420, −330, 90)) at the stacks; V7 from above the A3 canopies (≈ (60, −160, 50)) up the Spire.
   Write `data/vistas.proposed.json` + captures; the lead adopts.
3. **Navigation for gameplay**: per class, enable only links whose both ends snap within 4 m of that class's
   navmesh (report the rest); measure the metric that matters — every spawn socket → its arena centre, per
   class (target ≥ 95 %), plus arena → arena for medium (report); list failing sockets with distances (layout
   fixes them if needed). `run main.tscn 20` must log **0** `path_corridor` errors.
