# city-art — review r8 result (lead) + round 9 — PASS; the distant city must stop reading as lavender pixel blocks

## r8 verdict: PASS
`captures/look_city-art_r8_cover_ab.jpg` / `_wall_ab.jpg`: the low stacks now have containers standing clear of the
slab, and the walls read as board-formed concrete (boards, tie holes, one reveal). The ownership rule has a
two-direction test, and you found and fixed a vacuous r7 assertion. Good round.

## Round 9 — the far field (impact 9; it is in every vista)
Fresh captures of all 8 vistas (`captures/now_V1..V8.jpg`; sheets `tmp/lead/now_v1_4.jpg`, `now_v5_8.jpg`) and a layer
A/B at V2 and V5 (`captures/lead/far_layers_V2.jpg`, `far_layers_V5.jpg` = as shipped | hide `_hlod` | hide
`Skyline` | `--no-kit`). Past ~450 m the frame is **lavender-grey box masses covered in a pixel-step checkerboard**:
- **V5**: the large towers on the horizon are city-build's 96-box `skyline` ring (hide `Skyline` and they are gone).
- **V2**: the Spire mass, and the blocks round it, are city-build's `_hlod` proxies (hide `_hlod` and the boxes go;
  city-build is fixing the Spire's own visibility range).
Both wear `mc_skyline`. Three problems with that look, all in your shader/material:
1. **Hue and value**: the body is a cool lavender (`SKYLINE_BODY` #1d1a26 lifted by `sky_band` ×
   `band_gain` 0.86 and the haze floor) on a warm amber sky. Against the key art (v1/v2/v8: the distant city is a
   warm-grey/amber silhouette in the haze, darker at the base, sun-rimmed on one side) it reads as a foreign
   colour pasted in front of the sky. Sample the sky colour at the horizon behind the ring (the sky shader's own
   horizon colour at that bearing, `ArtPalette.SKY_HORIZON*`) and make the band a darker, slightly desaturated
   version of it, so distance takes the masses INTO the sky's hue instead of towards lavender.
2. **The checkerboard**: the window cells survive as a high-contrast pixel grid at 450–1,000 m (the HLOD variant's
   7.5 m cell is 2–4 px there). Lit windows at that distance should be a sparse SPARKLE (a few warm points, ~1–2 %),
   not a grid of light and dark squares. Cut the cell grid entirely on the HLOD and ring variants and replace it with
   a sparse hashed point pattern that dissolves to the mean with `fwidth` (no visible cell structure at any
   distance), plus horizontal floor bands at most (very low contrast).
3. **Silhouette**: boxes are boxes. Until city-kit's far meshes and the ring rows land, break the box read in the
   shader: vertical gradient (dark base → hazy top), a sun-side rim on vertical edges, a thin dark roofline, and
   aerial perspective strong enough that the far ring is a soft layer, not a wall.
Measure: the per-vista luminance/hue of the far band before/after (your `stats.py` approach), and the A/B sheets at
V2, V5, V7 (`captures/look_city-art_r9_far_V*.jpg`). Coordinate: city-build is adding `ring` rows (city-kit models
on the ring slots) and is gating `_hlod` hiding on city-kit's far gate. Your shader has to look right on whatever
remains boxes either way.

## Also, from the review queue
- **Prop weld** (monster-assets Requests #6, you own the prop pipeline): `blender/props/process_prop.py:170` imports
  with default glTF options, so every UV seam is open and the decimator tears it. Add `merge_vertices=True` + a
  weld gate (open edges < 2 %), reprocess the 30 props, and A/B one close-up (container_stack, truck).
