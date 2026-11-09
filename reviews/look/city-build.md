# Look diagnosis items for city-build (lead-verified workflow wf_5e92d07a-bee, 2026-11-02)

Source: an independent critique of the user's screenshot `tmp/lead/user_shot_1.png` (A6 hive fight) against the key art.
Do them in this order (impact per hour). Each item: what is in the picture, the cause (file:line), the fix.

## The 'fence of brown boxes' is the Crystal Bridge landmark, built from 3x3 m posts and 4x36 m slabs  (impact 7, ~3.5 h)

**In the picture:** The right half of the frame (x 800-1600, y 430-700): rows of dark-brown, unbevelled square posts that rise toward the right, a thick square bottom chord, pale flat slabs joining each pair of posts, a thin cyan strip at the base, and the maglev capsule poking out at (1400,670). It is the biggest structure in the frame and reads as a scaffold or a farm fence, not a landmark. ART.md §4 for D7 asks for 'glass + steel, gold reflections ... prismatic Crystal Bridge'.

**Cause:** blender/city/kit/landmarks.py:145-162, crystal_bridge. Layout entry: pos (-40,-330,176), length 300, width 36, height 28. It sits 120 m north of hive_a6, and its maglev prop slot at z 186 matches the capsule in view, so this is the structure on screen.

Its docstring promises 'a glazed prism arch ... faceted ribs'. It actually builds:
- 13 stations of `kit.box('mc_metal', ..., (3.0, 3.0, height*0.8+12))` posts on both sides, 34 m tall (:157-158)
- one 4x36x2 m `mc_glass` slab per station (:155)
- 4x4 m `mc_metal` chords (:159-160)
- a 1.2 m `mc_up_accent` strip (:161)
- the maglev slot (:162)

Every piece is an axis-aligned, unbevelled box. mc_metal is metal 0.9 / roughness 0.34 (world/art/material_library.gd:37), so in backlight it only reflects dark warm haze and comes out brown. Nothing is faceted, transparent or curved.

**Fix:** Rebuild crystal_bridge as an arch:
- Sweep a faceted 6- or 8-sided prism tube along the sin(t*pi) arch with kit.sweep. Glaze it with mc_glass in 4 m panels with 0.4 m bronze mullions on the facet edges, and run thin emissive edge lines (mc_up_accent, 0.3 m) along two facets.
- Replace the vertical 34 m posts with tapered, bevelled diagrid ribs (1.2 m tapering to 0.6 m) every 12 m, following the curve.
- Add bronze node caps at the rib joints (the 'gold reflections'), a slim deck slab with a lit underside, and run the maglev inside the glass.
- Or generate the landmark in Tripo (ART.md §5) and keep the kit only for the deck and collision.

Visual target: the glass skybridges in key art v2 and v8. A bright faceted tube that catches the sky, with a crisp arch silhouette that still reads as glass at 300 m.

## Every kit box is a sharp unbevelled cuboid, so no edge catches the low sun  (impact 5, ~4 h)

**In the picture:** Every deck edge, cover box, bridge post and roof slab in the frame meets its neighbouring face at a knife-sharp 90° with no highlight line. Against the haze the silhouettes read as untextured CAD blocks, most visibly the deck lips at (230-700, 790-830) and the bridge posts. Much of the richness in key art v1 and v2 comes from lit chamfers and slab edges catching the raking sun.

**Cause:** Kit.box in blender/city/kit/builder.py:61 and :202 emits plain 8-corner boxes, and every structural element is built from them: decks.py _parapet/_truss/_columns, connectors.py _railing, corridors.py barriers and beams, landmarks.py, props.py cover. There is no chamfer, bevel or weighted normal. mc_surface's panel_joint fakes seams on faces, but nothing on the edges.

**Fix:** Give Kit.box an optional chamfer, defaulting to 1.5% of the smallest side clamped to 0.1-0.6 m, that emits a chamfered box with face-weighted normals. The big faces stay flat and only the edge band shades. Use it for every element under 40 m; keep raw boxes only for interiors and collision.

Optionally, have mc_surface add a thin up-sun highlight on the chamfer band for the gold edge line in the key art. The extra triangles per tile are trivial, but check the budget anyway.

Visual target: key art v1 and v2, where every slab lip and parapet has a thin warm highlight on its sun side and a soft shadow line under it.
