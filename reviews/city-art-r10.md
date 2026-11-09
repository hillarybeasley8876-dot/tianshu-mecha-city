# city-art r10 — lead brief: nothing in the city may float (the user's complaint, 11-03)

The user played the city and asked, verbatim, "地编物件浮空问题解决下": fix the floating scenery.
This round is that and nothing else.

## What the lead already fixed (commit 8f2bfd1, read it first)
- **Every kit glb and every prop glb was drawn sunk by about half its height.** Their meshes were
  centred on their own middle, and the placers draw a mesh from the placement's base.
  - The visible result: every building at half height, and all roof dressing hanging in the air at the
    full roof height.
  - The fix: `tools/citykit/rebase_glb.py` moved every glb (gate: `--check`), and both Blender pipelines
    now bake the base pivot. **Your props moved too:** `game/world/props/meshes/*.glb` now have their
    base at y = 0 and no node translation.
- **`Basis.scaled()` is a GLOBAL scale** (it scales the rows, i.e. the world axes after the turn).
  - Every `Basis(UP, a).scaled(Vector3(w, h, d))` meant to size a box sheared it at any angle that is
    not a multiple of 90°.
  - The lead switched these to `scaled_local`: `kit_placer._basis`, the shopfront and parapet bands in
    `facade_signs.gd`, the Spire strips and all six in `cargo_blocks.gd`.
  - Use `scaled_local` for object dimensions from now on.
- **The gate exists: `game/tools/float_audit.gd`.**
  - Run it with `godot --path game --windowed --resolution 640x360 res://tools/float_audit.tscn -- --list=40`.
    It must be windowed, because MultiMesh instance transforms are only real on a real renderer.
  - It drops every RESTING dressing instance onto the RENDERED surface: the kit's near meshes plus
    city-build's tile render meshes, never the collision boxes.
  - It samples the centre and four footprint points, and reports per category what floats more than
    0.5 m or is buried more than 0.5 m.
  - Hanging things (signs, cables, scaffolds, holograms, the u01/u02 fasciae) are not judged.

## Where it stands after the lead's fix (`tmp/lead/r5/float4.log`)
| category | instances | float > 0.5 m | float > 3 m | worst |
|---|---|---|---|---|
| greeble duct / mast / plant / vent / mast_lamp | 1 761 | 1 226 | 951 | 122 m |
| prop ac / antenna / billboard / pipe / solar / storage / water / container | 929 | 484 | 314 | 109 m |
| kit s08 (roof machinery clusters) | 201 | 154 | 88 | 22 m |
| kit s07 (railings) | 1 500 | 902 | 838 | 12 m |
| kit f03 (deck_full) | 94 | 29 | 27 | 6 m |
| kit s06 (pylons) | 53 | 7 | 7 | 48 m |
| kit cover k05 / k06 / k09 / k10 / k11 / k02 / k07 / k08 | ~900 | ~75 | ~60 | 20 m |
| prop streetlamp / barrier / planter | 412 | 13 | 13 | 20 m |

**Why the roof dressing floats.** It is placed at `base_z + height` of the DESIGN box: the greebles
from `city_layout.json`, the roof machines from city-build's `roof_machine` slots, and s08 from
`assign.py`. A Tripo building reaches that height only somewhere on its footprint.
- A podium tower is a tall shaft on a low podium.
- A setback steps in.
- A t01 crown ends in a spire.

Over the rest of the footprint, the dressing hangs at the box top. Example: the greebles at
(-146, 160, -560) sit 122 m above the roof that is actually under them.

## The work
1. **Settle every resting dressing item on the surface the player SEES.**
   - Add a query service built from the same sources the audit uses: the kit near meshes from the
     placer's own transform lists (not MultiMesh readback, so it works head-less) plus the tile render
     meshes. Reuse the audit's grid and `TriangleMesh` code; move it into one shared class that both
     the audit and the settle pass call, and do not keep two copies.
   - **Roof dressing** (greebles, roof-machine props, s08): sample the item's footprint.
     - Put it on the HIGHEST kit-building surface under it, if that surface is near-flat (normal within
       15° of up). A setback or podium roof is a roof, so dropping to it is right.
     - If what is under it is not a kit building roof (street, deck, ground, nothing) or is sloped,
       DROP the item. A roof unit in the street is worse than none.
     - Count drops per category and print them.
   - **Street dressing** (lamps, barriers, planters, vehicles, stalls) and the kit pieces that stand on
     a deck or a street (s07 railings, f03, s06, cover): settle onto the highest surface within
     [intended − 3 m, intended + 3 m]. If none is there, report it with its id; do not hide it
     silently. Railings floating up to 12 m look like a wrong z rule in `tools/citykit/pieces.py`
     (`d.z + thickness + parapet`). Find out which, and fix the RULE as well as settling.
   - **Order.** `city.gd` builds `_environment()` (your dressing) BEFORE `_kit_placer()`, so the kit does
     not exist yet when the dressing is placed. Restructure the order so the surface exists first, and
     check nothing in the kit placer needed your globals before then (`McMaterials.ensure_globals()`).
     city-build and city-kit are idle; you may edit `city.gd` and `kit_placer.gd` for this. Do NOT touch
     `kit_placer._basis` or the scale handling (just fixed).
   - **Load time.** Measure the city load before and after on this machine. The settle may add at most
     1.5 s. If it costs more, bake it OFFLINE instead: a tool writes the settled heights to a data file,
     and a test fails when that file is stale against its inputs.
2. **The gate.**
   - `float_audit`: 0 instances floating more than 0.5 m in every resting category. Buried more than
     0.5 m: report it; it is a real problem only where you can see it, so judge the worst 10 in
     close-ups.
   - Whitelist only what you can defend in one line each (a pylon that meets a viaduct's underside is
     buried by design).
   - Promote the audit into the city tests so a future round cannot regress it.
3. **Evidence the user can see.**
   - The seven street cameras (`tools/citykit/cams_street.json`, through `tools/godot.sh shot`).
   - Two new high cameras that look ACROSS roofs at 80–150 m: one over a podium-tower district (D5/D7),
     one over the old town.
   - Before = commit 8f2bfd1, after = yours, side by side.
   - The A1yard camera now sits inside a full-height cover block: re-pin it.

## Done means
`float_audit` passes with the whitelist printed; the load-time number before and after; the
before/after sheets; and every count of dropped items, per category.

Report in `status/city-art.md` as usual, and commit per step with an explicit path list.
