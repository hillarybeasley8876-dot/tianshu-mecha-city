# Brief: city-layout — the map as data: graph, structure layout, validators, previews

## Goal
Turn the adopted map design into exact, validated data that the Blender build can follow blindly:
`data/map/level_graph.json` (nodes/edges) and `data/map/city_layout.json` (every street, viaduct, rail,
tunnel, deck, building, connector, arena, landmark, hive, anchor). Connectivity, metrics and composition
are proven by scripts and shown in previews, so the city is fun to move through AND beautiful in plan.

## Read first
`docs/MAP.md` (all — it is your contract), `ref/research/level-design-vertical.md` (§3 metrics, §4 the map,
§5 data contract, checks and the reference validator in §5.4 — reuse that code), `docs/SPEC.md` §2, §4,
`ref/images/level-design-vertical/` (look at `_sheet.jpg` + `sources.md`: Chongqing, Hong Kong, AC6 Grid
086, Titanfall maps), `ref/research/city-art-direction.md` when it exists (district looks, building kit).

## You own
`tools/map/**` (Python 3, run with `uv run --with numpy --with shapely --with networkx --with pillow
--with matplotlib`), `data/map/**`, `captures/layout_*`.

## Build
1. `tools/map/extract_graph.py`: parse §4.7/§4.8 tables from the dossier into `level_graph.json` (meta per
   MAP §1). `tools/map/validate_graph.py`: port §5.4 (C1, C2, C4–C11) with our constants → PASS.
2. `tools/map/build_layout.py` + `data/map/district_rules.json` + `data/map/overrides.json`: generate
   `city_layout.json` per MAP §3 schema and §4 district rules — seeded and deterministic. Order: terrain
   (escarpment crest along the dossier's Y ≈ +150 seam with lips where edges need free climbs, canal,
   plateau) → corridors (streets, Ring Viaduct, skyrail, tunnels, Spire avenue) following the graph's node
   positions → connectors realising every edge → arenas (polygons sized per dossier §4.5, cover pieces
   on 40–60 m spacing, 30–40 % soft) → landmarks → buildings filling the remaining blocks per district
   rules (respecting setbacks and corridor clearances, tiers by district, heights on the 4 m module,
   street walls along avenues, skyline breaks so the Spire stays visible) → hives, anchors, player start,
   skyline ring. Hand fixes go into `overrides.json` (never edit the generated JSON by hand).
3. `tools/map/validate_layout.py`: MAP §5 checks L1–L7 with clear failure messages (ids + coordinates).
4. `tools/map/preview.py`: `captures/layout_plan.png` (2,400 px top view: layers coloured — L0 dark blue,
   L1 grey, L2 teal, L3 orange, L4 magenta, Crown gold; buildings as tier-shaded footprints with heights
   labelled for C/D/E; graph nodes + edges overlaid; arenas outlined; hives/anchors/start marked) and
   `captures/layout_iso_{sw,ne,top}.png` (matplotlib 3D boxes/polylines, buildings as extruded boxes,
   decks/viaducts as slabs — enough to judge massing, layering and silhouettes). Also
   `captures/layout_section_ns.png` (S→N section through X ≈ 0 like dossier §4.3).

## Done when
- `validate_graph.py` → PASS with the printed summary (nodes, edges, loops, dead ends, travel times).
- `validate_layout.py` → PASS (all L-checks), printing counts: buildings per tier per district, connector
  kinds, cover per arena, anchors per arena, % of L1 streets covered overhead, Spire visibility %.
- Previews exist and you looked at them: no building sits on a road, every layer reads as connected, the
  Spire is the tallest thing by far, districts are visibly different in grain (dense Old Town vs open
  Foundry vs tower canyon). Report anything you could not satisfy honestly.
