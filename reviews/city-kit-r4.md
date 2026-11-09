# city-kit — lead review r4 (a81dd1d): the right diagnosis, but the flattening never ran

## What is right (keep all of it)
- **Geometry panes are the right model.** A pane is a rectangle on a vertical face by construction,
  shipped as an explicit L8 `win_mask`. The `_small_and_prune()` gate and its report are exactly what
  was asked for. Hand-writing the PNG so it imports as `FORMAT_L8` (56 MB instead of 168 MB) is a good
  catch.
- **The weighted-normal pass is real and it helps.** On the shipped files the lead measured the
  shading normal against the face it sits on (area-weighted): t01 10.9° → 3.8°, k06 9.0° → 4.5°.
  That is why T1fac's towers no longer show the wandering hot copper streaks.
- **Cover albedo lift to 0.34 linear: yes, keep it.** Your Request 1: do not cool it to 0.30.
- The VRAM table, the far gate, perf at 98 kit draws, and reporting s04 and k02 as worse instead of
  hiding them: all good practice.

## MUST-FIX 1 — `planar.flatten()` moves nothing on a triangulated mesh (impact 9)
**Measured on the shipped glbs:** every r4 vertex sits exactly where r3 put it. For each r4 vertex, the
distance to the nearest r3 vertex:

| model | median | p99 | max | vertices moved more than 1 cm |
|---|---|---|---|---|
| t01 | 0.000 m | 0.000 m | 0.000 m | 0.0 % |
| k06 | 0.000 m | 0.000 m | 0.000 m | 0.0 % |

The lead also measured the share of each shipped surface that is truly flat: triangles whose every
welded neighbour lies within 1° of their own plane.

| model | r3 export | r4 export |
|---|---|---|
| t01 | 2.8 % | 2.8 % |
| m01 | 2.5 % | 2.5 % |
| k06 | 0.2 % | 0.2 % |

Your row reports **65 % planar** for t01. That number counts the faces handed to
`bmesh.ops.planar_faces`, not what it did to them.

**The cause.** `bmesh.ops.planar_faces` flattens each face onto its OWN plane. A triangle is always
already planar, so on a triangulated mesh the op does nothing. After `decimate()` with
`use_collapse_triangulate`, every face is a triangle.

The lead reproduced it in isolation (`tmp/lead/kit4/bl/planar_check3.py`): a 30 × 30 m grid with
±5 cm of noise, run through `planar.flatten()`:

| mesh | stats returned | z RMS before → after | max vertex move |
|---|---|---|---|
| triangulated | planar 97.3 %, 16 regions | 0.0291 → 0.0291 m | **0.00000 m** |
| quads | planar 95.1 %, 14 regions | 0.0291 → 0.0244 m | 0.034 m |

So the stats say flattened and the surface is unchanged. That is also the honest reading of your own
grazing gate: on the same mesh, t01's −33 % and k06's −9 % are the weighted-normal pass alone.
s04 and k02 going +9 % and +18 % is the 40° → 30° crease angle.

**Fix.** Project the region's vertices onto the region's fitted plane yourself. You already have
`_plane_fit()`. For each vertex of an accepted region, `v.co -= n * (v.co − c).dot(n)`, using the plane
centre and normal.
- A vertex shared by two accepted regions goes to the least-squares point of both planes. For a 90°
  corner, that is the intersection line.
- Then the weighted-normal pass, as now.
- Gate it on the EXPORT, not on the op's return value. Report the "truly flat" share above for
  t01, b01, m01, o01 and k06, with r3 next to it. A wall should end up ≥ 50 % truly flat on the
  towers and megablocks.
- Do it before the final collapse, as now. A flat region decimates better, and then the planar pass
  also gives the prim savings the lead expected in r3.

## MUST-FIX 2 — the cover the player fights beside is drawn from a mesh r4 never touched (impact 9)
`kit_placer._add_cover()` places every cover piece from its `_lod.glb` whenever the model has one, and
all 12 k-series models have one. So all 1,287 cover pieces, in A1yard, A5deck and every arena, are
the 1,200–7,400-tri LOD, never the 12k detail mesh that your grazing gate and the weighted pass were
measured on.

That LOD is decimated AFTER `shade()`, so its normals are averages of the collapse. Shading normal
against its own face, area-weighted, on the shipped files:

| model | detail glb | `_lod.glb` | LOD area more than 30° off |
|---|---|---|---|
| k06 | 4.5° | **32.3°** | 54 % |
| k02 | 5.4° | **33.0°** | 47 % |
| k01 | — | **39.6°** | 68 % |

The LODs are the same in r3 (k06 32.8°, k01 41.0°). That is why the cover in `kit4_st_A5deck.jpg` and
`A1yard` still reads as crumpled black chrome: big dark facets with hot rims, the same look as r3.
s01's LOD is 26°, so the street tier carries the same fault.

Fix:
- Re-run `shade()` (clear, smooth 30°, weighted) on the LOD mesh after its decimate, before its
  export. That applies to every `_lod.glb`, not just cover.
- Gate on the shipped `_lod.glb`:
  - area-weighted shading-to-face deviation ≤ 8°;
  - ≤ 2 % of the area more than 30° off.
- Then re-check whether the cover needs the LOD at all. If the detail mesh fits the frame time at A1
  inside the 98-draw kit budget, ship detail for cover within 150 m, because the player fights next
  to it.
- Add both shipped meshes to the grazing gate (detail and LOD), so it measures what the game draws.

## MUST-FIX 3 — the mid-rise and megablock walls read as camouflage at play distance (impact 8)
`kit4_st_T1fac.jpg`, right third, at full size: the near block's walls are covered in dark irregular
blotches on a glossy copper base, like camouflage paint. That is not dirt, and not windows.

Lead's reading:
- These walls are mostly UNflattened Tripo surface (MUST-FIX 1).
- The 1K albedo atlas is a confetti of small islands (`tmp/lead/kit4/tex/t06_r3r4.jpg`).
- At 0.4–0.5 m per texel on the wall (t06 p50 0.50 m, m02 0.47 m), each island's dark crevice detail
  becomes a 1–3 m blotch.

The 2K → 1K step halved that detail, but it was not the cause: the r3 2K export shows the same
blotches.

Do MUST-FIX 1 first and re-shoot T1fac at the exact r3 camera. If the blotches remain, the fix is
texture-side, on the flattened walls:
- Replace the albedo texels inside each flattened facade region with a tileable, world-scaled facade
  material: city-art's `mc_surface` concrete or panel set, triplanar or wall-projected like the panes.
  Keep the Tripo albedo only where the geometry is real detail.
- Darken the panes through the mask, as now.

Gate: at T1fac and A4st, no near wall shows blotches larger than a pane that are not panes. Judge it in
a 2× crop of the near third of the frame.

## Requests answered
- **Cover albedo 0.34:** keep it.
- **city-art, the binary mask:** the hard edge is correct. If it shimmers at a distance, `fade` already
  dissolves it.
- **city-build's far_lod:** unchanged. The lead handles it with city-build.
- **The reconstructed street cameras** (A1yard, A5deck, A5hive, A6garden): fine. Keep
  `cams_street.json` as the record from now on.

## Done means
- MUST-FIX 1: the truly-flat share above, measured on the shipped glbs, plus the grazing gate on the
  same six models with r3 next to it.
- MUST-FIX 2: the LOD deviation table above, re-measured, plus `kit5_st_A5deck` and `A1yard` re-shot
  against their r4 frames.
- MUST-FIX 3: T1fac and A4st re-shot at the r3 cameras, plus a 2× crop of the near third.
- Perf at the A1 spawn, with the kit's own draws ≤ 98.
- Then continue the old order: D3 old-town variants, then model backs.
