# city-layout — lead notes (mid-round, from captures/layout_plan.png + iso 19:40)

The graph, arenas, Spire collar, Knot, escarpment, canal and hives are in the right places — keep them.
As a CITY the plan fails the key art: it reads as sparse suburbs (scattered small boxes on an empty
ground, random diagonal street lines, octagonal arenas). Fix the generator's structure, not by patching:

1. **Street network first, per district**: a hierarchy — avenues 80–96 m, streets 40–56 m, alleys 24–32 m —
   as connected grids with a district orientation (D3 Old Town: irregular terrace lanes following the
   escarpment contours; D5 Megablocks: wide canyon + cross streets; D7 Financial: rectilinear 120–160 m
   blocks; D1 Harbor: dock grid; D6 Foundry: industrial grid with rail spurs; D2 the Knot + radial roads).
   Every graph node sits on or next to a corridor; streets end on other streets (no dangling lines).
2. **Blocks → lots → buildings**: compute block polygons between corridors (shapely), subdivide into lots
   (Old Town 16–40 m lots, Financial 60–120 m, Megablocks one block = one megablock, Harbor warehouses
   40–80 m + container yards), and fill EVERY lot that is not an arena interior, plaza or reserved space.
   Building coverage of non-corridor land: D3/D5/D7 ≥ 65 %, D2/D4 ≥ 45 %, D1/D6 ≥ 40 % — print it.
   Street walls: along avenues the frontage must be ≥ 70 % built (canyons, not fields).
3. **Heights**: tier distributions per district so the skyline has a shape — Financial towers 128–240 m
   clustered south of the Spire, Megablocks 128–200 m as a wall in the NE, Old Town low 16–48 m with the
   pagoda punching up, Harbor/Foundry low-mid with the cranes/stacks as verticals. Nothing near the Spire
   above 200 m; keep the view corridors from H0 and the arenas to the Spire open (C15 ≥ 80 %).
4. **Arenas are shaped by the city**, not octagons: their outline = the streets/buildings around them;
   inside: multi-tier pieces (decks, ramps, cover) per dossier §4.5; ≥ 3 entries on ≥ 2 layers.
5. **Decks/viaducts read as continuous structures**: the Ring Viaduct must be one visible loop in the plan;
   decks attach to buildings or pylons (no floating rectangles without support in the data: add
   `supports` lists).
6. Iso views: render buildings in the plan's tier colours with simple lighting, and add one low-angle
   street-level view (camera at 20 m height from H0 toward the Spire) so density can be judged.
Re-run all validators after the restructure and report the coverage numbers per district.
- (critic) Add `sky_waypoints` to the layout (≥ 24 per district at +60…+200 m, connected so Harriers can route
  between districts without crossing buildings) and mark destructible/soft cover (30–40 % of arena cover).
- (r4, from city-build r1) 1) Connector endpoints: a 12 m keep-clear sphere at every connector `from`/`to`
  against buildings, cover and viaduct piers (35/48 endpoints sit inside built mass today — e.g.
  con_K1_K3_edgejump on a pier base, con_U4_O7_lift inside the tunnel lining, O1–O3 edgejumps in the Knot
  helix); add it to L1/L2 checks. 2) Arena decks: under-deck clear ≥ 32 m inside arenas (C13). 3) A1 Container
  Yard: add 3–4 tall cover pieces (stacked container towers / crane bases 24–32 m) so ≥ 40 % of A1 samples have
  full cover within 60 m (C14). 4) Block 9: declare `holes` for every corridor that claims `through` it.
  5) rail_W4_M5 and rail_M5_S3e terminate at Block 9's centre — end them at a station platform deck inside
  the hole (or pass through and continue), never inside solid mass. Rerun all checks; city-build rebuilds.
- (boss r1) Arena B (the Crown) is cluttered with tall cover boxes — a boss arena must be open: keep only low
  cover (≤ 8 m) on the rim steps and around the 4 fins and the core; no box field in the middle ring.
- (r5, from city-build r3) Spawn sockets: put every arena spawn socket on its arena's own TOP walkable surface
  (the tier the fight happens on), ≥ 16 m from walls, with 16 m of clear air above and ≥ 12 m of free floor
  around it (no cover piece within 8 m), so a 4 m-radius agent lands on a navmesh island connected to the arena
  centre. Rerun the checks; city-build rebuilds and measures reachability.
- (r6, from flow r3 E2E) `hive_a2` and `hive_a5` stand inside their arenas' own structures — of 48 candidate
  firing positions per pod none has a clear shot. Each hive needs ≥ 3 approach routes AND open ground of ≥ 40 m
  radius around its base on its tier with clear lines of fire to all four pods (10–55 m up the trunk) from at
  least 8 positions; move the hive or clear the structure. Add it to L4.
