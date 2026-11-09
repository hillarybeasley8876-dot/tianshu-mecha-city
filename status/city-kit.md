# city-kit status

## r10 — the props decimation shredded (lead r10 §1–§3; an ownership exception)

**Ownership this round.** `blender/props/**` and `game/world/props/meshes/**` were mine for r10.
Everything I changed in those paths is listed below; materials and shaders stayed city-art's and I
did not touch `mc_kit`, `mc_prop` or `material_library.gd`.

### §1 — `normalise()` was reading a stale bounding box (the rebuild trap)
`blender/props/process_prop.py::normalise()` scaled by `max(obj.dimensions)` and recentred on
`obj.bound_box`, both straight after `common.apply_transforms()`. Both are CACHED, depsgraph-evaluated
boxes, so on a fresh run they still held the pre-transform extents: the acceptance team measured the
crane coming out with its base at **y = −24.9 m**, sunk about 25 m into its deck, and the same trap
would have hit any prop rebuilt from then on. Replaced with `mesh_bounds()`, which reads the MESH DATA
and only the vertices a FACE references (the exporter does not write a loose vertex, so a box that
counts them ships the prop a few cm above its surface — the same fix
`blender/citykit/process.py::bounds()` already carries for the kit). The kit side never had the bug:
`fit_native()` already measured `obj.data.vertices`.

### §2 — the prop table: three budgets and one dead row
| prop | was | now | why |
|---|---|---|---|
| `crane` | `Prop(8000, 60.0, 1024, "rooftop")` | `Prop(40000, 60.0, 1024, "statue")` | a 60 m lattice landmark at the rooftop tier; 268,685 → 9,867 tris folded the rails into needle spikes |
| `cranes` | `Prop(8000, …)` | **deleted** | dead row, there is no `art/tripo/prop_cranes` |
| `ac_cluster` | `Prop(8000, 6.0, 512, "rooftop")` | `Prop(16000, 6.0, 1024, "rooftop")` | 264,283 → 7,999 was a 33× collapse into crumpled foil; it is the most-placed roof machine in the city (187 instances) |
| `food_stall` | `Prop(5000, 4.0, 512, "street")` | `Prop(10000, 4.0, 512, "street")` | 262,511 → 5,000 is a 52× collapse; the roof the player looks down on tore |

### §3 — the root cause behind the "open edges" column: the Tripo sources are not watertight
`blender/props/probe_holes.py` (new) measures the open-boundary loops of a source or a shipped glb
after the same positional weld the pipeline uses. Run over all 30 sources (`--all`):

* **27 of 30 carry between 1 and 27 tears.** Only `anchor_node`, `guardian_lion`, `koi_dragon` and
  `wreck_mech` are watertight.
* **The largest loop anywhere is 0.416 m** (blossom_tree); `food_stall`'s is 0.315 m and it is exactly
  the hole the acceptance pass photographed in its roof (Blender −0.58, 1.29, 2.08 = the Godot
  −0.58, 2.07, −1.29 in their audit).

Blender's collapse decimator **constrains boundary edges**, so an unfilled tear survives every budget
and only grows: ac_cluster's 0.270 m source loop came out of the 16k decimate as a single **1.09 m**
triangle. So `process()` grew two passes, both in the new **`blender/props/mesh_repair.py`**
(`process_prop.py` was 468 lines after the change and is back to 253; `probe_holes.py` shares
`boundary_groups` with the code that fills them, so the two can never disagree about what a hole is):

* **`prune_floaters()`** deletes connected components of ≤ 2 triangles. A stray triangle is invisible
  in a render but every one of its edges is a boundary edge, so it is a large share of the audit's
  open-edge column.
* **`fill_holes(cap)`** caps every open-boundary loop under
  `cap = min(0.45 m, 0.10 × size_m)` — a figure chosen from the measurement above, so it closes all 30
  sources and nothing legitimate is that small and open. A simple cycle is one `faces.new`; a
  component whose vertices carry degree 4 or 6 is several holes sharing a corner (food_stall's roof is
  three of them) and only `bmesh.ops.holes_fill` separates those; a component of two edges whose ring
  already exists is a one-sided FIN, not a hole, and is left alone. New faces are oriented against the
  faces they are stitched to (a global `recalc_face_normals` would rewrite the winding of the whole
  prop and fight the split normals the importer brought in) and `dissolve_degenerate` cleans the
  slivers a fan triangulation leaves. It runs **before** the decimate (removing the constraint) and
  **again after** it.

**All 30 props were reprocessed** through the repaired pipeline, not just the three named ones — the
tears are in every source. The split into `mesh_repair.py` was done last and re-verified: reprocessing
`food_stall` through the split modules produces a **byte-identical glb** (md5 `3a813a2a…`).

### §4 — the audit, all 30 props
`game/world/kit/tests/probe_props.gd` (a port of the acceptance team's `probe_mesh.gd`, props only)
measures the mesh **as shipped**, through `PropScatter.load_mesh`. `tools/citykit/prop_audit.py`
joins it with `prop_table.py`'s budgets and prints the table; it exits 1 on a budget or size bust, so
it is a gate as well as a report. Full table with the visual verdicts:
`tmp/city-kit/r10/audit_after.md` (verdicts in `tools/citykit/prop_verdicts.json`).

| prop | budget | size | open edges | flipped | verdict |
|---|---|---|---|---|---|
| ac_cluster | 15998 / 16000 | 5.98 / 6.0 m | 36 (0.15%), largest 0.26 m | 2 (0.01%) | **FIXED** |
| crane | 39999 / 40000 | 59.97 / 60.0 m | 2 (0.00%), largest 0.21 m | 0 (0.00%) | **FIXED** |
| food_stall | 9999 / 10000 | 4.00 / 4.0 m | 6 (0.04%), largest 0.11 m | 6 (0.06%) | **FIXED** |
| *(the other 27)* | all at budget | all within 0.5 % of the table size | ≤ 57 edges (0.33 %), largest ≤ 0.34 m | ≤ 51 (0.34 %) | fine |

**30 props audited, 0 over budget, 0 over size, every base_y 0.000 m.** The before table
(`tmp/city-kit/r10/probe_before.log`) had the crane at 9,867 tris against an 8,000 budget and 5 %
short of its 60 m, and food_stall's largest hole at 0.42 m.

**ac_cluster's residual 0.26 m is not a hole.** `probe_holes` on its source shows the component is two
boundary edges whose ring already exists — a one-sided fin attached along one edge, i.e. geometry that
is there, not a gap. That is why the six clay views show zero magenta. It is 0.06 m over the lead's
0.2 m numeric gate and I would rather say so than delete a real surface to make a number.

### §5 — the settle cache
The fingerprint in `world/art/settle/cache.gd` covers the layouts, `kit_assign.json`, `kit.json`, the
tile glbs and the kit glbs — **not the prop meshes**, so my rebuilds did not stale the bake. I
re-baked anyway (`SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600`) and diffed it:
**29 of 124 batches changed, all of them prop batches, max coordinate delta 0.0000 m** (sub-mm ray
hits), and one batch (`antenna_array|0`) now keeps one instance it used to drop. The file is
**committed** this round. city-art r16: if you change the fingerprint, re-bake after me — the stamp is
theirs, not mine.

## r9 — the far field is buildings now, not boxes (lead r9 §1–§4)

### §1 — the 96-box skyline ring has a kit model on every box
`tools/citykit/ring.py` (new) fits one kit model to each box in `city_layout.json["skyline"]`:

* **Model.** Candidates are the tower / megablock / mid-rise bands minus every model with a
  through-opening (the box behind it is gone, so a hole would be a window onto the sky) and minus
  every model with no `<id>_far.glb`. The fit obeys the buildings' own `ANISO_MAX` / `ANISO_SOFT`.
* **Yaw.** Every model is turned so its detailed face (-Y in Blender) looks at the city centre — the
  ring is only ever read from inside. Gate: **worst 87.3°**, all 96 within 90°.
* **Spread.** The boxes are walked in angular order and a model already on either angular neighbour is
  a HARD exclusion, not a penalty: 43 of the 96 boxes have exactly one model that fits inside the
  anisotropy cap, so a penalty only chooses which repeat happens. One row (`forced`) repeats because
  nothing else fits. Crown classes are penalised the same way.

Shipped: **96 of 96 boxes covered, 0 skipped.** Anisotropy p50 **1.23**, p90 1.49, max 1.77; 75 of 96
inside `ANISO_MAX`, 21 soft. Eight models, eight crown classes:

| model | m01 | m03 | b03 | r03 | r01 | b04 | t05 | t04 |
|---|---|---|---|---|---|---|---|---|
| boxes | 15 | 14 | 13 | 12 | 12 | 12 | 10 | 8 |
| crown | slab | stepped | fins | billboard | setback | terrace | halo | twin |

The palette is capped at `RING_MODELS_MAX = 8` with two slots reserved for a vertical crown
(`VERTICAL_CROWNS`) — ranking purely by "how many boxes did this model win" gives eight chunky
megablocks and a horizon with no spire, halo or mast on it at all, which is the flatness r9 exists to
remove. The eight are chosen by a first pass, so they are the models that actually fit the boxes.

**Drawing it.** `kit_placer.gd` grows a `ring` tier: the model's FAR glb, `visibility_range` 0 →
3 000 m, shadows off. `RING_BEGIN` is 0 and not the "nothing near" the brief asked for, because the
ring boxes are **not** far from everything: measured against the layout's streets, buildings and
arenas, all 96 are within 400 m of something the player can stand on and eight of them overlap the
±700 m map square. A `begin` above zero leaves a hole where city-build dropped the box. 3 000 m covers
the farthest pairing (a ring tower 1 229 m out seen from the opposite map corner is ~2 220 m).

**city-build side.** `build_city.py` reports `96 ring boxes (0 rows skipped)`, all 96 are
`dropped: true` in `game/world/city/layout.json`, and `skyline.glb` is gone.

### §2 — the eight unskinned buildings, and the nine assets it took
Five Tripo generations were already queued when the diagnosis landed; the credits went on nine assets
in the end (**585 credits, 12 646 → 12 061**, no regeneration needed — every concept's first pick
passed QA):

| id | what it is | why |
|---|---|---|
| m06 | square pierced megablock, flat roof deck | m05 has the right shape for Block 9 but a stepped crown, and Block 9's roof is walkable |
| m07 | slab whose whole ground floor is one full-width opening | `D5_p009` / `D4_p001` are pierced across their FULL width; m04's opening leaves piers standing in the street |
| m08 | two stacked openings, viaduct below and monorail above | `D7_s001` carries both, and nothing in the kit had two |
| w01 | single-file row of slot houses | the 4.2–6.0 m thick walls; nothing in the kit is under 9 m deep |
| w02 | long thin hillside gallery block | the same four, second proportion |
| r01–r04 | the ring's own masses, one per shape cluster of the 96 boxes | see §1 |

**The assigner grew a 2-D copy grid** (`assign.py::tile_pick`). r2 only divided a box's long axis into
2 or 3; r9 divides both, because a box can be too big for one model in either direction and a 2 × 2 of
a megablock over a 130 m square reads as one building. Each copy is scored on its own sub-box, so
nothing is stretched, and `TILE_PENALTY` is per COPY so a grid only wins when a single model genuinely
does not fit. `pick_hole` now falls back to the same grid inside the hole-only model set.

Shipped, all eight:

| building | model | grid | aniso | |
|---|---|---|---|---|
| D5_block9 | m04 | 2 × 1 | 1.52 | soft; the Liziba row, flat-topped so the walkable roof holds |
| D7_s001 | **m08** | — | 1.31 | the two stacked openings, one model |
| D5_p009 | **m07** | — | 1.13 | |
| D4_p001 | **m07** | — | 1.16 | |
| D2_w004 | **w01** | 1 × 2 | 1.02 | |
| D5_w046 | **w01** | — | 1.46 | |
| D5_w049 | **w02** | — | 1.88 | soft |
| D4_w033 | **w02** | — | 1.73 | soft |

**358 of 358 buildings covered (100 %)**, 0 skipped — was 350 of 358. **44 of 44 far-LOD tiles stand
their proxy down**, was 38 of 44: **no tile keeps the box proxy.**

### §3 — rebuilt through city-build's own tools
`python3 tools/citykit/assign.py` → `tools/blender.sh run blender/city/build_city.py` →
`SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600`. Results in **How to verify**.

Two things had to be worked around, both now Requests:

* `build_city.py::_export_skyline` returns early when the ring kit is empty (`Kit.merged()` is
  `None`), so it never rewrites `skyline.glb` — the stale 357 kB mesh from the pre-r9 build stayed on
  disk and kept rendering all 96 boxes. I deleted the generated file; a `--blockout` rebuild puts it
  back.
* `city_art.gd::_skyline()` warns `no 'Skyline' child` now that the ring is gone. Harmless (it
  returns 0) but it is a warning on every boot.

### §4 — c01 has a roof map
`blender/citykit/roofmap.py`: `MAX_CELLS` was a hard SKIP, which left c01 (109 × 181 m = 5 005 cells at
2 m) with no map at all. It is now a resolution budget — `_cell_for()` returns the finest pitch whose
map fits, never coarser than it has to be and never finer than 2 m:

| model | footprint | cells | pitch |
|---|---|---|---|
| c01 | 109 × 181 m | 48 × 79 | **2.30 m** |
| m06 | 176 × 95 m | 83 × 45 | 2.12 m |
| every other model | — | unchanged | 2.00 m |

All **67 of 67** models have a map, was 66 of 67. The row carries the `cell_m` it was built with, so a
consumer never has to assume 2 m.

`roofmap.py` also now rebuilds `kit.json` when it finishes. It writes each asset's `row.json` and the
index is derived from those, but nothing rebuilt it afterwards — so `test_roofmap.py` (which reads
`row.json`) passed while `test_roof_map.gd` (which reads `kit.json`) still failed on six models. That
ordering trap is gone.

### Gates

| gate | result |
|---|---|
| Ring boxes still rendered | **0** — 96 of 96 dropped from `skyline.glb`, all `dropped: true` in `layout.json` |
| Tiles keeping the box proxy | **0** — 44 of 44 far-LOD tiles stand down (was 38 of 44) |
| Buildings uncovered | **0** — 358 of 358 (was 350) |
| `tools/godot.sh check --only=res://world/kit/` | **9 files, 0 failed, 0 errors, 0 warnings** |
| `tools/citykit/test_assign.py` | **0 checks failed** (43 checks, 11 of them new for the ring) |
| `tools/citykit/rebase_glb.py --check` | **PASS** |
| `tools/citykit/test_roofmap.py` | **PASS**, 67 models, worst p95 0.422 m |
| `world/art/tests/test_roof_map.gd` | **PASS** — 40 probed, 40 answered (was 38), 0 rows without a map |
| `world/art/tests/test_settle_cache.gd` | **PASS (0 failures)** |
| `float_audit` | 2 dressing instances floating > 0.5 m (r8: 0); **0 of 3 823** STRUCTURE instances off surface |
| `tools/city/checks.sh` | **C16 PASS**, **C18 PASS**; C12/C13/C14/C15/C15b/C17 unchanged from city-build's own known failures |
| KitPlacer draws at the A1 spawn | **94** (gate ≤ 98; r8 was 89) |

**The ring's cost, measured back to back in one session** (identical code, ring rows present or not):

| position | ring | draws | primitives | KitPlacer draws |
|---|---|---|---|---|
| A1 spawn | off | 1 035 | 4.87 M | 78 |
| A1 spawn | **on** | 1 052 | 5.27 M | **94** |
| V5 spawn | off | 736 | 9.56 M | 116 |
| V5 spawn | **on** | 751 | 9.93 M | 130 |

So **+15 to +17 draws and +0.37 to +0.40 M primitives** — under 4 % of the frame's primitives at either
position, for 96 buildings of horizon. Three batchings were measured before this one shipped; the
rejected ones and their numbers are in `kit_placer.gd::TILE_FAR` and `_push`.

## r8 — the cover keeps its concept's colours, then all twelve (lead r8 §1–§4)

### §1 — the units were the diagnosis, and a second one was hiding behind it
r7 fitted every cover model to p50 0.20 / p97 0.50 **stored sRGB**, reading the lead's "painted white
steel at 0.45-0.55" as sRGB when the brief said linear albedo. 0.50 sRGB is 0.21 linear — mid-grey
under a dusk sun. `concept.CLASS_BAND` now carries the lead's r8 §1 table as the *targets*:

| class | stored sRGB | models |
|---|---|---|
| paint | 0.72–0.80 | k01, k02, k03, k06, k07, k10 |
| concrete | 0.50–0.60 | k04, k11, k12 |
| wood | 0.40–0.55 | k08 |
| steel | 0.25–0.40 | k05, k09 |

Which class a model is, is read off its concept by eye (`concept.CLASS_OF`) and not measured: a
concept's median value is a mixture of its lit and its shadowed side and says nothing reliable about
albedo. Shipped, per model: **v_p50 0.69–0.79 paint, 0.55–0.61 concrete, 0.46 wood, 0.28–0.32 steel.**

**`coverraster.geom` was reporting m² per texel as metres per texel.** The Jacobian's cross-product
length is the texel's AREA; r7 read it as a length, so every number downstream was √-wrong — measured
against the shipped glb, k07's real density is **121 mm per texel**, not the 14 mm r7 reported. Three
things followed from that and all three were visible in the studio render:

* the 100 mm panel seam was **0.85 of a texel**, i.e. the r5/r6 "the grid averaged away" failure, and
  `lines()` was flooring it at `mpt * 1.1` = 15 mm, which is 1/8 of a texel;
* every tangent-space slope was **9× too strong** and saturated against `SLOPE_CLAMP` — which is very
  likely the real cause of the "swirl of light and dark facets" r7 chased with `island_gradient`;
* the 1.2 m seam pitch at the true density is a 30 %-deep wash over a third of the surface, which is
  what the soft dark diagonal smudges across k07's tank were. `COVER_STAGE=levels` isolated them to
  the seam layer exactly. The pitch is now 2.4 m and the depth 0.14.

### §2 — the colour comes from the concept
`blender/citykit/concept.py` (new) masks the light-grey backdrop out of the concept image the Tripo
job actually used (read from `art/tripo/jobs.json`, not a naming convention — **k04, k10 and k11 came
from their second candidate**), and does a Reinhard transfer in Lab onto the low-passed bake.

* **a and b are transferred fully** (mean and std). Chroma in a concept is albedo.
* **L is not transferred at all**, deliberately: the concept's L std is 18–27 and almost all of that is
  the studio render's own lighting, and `levels()` then remaps the whole value distribution anyway.
* **Accents are protected twice** — pulled 60 % of the way onto their concept cluster's chroma, then
  levelled onto that cluster's *value* instead of the model's band. Without the second half a dark
  red insulator is lifted onto the same 0.72–0.80 as the white tank it is bolted to.

Measured on the shipped rows: k07's chroma mean moves from Lab a,b (1.94, 2.04) to the concept's
(−0.06, 1.39), and its stored albedo p50 from r7's tan to 0.79.

### §3 — the hazard bands are drawn, not preserved
`blender/citykit/hazard.py` (new) paints them in object space after the diffusion, because nothing
else can work: a 0.5 m band is **four texels** at the real density and the 0.45 m chroma blur is
specifically designed to erase it. 45° stripes at a 0.6 m period (5 texels), one texel of antialias,
the lead's yellow (0.85, 0.70, 0.10) on black.

* **k04** chevrons over the barrier faces — `hazard_pct` **6.13**
* **k05** its own red-on-white banner, which is what that concept actually carries — **0.43**
* **k07** the plinth — **0.06** of the atlas, and clearly readable in every capture
* **k12 is deliberately absent.** Both of its concept candidates show a white silo, grey culvert
  rings and bronze trim with cyan neon and **no hazard band anywhere**. The lead listed "the k12 silo
  base", but inventing a yellow band there would contradict §2 on the very sheet that is supposed to
  prove it. Reported rather than done.

### §4 — all twelve, and the gates

| gate | result |
|---|---|
| concept fidelity | `captures/kit/r8_concept_fidelity.jpg` — 12 rows, concept \| 15 m \| 40 m, in the real city under the street cameras' dusk |
| wedges, A1yard | **PASS** — 0.95 against the lead's rung |
| wedges, A5deck | **1.77 against the lead's rung, FAIL** — see below |
| geometry, `rebase_glb.py --check` | **PASS** |
| compile, `godot.sh check --only=res://world/kit/` | **9 files, 0 failed, 0 errors, 0 warnings** |
| textures, `test_kit_textures.gd` | **PASS, 50 window masks** |
| cost, KitPlacer draws at the A1 spawn | **92** (gate ≤ 98; r7 was 81) |
| cost, VRAM | kit **658 MB** against r7's 702 MB, **−44 MB** |
| settle bake | re-baked LAST, after city-art r12: `float_audit` **0 floating > 0.5 m**, **0 of 3 823 STRUCTURE off surface**; `test_settle_cache.gd` **PASS (0 failures)** |
| credits | **0 spent** — r8 is colour, levels and pixels |

### The A5deck wedge: the gate is below the floor the mandated albedo imposes
The lead's probe rung 3 replaces the albedo with plain white and a `base_color` of (0.25, 0.20, 0.16)
— **0.25 LINEAR**, a dark panel. The r8 §1 target is 0.72–0.80 stored sRGB = **0.48–0.60 linear**,
about 2.2× brighter. A flat surface that is 2.2× brighter has ~2.2× the low-frequency std under the
same lighting, before any texture variation at all.

So I measured the floor instead of arguing about it. `game/world/kit/tests/probe_cover_floor.tscn`
shoots each camera twice — as shipped, and with the albedo replaced by a FLAT colour passed on the
command line:

| reference panel | A5deck | A1yard |
|---|---|---|
| the lead's rung 3 (0.25 linear) | **1.77** | 0.95 |
| my probe at 0.21 linear (reproduces rung 3, so the tool is equivalent) | 1.80 | 0.93 |
| **a flat panel at the §1 target (0.55 linear)** | **1.14** | **0.98** |

**Against a flat panel of its own brightness the cover adds 14 % — the textures are not the problem.**
The 1.77 is the brightness difference between the mandated albedo and the reference panel. I also
tightened everything that *is* mine (band slack 0.10 → 0.05, knee 0.25 → 0.15, grime 0.40 → 0.22,
seam 0.18 → 0.14, wear 0.55 → 0.35) and the ratio moved 1.73 → 1.77, i.e. not at all: it is not
texture contrast.

### For the user
`captures/kit/r8_before_after.jpg` — A5deck, A6garden, A1yard and A3st, before on the left and after on
the right, at the shipping default scale. A5deck is the frame that changes: a canyon of dark brown
boxes becomes a yard of pale machines.

### Deviations, and why
* **The fidelity sheet is shot on a line-up rig, not on the placed instances.** Two reasons, both
  measured: **k04 is never placed at all** (a 25 × 3.5 m barrier cannot fill a 16–33 m cover box, so
  `tools/citykit/cover.py` never picks it), and the placed instances of the rest sit under decks where
  a 15 m camera is in shadow behind another box. `world/kit/tests/kit_lineup.tscn` puts all twelve in
  one clear row at the sky garden's height, in the real city, under the real dusk environment, with
  the real `McMaterials.kit` material. It is a look-dev rig and the row is not a place the player can
  stand. `tools/citykit/cams_cover.py` still exists and shoots the placed instances for the record.
* **Each model is turned to its best-lit side** (`fidelity_sheet.py --pick`, by measured frame
  brightness over yaws 0/90/180). One yaw for the whole row leaves a third of the kit back-lit, which
  would fail the gate for a lighting reason rather than an albedo one.
* **`vertex_wear` now takes a vertex's SHARPEST convex edge, not a mean over its edges.** The mean
  version put wear on 70–90 % of every model, because a decimated flat panel has six near-flat edges
  at every vertex and their sharpness sums past any threshold — the wear layer was drawing the
  decimator's own diagonals across flat faces. `QA_ONLY=albedo` against `QA_ONLY=normal` localised it.
* **`BASE_ROUGH` narrowed to (0.52, 0.70).** A Tripo ORM carries its bake's large-scale gloss
  variation, and at (0.48, 0.88) it showed in the studio render as soft dark creases; a flat material
  on the same glb is clean.

## r7 — the arena cover leaves the Tripo atlas (lead r7 §0 and §1)

### §0 — r6's assets are committed
`tools/citykit/rebase_glb.py --check` PASS and `test_kit_textures.gd` PASS (47 masks) first, then
`git add -A -- game/world/kit` as one commit (**1eabfcb**, 1 600 files: 1 045 modified, 272 deleted,
283 new). `git status game/world/kit` is clean. HEAD now rebuilds what the lead reviewed.

### §1 — what the cover pieces were, and what they are
The lead's diagnosis was right and the measurement behind it is sharper than "the atlas is confetti":
**a 12 k-tri collapse of a Tripo shell unwraps into ~8 800 islands whose median is 2.3 texels**, each
carrying its own value *and its own baked shading*. `smart_project` at 66 deg returns 9 011 islands
(median 1.5 texels), at 89 deg 8 689, and dissolving coplanar faces first only reaches 7 962 — the
count is the mesh, not the unwrapper. k07's walls are 62.7 % of its mesh **area** and 4.4 % of its
atlas **texels**, and the atlas leaves 91 % of itself empty with a 46x spread between its median and
p95 texel size.

`blender/citykit/covertex.py` + `coverraster.py` + `coverlook.py` (new; `process.py` branches on
`band == "cover"`, `kitmat.build_cover()` wires the result and skips the facade repaint, the band
grade and the emission classifier entirely):

1. **Layout.** `weld_uvs` gives one UV to the loops across every edge under 18 deg of dihedral;
   `average_islands_scale` + `pack_islands` then make the density uniform and pack. k07: **14 mm per
   texel** (from a 46x-spread atlas), 100 mm panel seams land on **7.2 texels**.
2. **The low-pass runs in 3D, and that is the whole finding.** A per-island mean — the obvious reading
   of "low-passed enough that the island confetti is gone" — **does not work**: an island is 2 texels
   across and carries ONE SAMPLE of the baked shading, so its mean IS that sample.
   `captures/kit/r7_k07_src.png` is the proof: flat patches, every one a different value, white next
   to black on one steel panel. `covertex.diffuse()` is a gaussian over face centres in metres —
   value at **2.0 m**, chroma at **0.45 m** — and on k07 it takes the value std from 0.158 to
   **0.037** while the chroma survives.
3. **Palette from the concept.** `coverlook.levels()` replaces `grade.BANDS["cover"]`'s
   `target / median` gain (that gain is what made twelve concepts read as one brown) with a two-point
   fit: the model's p50 -> 0.20, its p97 -> 0.50, hue and saturation untouched. Those are the units
   every other number in this pipeline uses (`grade._pixels` on a byte sRGB image = the stored value),
   so the lead's "painted white steel at 0.45-0.55" is the p97 and **0.50 is 0.21 scene-linear**.
4. **Chroma noise vs the concept's colours.** Diffusing hue/saturation barely moves it (std 0.144 ->
   0.135 even at a 2 m value sigma) — a Tripo atlas's colour varies per island and every island is a
   slightly different grey, which reads as tan and rust blotches over a machine the concept painted
   one colour. `desaturate_weak()` is a SOFT threshold instead of a linear cut: under 0.10 saturation
   a texel is a tint and keeps 22 % of it, over 0.34 it is a real colour and keeps all of it.
5. **Two artefacts that were neither of the things I first blamed**, both found by dumping the maps and
   looking at them rather than by reasoning:
   * the tangent-space normal was differenced **across island borders**, and with ~8 800 islands over
     6 % of the atlas nearly every texel has a border neighbour, so nearly every texel got a
     full-scale clamped slope. `coverlook.island_gradient()` differences inside one face only.
   * the gutters were **black**, and a 2-texel island minified to mip 3 averages 8x8 texels of mostly
     gutter. `coverlook.pad()` dilates the composed albedo 16 texels outward.
   With a flat grey albedo and a flat normal the same glb renders clean and crisp
   (`tmp/city-kit/r7/cmp_flat.jpg`), which is what localised both to the maps rather than the mesh.

### Verdict on the prototype: it wins, and I am calling it partial
`captures/kit/r7_concept_fidelity.jpg` is the sheet the lead asked for — concept, then in-game before,
then in-game after, for both prototypes at 15 m. `tmp/city-kit/r7/ab_k07.jpg` and `ab_k02.jpg` are the
same cameras at 15 m and 40 m.

* **k02 at 15 m is the clear win.** Before: bright orange crumpled foil over the tank bodies. After:
  the tanks read as painted cylinders with a soft gradient and visible panel structure.
* **k07 at 15 m is a real but smaller win.** The smeared vertical streaks down the tank body are much
  reduced and the radiator fins read more crisply; there is still soft mottling on the largest flats.
* **The wide A5deck shot barely moves, and that is expected**: only 2 of 12 cover models are rebuilt,
  so most of that frame is still k01/k03/k05/k09/k11. It is not evidence against the method.
* **Against the CONCEPT the gap is still large**, and honestly: the concept is a light grey machine
  with crisp fins, hazard stripes and logos; in the game it is a dark orange object at dusk. Most of
  that gap is the scene's lighting and grade, not the texture — the Blender studio preview of the same
  glb (`captures/blender/r7sat_k07_studio.jpg`) is a clean grey painted transformer. **The hazard
  band and the logos do NOT survive** (`hazard_pct` 0.0 on both models): the chroma diffusion at
  0.45 m washes a 0.5 m band out, and the soft saturation threshold then drops what is left. That is
  the clearest remaining item.

### Gates
| gate | result |
|---|---|
| wedges, `tools/citykit/wedge.py` on A5deck | **PASS** — shipped sigma-12 std 0.10343, plain-albedo 0.08499, **ratio 1.22** (gate <= 1.5) |
| geometry, `rebase_glb.py --check` | **PASS** |
| compile, `godot.sh check --only=res://world/kit/` | **5 files, 0 failed, 0 errors, 0 warnings** |
| cost, KitPlacer draws at the A1 spawn | **81** (gate <= 98; r6 was 89) |
| cost, VRAM | kit **702 MB** against r6's 685 MB, **+17 MB** for two models |
| settle bake | `SETTLE_BAKE=1 float_audit` -> **0 floating > 0.5 m**, **0 of 3 823 STRUCTURE off surface**; `test_settle_cache.gd` **PASS (0 failures)** |
| credits | **0 spent** — r7 is geometry, layout and pixels |

The lead's `world/art/tests/probe_kit_layers.gd` is adopted and was run unmodified
(`--probe-cams=res://world/kit/tests/cams_r7probe.json`, a one-camera list in my own folder).
`tools/citykit/wedge.py` is the metric, written here because the probe ships the pictures and not the
number.

### Deviations from the brief, and why
* **8 px of padding is not achievable at this island count and 2 px is used.** Blender's packer
  satisfies the margin by SHRINKING the islands: at 8 px it packed k07 to **0.13 % fill** and a texel
  came out **92 cm** across, which is the opposite of what the padding is for. After the 3D diffusion
  an island is one flat colour, so a mip that bleeds across a 2 px gutter pulls in a neighbour's flat
  colour — which is what the mip would average to anyway.
* **The seam is 100 mm, not the 45 mm I first wrote.** At the density the packer can deliver, 45 mm is
  0.7 of a texel, and a feature under a texel is the r5/r6 "the grid averaged away" failure. 100 mm is
  7.2 texels and reads at the 15-40 m the cover is actually seen from.
* **The normal map is 512, not the 1 k I first shipped.** At 1 k it cost +30 MB of VRAM for two models
  (~190 MB for the roll-out) and the seams it carries are 3.6 texels wide at 512 — still clear.

## Done

### r10 — the three shredded props, and the tear in every Tripo source
See the r10 section at the top for the whole story. In one line: `crane` 8k → 40k landmark tier,
`ac_cluster` 8k → 16k, `food_stall` 5k → 10k, the dead `cranes` row deleted, `normalise()`'s stale
`bound_box` replaced with a mesh-data measurement (the bug that would have shipped every rebuilt prop
25 m sunk), and **all 30 props reprocessed** through a pipeline that now prunes floaters and caps the
boundary tears 27 of the 30 Tripo sources carry. Gates: `prop_audit.py` 30/30 at budget,
`rebase_glb.py --check --set props` PASS, `check --only=res://world/props/` 0 errors, `test_props`,
`test_art` and `test_settle_cache` all PASS, and the float audit is byte-for-byte the same list of
instances before and after.

### r6 MUST-FIX 1 (normals) — a flat wall now shades as ONE value
`blender/citykit/pnormals.py` grows each wall as a region from its largest face (28 deg, 1 % of the
model's longest axis), refits its plane and writes **that plane's normal to every corner** of it,
after `tripo_import.shade()`. A region whose plane fit is worse than 0.55 of the deviation is a curve
(dome, tank) and keeps its smooth shading. Region growing rather than `planar`'s accumulator because
nothing MOVES here: the accumulator's strict fit gate and 90-plane cap covered 53 % of t01's area,
this covers **89 %** (median across the kit 81 %, max 97.6 %).

Gate — `tools/citykit/normalqa.py`, on the **shipped glb**, per planar region the spread of
`dot(N, sun)`, plus a region-free per-triangle corner range that cannot be gamed by picking regions:

| model | lit wall area inside the 2 % gate | area-wtd mean | largest regions |
|---|---|---|---|
| t01 | **98.1 %** | 3.51 % | 406 m² 0.10 %, 1670 m² 0.09 %, 384 m² 0.08 % |
| m01 | **99.3 %** | 0.35 % | 750 m² 0.04 %, 2492 m² 0.02 % |
| o01 | **100 %** | 0.02 % | 34 m² 0.10 % |
| c03 | **99.5 %** | 0.28 % | 1156 m² 0.02 % |
| b01 | **99.9 %** | 0.25 % | 626 m² 0.40 % |
| k03 | **100 %** | 0.03 % | 50 m² 0.00 % |
| s01 | **99.5 %** | 0.12 % | 292 m² 0.12 % |

Before (r5/r6pre, same tool): t01 39.9 % mean spread, per-triangle corner range 0.056; after 3.51 %
and 0.014. `GROW_DEG` / `DEV_FRAC` were swept against this on b01, the worst case in the kit: 20 deg
/ 0.004 left 68.9 % of its lit wall area inside the gate, 28 / 0.010 leaves 99.9 %, 40 deg starts
merging real corners and costs t01 three points.

### r6 MUST-FIX 1 (albedo) + MUST-FIX 2 + MUST-FIX 3 — the pale sheets were the EMISSION
Diagnosed by rendering the shipped glb twice under one grazing sun at 30 m: once lit, once with the
material replaced by an unlit emission of its own base colour (`blender/citykit/wallgate.py`, which
writes `captures/kit/wall_<id>.png` and `wall_<id>_alb.png` side by side). The albedo pass is clean
dark bronze; the lit pass was pale white. Three causes, all fixed:

1. **`emit_mask` classified the walls as lit interior.** It asked for "bright and warm" with no
   saturation floor, and a Tripo albedo is near-white, so it swallowed **15.7 % of t01's atlas and
   7.9 % of k03's** and shipped them at `EMISSION_STRENGTH` 2.4. That is the "large pale peach-to-white
   planes" the lead photographed, and on the cover pieces the same mask at island scale **is** the
   black/white speckle of MUST-FIX 2 (k03's albedo is clean; its lit frame was a confetti of white
   blobs). Fixed: a 0.20 saturation floor, a 4 %-of-atlas cap per model, emission off entirely for
   the cover / industrial / tileable bands, the mask zeroed over every repainted texel
   (`emit_masked_pct` median 50.8 %), and the strength dropped 2.4 -> 1.5. `interior_pct` is now
   **max 1.06 %** across the kit, was 15.7 %.
2. **The facade grid could not be drawn.** r5 specified a 0.16 m storey line and a 0.30 m mullion; a
   Tripo atlas spends 0.06-0.49 m per texel, so those came out **0.33-0.73 and 0.6-1.2 texels** wide
   on every tower, megablock, mid-rise and civic model — averaged away to nothing on the buildings,
   aliased into speckle on the props. `facade_tex` now widens every feature to at least 2.5 texels
   using the affine UV->wall map's Jacobian (`panes.raster` reports `mpt`), **clamps** that widening
   to a fraction of the feature's own period (unclamped, a coarse wall became 100 % spandrel and
   collapsed to one flat value — the blank plane the gate forbids), and carries the structure on a
   per-(bay, storey) value hash that drops to a 3x coarser cell when a cell is under 5 texels.
3. **Coverage.** The regions are now `wallgroup.wall_faces()` — every near-vertical face, bucketed by
   orientation and plane offset — instead of `planar.facade_faces()`'s strictly-fitted planes, which
   reached 1.5-31 % of each atlas. t01: **75 % of the mesh AREA is wall, all of it repainted**; roofs
   and soffits get the same value range without a storey grid (`top_faces`).

Wall albedo is the lead's range: **`wall_luma` min 0.199, median 0.246, max 0.340** scene-linear,
measured per model on the repainted texels only (`grade.albedo`'s `pinned` argument stops the
grade's `target/median` gain from moving them back up).

The **normal map and the ORM are flattened over the repainted texels** — they are baked from the same
confetti atlas through the same stretched UV islands and were putting a smeared bump-and-gloss field
under a clean albedo. Finding that also turned up a live bug: `_images_by_kind()` keys on the name
prefix and Tripo calls its normal map `NormalGL_<uuid>`, so `imgs.get("Normal")` returned None through
r5 and **the normal map was never actually replaced** — it shipped at Tripo's own strength under
every repainted wall. `kitmat._normal_node()` now walks the material's node tree for it.

### r6 — the roof map city-art asked for
`blender/citykit/roofmap.py` measures the real top surface off the DETAIL glb, on a 2 m grid in
**MODEL space**, and writes it into the model's `kit.json` row as `roof`.

**How city-art reads it** (`game/world/kit/kit.json` -> `models[] -> roof`):

```
cell_m   2.0                      grid pitch, metres
nx, ny                            grid size
origin   [x, y]                   model-space coords of cell (0, 0)'s MIN corner
z0, z_span                        height = z0 + byte/255 * z_span
flat_deg 15.0                     what "flat" means
h        base64, nx*ny bytes      row-major, +x fastest, from `origin`
flat     base64, nx*ny bytes      255 = stand a machine here, 0 = do not
```

To place a unit at model-space `(mx, my)`: `cx = floor((mx - origin[0]) / cell_m)`,
`cy = floor((my - origin[1]) / cell_m)`, index `cy * nx + cx`; `z = z0 + h[i]/255 * z_span`; place only
if `flat[i] > 127`. `h[i] == 0 && flat[i] == 0` means the model does not cover that cell at all — a
cell whose highest surface is a mast is recorded at the mast's top with `flat = 0`, which is the
honest answer. To go to world space, apply the same transform the placer uses for that instance.
57 of 58 models have a map (one tileable piece exceeds the 4 096-cell cap and is skipped).

Gate — `tools/citykit/test_roofmap.py` walks the map the way a scatterer would (pick a flat cell, read
its height, raycast the shipped mesh): **57 models, worst p95 0.376 m** against the lead's 0.5 m.

### r6 — two base bugs the gate found while I was measuring
* `process.bounds()` counted **loose vertices**, which the glTF exporter does not write. `fit_native`
  put f01's box minimum at z = 0 and the shipped glb's lowest vertex came out at **+0.058 m**. It now
  walks the vertices the FACES use.
* `farlod` did not re-base the collapsed far tier. A 4 000-tri collapse does not keep the extreme
  vertices: l03's far came out spanning y **-2.76..+38.35** against the detail's 0.00..+40.00, so the
  silhouette jumped 2.8 m at the 450 m swap. It now scales and translates the far mesh onto the
  detail's box.

`tools/citykit/rebase_glb.py --check` is **PASS** after a clean `process_all`.

### r6 — A4st re-pinned
`tools/citykit/cams_street.json` adopts city-art r10's pins for A1yard, A4st and A5hive. A4st no
longer sits against a wall.


### Wave 1 (r1 PASS) — 40 architecture assets
40 concepts → 40 Tripo jobs → `game/world/kit/<id>/<id>.glb` → `kit_assign.json` + street pieces →
`kit_placer.gd`. 2 665 credits.

### r2 / r3 / r4
See git history (`b341ead`, `2b9fb70`, `96cb35a`, `a81dd1d`).

### r5 MUST-FIX 1 — the planar pass now actually moves vertices
The lead was right: `bmesh.ops.planar_faces` flattens each face onto its **own** plane, and a
triangle is already planar, so on the triangulated mesh the decimator leaves it moved nothing. The
r4 row reported "65 % planar" for t01 and the shipped surface was 2.8 % flat.

`blender/citykit/planar.py` is rewritten around a **Hough-style accumulator**, because the shape of
the previous solution was wrong as well as its operator:

1. find the model's dominant planes — direction bucket, then plane-offset bucket inside each
   direction — and keep the ones that still fit a plane inside `FIT_M` (0.07 m RMS);
2. assign every face to the plane it belongs to (`ASSIGN_DEG` 25°, `ASSIGN_DEV` 0.60 m, both tuned by
   sweeping against the *shipped* flat share);
3. keep each plane's faces as one **connected blob** (`KEEP_FRAC` 0.30) — without this a wall whose
   faces are split between two near-identical planes comes out as interleaved stripes and a 1 400 m²
   plane measured only 37 % flat;
4. project every vertex onto the planes of the faces around it, by hand. A vertex shared by two
   planes goes to the least-squares point of both, solved **in an orthonormal basis of the normals'
   span** — the damped 3×3 solve blows the shared component up by 1/epsilon (measured: a 46 m move on
   a 30 m grid);
5. `MAX_MOVE` 0.35 m caps how far any vertex is dragged, so a corner that is not a corner of the
   building is left alone.

Two things that are the wrong shape of solution, both measured on t01 and both now in the module
docstring so the next person does not repeat them:

* **Region growing** (the r4 approach, grown properly) tiles the surface with ~1 100 patches. Every
  vertex then sits on the border of 2-16 of them (10 701 vertices, mean 4.5 patches each), the
  shared-vertex solve satisfies none of its planes, and the export plateaus at **~21 % flat** however
  the tolerances are tuned. A wall has to become ONE plane with a large interior.
* **Flattening before the last collapse** is wasted work: Blender's collapse does not preserve
  coplanarity. A 50 %-flat 120 k mesh came out **6 % flat** after one 3:1 collapse. The pass now runs
  at the FINAL triangle count, `FLATTEN_PASSES = 5` times (each pass re-derives the planes from the
  surface the previous one left: 1 pass 15.8 %, 3 passes 21.4 %, 6 passes 24.7 %, 12 passes 24.6 %).

**The gate is on the export.** `tools/citykit/meshqa.py` reads the shipped glb and measures the
share of surface area whose every welded neighbour is within 1° of the triangle's own plane — the
lead's definition. `tools/citykit/flat_report.py` puts r3 next to it
(`blender/citykit/export_r3.py` writes the r3 baseline: collapse, clear custom split normals,
smooth 40, no planar pass, no weighted normals).

| model | tris | truly flat r3 | truly flat r5 | shading dev r3 | shading dev r5 |
|---|---|---|---|---|---|
| t01 | 40 000 | 3.6 % | **21.2 %** | 7.5° | **2.2°** |
| b01 | 24 997 | 4.1 % | **29.9 %** | 3.8° | **1.5°** |
| m01 | 39 994 | 3.0 % | **6.7 %** | 5.7° | **2.7°** |
| o01 | 19 999 | 0.3 % | **17.0 %** | 5.3° | **2.0°** |
| k06 | 11 996 | 0.4 % | **27.5 %** | 6.7° | **2.4°** |

The lead's gate was "≥ 50 % truly flat on the towers and megablocks". **Not met**: the best is
29.9 % (b01) and m01 is 6.7 %. The ceiling is structural, not a tuning problem — see Known issues.

### r5 MUST-FIX 2 — the LOD is reshaded, and the gate measures it
Every `_lod.glb` was decimated **after** `shade()`, so it shipped the collapse's averaged normals,
and `kit_placer._add_cover()` places all 1 265 cover pieces from it. `process.py` now runs
`tripo_import.shade()` again on the LOD before its export. Measured on the shipped files
(area-weighted angle between the stored NORMAL and the face, and the share of area over 30°):

| model | detail glb | `_lod.glb` r4 | `_lod.glb` r5 | gate ≤ 8° / ≤ 2 % |
|---|---|---|---|---|
| k01 | 4.1° / 0.0 % | 27.9° / 35.2 % | **3.8° / 0.0 %** | PASS |
| k02 | 3.5° / 0.0 % | 24.7° / 32.4 % | **2.4° / 0.0 %** | PASS |
| k06 | 2.4° / 0.0 % | 22.0° / 25.9 % | **2.9° / 0.0 %** | PASS |
| s01 | 1.1° / 0.0 % | 17.7° / 15.6 % | **1.5° / 0.0 %** | PASS |
| s07 | 1.7° / 0.0 % | — | **2.6° / 0.0 %** | PASS |

The lead also asked whether the cover needs the LOD at all. It does not, inside 150 m: every cover
piece is now pushed into **two** batches — `cover_near` (the 12 k detail mesh, shadows on, 0-150 m)
and `cover_far` (the LOD, 150-450 m) — and Godot's visibility ranges swap between them. Only one of
each pair is ever in the frustum, so the swap costs memory and **no draws**.

### r5 MUST-FIX 3 — the flattened facades get a world-scaled material
`blender/citykit/facade_tex.py` repaints the albedo **inside** the regions
`planar.facade_faces()` calls a wall, and only there, with a procedural facade evaluated at each
texel's real position on the wall in metres: concrete at the band luma, a slow ~9 m weathering term
instead of the atlas's high-frequency blotches, a storey line and spandrel every 4.0 m, a mullion
and a half-bay panel joint every 3.4 m. The bay/storey numbers are read from `panes.py`, so they
cannot drift from the window mask or from `mc_kit`'s `win_cell_m` / `win_floor_m`.

The first version only reached 8.7 % of t06's atlas, because the wall *planes* are 79 % of its
vertical area but the atlas spends its resolution on the small protruding elements — exactly where
the blotches survive. `planar.vertical_groups()` now buckets every near-vertical face by quantised
normal and the repaint covers those too, with the grid off and more of the original albedo kept
(`KEEP_REST` 0.40) so a duct or a sign keeps its own colour. t06: **8.7 % of the atlas as facade,
11.1 % more as plain vertical.**

**Judged, not assumed** — `captures/kit5_T1fac_near.jpg` is the 2× crop of the near third, r4 left,
r5 right. The large near wall the lead's example pointed at is substantially cleaner: r4's dark
grid of blotches is gone and what is left is smooth pale concrete. The near tower's balcony faces
still carry mottling. **Partial pass, honestly reported.**

The rasteriser's affine UV-to-wall maths now has one home: `panes.raster()` reports each texel's
(along-wall, height) to a callback, and the window mask and the repaint both use it.

### r5 — a placement bug found while measuring (bigger than it looks)
`fit_native()` left the pivot in the **mesh** *and* a node translation on the object, and
`kit_placer._first_mesh()` takes the Mesh resource and drops the node. So every model's mesh was
**centred on its own origin** and the placer drew each tower with its middle at `base_z` — half of
it underground. Measured on t06: mesh y −75..+75 in the r4 glb, 0..150 now. That is why the r3/r4
skyline looked low and distant, and it is why the whole city reads differently at T1fac now (a
150 m tower that was half-buried is standing). `common.apply_transforms()` after `set_origin()`
bakes it; all 58 glbs now carry no node translation at all.

`process.bounds()` also read a **cached** `obj.bound_box` after a direct vertex edit, so
`fit_native()` could scale a model by a height that no longer existed; it now forces a view-layer
update.

### r5 — the grazing-light gate, detail AND LOD
`graze.py --lod` renders the model's own `_lod.glb` on the right and r4's shading order on the left,
so MUST-FIX 2 has a picture as well as a number (`captures/kit/graze_<id>_lod.png`).

| model | r3 mean | r5 mean | change | | model | r3 mean | r5 mean | change |
|---|---|---|---|---|---|---|---|---|
| t01 | 0.1141 | 0.0783 | **−31 %** | | k01_lod | 0.0864 | 0.0885 | +2 % |
| b01 | 0.0781 | 0.0679 | −13 % | | k02_lod | 0.0686 | 0.0744 | +8 % |
| o01 | 0.0651 | 0.0549 | −16 % | | k06_lod | 0.0602 | 0.0585 | −3 % |
| s04 | 0.0892 | 0.0790 | −11 % | | s01_lod | 0.0759 | 0.0550 | **−28 %** |
| k02 | 0.0634 | 0.0810 | **+28 %** | | | | | |
| k06 | 0.0626 | 0.0537 | −14 % | | | | | |

s04 went from r4's **+9 %** to **−11 %** and k06 from −9 % to −14 %. k02 is still worse (+28 %): it
is a tank-and-gantry cluster with almost no flat wall, so flattening it facets real curvature. It is
the one model where the pass costs more than it buys; reported rather than hidden.

## In progress / next
0. **r10 is done and gated** — see the r10 section at the top. The props' own remaining item is the
   settle fingerprint (a Request to city-art), not geometry.
0. ~~Roll the cover method out to the other ten k-models~~ — **done in r8**, all twelve.
0b. ~~The hazard band does not survive~~ — **done in r8** (`hazard.py` draws them; k04 6.13 %,
   k05 0.43 %, k07 0.06 %).
0c. **Logos are still a stretch goal.** r8 carries a coloured band where the concept has one (the
   accent clusters do that for free), but no text or mark. A decal pass over the concept's own logo
   regions would need a second concept crop per model.
0d. **k04 is never placed.** `tools/citykit/cover.py` cannot fit a 25 x 3.5 m barrier into a 16-33 m
   cover box, so the model that carries the best hazard band in the kit is in no arena. Either the
   layout needs a few long thin cover boxes or the barrier needs to be a `pieces` row along a deck
   edge. Not mine to decide — see Requests.
0e. ~~The 8 buildings still uncovered~~ — **done in r9**, 358 of 358.
0f. **r02 and r04 are never placed.** They were generated for the ring's two tall shape clusters, but
   the ring's palette is capped at eight models chosen by how many boxes each one WINS, and a slender
   tower rarely wins a 50-109 m wide box. `RING_VERTICAL_SLOTS` keeps t04 and t05 in for their crowns;
   r02 (mast) and r04 (antenna) lose to them. Either raise the cap when the draw budget allows, or
   give the palette a rule that picks a vertical model per SHAPE cluster rather than by usage.
1. **D3 old-town variants** (~4 models, ≈ 260 credits): a foundry hall and a civic archive in the old
   town is an art-direction bug. Never started; r6 spent nothing.
2. **Model backs** (r2 item 5, never started).
3. **A ring-only far mesh.** The ring draws the same `<id>_far.glb` the in-city 450-1 100 m band uses
   (4-12 k triangles). The ring is 700 m and up, so 2 500 would do; a `farlod.py --ring` pass writing
   `<id>_ring.glb` would take the ring's 0.40 M primitives down by about half. Not done because it
   needs a new column in `kit.json` and a second gate run.
4. **The world-scale grid is still subtle on the largest near walls.** It is clearly there on the
   geometry that has any relief (`captures/kit/wall_c01.png`, `wall_t04.png`, `wall_t01.png` all show
   a 4 m storey grid), and `tmp/city-kit/crop6_T1fac.jpg` shows the blank pale sheet gone and panel
   joints and value structure in its place — but on the biggest, flattest wall in the T1fac frame the
   4 m bands read as a soft modulation under a strong specular rather than as drawn storeys. Two
   levers I did not pull: the specular term on `mc_kit` (city-art's), and a higher albedo resolution
   on the towers (0.35 m/texel today; 2K would halve it and cost ~600 MB of VRAM).

## How to verify (exact commands)
```
# r10 — the props
python3 tools/citykit/rebase_glb.py --check --set props          # PASS: every prop stands on y=0
tools/blender.sh run blender/props/probe_holes.py -- --all       # the tears in all 30 Tripo sources
tools/godot.sh test res://world/kit/tests/probe_props.gd -- --timeout=900 > tmp/probe.log
python3 tools/citykit/prop_audit.py tmp/probe.log --verdicts=tools/citykit/prop_verdicts.json
tools/godot.sh check --only=res://world/props/
tools/godot.sh test res://world/props/tests/test_props.gd
tools/godot.sh test res://world/art/tests/test_art.gd
tools/godot.sh test res://world/art/tests/test_settle_cache.gd
tools/godot.sh run res://tools/float_audit.tscn 600              # windowed; 2 floaters, both pre-existing
# the sheets (windowed, offscreen, one tile in a screen corner so it cannot cover another unit's run)
tools/godot.sh shot --scene=res://world/kit/tests/props_studio.tscn --out=propsqa --times=99999 \
  --warm=2 --qa-out=$PWD/tmp/kit-r10 --qa-tag=after --qa-views=q34
tools/godot.sh shot --scene=res://world/kit/tests/props_studio.tscn --out=propsqa --times=99999 \
  --warm=2 --qa-out=$PWD/tmp/kit-r10 --qa-tag=a6 --qa-props=crane,ac_cluster,food_stall
# the props' own frame cost (perf_probe.gd never reported them: they are 2 levels under World)
tools/godot.sh shot --scene=res://world/kit/tests/prop_cost.tscn --out=propcost --times=99999 \
  --warm=2 --skip-menu --spawn=-470,70,560,0
# before/after: tools/citykit/props_swap.sh puts the pre-r10 meshes back, runs a command, restores
tools/citykit/props_swap.sh save
tools/citykit/props_swap.sh before tools/godot.sh run res://tools/float_audit.tscn 600
tools/citykit/props_swap.sh after  tools/godot.sh run res://tools/float_audit.tscn 600

# r9 — the skyline ring, the eight buildings, the roof map
python3 tools/citykit/assign.py                           # writes the `ring` section + the game copy
python3 tools/citykit/test_assign.py                      # 43 checks, 11 of them the ring's
tools/blender.sh run blender/city/build_city.py           # skin: 358 buildings, 44 far tiles, 96 ring boxes
python3 -c "import json;d=json.load(open('game/world/city/layout.json'));\
print(sum(1 for r in d['skyline_ring'] if r['dropped']), 'of', len(d['skyline_ring']), 'dropped')"
ls game/world/city/skyline.glb 2>&1                       # must be "No such file" — see Requests
tools/godot.sh check --only=res://world/kit/
tools/godot.sh shot --out=r9after --warm=60 --env-only "--cams=$PWD/tools/citykit/cams_r9.json"
tools/godot.sh perf --skip-menu --no-enemies --warm=40 --spawn=-583,16,640,-37.5   # KitPlacer draws
python3 tools/citykit/test_roofmap.py
tools/godot.sh test res://world/art/tests/test_roof_map.gd
SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600    # re-bake LAST, after any kit.json change
tools/godot.sh test res://world/art/tests/test_settle_cache.gd
tools/city/checks.sh                                      # C18 is the one the lead named

# the ring's own cost, back to back: empty the `ring` list in game/world/kit/kit_assign.json, run the
# perf line again, then `python3 tools/citykit/assign.py` to put it back.
```

```
tools/citykit/process_all.sh                          # 58 models: import -> planar -> pnormals -> panes -> repaint -> grade -> export
tools/blender.sh run blender/citykit/farlod.py  -- --all
tools/blender.sh run blender/citykit/fargate.py -- --all
tools/blender.sh run blender/citykit/roofmap.py -- --all      # AFTER process_all: it rewrites row.json AND kit.json
python3 tools/citykit/prune_tex.py --apply
tools/blender.sh run blender/citykit/process.py -- --id t01   # any single model; also rebuilds kit.json
tools/godot.sh check --only=res://world/kit/
python3 tools/citykit/win_import.py --apply --force && tools/godot.sh import
python3 tools/citykit/assign.py
python3 tools/citykit/test_assign.py                  # 33 checks
tools/godot.sh test res://world/kit/tests/test_kit_textures.gd
python3 tools/citykit/rebase_glb.py --check           # the pivot gate, after every process_all
python3 tools/citykit/normalqa.py game/world/kit/<id>/<id>.glb   # the shading gate, any glb
python3 tools/citykit/test_roofmap.py                 # the roof-map gate, all models
tools/blender.sh run blender/citykit/wallgate.py -- --ids t01,m01,o01,c03   # the grazing-sun gate, lit + albedo
SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600    # re-bake after ANY glb/kit.json change
tools/godot.sh test res://world/art/tests/test_settle_cache.gd
python3 tools/citykit/flat_report.py                  # the flatness gate, r3 next to r6
python3 tools/citykit/vram.py
tools/godot.sh perf --skip-menu --no-enemies --warm=40 --spawn=-583,16,640,-37.5
tools/godot.sh shot --out=kit6_st --warm=60 --env-only "--cams=$PWD/tools/citykit/cams_street.json"

# r7 — the cover path (k02 / k07 are the prototypes; --id k01,k03,k04,k05,k06,k08,k09,k10,k11,k12 rolls out)
tools/blender.sh run blender/citykit/process.py -- --id k07
COVER_DUMP=1 tools/blender.sh run blender/citykit/process.py -- --id k07   # writes captures/kit/r7_k07_*.png
tools/blender.sh preview game/world/kit/k07/k07.glb r7_k07 --views=front34,close_front34 --size=900x900
tools/godot.sh import
tools/godot.sh shot --out=kit7b --warm=60 --env-only "--cams=$PWD/tools/citykit/cams_r7.json"
tools/godot.sh shot --scene=res://world/art/tests/probe_kit_layers.tscn --out=r7probe --env-only \
  --warm=1 --times=9999 --probe-cams=res://world/kit/tests/cams_r7probe.json
python3 tools/citykit/wedge.py captures/r7probe_A5deck_shipped.jpg captures/r7probe_A5deck_plainalbedo.jpg

# r8 — the concept palette, all twelve cover models
tools/citykit/process_all.sh k01 k02 k03 k04 k05 k06 k07 k08 k09 k10 k11 k12
tools/blender.sh run blender/citykit/farlod.py  -- --all      # AFTER process_all: it rewrites row.json
tools/blender.sh run blender/citykit/fargate.py -- --all
tools/blender.sh run blender/citykit/roofmap.py -- --all
python3 tools/citykit/prune_tex.py --apply
python3 tools/citykit/win_import.py --apply --force && tools/godot.sh import
QA_FLAT=1  tools/citykit/qa.sh k07          # geometry only, no maps
QA_ONLY=albedo tools/citykit/qa.sh k07      # one map at a time — how the seam/wear artefacts were found
COVER_STAGE=levels tools/blender.sh run blender/citykit/process.py -- --id k07   # levels only, no procedural layer
COVER_DUMP=1   tools/blender.sh run blender/citykit/process.py -- --id k07        # captures/kit/r7_k07_*.png

# the concept-fidelity sheet (12 rows: concept | 15 m | 40 m)
python3 tools/citykit/cams_lineup.py
tools/godot.sh shot --scene=res://world/kit/tests/kit_lineup.tscn --out=r8yaw0 --env-only --warm=60 \
  --times=9999 "--lineup=res://world/kit/tests/lineup_y0.json" \
  "--cams=$PWD/tools/citykit/cams_lineup15.json"        # and yaw90, yaw180
python3 tools/citykit/fidelity_sheet.py --pick          # writes the per-model yaws into lineup.json
tools/godot.sh shot --scene=res://world/kit/tests/kit_lineup.tscn --out=r8fid --env-only --warm=60 \
  --times=9999 "--cams=$PWD/tools/citykit/cams_lineup.json"
python3 tools/citykit/fidelity_sheet.py --sheet --prefix r8fid   # captures/kit/r8_concept_fidelity.jpg

# the wedge gate, and the floor it is measured against
tools/godot.sh shot --scene=res://world/art/tests/probe_kit_layers.tscn --out=r8probe --env-only \
  --warm=1 --times=9999 --probe-cams=res://world/kit/tests/cams_r8probe.json
python3 tools/citykit/wedge.py captures/r8probe_A5deck_shipped.jpg captures/r8probe_A5deck_plainalbedo.jpg
tools/godot.sh shot --scene=res://world/kit/tests/probe_cover_floor.tscn --out=r8floor55 --env-only \
  --warm=1 --times=9999 --probe-cams=res://world/kit/tests/cams_r8probe.json --floor-color=0.55
python3 tools/citykit/wedge.py captures/r8floor55_A5deck_shipped.jpg captures/r8floor55_A5deck_flat.jpg

tools/godot.sh perf --skip-menu --no-enemies --warm=40 --spawn=-583,16,640,-37.5   # KitPlacer draws
tools/godot.sh shot --out=r8st --warm=60 --env-only "--cams=$PWD/tools/citykit/cams_street.json"
SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600    # re-bake LAST, after city-art r12
tools/godot.sh test res://world/art/tests/test_settle_cache.gd
```
Order matters: `process_all.sh` rebuilds `kit.json` from the per-asset `row.json` files, so `farlod`,
`fargate` and `roofmap` must run **after** it or their rows are wiped.

## Evidence
- **`captures/kit/r10_crane_before.jpg` / `r10_crane_after.jpg`** — the crane, six clay views over six
  textured views, before r10 on the first and after on the second. Before: needle legs, a crumpled
  faceted cab, magenta slivers along every rail. After: straight legs, a lattice boom, a stair tower
  with treads, cab windows, white/yellow paint, **0 magenta pixels**.
- **`captures/kit/r10_ac_cluster_before.jpg` / `_after.jpg`** — same layout. Before: crumpled foil,
  kinked ducts, magenta on the fan grilles and under the frame. After: straight box ducts, readable
  fan grilles, an upright stack, 0 magenta.
- **`captures/kit/r10_food_stall_before.jpg` / `_after.jpg`** — the clay TOP view is the one that
  matters (it is the side a 16 m mech sees): three magenta patches in the canopy before, none after.
- **`captures/kit/r10_props_all_{before,after}_{clay,tex}.jpg`** — all 30 props, q34, as a 6 × 5
  contact sheet, clay and textured, before and after. After: no magenta anywhere on the sheet.
- **`captures/kit/r10_ingame_before.jpg` / `_after.jpg`** — the in-game H0/A1 frames, three cameras:
  `A1yard` (the acceptance team's own budget camera, −566,26,524 → −449,8,410 fov 62), `H3deck`
  (−488,62,296 → −520,78,332 fov 60, the crane deck) and `H0crane` (−470,70,560 → −470,58,340 fov 55,
  all four harbour cranes). Before, the H3 crop is a wall of gold shards; after it is a gantry crane.
  Full size: `captures/kit_r10_{before,after}_{A1yard,H3deck,H0crane}.jpg`.
- **`tmp/city-kit/r10/audit_after.md`** — the 30-prop audit table with the visual verdicts.
  `tmp/city-kit/r10/probe_before.log` and `probe_after.log` are the raw probe output either side.
- **`tmp/city-kit/r10/holes_source.log`** — the open-boundary loops of all 30 Tripo sources: 27 of 30
  are not watertight, largest loop anywhere 0.416 m.
- **Frame budget.** `game/world/kit/tests/prop_cost.tscn` (new) hides the `Dressing` node and reports
  what the props cost; `perf_probe.gd` never reported them because they sit two levels under `World`.

  | camera | prop draws | prop triangles before | after | frame before | after |
  |---|---|---|---|---|---|
  | A1 spawn (−566,26,524) | 32 → 31 | 841,037 | 840,723 | 16.66 ms | 16.64 ms |
  | H0 harbour (−470,70,560) | 89 → 89 | 2,086,859 | 2,626,353 | 23.73 ms | 24.17 ms |

  The harbour camera is where the crane change lands: **+539,494 triangles (+25.9 %) for +0.44 ms**,
  inside the ≤ +0.5 ms gate. The frame numbers are single 40-frame samples in a 9 M-primitive scene,
  so treat ±0.5 ms as the noise floor — the triangle counts are the reliable measurement.
- **`tmp/city-kit/r10/float_before.log` vs `float_after.log`** — the float audit either side of the
  change: the **same two** instances float (`prop:antenna antenna_array_-1_-1` 0.8 m and
  `greeble:vent` 0.8 m, both pre-existing from r9's roof maps and city-art's greebles) and the **same**
  BURY list, positions differing by ≤ 3 cm. Nothing newly floating, nothing newly buried.
- `tmp/city-kit/r10/reprocess_all.log` — the `process_prop.py --all` run over all 30 props.
- **`captures/kit/r9_before_after.jpg`** — the lead's r9 look gate: V2, V5, V7 and the two roof
  cameras (RD5 on Block 9's roof, RD7 on the tallest D7 tower), before r9 on the left and r9 on the
  right, at the shipping default. **RD7 is the one that answers the review**: before is a wall of
  plain pale boxes with stepped tops, after is a skyline of buildings with crowns, spires and lit
  windows. RD5 before is a flat orange plane — that is tile t5_4's HLOD proxy standing up because
  Block 9 was unskinned; after, the proxy is down and the kit city is there.
- **`captures/kit/r9_v5_horizon_2x.jpg`** — the 2× crop of the V5 horizon the lead asked for. Before:
  a flat dark silhouette band with a stepped top. After: a lit skyline. Measured over the right-hand
  horizon (where the ring dominates), mean luminance **99.6 → 144.2** and the p5–p95 range
  **100.6 → 159.9**: the ring reads **brighter and higher-contrast** than the boxes did, not darker.
  See Requests — `mc_kit_body`'s haze is much weaker at 750–1 900 m than `mc_skyline`'s `sky_band` mix.
- `captures/r9before_*.jpg`, `captures/r9after_*.jpg` — the same five cameras full size;
  `captures/r9after1_*.jpg` are the same at `--render-scale=1`.
- `captures/kit/<id>.jpg` for m06, m07, m08, w01, w02, r01, r02, r03, r04 — the per-asset QA sheets
  (4 lit angles + top). All nine passed on the first generation: no fused geometry, no floating junk,
  no baked-in ground. m06 and m08 carry the elevated railway Tripo modelled through their openings,
  which sticks out past the footprint and inflates their bounding box (m06 measures 176 × 95 m rather
  than the square the concept asked for) — that is why Block 9 took m04 instead.
- `tools/citykit/test_assign.py` -> **0 checks failed** (43 checks). Eleven are new and gate the ring:
  every skyline box covered or skipped with a reason, index order, no double cover, per-row anisotropy
  recomputed from the box, no row past `ANISO_SOFT`, every ring model ships a far glb, no ring model
  has a through-opening, every ring model faces the centre within 90°, no two angular neighbours share
  a model (except rows marked `forced`), neighbouring crowns vary, at least six models used.
- `tools/godot.sh check --only=res://world/kit/` -> **9 files, 0 failed, 0 errors, 0 warnings.**
- `tools/citykit/rebase_glb.py --check` -> **PASS.**
- `tools/citykit/test_roofmap.py` -> **PASS**, 67 models, worst p95 **0.422 m**.
- `world/art/tests/test_roof_map.gd` -> **PASS** — 40 buildings probed, 40 answered (was 38),
  358 rows, 0 on a model with no map.
- `world/art/tests/test_settle_cache.gd` -> **PASS (0 failures)**; `float_audit` -> **2 dressing
  instances floating more than 0.5 m**, **0 of 3 823** STRUCTURE instances off their surface.
- `tools/city/checks.sh` -> **C16 PASS**, **C18 PASS** (137 335 samples on a 4 m grid, 0 with no
  rendered face within 0.3 m). C12 41/48 arcs blocked, C13 18.0 % under headroom, C14, C15 47.6 %,
  C15b 6/7, C17 — all match city-build's own long-standing numbers in `status/city-build.md`.
- Perf at the A1 spawn (`tools/godot.sh perf --skip-menu --no-enemies --warm=40
  --spawn=-583,16,640,-37.5`): **KitPlacer 94 draws / 3.22 M prims**, whole frame 1 052 draws /
  5.27 M prims. r8 was 89 / 3.20 M and 1 065 draws — the ring's +17 draws and +0.40 M primitives are
  the whole difference, and the placer is inside the lead's 98.
- VRAM: kit textures **761 MB** resident with mipmaps (675 images); everything under `game/world/`
  **1 027 MB**. r8 was 685 MB / 951 MB — nine new models, one 2 K albedo among them (m06, m08).
- Credits: **12 646 → 12 061, 585 spent** on nine image→model generations. No regeneration was needed:
  every concept's first pick passed its QA sheet.
- **`captures/kit/r8_concept_fidelity.jpg`** — the lead's r8 §4 gate: twelve rows of concept | in-game
  at 15 m | in-game at 40 m, in the real city under the street cameras' dusk. Every paint-class model
  reads white or light grey; k04's chevrons and k07's plinth stripes are visible in the 40 m column.
- **`captures/kit/r8_before_after.jpg`** — for the user: A5deck, A6garden, A1yard and A3st, before on
  the left (r7 for A5deck/A6garden, r6 for A1yard/A3st — r7 only rebuilt k02 and k07) and r8 on the
  right, at the shipping default scale.
- **`captures/r8probe_A5deck_*.jpg`** and **`captures/r8floor55_A5deck_*.jpg`** — the wedge ladder and
  the floor measurement behind the table in the r8 section.
- **`captures/kit/k07.jpg`** (and the same for every k-model) — the per-asset QA sheet, 4 lit angles +
  top. `tmp/city-kit/r8/k07_flat_s.jpg` is the same model with a flat material, and
  `tmp/city-kit/r8/k07_layers.jpg` is albedo-only against normal-only: the two rungs that localised
  the seam wash and the wear diagonals to the maps rather than the mesh.
- **`captures/kit/r7_k07_albedo.png`** and the other `COVER_DUMP` maps — the composed albedo, ORM,
  normal, layout and every procedural field, for one model.
- **`tmp/city-kit/r6_ab.jpg`** (and the 2x crops `tmp/city-kit/crop6_T1fac.jpg`,
  `crop6_A4st.jpg`, `crop6_A5deck.jpg`, `crop6_A6garden.jpg`) — lead_r6pre left, r6
  right, same cameras. The four things r6 changed, in one
  sheet: T1fac's pale blank sheet is gone and has panel structure; A4st is off the wall; A5deck's
  transformer blocks read as brown painted steel where r6pre had black/white speckle; A6garden's crate
  is clean.
- **`captures/kit/wall_<id>.png` + `wall_<id>_alb.png`** — the grazing-sun gate at 30 m, lit and
  unlit-albedo, t01 / m01 / o01 / c01 / c03 / b01 / t04 / k03. The albedo pass is what proved the pale
  sheets were the emission.
- `captures/kit6_st_*.jpg` (7 street cameras), `captures/kit6nk_*.jpg` (`--no-kit` A/B).
- `tools/godot.sh check --only=res://world/kit/` -> **9 files, 0 failed, 0 errors, 0 warnings.**
- `tools/citykit/test_assign.py` -> **0 checks failed.**
- `tools/citykit/rebase_glb.py --check` -> **PASS.**
- `tools/citykit/normalqa.py` -> **PASS** (gate: >= 95 % of lit wall area inside the 2 % spread).
- `tools/citykit/test_roofmap.py` -> **PASS**, 57 models, worst p95 **0.376 m**.
- Far gate: **58 of 58 PASS.**
- `test_kit_textures.gd` -> **47 window masks, all FORMAT_L8 with mipmaps.**
- `test_settle_cache.gd` -> **PASS (0 failures)**; `float_audit` -> **0 dressing instances floating
  more than 0.5 m**, 0 of 3 905 STRUCTURE instances off their surface.
- Perf at the A1 spawn: **30 fps / 1 065 draws / 5.24 M prims**; **KitPlacer 89 draws, 3.20 M prims**
  — inside the lead's <= 98. (r5: 32 fps / 1 145 draws / KitPlacer 96. Fewer draws, one frame slower;
  the wall repaint and the plane normals cost nothing at runtime, they are baked into the glb.)
- VRAM: kit textures **685 MB** resident with mipmaps (591 images); everything under `game/world/`
  **951 MB**. Unchanged from r5 — r6 changed pixels, not resolution.
- Credits: **13 101, unchanged — r6 spent nothing.** The whole round is geometry, pixels and two
  base bugs.

## Known issues
- **ac_cluster's largest open boundary is 0.26 m, 0.06 m over the lead's 0.2 m numeric gate, and it is
  not a hole.** `probe_holes.py` shows the component is two boundary edges whose ring already exists —
  a one-sided fin attached along one edge, so the surface is there. Six clay views show zero magenta.
  Closing it would mean deleting real geometry, which I am not doing to make a number.
- **The prop meshes are not in the settle fingerprint.** `world/art/settle/cache.gd::INPUTS` covers
  the layouts, `kit_assign.json`, `kit.json`, the tile glbs and the kit glbs, but not
  `world/props/meshes`. So a future prop rebuild will NOT stale the bake and the discipline is on
  whoever rebuilds. Request written; the file is city-art's.
- **The frame-time samples in the budget table are noisy.** One 40-frame sample each, in a scene that
  also carries city-art's in-flight r16 work and whatever else is on the machine. The triangle counts
  and draw counts are exact; the milliseconds are ±0.5 ms.
- **The r9 floaters are still there** (`prop:antenna antenna_array_-1_-1` 0.8 m at y 11.7,
  `greeble:vent` 0.8 m). Unchanged by r10 and not mine.
- **The ring reads brighter and sharper than the boxes did, and I measured it.** Over the V5 right-hand
  horizon the mean luminance goes 99.6 → 144.2 and the p5–p95 range 100.6 → 159.9. That is not the
  "darker" failure the lead warned about, but it is the same shader gap seen from the other side:
  `mc_skyline` mixed its surface toward `sky_band` with `t` up to 0.97, while `mc_kit_body`'s haze runs
  through `mc_haze`, whose far band is `smoothstep(750, 1900, d) * haze_far_amount` — about 0.11 of
  the amount at 1 km. The ring therefore sits forward of the horizon band. Request written; the files
  are city-art's and I have not touched them.
- **Frame time at V5 could not be compared cleanly across r8 and r9.** The before run (10:45) and the
  after run (12:15) straddle city-art's in-flight r13 shadow/`mc_surface`/`mc_kit_body` work, and the
  machine is shared. What IS clean is the ring's own cost, measured back to back in one session with
  the ring rows present or not: **+15 draws, +0.37 M primitives at the V5 spawn**. V2 improved
  outright (15 → 23 fps, 18.78 → 14.54 M primitives, 1 263 → 1 251 draws). The V5 fps reading moved
  25 → 11 with draws and primitives essentially unchanged (789 → 751, 9.84 → 9.93 M), which is a
  shader/shadow cost and not the ring's; it wants re-measuring once city-art's r13 lands.
- **The before/after captures are contaminated by city-art's uncommitted work.** `city_art.gd`,
  `material_library.gd`, `quality.gd`, `mc_kit_body.gdshaderinc` and `mc_surface.gdshader` all changed
  between the two capture runs, which is visible as a darker foreground in r9's V5. The horizon — the
  thing r9 changed — is unaffected, but the near-field difference in those sheets is not mine.
- **2 dressing instances float more than 0.5 m** (`prop:antenna antenna_array_-1_-1` 0.8 m,
  `greeble:duct` 0.5 m, both at y 11.7). r8 had 0. They appeared when c01 and m06 got roof maps, so
  the settle now has a real surface to aim at where it previously had the design box top; the two
  props sit just off it.
- **`skyline.glb` has to be deleted by hand.** `build_city.py::_export_skyline` returns early when the
  ring kit is empty, so it never rewrites the file and the stale mesh keeps rendering. I deleted the
  generated artefact; a `--blockout` rebuild restores it. Request written.
- **w01 is on 26 buildings.** It is the only model in the kit under 9 m deep, so every thin box in the
  layout now takes it, and the tier fallback lets it out of its declared D2/D4/D5 into D3/D6/D7. The
  fits are honest (p50 anisotropy 1.25 across the city, unchanged) but 26 copies of one facade is a
  repetition risk I did not spend credits to fix.
- **The flatness gate (>= 50 % truly flat) is still not met** and r6 did not chase it: the lead
  dropped it in r6 ("your argument about the triangle budget holds"). The r5 numbers stand. What r6
  changed is the thing the player sees — the SHADING is now flat inside a region whether or not the
  geometry is.
- **The pane rasteriser's pre-prune sliver rate went up** (median 13.4 %, 32 models over the 10 %
  gate, worst o03 68.3 %). Cause: the pane regions are now every wall rather than the few strictly
  planar ones, so there are far more region borders for a 2.0 x 2.4 m pane to be clipped by. **Every
  sliver is erased before the mask ships** (`pruned_pct == small_pct`) and the shipped `pane_px` is
  measured after the erase, so what the shader lights is unchanged in kind — but the number the gate
  reads is worse and I would rather say so than tune the gate to hide it.
- **The world-scale grid is subtle on the largest, flattest near walls** — see In progress item 4.
- **t04 has one 389 m2 region at 34 % spread** (`normalqa`), which is 4 % of its lit wall area and
  keeps it at 95.9 % rather than 99 %+. It is a facade the region growing broke on rather than
  merged; the other 1 081 regions on that model are at 0.01-0.20 %.
- **k02 is still the one model where flattening costs more than it buys** (r5 finding, unchanged).
- **At the mandated albedo the near cover clips toward white in the A5deck sun.** 0.72-0.80 stored
  sRGB is 0.48-0.60 linear, which is a very bright albedo for a surface in direct dusk sun; the
  `r8_before_after.jpg` A5deck pair shows the nearest pieces reading as near-white with the shading
  compressed. The albedo is what the lead specified and the wedge floor measurement says the texture
  is not adding the contrast, so the remaining lever is the lighting/tonemap side (city-art's), not
  the texture.
- **The cover's albedo resolution is 121 mm per texel on the big models** (k07, k02, k12) because a
  9 000-island layout of a 1 200 m2 shell into a 1 k atlas cannot do better. That is why the panel
  seam is 2.4 m and the hazard period 0.6 m: both are at the narrowest this atlas can draw. A 2 k
  atlas would halve it and cost roughly +250 MB of kit VRAM.

## Requests (to the lead / other units)
- **city-art (r16, the important one)**: **I rebuilt every prop mesh this round** — all 30 glbs under
  `game/world/props/meshes/`, plus `ac_cluster`'s texture set (512 → 1024). Triangles went up on
  `crane` (9,867 → 39,999), `ac_cluster` (7,999 → 15,998) and `food_stall` (5,000 → 9,999); the other
  27 are at the same budgets with the same textures, but their glbs are rewritten (tears capped,
  floaters pruned). **Nothing in `world/art/` was touched except `settle_cache.json`**, which I
  re-baked and committed. If you change the settle fingerprint, re-bake after me.
- **city-art**: add `res://world/props/meshes` to `SettleCache.INPUTS` (size+mtime, like the kit glbs).
  A prop rebuild changes where the settle puts it and today nothing detects that.
- **city-art**: `perf_probe.gd` only descends one level under `World`, so the props
  (`World/ArtEnvironment/Dressing`) never appear in its table. Either descend two, or use
  `world/kit/tests/prop_cost.tscn`, which is mine and does exactly that.
- **lead**: `ac_cluster`'s 0.26 m open boundary is a one-sided fin, not a hole (see Known issues). The
  0.2 m numeric gate cannot be met without deleting real geometry. Either accept it with the clay
  evidence, or change the gate to "no magenta in the clay pass", which is what the eye actually reads.
- **lead**: `tools/godot.sh run` silently drops every argument after `<scene> <seconds>`, so a
  windowed tool that needs its own flags has nowhere to go — I had to launch mine through
  `shot --scene=... --times=99999`, which works but is a hack. A `tools/godot.sh windowed <scene>
  [-- args]` that forwards would be the fix; `tools/*.sh` is yours.
- **city-art (r9, the important one)**: **the skyline ring is under-hazed.** The 96 boxes used to wear
  `mc_skyline`, which mixes its surface toward `sky_band` with `t` clamped at 0.97; the kit models that
  replaced them wear `mc_kit_body`, whose haze runs through `mc_haze` — `smoothstep(750, 1900, d) *
  haze_far_amount`, about **0.11 of the amount at 1 km**. Measured over the V5 right-hand horizon:
  mean luminance **99.6 → 144.2**, p5–p95 range **100.6 → 159.9**. The ring reads brighter and
  higher-contrast than the horizon band it replaced, which is visible in
  `captures/kit/r9_v5_horizon_2x.jpg`. I have not touched `mc_kit_body` or `mc_haze`. What would fix
  it, in your files: either pull `haze_far_begin` in (750 → ~500 m) for the kit body, or raise
  `haze_far_amount`, or give the ring's material a `sky_band` mix like `mc_skyline` has. The ring is
  740–1 229 m out and read from 300 to 2 200 m, so whatever you pick has to hold across that whole
  range.
- **city-build**: `build_city.py::_export_skyline` returns early when the ring kit is empty
  (`Kit.merged()` is `None`), so it never rewrites `skyline.glb` and the stale mesh keeps rendering
  every box a `ring` row dropped. I deleted the generated file by hand this round; it needs an
  `os.remove` in that early return, or the export has to write an empty mesh.
- **city-art**: `city_art.gd::_skyline()` now warns `no 'Skyline' child on ...` on every boot, because
  the ring is gone. It returns 0 and nothing breaks, but the warning should go once the ring is
  permanently the kit's.
- **lead**: `game/world/art/settle_cache.json` has been re-baked again for r9 and is **left
  uncommitted** — the file is city-art's, not mine, and my gate requires a re-bake after any kit.json
  change. Same request as r7 and r8.
- **lead**: `game/world/art/settle_cache.json` has been re-baked (my r7 gate requires it after
  any glb change) and is **left uncommitted** because the file is city-art's, not mine. It needs
  committing by whoever owns it, or a decision that I own it.
- **city-art**: the roof map is in `kit.json` and documented above — please consume it next round and
  stop dropping the 1 099 rooftop units. `tools/citykit/test_roofmap.py` is the gate; if a dressing
  point you sample lands wrong, that test will show it.
- **city-art**: the r6 specular request is WITHDRAWN — the lead's r11 elimination showed the foil is
  painted into the albedo atlas, not a specular term, and city-art r11 is moving the building walls
  onto an object-space facade in `mc_kit_body`. I have not touched `mc_kit_body` and will not.
- **city-art**: `kit_placer.gd` untouched. `game/world/art/settle_cache.json` HAS been re-baked
  this round, because my r7 gate requires it after any glb change — see the lead request above; it is
  left uncommitted rather than committed over your file.
- **lead**: the 8 uncovered buildings and the D3 old-town variants are still open and both need
  either credits or a layout decision.
- **lead (r8, the important one)**: **the A5deck wedge gate cannot be met at the r8 §1 albedo, and I
  have the measurement.** The gate compares against `probe_kit_layers.gd` rung 3, which is a flat
  panel at `base_color` (0.25, 0.20, 0.16) — **0.25 linear**. The §1 target is 0.48-0.60 linear, 2.2x
  brighter, so a *perfectly flat* surface at the mandated albedo already measures ~1.6x before any
  texture. `game/world/kit/tests/probe_cover_floor.tscn` measures it directly: against a flat panel at
  the §1 target the shipped build scores **1.14 on A5deck and 0.98 on A1yard**; against the lead's rung
  it scores 1.77 and 0.95. Two ways out, both yours to pick: change rung 3's `base_color` to the §1
  target (then the gate measures what it was written to measure), or raise the gate to ~1.9 for the
  cover band. I am not going to darken the albedo below the number the same review specified.
- **lead**: **k04 is never placed by the assigner** — a 25 x 3.5 m jersey-barrier line cannot fill a
  16-33 m cover box, so the model with the kit's best hazard band appears in no arena. It needs either
  a few long thin cover boxes in the layout, or a decision that barriers are a `pieces` row along deck
  edges (which is where they would read best anyway).
- **lead**: `game/world/art/settle_cache.json` has been re-baked again for r8, still left uncommitted
  for the same reason as r7.
