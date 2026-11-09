# Brief: hero-v3 — a new hero mech (black-gold "Tianshu" star general), a true mechanical rig, mech animation

## Why
The user watched the current hero and said: "走路骨骼太鬼畜了 … 换个帅一点的机器人模型 别高达了". The lead's 60 fps
frame-by-frame review of the current build (`tmp/lead/anim/hero_look.avi`, sheets `tmp/lead/anim/c_*.jpg`,
`s60_*.jpg`) found four root causes — design these out, do not patch around them:
1. **The saber is not in the hand.** The model has no real swing animation, so `saber_visual.place_swing` teleports a
   14 m blade along a computed arc every tick: it spins at the feet, flashes overhead, never follows the arm.
2. **Wrong skinning method.** One fused Tripo body cut per face to the nearest bone gives jagged, non-armour seams
   that tear and intersect in motion, plus gunmetal joint balls to hide them ("bubbles").
3. **Human mocap on a 16 m mech.** Flailing arms, bouncing shoulders, two locomotion cycles beating against each
   other, a crouched duck-walk when strafing.
4. **Thruster particles are white box quads** that TAA smears into mosaic ghosts.

## The new design (approved by the lead; the user may still switch — keep the pipeline design-agnostic)
`art/concept/hero/v3/a1-1.png` — matte graphite-black armour with brushed-gold trim and thin cyan seams, an ancient
Chinese general's helm reimagined with one amber visor slit, layered lamellar pauldrons, a chest core behind a
slatted grille, armoured tassets, legs with exposed pistons, and **seven blade drones on a back frame like the Big
Dipper (北斗七星 — 天枢 is its first star)**. Tripo results (lead-generated, read-only, git-ignored):
- `art/tripo/hero3_a1/model.glb` — single textured mesh, 1.93 M tris, 8K albedo + 4K ORM/normal. **The look.**
- `art/tripo/hero3_a1p/model.glb` — the same image with `generate_parts`: **22 separate part meshes**, untextured
  (parts 16–21 are degenerate specks: drop them). **The segmentation.**
- Previews: `captures/blender/hero3_a1_studio_*.jpg`; alternatives d1 (crimson dragon) and b1 (industrial) in
  `art/tripo/hero3_d1|b1` — not used unless the lead says so.

## You own
`blender/hero3/**` (new), `game/player/model/hero3/**` (new), `captures/hero3_*`. Read-only for you: the current
hero (`game/player/model/hero/**`, `blender/hero/**` — reuse code by copying what you need into your own files; do not
edit them, the game keeps running on them until the switch).

## Build
1. **Segment into rigid armour pieces** (`blender/hero3/segment.py`, deterministic):
   - Normalise the textured mesh: 16.0 m to the helm top, feet at z = 0, facing −Y (Godot −Z after export).
   - Transfer the 22-part segmentation onto the textured mesh (nearest part per face from `hero3_a1p` after
     aligning the two — same image, same pose; ICP if needed), then split it along **planar cuts** at the joints
     where the parts do not already separate: shoulder, elbow, wrist, hip, knee, ankle, waist, neck — cut with a
     plane perpendicular to the bone, **cap every opening** (fill + inset, dark metal) so no hollow shells show.
   - Each piece gets exactly ONE bone. Pieces may overlap slightly at joints (as real armour does) but must not
     interpenetrate at the rest pose or at the stress poses below.
   - At each joint add a modelled mechanism (cylinder hinge with end caps for elbow/knee, ball-and-socket housing
     for shoulder/hip, piston pairs at the knee and ankle that are driven by bone constraints so they stay
     attached) in dark gunmetal with a gold ring — **no free-floating spheres**.
   - Decimate pieces to a 160k-tri budget total (LOD0) and 60k (LOD1); bake the 8K albedo to 4K, keep PBR.
2. **Skeleton**: build a clean mech skeleton (no fingers beyond 3 segments per finger group, no twist bones):
   root, pelvis, waist, chest, neck, head, clavicle/upperarm/forearm/hand ×2, thigh/calf/foot/toe ×2, 7 drone bones
   on a back-frame bone, weapon bones. Name bones so the existing contract maps (keep `Pelvis`, `Spine01`, `Spine02`,
   `Head`, `L_/R_Clavicle|Upperarm|Forearm|Hand|Thigh|Calf|Foot` where they exist, so camera/weapons/melee code that
   asks for those names keeps working).
3. **Animation — authored for a 16 m machine, not mocap.** Key it in Blender (`blender/hero3/anims/*.py`, one file
   per clip family, each clip readable as data) or procedurally in Godot where better:
   - **Locomotion is procedural** (`game/player/model/hero3/hero3_gait.gd`): two-bone IK legs on a step planner —
     feet plant and stay locked in world space, each step lifts ≤ 1.2 m and lands with a heel-to-toe roll, the pelvis
     dips 0.3–0.5 m on each plant (weight), the torso counter-rotates ≤ 6°. Step length and cadence come from the
     real ground speed (walk 9 m/s, run 16 m/s = thruster-assisted bounds with ≤ 30 % ground contact, backpack
     jets pulse on each push-off). Strafing and walking backward are real side/back steps, not a crouched clip.
     Turning in place = foot repositioning steps, not sliding.
   - **Upper body is held** in a combat-ready pose while moving: rifle up when aiming, saber held when drawn, arms
     do not swing like a person's. Gentle mechanical settle on stops (overshoot ≤ 2°, 0.25 s).
   - **Authored action clips** (SPEC §10 ids used by the game — read `data/hero_anim_map.json` and
     `game/player/model/hero/hero_clips.gd` for the full id list; every id must answer `play_action`):
     melee_l1/l2/l3, lunge, charge_slash, air_l1/l2, return_cut, ram_kick, execution, guard_up, parry,
     catch_hold/release, fire_r, charge_r, reload, missile_launch, anchor_fire, fins_send, burst, well_throw,
     plunge_dive/land, overdrive_ignite, lance_fire, rift_out/in, ward, dash_f/b/l/r, slide, hover, fly, jump,
     fall, land_light/heavy, hit_light/heavy, hit_knockdown, stagger, death. Melee clips must match the
     frame data in `game/combat/melee/melee_table.gd` (startup / active / recovery at 60 fps) — the blade's
     sweep happens on the active frames — with anticipation, a fast committed swing, and a held follow-through.
   - The **saber is a bone-attached blade** (`saber_r` socket on R_Hand): it never leaves the hand.
4. **Godot scene** `game/player/model/hero3/hero3_model.tscn` + scripts implementing the full **HeroModel API**
   (CONTRACTS §5): set_locomotion, play_action (returns clip length), set_aim, socket (all names incl. `saber_r`,
   `wing_l`, `wing_r` — the 7 drones are split 4/3 between the wing sockets so `corona_fins.gd` still works),
   set_thrusters, set_wings (drones fan out from the back frame like the concept), set_overdrive (cyan → amber),
   set_saber_drawn, hit_pause (creep default 0.05), model_state. Same origin/facing/7.5 m offset as today.
   Thrusters: cone flame meshes with an animated additive shader + heat shimmer, no box particles.
   Files ≤ 400 lines each (split gait / actions / rig / fx / sockets).
5. **Switch**: when every gate below passes, tell the lead; the lead flips `PlayerMech.HERO_MODEL` (one line).

## Gates (tests + captures, all required)
- `tools/godot.sh test res://player/model/hero3/tests/test_hero3.gd`: every SPEC id answers `play_action`;
  planted-foot slide ≤ 3 % of the stride at 9 and 16 m/s; feet never below the ground; knee ≤ 170°; **saber tip
  stays within 0.5 m of its socket-defined line in every frame of every melee clip**; no piece intersects another
  at rest or in the 4 stress poses (sample the mesh, report the worst penetration, gate ≤ 5 cm).
- 60 fps filmstrips (8 frames per cycle, front + side) of walk, run, strafe, back-walk, turn-in-place, melee_l1→l3,
  guard, fire, dash, jump/land: `captures/hero3_strip_<clip>.jpg`; plus lit turntable `captures/hero3_turn.jpg`
  and the 4 stress poses `captures/hero3_pose_*.jpg`. The lead judges motion from these — no evidence, no pass.
- A drive capture with the new model in the sandbox (same timeline as `tmp/lead/anim/hero_look.json`).
