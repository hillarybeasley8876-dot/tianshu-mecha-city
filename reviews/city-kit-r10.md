# city-kit r10 — lead brief: the props that decimation shredded (an ownership exception: props this round)

## Why
The lead's acceptance pass rendered all 30 Tripo props in a neutral studio and in game, in textured
and clay passes, with magenta back faces. Two read as garbage, and they sit where the player looks
first:
- **The 60 m harbour gantry crane** is the biggest thing in the opening H0/A1 frames. In game it fills
  the foreground as gold shards: spike legs, a crumpled cab and a smeared texture.
- **ac_cluster** is the most-placed roof machine (every district's roof pool) and reads as crumpled
  foil. food_stall has flipped or holed roof spots.

The root cause is verified: the prop table's budget, not the Tripo source. Re-running
`process_prop.py` at the 8k rooftop budget reproduces the shipped crane exactly (9,867 tris), and the
same pipeline is clean at 20k and 40k.

Findings, with the verifier's corrections, are in `~/m/mc-lead/accept/findings_all.json`:
`props-crane-shredded` and `props-ac-cluster-food-stall-decimation`. The acceptance studio and probes
are at `~/m/mc-accept/game/tmp_accept/asset-qa/` (`qa_studio.tscn --qa-mode=props --qa-props=…`,
`probe_mesh.gd`). Port what you need into your own tests folder.

**Ownership exception for this round:** `blender/props/**` and `game/world/props/meshes/**` (city-art's
paths) are yours. city-art r16 runs in parallel and will not touch props meshes; tell them in your
status what you changed. You are the unit that knows Tripo processing: `merge_vertices`, the
base-centred pivot, LOD tiers.

## 1. (major) The crane
- In `blender/props/prop_table.py:43-44`, give `crane` the statue/landmark tier:
  `Prop(40000, 60.0, 1024, "statue")`. Delete the dead `cranes` row (there is no `art/tripo/prop_cranes`).
- **Before reprocessing, fix `normalise()`.** It reads `obj.bound_box` straight after
  `apply_transforms` with no depsgraph update, so a fresh run exports the mesh centred: base at
  y = −24.9 m, i.e. sunk about 25 m. Call `bpy.context.view_layer.update()` first, or measure
  `obj.data.vertices` instead.
- Reprocess: `tools/blender.sh run blender/props/process_prop.py -- --name crane`, then reimport.
- **Gate:**
  - `python3 tools/citykit/rebase_glb.py --check --set props` passes;
  - studio tex and clay views of the crane from 4 sides plus top: straight legs, a boom and lattice,
    no spikes, no magenta;
  - the in-game H0/A1 frame reads the cranes as cranes.

## 2. (minor) ac_cluster and food_stall
- **ac_cluster.** It was decimated 33× (264,283 → 7,999 tris): kinked ducts, a twisted stack, magenta
  slivers on the fan grilles, and the largest open boundary of all 30 props (1.09 m). Give it ≥ 15k,
  or a clean box/duct rebuild. It is instanced a lot, so measure the instance count × tris against the
  budget.
- **food_stall.** Fix the three flipped or holed roof spots. That is the side a 16 m mech sees.
- **Gate:** clay top and q34 views of both with no magenta; ac_cluster's ducts read straight;
  `probe_mesh` open boundary < 0.2 m.

## 3. Audit all 30 props
Use the same studio, clay pass and `probe_mesh`, and write one table:

| column | what |
|---|---|
| budget | tris / budget |
| size | longest side against the table's size |
| open edges | count, and the largest hole |
| flipped | flipped faces |
| visual verdict | from the clay q34 |

Fix every prop that reads shredded the same way (the budget tier or a rebuild). List the rest as fine,
with their numbers. Re-bake the settle cache if any prop's footprint changes:
`SETTLE_BAKE=1 tools/godot.sh run res://tools/float_audit.tscn 600`. Then commit the new
`world/art/settle_cache.json`; city-art r16 is changing the fingerprint at the same time, so
coordinate through status files, and whoever lands second re-bakes.

## Gates (all)
- `tools/godot.sh check --only=res://world/props/` is clean, `test_art` passes, and
  `rebase_glb.py --check --set props` passes.
- The float audit: no prop newly floating or buried (`game/tools/float_audit.tscn`, windowed).
- The props sheet before and after, and the in-game H0/A1 frame before and after, are in your status.
- Frame budget: the total prop triangles at the A1 spawn before and after; ≤ +0.5 ms.
- `status/city-kit.md` gets an r10 section.

## Coordination
- city-art r16 (world/art, post, the settle fingerprint) runs in parallel. Props meshes are yours this
  round; materials and shaders stay theirs.
- Commit with an explicit path list, and check `git status game/world/props` before you report done
  (r6 once left 1.6k files uncommitted).
