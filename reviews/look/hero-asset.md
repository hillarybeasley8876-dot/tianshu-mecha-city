# Look diagnosis items for hero-asset (lead-verified workflow wf_5e92d07a-bee, 2026-11-02)

Source: an independent critique of the user's screenshot `tmp/lead/user_shot_1.png` (A6 hive fight) against the key art.
Do them in this order (impact per hour). Each item: what is in the picture, the cause (file:line), the fix.

## Hero: untextured cyan boxes stuck on the visor and chest, crinkled white armour, flat cards for jets  (impact 6, ~2.5 h)

**In the picture:** Bottom-left: two flat, evenly filled cyan slabs with hard edges, at about (30-120, 690-765) and (105-160, 805-860). They sit on the armour like stickers and are the brightest thing on the mech. The white plates around them show a crinkled-foil highlight pattern and single-pixel sparkles along the edges. The twin cannon at (45-170, 590-660) reads as a dark brown tube.

In other captures:
- hero3_rest_front34.jpg: the same slabs are the cyan rectangle on the face and the bracket on the chest.
- hero_thrust_rear34.jpg: the jets are stacks of white rectangles, and grey joint balls show at the shoulders, hips and knees.

**Cause:** - Accent boxes: game/player/model/hero/hero_fx.gd:37-40 (ACCENTS) adds a 1.1x1.8x0.2 m BoxMesh on Spine02 and a 1.5x0.42x0.2 m one on Head (built at :126-136). Both use one flat StandardMaterial3D (:112-118: albedo 0.02, cyan emission). Its energy is 0.7 at idle, up to 5.2 under thrust and 8.6 in overdrive (:81). Untextured boxes over a Tripo face and chest that already carry baked cyan detail read as stickers.
- Jets: untextured additive QuadMesh cards (:186-197) with no soft falloff, so they render as rectangles.
- White plates: the Tripo ORM roughness is about 0.32 (median on white texels), so every lump of the Tripo surface reflects the bright backlit sky as a crinkle.
- Sparkles: the body was decimated without welding (blender/hero/hero_lib.py:24). It has 58.7k open seam edges on 150k tris with gaps of about 1.7 mm, which leak sky as sparkle pixels under TAA.
- Joint fillers: grey UV spheres (blender/hero/hero_parts.py:303-321).

**Fix:** 1. Delete the two ACCENTS boxes. Build a hero emission mask from the albedo's own cyan: 0.5-4% of each hero atlas is already close to #4FE6FF, and the hue-window code in process_prop.py:56-83 can extract it. Render the hero through a ShaderMaterial with `instance uniform vec3 glow_tint` and `glow_energy`, so overdrive recolours the baked strips from cyan to amber; this resolves the 'baked PBR cannot be recoloured' note at hero_fx.gd:36. Energy 1.0 at idle, 2.5 under thrust.
2. Jets: give the draw-pass material a radial GradientTexture2D alpha, stretch along velocity, and turn on proximity_fade. Use 0.3x1.4 m cards with an #EFFFFF core fading to #36E2FF.
3. Set a roughness floor of about 0.48 on the white plates, in the shader or by remapping ORM G.
4. Re-import with glTF merge_vertices=True before decimating (same bug as the monster seam issue).
5. Replace the joint spheres with short gunmetal cylinders or bellows aligned to each bend axis.

Visual target: hero3_rest_rear34 already holds up in grey light. At dusk the mech should read white and cobalt with thin cyan seam lights (ART.md §2), like the small mech in key art v2, never glowing slabs.
