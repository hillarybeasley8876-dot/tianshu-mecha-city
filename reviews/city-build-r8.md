# city-build — review r7 result (lead) + round 8 — PASS; now the far field and the landmarks

## r7 verdict: PASS
Reproduced: `skin_probe.gd` → **SKIN PROBE PASS (0 failed)**: 358/358 footprints, 736/736 slots, navmesh polys
unchanged. The breach analysis (the slot was in mid-air, not a lost collider) is exactly right, and so is the exact
collision diff (`probe_skin.py`, identical to the decimal). Good catch on the 100 ignored `pieces` rows, and on
city-art's cargo skin hiding the cover hook (city-art has since landed the ownership rule).

## Round 8 — build

### 1. Landmarks must be themselves from every vista (impact 9, small)
`captures/lead/far_layers_V2.jpg` = V2 as shipped | `--art-debug=hide=_hlod` | `hide=Skyline` | `--no-kit`.
V2 is the Spire vista, 561 m from the Spire, and **the Spire there is its `_hlod` collision mass in the skyline
shader**: a lavender pixel-block trumpet. Hide the `_hlod` and the Spire disappears except its light strips,
because `city.gd::_fix_up` gives every non-HLOD mesh `visibility_range_end = DETAIL_END` (450 m), the
landmark's own render chunks included. The city's hero landmark is visible from the whole map and cannot end at
450 m. Fix: landmark render chunks (spire + crown, crystal_bridge, reactor_stacks, stilt_pagoda, harbor_cranes,
interchange_knot, civic_hologram, block9) get their own range, at least 2,000 m. Tag them in the build (a
`landmark` name prefix or meta) and give them a cheap LOD if the triangle cost is high. Measure prims and draws at
V2 before and after. The HLOD must not double-draw the landmark: cut the landmark's own volume out of its tile's
`_hlod`.

### 2. The look items (`reviews/look/city-build.md`) — both are yours
- **Crystal Bridge** (impact 7): a 300 m scaffold of 3×3 m posts and pale slabs that reads as a farm fence. Rebuild
  it as the glazed faceted arch the docstring promises (sweep, mullions, diagrid ribs, lit underside, maglev
  inside the glass), or a Tripo landmark with the kit only for deck and collision. A/B at the A6 hive shot and from
  V2/V6.
- **Chamfered kit boxes** (impact 5): an optional chamfer in `Kit.box` (1.5 % of the smallest side, clamped
  0.1–0.6 m) with face-weighted normals, used for every element under 40 m (deck lips, parapets, posts, beams,
  cover); raw boxes for interiors and collision only. Report the triangle delta.

### 3. The skyline ring becomes kit-able (with city-kit and city-art)
`captures/lead/far_layers_V5.jpg`: the big lavender towers at V5 are your 96-box `skyline` ring (hide `Skyline` and
they are gone), dressed in city-art's window-cell shader. That is the purest "building blocks" left in the frame. Add
a `ring` row kind to `kit_assign.json` (`{"kind": "ring", "index": 12, "model": ...}`, index into
`city_layout.json["skyline"]`) that drops that box from `skyline.glb` exactly like `cover`, and export the ring
slots (centre, size, height, index) so city-kit can place far models there. City-art is softening the ring shader
meanwhile.

### 4. Far tiles: hold the 29
City-kit's far meshes are shredded (`captures/blender/kitfar_b01_studio.jpg`) and are being rebuilt. Keep the
`far_lod` hook, but make `city.gd` stand a proxy down only for far rows that carry `"gate": "pass"` (city-kit adds
it per model once their hole gate passes). Until then the proxy stays.

## Evidence
V2/V5/V8 before/after for item 1 (`captures/cb8_landmark_V*.jpg`), the bridge A/B, a chamfer close-up at A1, prims
and draws per vista, all existing tests and probes green.
