# city-kit r7 — lead brief: commit r6, then make the arena cover read as its concepts

## 0. Commit r6's assets first
Your r6 commits hold the code, `kit.json` and `kit_assign.json`, but **not the assets they describe**.
`git status game/world/kit` shows 1 045 modified, 272 deleted and 298 untracked files:
- every regenerated glb;
- the albedo and ORM;
- the new `*_normal.png`;
- the pruned `NormalGL_<uuid>` files.

HEAD still carries the lead's 8f2bfd1 glbs. The game, city-build's settle re-bake (e2fdcf3) and every
capture since 01:00 ran on your working tree, so the repository does not rebuild what was reviewed.

Do this:
1. Run `tools/citykit/rebase_glb.py --check` and `tools/godot.sh test res://world/kit/tests/test_kit_textures.gd`.
2. Commit `game/world/kit/` as ONE commit with `git add -A -- game/world/kit`, so the deletions go too.
   Use no other paths, and say the file count in the message.
3. Check that `git status game/world/kit` is clean afterwards.

## The lead's r6 verdict
Accepted:
- the emission diagnosis and fix;
- the plane normals;
- the roof map and its test;
- the two base bugs;
- the A4st pin.

The foil you saw on the big near walls is not the specular:
- `reviews/city-art-r11.md` has the in-game elimination. The foil is painted into the confetti albedo
  atlas, and it goes away only when the albedo is replaced.
- city-art r11 is moving the building walls onto an object-space facade in `mc_kit_body`, so do not
  repaint walls into the atlas again.
- The specular request to city-art is withdrawn.

## 1. The arena cover reads as brown crumpled cardboard (impact 8)
Arenas are where the player fights, and the cover is what they fight beside. The shapes are right;
the surfaces are not.
- **The concepts** (`art/concept/citykit/k01..k12-*.png`) are distinct objects:
  - white storage tanks with blue logo bands (k02);
  - stacked logistics crates (k03);
  - a sandbag barrier with a red warning banner (k05);
  - a crashed truck and container (k06);
  - a grey transformer on a yellow and black hazard plinth (k07);
  - wooden cable drums (k08);
  - a fallen billboard (k09);
  - a hoarding fence of city banners (k10);
  - a rubble pile (k11);
  - concrete pipes and a silo (k12).
- **In the game** every one of them is the same brown with crumpled light and dark wedges. Look at
  `captures/kit6_st_A5deck.jpg` and `A6garden.jpg`, and the lead's `captures/lead_r11_kit_layers_A5deck.jpg`
  (with a plain albedo the wedges mostly go).
- **Two causes:**
  - the Tripo atlas is confetti with baked shading, the same as on the walls;
  - the grade pulls every model into one narrow bronze value range, so the concept's palette is lost.

**Prototype on two models first: k02 (tanks) and k07 (transformer).** For each:
1. A clean UV layout in Blender. Use a projection per part, or Smart UV Project with large islands,
   and 8 px or more of padding at the target resolution.
2. Bake the Tripo albedo onto the new UVs LOW-PASSED, enough that the island confetti and its baked
   shading are gone and the part colours stay (white tank body, logo band, steel frame).
3. Add a procedural layer in Blender at metre scale, baked into the same maps:
   - panel seams;
   - edge wear on convex edges;
   - grime toward the base;
   - the hazard stripes and logo bands where the concept has them.
4. **Palette from the concept, not the city grade.**
   - Painted white steel at linear albedo 0.45–0.55. The pale sheets in r6 came from the emission,
     not from albedo, so this value is allowed.
   - Hazard yellow, the concept's logo colours.
   - Concrete at 0.25–0.35.
   - The cover band keeps emission off, as in r6.

**Show the prototype in the game, before and after:**
- the A5deck camera;
- one close camera on each prototype model at 15 m and at 40 m;
- the concept image beside each.

Roll the method out to all twelve k-models only when the A/B clearly wins. If it does not, say why and
stop there.

**Gates for the roll-out:**
- **Wedges.** The lead's probe, `world/art/tests/probe_kit_layers.gd` (city-art is adopting it this
  round; `game/tmp_lead/kitlayer_ab.gd` until then). Run it on A5deck. The shipped crop's low-pass
  luminance std (σ = 12 px) must be at most 1.5× its plain-albedo twin.
- **Concept fidelity.** One sheet, twelve rows: the concept, then the in-game crop.
- **Geometry.** The colliders are city-build's boxes from the layout, so each model must still fill
  its box to within 0.3 m. `rebase_glb.py --check` PASS.
- **Cost.** Kit draws at the A1 spawn stay at 98 or under; report the VRAM delta.
- **The settle bake.** A new glb changes `kit.json`, so re-bake (`SETTLE_BAKE=1 tools/godot.sh run
  res://tools/float_audit.tscn 600`). Then run `test_settle_cache.gd`, and `float_audit` STRUCTURE must
  stay at 0.

## 2. Coordination
- **city-art r11 is editing `mc_kit_body.gdshaderinc` right now**, so keep out of it. Its new
  `facade_mix` will be 0 for the cover band, so your baked maps are what the cover shows.
- city-build is idle. If a collider has to change, write the request instead of editing its files.

Commit per step with an explicit path list. Report in `status/city-kit.md` (an r7 section).
