# MAP — "Escarpment City around the Spire" (lead-owned contract)

Source design: `ref/research/level-design-vertical.md` §3 (metrics), §4 (map: districts, arenas, loops, node
list §4.7, edge list §4.8), §5 (data contract + checks C1–C17 + reference validator §5.4). That design is
ADOPTED as the skeleton; this file fixes what the dossier leaves open and defines the layout data.
Coordinates: Blender X = east, Y = north, Z = up, metres, origin = map centre. Godot = (X, Z, −Y).

## 1. Tuning constants the checks must use (from SPEC §4, not the dossier's guesses)
H 16, capsule r 4 h 16, J 40 (boost-jump apex), free climb ≤ 32 m, ambiguity 33–47 m (tagged `skill`
only), hard step ≥ 48 m, R_min 150 / R_max 250 (air range), v_boost 42, v_assault 84, dodge 24 m,
fall gravity 25.5 m/s² (use it in arc sampling C12), no-fly ceiling +260, playable ±700 m, skyline ring to
±900 m (scenery only, beyond soft walls).

## 2. Gameplay assignments (supersede SPEC §8 place names)
- Start: H0 Insertion Pier (drop from the carrier). Tutorial fight: A1 Container Yard (Rippers, 1 Mantis).
- **Hive Spires (蚀巢, 3 objectives, any order)**: in A2 Interchange Knot (west, L1–L3), A5 Foundry Decks
  (east, L1–L3 + stack), A6 Sky Garden (south rooftops, +144). Each sits at the arena's centre of mass,
  60 m tall, on the arena's highest tier that still has ≥ 3 approach routes.
- A3 Spire Plaza and A4 Megablock Canyon host roaming packs, ambushes and the Harrier patrols.
- Boss: Brood Titan (60 m) on the Crown deck B1 (+224, 320 × 320 m) — entered only by the Ascension
  Catapult (vcat) at S4 after all 3 spires fall; the Titan walks the skyline ring before that (scripted path
  outside the playable square, visible from ≥ 80 % of the map, roars when a spire dies).
- Skyhook anchor nodes: glowing anchors every 40–60 m on rooftop edges, skybridge undersides, crane
  booms, viaduct pylons — at least 8 per arena, all reachable within 120 m (anchor range).

## 3. Layout data: `data/map/level_graph.json` + `data/map/city_layout.json`
`level_graph.json` = dossier §5.1 format, nodes/edges transcribed from §4.7/§4.8, `meta` from §1 above.
`city_layout.json` = every structure as data (Blender builds geometry ONLY from this file):
```
{ "meta": {"units": "m", "up": "Z", "version": 1},
  "bounds": {"half": 700, "ceiling": 260, "skyline_half": 900},
  "terrain": {"escarpment": {"crest": [[x,y],...], "height": 32, "lips": [{"pos":[x,y], "width": 40}]},
              "canal": {"polygon": [[x,y],...], "water_z": -16, "bank_z": 0},
              "plateau": {"polygon": [[x,y],...], "z": 32}},
  "streets":   [{"id","kind":"avenue|street|alley","z":0|32,"width":m,"points":[[x,y],...]}],
  "viaducts":  [{"id","kind":"ring|spur","z":32,"width":56,"points":[[x,y],...],"pier_spacing":48}],
  "rails":     [{"id","z":80,"width":24,"points":[[x,y],...],"through":["building ids it pierces"]}],
  "tunnels":   [{"id","kind":"trunk|squeeze|old_line","z":-40,"width":56,"clear":34,"points":[[x,y],...]}],
  "decks":     [{"id","kind":"plaza|skydeck|garden|crown|platform|terrace","z":m,"thickness":4|6,
                 "polygon":[[x,y],...],"parapet":5,"under_clear":m}],
  "buildings": [{"id","district":"D1..D7","tier":"A|B|C|D|E","archetype":"slab|setback|podium_tower|
                 twisted|megablock|industrial|terrace|warehouse|pagoda|stack","center":[x,y],"size":[w,d],
                 "rot":deg,"base_z":0|32,"height":m,"roof_walkable":bool,"breaches":[{"face":"n|e|s|w",
                 "z":m,"width":m,"height":m}]}],
  "connectors":[{"id","edge":["K3","K4"],"kind":"path|ramp|edgejump|stairs|lift|vcat|lcat|vent|drop|rail",
                 "from":[x,y,z],"to":[x,y,z],"width":m,"tags":[]}],
  "arenas":    [{"id":"A1..A6|B","polygon":[[x,y],...],"tiers":[z,...],
                 "cover":[{"center":[x,y,z],"size":[w,d,h],"soft":bool}],
                 "spawn_sockets":[{"id","pos":[x,y,z],"kind":"hatch|door|lift|tunnel|drop|breach"}]}],
  "landmarks": [{"id","kind":"spire|pagoda|knot|cranes|crystal_bridge|stacks|block9|hologram",
                 "pos":[x,y,z],"params":{}}],
  "hives":     [{"id","arena","pos":[x,y,z]}],
  "anchors":   [{"pos":[x,y,z],"normal":[x,y,z]}],
  "player_start": {"pos":[x,y,z],"yaw_deg":deg},
  "skyline":   [{"center":[x,y],"size":[w,d],"height":m}] }
```
**v2 fields (layout r2, additive)** — buildings: `podium_z`, `holes: [{polygon, z, height, clear}]` (arcades /
corridor-through openings), `through: [corridor ids]`, `fronts: street id` (kerb wall lot), `carries: deck id`,
`supports`; decks: `skybridge` + `span: [building ids]`, `columns`, `supported_by`, `canopy`, `under_clear`,
crown `rim_steps` / `fins` / `core` / `holes`; corridors: `through: [building ids]`.
**Sky graph (r3)**: `"sky_waypoints": [{"id","pos":[x,y,z],"district","arena"?}]`, `"sky_edges": [[id,id],...]`
— flyer routing (Harriers, boss adds): +60…+250 m, nodes ≥ 12 m and edges ≥ 8 m clear of every box, one
connected graph, ≥ 24 nodes per district, ≥ 6 within 150 m of each arena centre, ≥ 8 ringing the Crown.
Every graph edge must be realised by exactly one connector (or a street/viaduct/rail/tunnel segment that
contains both endpoints); every node lies on a walkable surface of its layer (± 2 m).

## 4. District rules (the generator's brief; numbers from dossier §3.2/§4.4)
| District | Street pattern | Buildings (tier mix, archetypes) | Must-haves |
|---|---|---|---|
| D1 Harbor (SW) | docks −12 along the canal, Canal Road (avenue 80 m) | A warehouses + container stacks 12–16 m (cover), B 48–64 m port offices | 4 gantry cranes (+48 cab = H3), dock trench, insertion pier H0 |
| D2 Interchange Knot (W) | spiral ramps r 60–90 m at levels 0/+16/+32/+56/+80 around K1–K5 | B/C towers outside the knot ring only | the Knot (landmark): 3 stacked loops + flyovers; Ring Viaduct W passes through |
| D3 Old Town (NW, plateau +32) | narrow 24–32 m alleys + 40 m streets on terraces +16/+32/+48 | A/B terrace blocks (Chongqing/Kowloon density), balconies as stairs | Stilt Pagoda to +128, cliff caches, mine shaft to L0 |
| D4 Spire & Civic Core | Spire Avenue 96 m N–S; Plaza A3 sunken court −20; Forum S5 on the plateau; **Civic Quarter** street grid on the plateau north of the Forum | D landmark towers ring the plaza; Civic Quarter: setback halls, podium towers, a colonnaded archive block, 48–144 m rising to the north edge (a backdrop behind the Spire) | the Spire 360 m (stepped crown, collar ring +80, roof ring +160, crown deck +224, light tether into the sky), Root Station S2 (L0) |
| D5 Megablocks (NE, plateau) | canyon floor (L2) 90 m wide between megablocks | C/D megablocks 128–240 m, skybridges at +80/+128 every 80–120 m | Block 9 with the rail hole + giant hologram, facade breaches (spawns) |
| D6 Foundry (E/SE) | open deck lattice +32/+80 over a L1 floor, molten channel | industrial halls (B), 4 reactor stacks to +144 with plumes | vcat + updraft vent, conveyor tunnels |
| D7 Financial (S) | avenue grid 80–96 m, streets 48 m | C/D glass towers 128–240 m | Sky Garden deck +144 between towers (A6), Crystal Bridge +176 |
General (revised after layout r1 and r2): widths come from OUR dodge (24 m) — `avenue_min = 2 × (24 + 4) = 56 m`:
avenue 56–72 m, street 36–48, alley 24–32; building setback ≥ 4 m from any corridor edge. **Podium-through**:
streets (not avenues) may pass THROUGH building podiums via arcades ≥ 32 m clear × the street width (towers
above; up to 40 % of street length in D4/D5/D7) — counts as frontage. **Viaduct/rail-through** (r2): in D4/D5/D7
a tower may straddle the Ring Viaduct (+32) or the Skyrail (+80) — the corridor runs through a hole = corridor
width + 2 × 4 m, clear ≥ 40 m above a viaduct deck / ≥ 32 m above the rail (Liziba-style, a signature image);
declared as `holes` + `through` on the building and in the corridor's `through`. **Coverage** is measured
against BUILDABLE land (non-corridor land minus arena floors, plazas and landmark keep-outs; print both):
D3 ≥ 65 %, D5 ≥ 75 %, D7 ≥ 60 %, D2/D4/D6 ≥ 50 %, D1 ≥ 40 %; avenue frontage built ≥ 50 %. The Crown deck B
is CIRCULAR (Ø 300 m, stepped rim, 4 fins 24 m tall), not a square. Accepted graph exception: C11 A4→A5 (the
L3 rail alternative is 0.7 s slower). **Overhead cover**: inside arenas and within 100 m of their outline
40–60 % of L1 street length lies under decks/viaducts; elsewhere ≤ 25 %, and only structures that read as
architecture (podium decks spanning between buildings, skybridges, viaducts, rails) — no free-standing
canopies outside arenas; every deck has `columns` at ≤ 48 m or a `span` between two buildings. No straight
sightline > 300 m along a street; building facades on a 4 m floor module; roofs of tier C/D within the L4 band
are walkable with 4–6 m parapets.

## 5. Checks (must pass before city-build starts; rerun after every change)
Graph: dossier C1–C11 on `level_graph.json` (port the §5.4 validator, add our constants).
Layout (new): L1 every edge realised (see §3); L2 no building/deck intersects any corridor (street, viaduct,
rail, tunnel) except declared `through`/breach holes; L3 widths/grades/clearances per §4 (ramps ≤ 20°,
under-deck clear ≥ 24 m, tunnels clear ≥ 32 m); L4 arenas: ≥ 3 entries on ≥ 2 layers, every sampled point
within 60 m of full cover ≥ 20 m tall, ≤ 5 % sightlines > 350 m (2.5D ray test vs building/cover boxes);
L5 Spire crown visible from ≥ 80 % of navigable samples (2.5D); L6 anchors ≥ 8 per arena; L7 everything
inside ±700 m except skyline; L10 sky graph connected with the clearances above. Godot-side C12–C17 run later in city-build.
Previews (every round): top plan coloured by layer + 3 isometric views (`tools/map/preview.py`).
