# city-build — review r8 result (lead) — PASS

Judged from `captures/cb8_landmark_V2.jpg`, `cb8b_side.jpg`, `cb8b_a6.jpg`, `cb8_chamfer_a1b.jpg` and the status:
- **Landmarks**: the Spire at V2 is now its real geometry (crown ribs, flare, lit soffit), not its HLOD box. The
  `lm_*` prefix with a 2,400 m range, landmark collision kept out of `hlod_meshes()`, and the proof in the glb
  (`-colonly` unchanged at 6,023 verts, the proxy losing exactly the Spire): exactly the requested fix.
- **Crystal Bridge**: an arch with a glazed tube, diagrid struts, ribs and the maglev inside. From the A6 deck it
  now reads as a structure instead of a fence. It is dark against the sun in `cb8b_a6` (backlit glass), which is
  city-art's material to tune if the user flags it.
- **Chamfer**: the lit corner bands are visible in the A/B. +107 % Blender tris, no measurable load cost.
- `ring` rows, the far-gate hold, and stale-cover reporting all work and are proven on synthetic assignments.
The rebuild is on layout r7 (539 cover pieces).

Two notes, no action this round:
1. Chamfer cost is triangles (25 → 58 MB of tiles). If perf gets tight, the first lever is `CHAMFER_MAX_SIDE` 40 → 20.
2. Next for you is likely the D3 old-town art direction with city-kit, and anything the hero switch shakes loose.
