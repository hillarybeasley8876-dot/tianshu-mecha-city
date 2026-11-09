- (layout r3, 23:50) Layout r3 landed (revision 3, additive): Civic Quarter buildings (`quarter: "d4q"`), D7
  carriers + 2 straddling towers (`holes` + `through` on both the building and the corridor), canopy decks only
  near arenas, D3 party-wall terraces, `sky_waypoints` / `sky_edges` (export them for `world.sky_path()`).
  The two straddling towers are signature set pieces: light the corridor's passage through them like a tunnel
  (soffit lights, signage, the rail/viaduct visibly entering and leaving) so the ride through reads.
- (city-art r1, CONTRACTS §7 "Art integration") In `world/city.tscn`: instance `res://world/art/environment.tscn`
  as a child and remove your blockout sky/sun/WorldEnvironment; city-art's environment applies the materials
  to your tiles on ready. Keep a `--blockout` flag path if you want flat role colours for your own checks.
- (02:xx) NAV VERDICT — read reviews/city-build-nav.md first: one-line sync fix + the real problems (fragmented bakes, unattached links). Do it in this round.
- (boss r1, CONTRACTS §6 "Crown rim") Export the Crown's outer rim as separate StaticBody3D segments in group
  `&"crown_rim_segment"` with meta `angle_deg` (12–16 segments) so the boss can break them in phase 2.
- (packaging, 01:15) The exported .app loads **0 tiles**: `city.gd` lists `TILE_DIR` with `DirAccess` and the
  export has only `*.glb.import`/remaps there. Use `ResourceLoader.list_directory(TILE_DIR)` (or an index JSON
  written by build_city.py) — verify with `tools/godot.sh export` + the app booting headless (lead does this).
- (layout r4) Layout revision 4 landed (additive; graph untouched): keep-clear endpoints, arena canopies at +40,
  A1 container towers, Block 9 `holes` ×7 + `deck_block9_platform` as the Skyrail terminus, the open Crown.
  Rebuild from it; C14 must exempt arenas with `open_cover = true` (the Crown). Report C12–C17 again.
- (enemies r9, 03:05) Measured on your r2 bake: 2,005 / 856 / 260 islands (small/medium/large), the biggest only
  10–14 % of the polygons; ~26 % of path queries fail (enemies now steer straight when they do). Likely cause
  besides real geometry: with edge connections OFF, chunk seams only merge where vertices weld exactly — if the
  bake is chunked, bake ONE region per class (it is fast now) or weld the seams. Report islands before/after.
- (boss r2) The built Crown's rim profile does not match `B1_crown.rim_steps`: probe heights 226/234/241/248 m at
  r 0.92/0.72/0.55/0.80 (non-monotonic). Build the three rim steps rising outward exactly as the layout says.
- (city-art r3) Your HLOD proxies carry the map-edge backdrop (`t-1_3_hlod` is a planar 0 × 260 × 1,406 m card
  whose nearest corner is ~250 m from the map centre) — that is the flat wall in every vista. Keep the backdrop
  out of the HLOD merge and push it to the skyline-ring radius (or give it its own role). The A4 megablock
  podium walls have no footprint in the layout data the facade mask reads — export them as buildings (or tell
  city-art which tiles/meshes are podium walls) so they get windows at eye level.
- (12:10, PRIORITY — user feedback "场景和搭积木有什么区别") New unit **city-kit** fits Tripo-made architecture over
  the blockout (`data/map/kit_assign.json`: building id → kit model + transform). Add a **skin mode**: for every
  building / deck edge / railing listed there, keep collision + occluder but do NOT emit its render mesh (a
  `--blockout` flag still shows everything). Also export the deck/viaduct edge polylines + heights in
  `layout.json` (`edges: [{id, points, z, kind}]`) so city-kit can lay railings, and give city-kit one instancing
  line in `world/city.tscn` for `res://world/kit/kit_placer.tscn`.
