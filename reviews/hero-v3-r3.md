# hero-v3 — lead review r3 (gait commit 2604319)

## Verdict
The skeleton finally moves and the walk reads as a walk. I checked the fixed-camera movie frame by frame:
the planted heel holds the same pixel column from f53 to f77 while the body passes over it, so
**planted feet do not slide**. The cadence, stride and alternation are right. Your root-cause work on
`_write_global` was excellent.

It is **not accepted yet**. Six defects show in your own captures and in lead probes that sample the
SKINNED mesh. Your gait test cannot see them because it measures targets, not the mesh. Fix them in
the order below. Then do the action clips in the same round (block B).

**Your Requests:**
- **Request 1: your geometry is right, and my r2 pair (drop 1.2–2.0 m and knee 25–60°) was
  inconsistent.** But neither reading is the answer. The free variable you did not use is **duty**.
  At duty 0.65 the foot travels ±0.65 × 7.0 = ±4.55 m from the hip, and that is what forces the
  2 m bob. Item A1 gives the consistent target.
- **Request 2: accepted.** The run keeps 21 % flight and an 8.8 m stride. It still gets A2, A3 and
  the one-trough rule from A1.

All lead probes are in `tmp/lead/probe/` (`probe_skin.gd`, `probe_waist.gd`, `probe_pelvis.gd`,
`probe_air.gd`). They run with `tools/godot.sh test <abs path> --timeout=1400`. Promote what you
need into `hero3/tests/` as gates, the way you promoted the core sweep. Crops are in
`tmp/lead/h3vid/crop/`: `toeoff.jpg`, `track.jpg`, `waist_front2.jpg`.

## Block A — the gait (commit when done, then reshoot the strips and the fixed-camera movie)

**A1. The pelvis bob is 2.2 m and W-shaped. Make it ≤ 0.7 m with one trough per step.**
Measured with `probe_pelvis.gd` at walk: the pelvis goes 8.38 → 6.32 → 7.29 → 6.42 → 8.38 inside
every step. That is 8 local minima in 3.8 steps: a 1 m secondary bounce at about 2.6 Hz on top of a
2 m bob. This is exactly the "鬼畜" the user complained about. The cause is that `_apply_pelvis`
follows the furthest foot each frame. During double support that distance goes 4.55 → 3.5 → 4.55,
so the hips rise in the middle of double support and fall again.

Target on the measured leg (l1 4.14, l2 2.02, hip 8.60, ankle_h 2.77):
- `DUTY_WALK` 0.65 → **0.56**: 12 % double support, which passes the ≥ 10 % gate.
- `STRIDE_WALK` **6.6 m**: 1.36 steps/s at 9 m/s. The foot excursion becomes ±0.56 × 6.6 = ±3.7 m.
- Mid-stance crouch about 0.35 m below the rest hip, so the **knee is 50–60° at mid-stance**.
- The pelvis is lowest across double support and highest at mid-stance. Drive it from the phase with
  one smooth curve, and keep it flat at the reach-limited depth through the whole double-support
  window. It must not track the instantaneous furthest foot. Reaching ±3.7 m needs about 0.9 m of
  drop, so the dip is about 0.55–0.6 m.
- Gates: pelvis peak-to-peak ≤ 0.7 m at walk; exactly one local min and one local max per step
  (ignore wiggles < 2 cm); run ≤ 1.2 m with one trough per step; ankle miss stays ≤ 0.15 m.

**A2. Toes and heels sink into the floor: 0.81 m at push-off, about 0.3 m at heel strike.**
`probe_skin.gd` CPU-skins the leg vertices. The rest pose sits 0.10 m below ground, mid-stance
0.01–0.12 m, the push-off end of stance and lift-off 0.47–0.81 m, and heel strike 0.28–0.34 m.
In `toeoff.jpg` (f79–f91) the toe plates go visibly under the ground line. The cause: `Hero3Foot.roll`
pitches the foot about the ANKLE, so the toe swings down into the floor when the heel lifts.
- At heel strike, pivot about the heel edge: move the ankle target so the heel stays on the ground.
- At push-off, use the **Toe bone** (`L_Toe` / `R_Toe` exist and the gait never writes them). Keep the
  toe plate flat on the ground and pivot the foot about the toe hinge, so the heel and ankle rise. This
  also gives the trailing leg free reach.
- Gate: in every sampled frame of walk, run, strafe, back and turn, no skinned foot or toe vertex is
  more than 0.05 m below the rest-pose baseline.

**A3. The stance is narrow and the legs brush each other.**
The feet are planted directly under the hip heads, 2.46 m apart; the rest pose has them 5.8 m apart.
At rest the two leg meshes share no 0.3 m voxel. At walk they share 807 verts' worth, and at run 137.
Plant each foot about 0.8 m outboard of its hip head, so the feet are about 4 m apart centre-to-centre
at idle, walk and run.
Gate: zero shared 0.3 m voxels between the skinned left and right legs in every sampled frame. That is
the same measure `probe_skin.gd` uses, and the rest pose already passes it.

**A4. Strafing crosses the legs through each other.**
In a left strafe the right ankle ends up 5.0 m LEFT of the left ankle, and the leg meshes overlap
(14,635 shared-voxel verts). It is also visible in `hero3_strip_strafe.jpg` front, frames 3–4 and 7–8.
`_landing_spot` uses the full 7 m walk stride in any direction.

Do what TPS mechs do. The lower body yaws toward the travel direction: up to ±60° for forward
diagonals and pure lateral, up to ±45° for back diagonals (mirrored, so the mech backpedals). Smooth
it over about 0.25 s. The torso counter-rotates by the same amount so the chest and arms keep facing
the aim. The knee pole (`Hero3LegIk.POLE`) must follow the pelvis yaw, not model −Z. The game can strafe at
full speed too: `mech_locomotion.gd` `_target_speed` gives 9–16 m/s from stick magnitude in any
direction.

Gate: in the pelvis frame, each foot stays on its own side of the centreline, with minimum ankle
separation ≥ 1.8 m, at walk and run, for all 8 directions.

**A5. The waist splits open.**
`SPINE_COMP` translates Spine01 up by 45 % of the drop. At the deepest walk drop, the
Pelvis-weighted plates reach 8.61 m and the Spine01-weighted plates start at 9.08 m: a 0.46 m open gap.
At rest they overlap by 0.57 m. You can see the black band in `waist_front2.jpg` (cells 1 and 5).
With A1's smaller bob, remove the translation. Never move a child bone away from its parent; if any
compensation is still needed, use pitch.
Gate (`probe_waist.gd`): the Pelvis and Spine01 skinned spans overlap by ≥ 0.2 m in every frame.

**A6. In the air, the legs reach for the plants they left on the ground.**
In hover, fly, jump, fall and plunge_dive, `_plan` stops but the IK keeps aiming at the old world
plants. After 1 s of flight the target is 26 m away and the leg hangs straight back and down
(`probe_air.gd`). 飞行 is a core verb, so this is visible all the time.
- In the air: release the plants and blend within 0.2 s to an air pose: knees 35–50°, feet 1–2 m
  behind the hips, toes down, a little splay.
- On `land_light` / `land_heavy`: replant both feet under the hips and add a landing crouch. Match
  `mech_tuning.gd`'s landing windows: the soft dip is drawn over `land_pose_time` 0.18 s, and the hard
  landing recovers over `hard_recovery` 0.38 s. Dip the pelvis about 0.6 m soft and 1.2 m hard.
  This is impact, so give it weight.
- Gate: in the air, the ankle-to-hip distance is ≤ 5.8 m and the ankle is never more than 3 m behind
  the hip.

Then rerun every A gate and `test_hero3.gd`. Reshoot the walk, run, strafe, back and turn strips, plus
the fixed-camera walk movie. **Commit block A on its own** and update your status.

## Block B — the action clips (this is what gates the switch)

**B1. The id list.** Every id the game calls must answer `play_action`. Your test list is missing
**`gatling_spin`** (`combat/weapons/gatling.gd:157` calls it), so the list is the 45 brief ids plus
`gatling_spin`. Grep `play_action(&"` under `game/combat` and `game/player/mech` and make sure none
are missing.

**B2. Composition with the gait (design this first and write it down in status).**
- Upper-body clips layer over the walking legs: fire_r, charge_r, gatling_spin, reload,
  missile_launch, guard_up, parry, catch_*, melee_l1–l3, air_l1/l2, return_cut, charge_slash, and the
  skill casts. The gait keeps the legs, and posture skips only the bones the clip drives.
- Full-body clips take the legs and then hand them back through a replant: dash_f/b/l/r, slide, jump,
  land_*, hit_*, stagger, death, execution, lunge, ram_kick, plunge_*, rift_out/in.
- Keep the clips as readable data (one file per family), the way `hero_clips.gd` does. A blend in and
  out of ≤ 0.08 s for melee, and a hit-stop that freezes the clip (`hit_pause` already exists).

**B3. Melee timing against `melee_table.gd`.**
Read the table; do not edit `combat/melee`. For every melee clip, ≥ 80 % of the saber tip's sweep
angle must fall inside frames [startup+1, startup+active] at 60 fps. Anticipation goes in startup and
a held follow-through in recovery. The sweep must span the whole active window, not 5 ticks of it,
because the trail needs an arc. The current timings on the old rig, for reference, are in
`status/melee-defense.md` Requests 1.
Write a hero3 test that measures this per clip and prints a table like that one, plus the brief's gate
that the saber tip stays within 0.5 m of its socket line.

**B4. Filmstrips (60 fps, 8 frames, front + side):** melee_l1→l3 as one string, guard_up, parry,
fire_r, dash_f, and jump→land_heavy. Include a view where the legs are walking under an upper-body
clip.

Work order: B2 design → melee and defense → dash, jump and land → hits and death → weapons → skills.
Commit per family so I can review while you work.

## Not your job (lead will handle at the switch)
The first-person eye rides the `cockpit` socket raw. After A1 the head still bobs about 0.6 m, so I
will low-pass the eye height on the camera side when hero3 goes live.
