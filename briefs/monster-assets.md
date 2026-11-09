# Brief: monster-assets — the HUSK monsters as rigged, animated Godot models

## Goal
Turn the lead's Tripo monsters into game-ready models that the enemies unit swaps in for its placeholders:
correct size, readable silhouettes, glowing acid-green veins and violet weak points, smooth skinned
animation with weight and menace, sockets and weak-point positions, LODs, hit flash — and the hive spire
objective with damage states.

## Inputs (lead-owned, read-only; git-ignored binaries) — see `art/tripo/jobs.json`
| Type | High-res (2 M tris, 8K) | Rigged export (Tripo 20k remesh + skeleton + clips) | Rig | Clips from Tripo |
|---|---|---|---|---|
| ripper (6 m long) | `art/tripo/mon_ripper/model.glb` | `art/tripo/mon_ripper/rigged.glb` | quadruped | walk only → script the rest |
| mantis (14 m tall) | `mon_mantis/model.glb` | `mon_mantis/rigged.glb` | biped | presets + text motions (`data/monster_motions/mantis.json`) |
| spitter (12 m tall) | `mon_spitter/model.glb` | — (Tripo refused to rig it) | build your own | script all |
| harrier (16 m span) | `mon_harrier/model.glb` | — (Tripo export has no skeleton) | build your own (2 wings × 3 bones, spine 3, neck/head 2, tail 3, legs 2×2) | script all |
| juggernaut (22 m) | `mon_juggernaut/model.glb` | `mon_juggernaut/rigged.glb` | biped | presets + text motions |
| titan (60 m boss) | `mon_titan/model.glb` | `mon_titan/rigged.glb` | biped | presets + text motions |
| hive (60 m, static) | `mon_hive/model.glb` | — | none | — |
Concepts: `art/concept/monsters/<type>-1.png`. Clip names in rigged exports: presets by name, text motions by
prompt text — map them with `data/monster_motions/<type>.json` + the export's animation order (same order
as the job's `anims` keys in `art/tripo/jobs.json`).

## You own
`blender/monsters/**`, `game/enemies/models/**`.

## Build
1. **Meshes**: rippers, mantis, harrier, juggernaut use the Tripo 20k remeshed mesh (its texture is baked)
   — check it against the high-res render; if it is visibly too coarse, decimate the high-res to ≤ 45k and
   transfer the skin weights (Data Transfer, nearest face interpolated, smooth). Titan: high-res decimated
   to 150k (LOD0) / 60k (LOD1) with transferred weights. Harrier: decimate to 30k and build its wing rig like the spitter's. Spitter: decimate to 40k, build a quadruped
   armature (4 legs × 3 bones, spine 3, neck/launcher 2, sac 1) and weight it (Blender automatic weights on
   the decimated mesh; fix by hand-scripted vertex-group cleanup if heat fails). Hive: 60k + 2 damage states
   (cracked: shrink pods + darken glow; destroyed: collapsed stump) + a convex collision proxy.
2. **Animation**: keep Tripo clips (rename to ids below); script the missing ones in Blender with keyframed
   bone rotations on the Tripo skeletons (gait phase offsets, body bob/roll, anticipation and follow-through,
   ease curves — no linear mechanical motion). Required ids: ripper `idle walk run leap bite hit death`;
   mantis `idle walk run slash_1 slash_2 slash_3 grab sidestep_l sidestep_r threat hit stagger death`;
   spitter `idle walk fire hit death` (fire = crouch, sac contracts, launcher recoils); harrier `fly glide
   dive strafe hit death`; juggernaut `idle walk charge ground_slam swipe roar hit stagger death`; titan
   `idle walk roar stomp swipe beam_breath summon hit stagger death`. Locomotion loops in place.
3. **Godot scenes** `game/enemies/models/<type>/<type>_model.tscn` + script implementing the monster model
   API (CONTRACTS §6: `set_locomotion(state, speed)`, `play_action(id) -> float`, `socket(name)`,
   `hit_pause(s)`, `set_hit_flash(v)`), real-world size, facing −Z, origin at the feet (harrier: body
   centre). Materials: keep Tripo PBR, add an emissive mask derived from the albedo (acid green / violet
   pixels → emission, energy ~3) so veins and weak points glow; hit flash via instance shader parameter
   (white additive, 0→1). Sockets: `mouth`/`muzzle`, `claw_l`, `claw_r`, `core` (centre of mass), plus
   `weak_*` markers at every violet core (the enemies unit puts weak-point Hurtboxes + Targetables there).
   LOD via VisibilityRange (titan) or import LODs; shadows on for juggernaut/titan/hive only.
4. Coordinate with the enemies unit through status files (socket names, sizes, any API gaps).

## Done when
- `tools/blender.sh run blender/monsters/build_all.py` rebuilds every model deterministically and prints tri
  counts, bones, clips (id + duration) per type.
- `tools/godot.sh check --only=res://enemies/models/` → 0 errors; `tools/godot.sh test
  res://enemies/models/tests/test_models.gd` (each type: size within ±5 %, every required action plays,
  sockets exist, hit flash parameter changes, hit_pause freezes).
- Captures `captures/monsters_*.jpg`: line-up of all types next to the 16 m hero placeholder (scale!), each
  type's key attack pose strip (6 frames), the hive in 3 states, glow visible under sandbox light. Watch the
  scripted cycles in a movie: no foot sliding beyond ~10 %, no popping, menace in the motion.
