# city-layout — round 7 (lead) — the cover field is stacked on itself, and the vista cameras are inside it

## What the lead found (measured on the current `data/map/city_layout.json`)
- **1,070 cover pieces, 784 distinct centres.** 286 pieces sit at EXACTLY the same (x, y, z) as another piece. There
  are 82 groups of 2–12 boxes on one centre (A5 max 12, A2 9, A6 9, A1 7), and 3,404 overlapping pairs in total.
  Per arena: A2 330 pieces / 212 centres, A5 324 / 203, A6 93 / 53, A1 118 / 111.
- Cause (read `tools/map/arenas.py`): `_top_up` measures the 60 m rule against `full` only. `_place_near` returns
  the first legal spot in its fixed ring order (0, 16, 24 … 68 m × 8 bearings), never checks the new box against
  the existing pieces, and the grid is swept again by `cover_pass`, which runs TWICE in `build_layout.py`
  (lines 336 and 353), plus `hive_repair.recover_cover`. Whenever a grid point is blocked by a keep-clear sphere,
  every later pass lands its replacement on the same nearest legal spot, so the boxes pile up.
- What it costs: (1) the cube-field look the user called "搭积木" is denser than the design intended; (2) every
  stacked piece is a separate collider + breakable slot + render box + city-art skin + kit cover row (city-kit
  wrote 1,070 rows, a third of them for invisible duplicates); (3) **two vista cameras now sit inside cover**:
  V4 (`480,100,-410`) is inside A4's piece #52 (top +100 m = the camera height), and V6 (`-42,176,500`) has A6's
  #77/#88 (top +172) 4 m under it with five more boxes on two centres. Captures `captures/now_V4.jpg` / `now_V6.jpg`
  vs `--art-debug=hide=Cover_`: the cover is all you see.

## Build
1. **No piece may overlap another on the same surface.** A placement check in `_place` against every existing piece
   at that z, using the real rects (yaw included), with a minimum gap of 6 m (a 16 m mech must be able to walk
   between two pieces, otherwise make them one deliberate wall). That covers `_place`, `_place_near`, `_top_up`,
   `cover_pass`, `hive_repair._place_clear` and `towers_for`.
2. **One top-up, not three sweeps from scratch**: make `cover_pass` idempotent (a second call adds 0 when nothing
   changed) and assert it.
3. **Keep the gameplay rules**: L4 / C14 (a ≥ 20 m piece within 60 m of every point), the hive lanes (r6), the
   open Crown. If the overlap rule makes L4 fail somewhere, report where (a keep-clear sphere can make an area
   impossible) rather than relaxing the overlap rule.
4. **Vista cameras stay clear**: a keep-out sphere of 30 m around every `data/vistas.json` `pos_godot` (convert:
   map (x, y, z) = (x_g, −z_g, y_g)) for cover and any other solid you place.
5. Report the new numbers: pieces, distinct centres (must equal pieces), overlapping pairs (must be 0), per arena,
   and C14/L4 results; `validate_layout` green.

## Then (lead does the rest)
The lead will rerun city-build (`build_city.py` + bake + skin probe), and city-kit regenerates its cover rows
(`tools/citykit/cover.py`, ids are `<arena>#<index>` in layout order, so the ids change with this rebuild: tell
city-kit when the file lands). Commit the layout with an explicit path list and update `status/city-layout.md`.
