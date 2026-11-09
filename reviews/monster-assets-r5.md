# monster-assets r5 — lead brief: the monsters tear when they move, flash white, and float

## Why
The lead's acceptance pass (frozen at b5d26d4, `~/m/mc-accept`) rendered every monster:
- a neutral studio pass: 6 views plus close-ups, LOD0 and LOD1, the shipped material and a clay pass
  with magenta back faces;
- 6 frames of every one of the 62 clips;
- in-game frames at 40–60 m.

**The worst defect on screen is the skin.** Mantis, juggernaut, titan and titan_skyline tear in every
clip, idle included, and the ripper, spitter and harrier tear in some. Long flat sheets are stretched
between limbs: lime-green planes in the shipped shader, magenta in clay, and they are visible in game
at 40 m. Then the white flashes (trailer r2 found the "pale ghost" Mantis), and the floating mantis.

The findings and the verifier's corrections are in `~/m/mc-lead/accept/findings_all.json`:
- `monsters-fused-skin-tears`
- `monsters-floor-contact`
- `monster-tell-whitewashes-body`
- `hive-destroyed-open-stump`
- `hygiene-orphan-titan-textures`

The acceptance probes are in the frozen worktree; port the ones you need into
`game/enemies/models/tests/`:
- `~/m/mc-accept/game/tmp_accept/asset-qa/probe_fuse.gd` (bridge triangles per bone pair);
- `probe_anim.gd` (per-edge stretch against the bind length);
- `probe_floor.gd` (the lowest skinned vertex per frame);
- `probe_mesh.gd` (open edges and holes);
- `qa_studio.tscn` (studio and clay turnarounds).

Re-check every item on HEAD first; if something is already fixed, say so with the evidence.

## 1. (major) The skins tear in every clip
**This is a weights problem, not a mesh problem** (the verifier's correction). Tripo's own `rigged.glb`
plays the same clips with 0 torn triangles on the mantis and the titan; the weights the build writes
in `blender/monsters/` are what tear them.
- **Titan (then rebuild titan_skyline).** `mon_rig.add_tail` gives the tail chain every vertex behind
  a plane 2 m behind the pelvis, and drops that vertex's own weights. 63,862 of 106,714 LOD0 vertices
  carry > 0.3 tail weight, including 9,363 leg and foot vertices. Choose tail vertices by mesh
  connectivity from the tail root, or by distance to the fitted chain, and keep the body's weights.
- **Ripper, mantis, juggernaut, titan.** `mon_lib.transfer_weights` (POLYINTERP_NEAREST, from Tripo's
  remesh onto the decimated hi-res mesh, called from `mon_build.build_tripo`) hands whole patches
  another limb's weights wherever limbs are close at bind. For example, 328 mantis vertices sit at
  100 % R_Claw1 inside the R_Foot/R_Calf skin. Either skin Tripo's remesh (the build's `mesh="remesh"`
  path), or repair the transfer: re-weight by connectivity, or smooth the weights across limb islands.
- **`check_skin` cannot see a sheet that stays inside the bounding box.** That is how it reported
  "skin sanity 1.04–1.32" on these models. Replace it in `build_all` with a per-edge test: fail when
  any LOD0/LOD1 edge passes 2× its bind length in any clip.

**Gate:**
- `probe_anim`: worst per-edge stretch ≤ 2× in every clip of every type, LOD0 and LOD1;
- `probe_fuse`: the longest bridge edge ≤ 0.3 m in every clip;
- a clay turnaround and clip strips per type with no magenta or green sheets;
- in game: mantis and juggernaut at 40 m with no flat green planes. Show the sheets.

## 2. (major) The white flashes: the hit flash and the tell
- **The hit flash** (trailer r2: `captures/trailer/sheets/ghost_mantis_hitflash.jpg`,
  `ghost_archetype_ab.jpg`).
  - `monster_body.gdshader:78` adds `hit_flash × flash_energy` to EMISSION. `flash_energy` defaults
    to 4.0, i.e. 2.4 of pure white against the monster's own emission of 2.0.
  - No `<type>_rig.json` look block sets it, so all seven archetypes use the default.
  - Every missile impact re-arms it, so a missile salvo turns the Mantis into a flat beige ghost.
  - Fix: a per-type flash that brightens the form instead of erasing it: a lower energy, tinted, or
    rim-weighted. Decide whether rapid re-hits re-arm it or add to it.
- **The tell** (`monster-tell-whitewashes-body`).
  - `monster_body.gdshader:70`: the `0.8 +` term lands on every texel, so at tell = 1 the whole
    carapace emits. Median luma jumps 0.04–0.26 → 0.82–0.85, with 84–98 % of the pixels above 0.5.
  - Line 69's comment says the tell lights only the veins and the cores. Make the code do that: the
    emission mask, plus at most a thin rim.
- **Gate:** forced-flash and forced-tell frames against the neutral frame for every type. The
  carapace median luma stays within 1.5× of neutral while the veins and cores brighten; show the
  frames. Then re-run the trailer's `c_missiles` setup, or a missile salvo on 3 mantises, and show
  that no mantis reads as a ghost.

## 3. (minor) Floor contact
The mantis floats: its walk and run both play the `run` loop, which never touches the floor (lowest
+0.36 m, up to +1.44 m; above 0.3 m in 38/38 frames), and its idle hovers up to +0.95 m. Others sink:
- juggernaut idle down to −1.13 m;
- spitter scuttle −1.01 m;
- ripper scuttle −0.52 m;
- titan idle −2.15 m.

Plant the feet: re-key, or use per-clip vertical offsets from the lowest planted foot. The rig json's
`grounded` flag is read by nothing.

**Gate:** `probe_floor`:
- mantis run and idle: 0 frames hovering > 0.3 m;
- every grounded clip: the lowest point ≥ −0.15 m.

## 4. (minor) The destroyed hive stump is see-through
`HiveDestroyed` has an 81 m-perimeter hole at the top and back-faced inner walls. Players mostly see
hives from above. Cap it, with a dark interior.

**Gate:** `probe_mesh` largest hole < 1 m, and a top view with no see-through.

## 5. (minor) Orphan textures
Delete `game/enemies/models/titan/titan_skyline_{Color,EM,NormalGL,ORM}_*.jpg` and their `.import`
files. They are byte-identical leftovers.

**Gate:** `git grep 'models/titan/titan_skyline'` is empty, and `tools/godot.sh check --only=res://enemies/models/`
is clean.

## Gates (all)
- `tools/godot.sh check --only=res://enemies/` is clean; `test_models` and every enemies suite pass.
- The new stretch, floor and flash tests fail on the old build and pass on the new one. Say so, with
  both numbers.
- Sheets: a clay turnaround per type, clip strips for the worst clips (mantis idle, juggernaut idle,
  titan idle and stomp, ripper scuttle), forced flash and tell, and in-game frames at 40 m.
- `status/monster-assets.md` gets an r5 section with the numbers and the commands.

## Coordination
- **enemies r11 runs in parallel** (spawning safety, near-miss). EnemyBase and the AI are theirs: if a
  floor fix needs an EnemyBase offset, put it in Requests.
- **Re-exports.** Use `merge_vertices=True` and the base-centred pivot rule (the memory of the r3
  shredding: the decimator tears open UV seams). Run `python3 tools/citykit/rebase_glb.py --check`
  equivalents for your glbs if they apply.
- **Tripo web credits** are available, but only use them if the re-rig route needs a new source pose,
  and ask in Requests first.
