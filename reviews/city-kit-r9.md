# city-kit r9 — lead brief: the far field is boxes; make it buildings

## What the player sees
From any high camera (V2, V5, D5/D7 roofs; `captures/r12_facade_ab.jpg` and `r12_roofs_ab.jpg`), the
horizon is a wall of plain pale boxes with stepped tops. That is the user's 搭积木 complaint, at the
scale of the whole city. Two sources:

1. **The skyline ring.** These are the 96 boxes in `data/map/city_layout.json["skyline"]`:
   - 740–1 229 m from the centre;
   - 80–260 m tall (median 168);
   - 55–109 m wide;
   - height:width 0.75–3.8.

   city-build has supported `ring` rows since its r8 (`blender/city/skin.py`: a `ring` row indexes
   `skyline` and drops that box from `skyline.glb`). **No ring row has ever been written,** so all 96
   boxes still render.
2. **Six tiles keep their box proxy.** `far.build()` stands a tile's HLOD proxy down only when every
   building in it is skinned. Eight unskinned buildings hold six tiles up:

   | tile | unskinned |
   |---|---|
   | t2_3 | D2_w004 |
   | t2_6 | D4_w033, D4_p001 |
   | t4_1 | D7_s001 |
   | t5_4 | D5_w049, D5_block9 |
   | t5_5 | D5_p009 |
   | t6_6 | D5_w046 |

## Do
1. **Ring rows.** For each of the 96 skyline boxes, emit a `ring` row in `kit_assign.json`.
   - **Model.** A tall box gets a tower, a wide one a megablock or mid-rise. Fit it with the same
     anisotropy limits the buildings use. Spread the models so no two neighbours share one, and so the
     crowns vary (spires, setbacks, flat tops).
   - **Yaw.** Turn each model to present its best silhouette to the city centre.
   - **Draw it.** The placer draws ring rows from the model's FAR glb.
     - Visible over the whole map: the ring is the horizon from every point. Set the visibility range
       to cover the farthest pairing (about 3 km), and nothing near.
     - One MultiMesh per model.
   - **Haze.** The boxes wore city-art's `mc_skyline` horizon band. A kit model wears `mc_kit_body`,
     whose haze already runs through `mc_haze`. Check at V2, V5 and V7 that the ring sits in the
     horizon band and does not read darker or sharper than the boxes did. If it does, write it as a
     request to city-art; `mc_kit_body` / `mc_haze` are city-art's files.
2. **Skin the eight buildings.** Fit existing models where the box allows.
   - Special shapes stay special. `D5_block9` is the Liziba-style megablock the rail pierces; it needs
     a model with the hole, or it stays a proxy and says so. `D4_p001` is a podium shaft.
   - Tripo credits are available (13 101) if a new model is the right answer. Follow the Tripo rule:
     never retry a creating POST after a transport error.
3. **Rebuild through city-build's own tools** (city-build is idle). Do NOT edit its files; running
   them is fine:
   - `python3 tools/citykit/assign.py`, then `tools/blender.sh run blender/city/build_city.py`, so
     `skyline.glb` drops the ring boxes and the six tiles stand down;
   - then re-bake the settle cache and run `test_settle_cache`, `float_audit`, and city-build's C18
     (`tools/city/checks.sh`).

4. **c01 has no roof map.** Its 109 × 181 m footprint is 5 005 cells at 2 m, over `roofmap.MAX_CELLS`
   (4 096), so it is skipped, and `world/art/tests/test_roof_map.gd` FAILS on it (3 placed rows). Use a
   coarser cell for big models, so every building model gets a map. Then re-run `test_roofmap.py`
   and city-art's `test_roof_map.gd`.

## Gates
- **Count.** Ring boxes still rendered: 0 (or each one named with its reason). Tiles keeping the proxy:
  0, or named.
- **The look.**
  - V2, V5, V7 and the D5/D7 roof cameras, before and after, at the shipping default.
  - The horizon reads as a skyline of buildings, with no stepped-box wall.
  - Also a 2× crop of the V5 horizon.
- **Cost.**
  - Vista draws and primitives before and after: the ring adds 96 far instances, so print the delta.
  - Frame time at V2 and V5, matched arms, `--render-scale=1`.
- **Unchanged.** `rebase_glb.py --check` PASS, `test_assign.py`, and KitPlacer draws at the A1 spawn at
  98 or under.

Commit per step with an explicit path list. Report in `status/city-kit.md` (an r9 section).
