# city-kit — review r1 (lead) + round 2 brief — wave 1 PASS, now make it carry the whole frame

## r1 verdict: PASS
40 assets, `kit_assign.json` 353/391, rules test green, 2,665 credits — good, honest status. The lead rebuilt the
city in skin mode (commit 5ec4a53: 353 buildings → 4,716 kit instances) and the D7 close shots now read as a real
city (`captures/lead/city_kit_before_after.jpg`). **But the user still sees "building blocks"** at most vistas
(`captures/skin2_V1..V8.jpg`). The lead traced what is still a box — it is not your buildings:
1. **Arena cover** (`blender/city/kit/props.py::cover`): ~1,060 brown/white boxes 8–28 m, one concrete or metal box
   plus a white cap each, across every arena — that is the cube field filling V1 (`tmp/lead/v1_cover_overlay.jpg`).
2. **The far band**: kit detail ends at 450 m and city-build's HLOD proxies (the collision mass, boxes) take over —
   most of every vista is past 450 m.
3. **The 38 skipped buildings** (Block 9, the slabs over 3:1, through-holes) keep their procedural mesh.
4. Decks, viaduct parapets, connectors and pylons are still procedural slabs (pieces: railings only).

## Round 2 — build (≤ 4,500 credits, same budget rules and Tripo safety as wave 1)
1. **Cover kit** (the biggest visual win): 10–12 new assets sized to the cover boxes — container stacks (2–4 high,
   weathered, logos of fictional brands), cargo crates on pallets, concrete jersey-barrier walls, sandbag/plate
   barricades, wrecked hover-trucks, generator/transformer units, cable-drum stacks, a collapsed billboard,
   construction-site hoardings; the soft (breakable) ones visibly flimsy, the hard ones massive. Reuse the 30
   existing props first (`art/tripo/prop_*`, `game/world/props/meshes/` — container_stack, truck, wreck_car,
   barrier, storage_tank, pipe_cluster already exist). Fit every cover box (anisotropy ≤ 1.3, or tile copies along
   the long axis; never scale a container more than 1.3× on any axis — stack/tile instead). Coordinate with
   city-build: their build drops the cover render boxes for every cover id your assignment covers (collision and
   breakable slots unchanged) — ask them for a `cover` row kind in `kit_assign.json`, exactly like buildings.
2. **Far field**: replace the box HLOD look past 450 m — per-model LOD2 impostor or a heavily decimated kit mesh
   (≤ 1.5k tris, 256 px atlas) placed by the same assignment, visible 450–1,600 m, so the skyline is the same
   buildings at distance. Work with city-art (their HLOD/skyline material) and city-build (their `_hlod` proxies
   must hide where your far LOD covers). Perf gate unchanged (≤ 3,500 draws, ≤ 16.6 ms at every vista).
3. **Skipped buildings**: stacked or tiled kit models for the 33 extreme-aspect slabs (two models end to end, or a
   long-block asset: generate 2–3 long slab buildings 4:1 / 6:1 for D1/D2/D5); Block 9 gets the m04 tunnel block.
4. **Structures**: deck undersides/edges (a deck-edge fascia with lights and a soffit), viaduct parapets (s07 already
   exists — place it on viaducts too), pylons (s05) under every viaduct span, paifang (s04) at district entries,
   skybridges (s06) where the layout has them. Coordinate rows with city-build exactly as wave 1.
5. **Backs of models**: the mushy backs are visible from the decks. For the 12 most-seen models (by vista + street
   coverage) generate a back view with ys-api from the front concept (same building, rear) and use Tripo
   multiview if Studio exposes it, else mirror-and-blend the front texture onto the back faces in Blender.

## Done when
- The 8 vistas + 6 street shots (A1 container yard, A3 plaza, A4 canyon, A5 deck, A6 Sky Garden, the A5 hive) with
  NO procedural box readable as a box in the frame, side by side with the key art (`captures/kit2_*.jpg`), honest
  per-shot note; perf + VRAM per vista; `test_assign.py` extended for cover/far/structure rows; credits logged.
