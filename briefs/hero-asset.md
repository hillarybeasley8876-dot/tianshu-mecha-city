# Brief: hero-asset — the TIANSHU hero mech, rigged rigid-mechanical, animated, in Godot

## Goal
Turn the lead's Tripo assets into the playable hero model: the original white/cobalt mech (art/concept/hero/
v2/g1-1.png is the design), 150k-tri body with 4K PBR, rigid mechanical skinning (armour pieces never bend),
two wing binders made of the six blade drones, beam rifle, shield, saber hilt, all sockets, ~45 animation
clips from Tripo's rig, and a Godot scene implementing the HeroModel API (CONTRACTS §5) with an upper-body
aim layer. It must look like key art in every frame.

## Inputs (lead-owned, read-only; git-ignored binaries)
- `art/tripo/hero_body_front/model.glb` — high-res wingless body (1.9 M tris, 8K PBR, A-pose, faces +X).
- `art/tripo/hero_anims/hero_proxy.glb` — Tripo-rigged 20k proxy of the SAME body: 78-joint biped skeleton
  (BoneRoot, Hip, Pelvis, L/R Thigh/Calf/Foot/ToeBase + twist/share bones, Waist, Spine01/02, Neck, Head,
  L/R Clavicle/Upperarm/Forearm/Hand + fingers) with 45 clips. Text-motion clips are named after their
  prompt: use `data/hero_anim_map.json` (glTF animation index → SPEC §10 id, verified) to rename them;
  prompts in `data/hero_motions.json`. Exported facing −Y.
- `art/tripo/hero_blade/model.glb` (one blade drone, 7 m), `hero_rifle/model.glb`, `hero_shield_v2/model.glb`
  (kite shield, front view; the old `hero_shield` folded V is rejected — do not use it).
- Design references: `art/concept/hero/v2/g1-1.png` (with wings), `art/concept/hero/parts/*.png`.

## You own
`blender/hero/**`, `game/player/model/hero/**`.

## Build
1. `blender/hero/build_hero.py` (headless, deterministic): decimate the body to 150k (LOD0) and 70k
   (LOD1) with Collapse (UVs kept), textures to 4K (LOD1 2K); align the proxy to the body (both come from
   the same mesh: rotate −Y→+X facing, then refine with a few ICP iterations on vertices; report RMS < 2 cm
   at 16 m scale); scale everything so the hero is **16.0 m** to the crest top, feet at z = 0, facing −Z in
   Godot after export.
2. **Rigid skinning**: transfer vertex groups from the proxy (Data Transfer, nearest face interpolated),
   fold twist/share bones into their limb bones, then rigidify per FACE (dominant bone) and split vertices
   along bone boundaries so every armour piece moves rigidly (no stretched faces). Fingers: keep the
   finger bones (hands are visible) — rigid per finger segment. Verify by posing (elbow 90°, knee 90°,
   shoulder raise 80°, waist twist 45°) and rendering: no stretched or torn surfaces, only mechanical gaps.
3. **Wings**: decimate the blade to ≤ 12k tris; build each binder from 3 blade instances fanned 0°/18°/36°
   on new bones `Wing_L_Root → Wing_L_1..3` (and _R) parented to Spine02 at the backpack mounts seen in
   g1-1.png; folded rest pose = blades along the back; `set_wings(open)` rotates them to the g1 spread.
   The blades are also the Corona Fins (skills unit hides docked blades and flies copies).
4. **Weapons**: rifle (≤ 25k tris) attached to R_Hand with the grip in the palm, muzzle marker at the
   emitter; shield (≤ 20k) on the L_Forearm; saber hilt (simple 1.6 m cylinder + guard, white/cobalt) on
   the right hip when stowed, moved to R_Hand during melee (socket `saber_r`).
5. **Animations**: import every clip from the proxy (same skeleton); make locomotion loops in place
   (strip horizontal root/Hip translation; keep vertical); trim/loop idle, walk, run, slide, hover, fly;
   name them exactly as SPEC §10 ids; slow heavy-impact clips by ×0.9 if they look too light. Export
   `game/player/model/hero/hero.glb` (+ `hero_lod1.glb`) with the skeleton, meshes, sockets and clips.
6. **Godot scene** `game/player/model/hero/hero_model.tscn` + `hero_model.gd` (HeroModel API, CONTRACTS
   §5): AnimationTree — locomotion BlendSpace/state machine (idle/walk/run/slide/assault/hover/fly/fall/
   land) + OneShot action layer (all action ids, blend 0.08 s, returns clip length) + upper-body aim
   layer (SkeletonModifier3D chain: Waist/Spine02/Neck/R_Upperarm toward `set_aim(point)` with limits,
   weight blend); `hit_pause(s)` freezes the tree (speed 0) and vibrates the mesh visually; thrusters =
   GPUParticles3D + emissive at backpack nozzles, calf pods and shoulder pods driven by
   `set_thrusters(level)`; `set_overdrive(on)` shifts glow cyan → gold-red and enables an afterimage
   hook; sockets as Marker3D under BoneAttachment3D with the exact names in CONTRACTS §5; LOD1 via
   VisibilityRange at 120 m.

## Done when
- Blender: `tools/blender.sh run blender/hero/build_hero.py` reproduces everything from the inputs; prints
  tri counts, texture sizes, alignment RMS, bone count, clip list with durations.
- `tools/blender.sh preview game/player/model/hero/hero.glb hero --views front34,rear34,side,top` and pose
  renders `captures/hero_pose_*.jpg` (rest, 4 stress poses, wings open) — compare to g1-1.png.
- `tools/godot.sh check --only=res://player/model/hero/` → 0 errors; `tools/godot.sh test
  res://player/model/hero/tests/test_hero_model.gd` (every action id plays and returns a length, every
  socket exists, aim layer turns the chest toward a point ±90°, hit_pause freezes).
- Godot captures `captures/hero_*.jpg`: turntable (8 angles, sandbox light), a strip of 12 action frames
  (melee_l1..3, lunge, charge_slash, guard_up, fire_r, missile_launch, burst, plunge_land,
  overdrive_ignite, lance_fire), locomotion (walk/run/slide/fly), wings folded vs open. Also when the
  mech-move unit's player exists, run its tour timeline with your model and capture 6 frames.

## Lead addendum (from weapons integration)
Add `missile_l` / `missile_r` sockets at the shoulder-top thruster pods (missile rails) and verify the
weapons unit's integration scene (`game/combat/weapons/tests/integration.tscn`) launches from them.
