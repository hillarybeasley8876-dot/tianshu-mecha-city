# Look diagnosis items for city-art (lead-verified workflow wf_5e92d07a-bee, 2026-11-02)

Source: an independent critique of the user's screenshot `tmp/lead/user_shot_1.png` (A6 hive fight) against the key art.
Do them in this order (impact per hour). Each item: what is in the picture, the cause (file:line), the fix.

## Mipmaps are off on every tiling city texture, so all slabs, posts and box faces turn to sandpaper and moiré  (impact 8, ~1 h)

**In the picture:** The dotted orange moiré on the deck and cover tops in the lower half (x 250-700, y 780-880) and on the rooftops at far left (y 740-800). The crawling grain on the dark bridge posts across the right half (x 800-1600, y 430-700). The speckle on every dark box side behind the hero. The key art has smooth gradients on stone and wet slab; here every flat surface fizzes. It gets worse in motion because TAA, which is on in the high preset, turns the noise into crawling shimmer.

**Cause:** All 15 CC0 maps in game/assets/textures/*/ (brushed_concrete, metal_plate, concrete_panels, clay_plaster, clay_roof_tiles_02) are imported with mipmaps/generate=false, e.g. game/assets/textures/metal_plate/metal_plate_diff.jpg.import:26. The imported .ctex headers of metal_plate_diff and brushed_concrete_diff (1024 px) contain 0 mip levels. Godot's detect_3d never upgrades them because world/art/surface_factory.gd:60-75 binds them to a ShaderMaterial at runtime. mc_surface.gdshader:71-73 then samples them triplanar at tile_m 1.0-2.5 m (material_library.gd:27-48). At 60-150 m that is about 20-60 texels per pixel with no mips; metal_plate at 1 m is the worst. The procedural grooves are not antialiased either: the paver groove (mc_surface.gdshader:228-229) and panel_joint (:77-85) use fixed-metre smoothsteps with no fwidth fade, unlike the facade grid at :123-124. Hero, monster and prop textures are all imported with mipmaps on, which is why they do not fizz.

**Fix:** 1. Set mipmaps/generate=true and compress/mode=2 (VRAM) in the 15 .import files and run tools/godot_import.sh. Make tools/textures/fetch.py write that .import next to each map so the next fetch cannot bring the bug back.
2. Add filter_linear_mipmap_anisotropic to the samplers at mc_surface.gdshader:18-20 (and the same in mc_kit_body.gdshaderinc:27-32). Decks are seen at grazing angles, so anisotropic filtering is what keeps them crisp.
3. Fade the paver groove and panel_joint the way the facade code does, e.g. `float aa = clamp(max(fwidth(v_world.x), fwidth(v_world.z)) / 0.12, 0.0, 1.0); groove *= 1.0 - aa;`.

Visual target: the wet slab in key art v1 and the pale stone in v2. Big smooth value gradients, zero shimmer, the paver grid readable to about 40 m and gone by about 80 m. Check with a still and a 2 s pan from this exact spot: no dot pattern on any top.

## The prop processor shrinks every prop's albedo in place to the size of its emission mask  (impact 4, ~1 h)

**In the picture:** The maglev car on the bridge at about (1370-1430, 655-685) is a blurry brown capsule with one smeared cyan stripe: no panel lines, windows or livery. The same 256-512 px mush is on every roof machine and street prop in the mid-ground. The crates and machinery in key art v1 carry crisp stencils, ribs and grime.

**Cause:** In blender/props/process_prop.py:64-65, emissive_mask_from_albedo calls `src.scale(tex, tex)` on the real imported Color image, not on a copy, with tex = max(min(tex//2, 512), 128). That image datablock is the one wired to Base Color, so the GLB exports the mask-sized albedo.

Shipped sizes confirm it:
- container_stack, maglev_car, crane: spec 1024, shipped 512
- wreck_mech, mech_statue: spec 2048, shipped 512
- streetlamp, barrier: spec 512, shipped 256
- overall: 17 props ship at 256 px and 13 at 512 px

resize_textures (:91) also halves NormalGL, which contradicts prop_table.py's own docstring ('normal is the same'). The export uses JPEG quality 75 (:174), and EMISSION_STRENGTH 6.0 (:26) blooms the light strips. The Tripo sources are exported at 4096 px (tools/tripo/pipeline.py:113), so the detail is there to keep.

**Fix:** Change :64-65 to `src = src.copy(); src.scale(tex, tex)` and remove the copy after packing, as mon_emit.py:82 does. In resize_textures, keep NormalGL at the albedo size and halve only ORM and the mask. Set jpeg_quality to 90 and EMISSION_STRENGTH to about 2.5. Re-run `tools/blender.sh run blender/props/process_prop.py -- --all`, reimport, and confirm with a size dump that every prop's albedo matches its prop_table tex.

Visual target: the pier props in key art v1, with stencils, ribs and panel lines readable at 20-40 m.

## The 'crates' are bare kit boxes: 360 breakable-cover slots that nothing ever dresses  (impact 5, ~3 h)

**In the picture:** The blocks in the lower middle and left (x 230-700, y 760-900) and the dark masses behind the hero are plain rectangular boxes 17-30 m wide. They have dark grainy sides and a slightly inset pale cap, with no ribs, doors, stencils, straps or damage. These are the A6 cover pieces. They are the closest geometry after the hero, so they set the quality bar for the whole frame, and they read as untextured blockout.

**Cause:** In blender/city/kit/props.py:25-31, arena cover is built with `kit.box(role)`: mc_metal for soft cover, mc_concrete for hard cover, each with an mc_panel_white cap at 0.94 scale and 0.8 m thick. Soft pieces emit a breakable_cover slot, and layout.json has 360 of them. But game/world/props/prop_placer.gd:70 lists 'breakable_cover' in IGNORED_SLOTS, so no Tripo prop or dressing is ever placed there.

**Fix:** city-art dresses every breakable_cover slot to its footprint, with one of two approaches:
- Fill the volume with 1-3 scaled container_stack, crate or wreck props (after the prop texture fix), rotated a few degrees off the grid.
- Or keep the box for collision and swap its render mesh for a kit 'cargo block': corrugated sides (a CC0 corrugated-steel set with a real normal map at 2.5 m tile, added via tools/textures/fetch.py), 0.4 m chamfered corner posts, a hazard-stripe band, stencil decals and district paint. Per ART.md §4: faded rust and teal containers in D1, white-and-gold crates in D7.

Hard cover becomes bevelled concrete planters and barriers.

Visual target: the stacked containers and crates on the pier in key art v1.
