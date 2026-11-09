# Look diagnosis items for monster-assets (lead-verified workflow wf_5e92d07a-bee, 2026-11-02)

Source: an independent critique of the user's screenshot `tmp/lead/user_shot_1.png` (A6 hive fight) against the key art.
Do them in this order (impact per hour). Each item: what is in the picture, the cause (file:line), the fix.

## The hive's emission mask is flat full-saturation acid at energy 3.0, so the trunk blooms into a lime blob  (impact 8, ~2 h)

**In the picture:** The trunk, from y 480 down to the bottom of the frame at x 680-800, is one lumpy lime-yellow glow. No chitin, ribs or dark mass can be read; the lighter green 'scales' are the painted pods and veins blown out. A wide green halo washes over the building behind it at (580-680, 720-795) and over the HUD hexes. ART.md §1 asks for 'a dark, glistening corruption with acid-green veins'; this reads as a glowing green tree.

**Cause:** blender/monsters/mon_emit.py:90 writes `to_linear(acid*ACID + violet*VIOLET)`. Every mask texel is full-saturation #9BFF3A or violet, not modulated by the albedo, so a vein's dark edge glows as hot as its core. The classify thresholds (:60-74) let about 9.3% of the hive's used UV glow (measured on hive_EM_hive.jpg), as hundreds of separate blobs. EMISSION_ENERGY = 3.0 (:21, set at :113) is baked into the GLB, hive_model.gd:102 copies it to the shader, and monster_body.gdshader:46 multiplies it by the intact state scale of 1.0 (hive_model.gd:15). The green channel therefore reaches about 3.0 linear against glow_hdr_threshold 1.45. world/art/quality.gd:79-86 then spreads it over 100+ px (hdr_scale 2.0, all 7 glow levels on high, bloom 0.09). The hive's NormalGL is almost flat and the shader has no rim term, so nothing shapes the dark shell against the sun.

**Fix:** 1. Ten-minute partial fix: in hive_model.gd:102 set emission_energy to about 1.1 for the hive (a per-type value instead of the GLB's 3.0). Keep 0.45 / 0.12 as the cracked and destroyed scales.
2. In mon_emit.py build_mask: multiply the mask by smoothstep(0.25, 0.75, albedo luminance) so bulbs have hot centres and dark edges. Erode it 1-2 px so only vein cores survive, and drop isolated blobs under about 40 px. Target about 3-4% lit area on the trunk, with full value only on the four pod clusters.
3. Per-pod control: write the pod index into the mask's B channel, using the acid clusters from mon_hive.py pod_sockets (:36-43). Add an `instance uniform vec4 pod_alive` to monster_body.gdshader so flow can switch off one pod's glow when it bursts; this replaces the spheres. Pod cores at energy about 2.5, veins at 1.0.
4. The dusk rim comes from the shader change in the monster-silhouette issue.

Visual target: captures/monsters_hive_intact.jpg relit at dusk. A near-black ribbed spire with thin acid veins and four bright pods, matching the infection creep in key art v2.

## Harrier and rippers turn brown and fuzzy against the dusk: chitin too bright and metallic, no rim light, speckled glow  (impact 7, ~2 h)

**In the picture:** The harrier at top-left (50-290, 160-350) reads as a flat brown, half-transparent cut-out with random green flecks and one violet dot. The two rippers under their tags at (1150-1300, 775-810) are brown smudges with green and violet sparkles, about the same value as the deck they stand on. ART.md §1 says 'the dark-green-glowing monsters must pop against warm mid-tones at every distance'. Here they are the warm mid-tone.

**Cause:** The monster albedo is far brighter than ART.md's chitin #1B2430 (linear luminance 0.016). Measured median linear luminance: harrier 0.067, ripper 0.031, hive 0.074, i.e. 2-4.6x too bright.

The ORM is partly metallic: the harrier has metal 0.46 and roughness 0.47; the ripper has metal 0.15 and roughness 0.15. The bodies therefore mostly reflect the warm sky and haze, and come out brown.

monster_body.gdshader:35-50 uses Tripo's albedo and ORM as they are (ALBEDO :37, ROUGHNESS :41, METALLIC :42), with no darkening, no metallic cap and no fresnel or rim term.

The emission mask covers about 6% of the UV (harrier 6.3%, ripper 5.8%) but is scattered specks from the hue classify (mon_emit.py:60-74) at energy 3.0 (:21). At 80 m each speck becomes a sub-pixel sparkle rather than a readable stroke.

**Fix:** In monster_body.gdshader:
- Add a per-type `uniform float albedo_gain` (harrier about 0.25, ripper about 0.5, hive about 0.22) to land on #1B2430.
- Set `METALLIC = min(orm.b, 0.15)` and `ROUGHNESS = max(orm.g, 0.35)` so the chitin reads as wet, dark and non-metallic.
- Add a rim: `float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0); EMISSION += rim * rim_color * rim_gain * mix(1.0, 2.0, smoothstep(40.0, 160.0, dist));`. Use acid #9BFF3A at gain 0.6, or cool #8FA7C4 for the harrier against the sky.

In mon_emit.py, rebuild the masks as connected strokes: eyes, spine ridge, wing-bone leading edges and claws. Use a dilate-then-skeleton pass or per-type painted masks, with no isolated specks that would be under 3 px at 80 m.

Visual target: the monster in key art v8. A near-black silhouette with a thin acid outline and glowing eyes and spine, readable as a shape at 100 m against both the sky and a warm deck.

## Monster meshes are decimated without welding, so every UV seam becomes an open crack  (impact 3, ~1.5 h)

**In the picture:** Monster edges flicker with sky-coloured single pixels under TAA: the harrier's wing membranes and the rippers' legs. The same defect causes the sparkle pixels on the hero at bottom-left. The effect per frame is small, but every monster edge looks noisy instead of solid, and it will show in any close-up (the hive at 30 m, a ripper kill).

**Cause:** blender/monsters/mon_lib.py:32 imports the Tripo GLB with default glTF options. merge_vertices is off, so every UV seam arrives as an open boundary. mon_lib.decimate (:59-70) then COLLAPSE-decimates the two sides of each seam independently, and they drift apart.

Measured on the shipped GLBs after welding coincident points:
- ripper: 12,876 open edges on 20k tris; 99% of seam vertices have an unwelded twin at a median 5.2 mm
- harrier: 16,861 open edges on 30k tris; median gap 5.7 mm
- hive: 44k open edges even after a 6 mm weld
- hero (same import in hero_lib.py:24): 58.7k open edges on 150k tris; median gap 1.7 mm

**Fix:** Pass merge_vertices=True to bpy.ops.import_scene.gltf at mon_lib.py:32, and do the same in hero_lib.py:24 and process_prop.py:162. Alternatively, run bmesh remove_doubles(dist=1e-5) before decimating. With welded vertices, Blender's collapse decimator keeps each seam as a UV boundary on shared vertices instead of tearing it open.

Rebuild with blender/monsters/build_all.py. Add a QA gate to the build: welded boundary edges under 2% of all edges.

Visual target: a lit close-up turntable of each monster with solid, unbroken silhouettes and no background showing through along seams.
