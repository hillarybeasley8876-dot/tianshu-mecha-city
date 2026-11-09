# melee-defense — round 4 (lead) — the saber must stay in the hand

## Why
The lead's 60 fps review of the current build (`tmp/lead/anim/c_melee.jpg`, `s60_melee.jpg`): in a three-hit
string the 14 m blade spins around the mech's feet, flashes vertically overhead and lies horizontal at knee height
on consecutive frames, detached from the arm. Cause: `saber_visual.place_swing()` puts the blade on the arc every
active tick (`_blade.global_transform = Transform3D(Basis.looking_at(d, up), root)`), because the old model had no
swing clips. The user called the whole hero "鬼畜"; this is the worst part.

## Build
1. **Blade = hand.** The blade is ALWAYS the `saber_r` socket's transform (plus the extend/ignite scale). Delete the
   arc-placement path (`place_swing`, `_swing_hold`, the stow-hold logic tied to it). The hit volume may still use
   your arc maths for gameplay (that is fair and readable), but what is drawn is the hand-held blade, and the trail
   ribbon samples the REAL blade root→tip from the socket each physics tick.
2. **Hit timing from the animation**: the active window stays in `melee_table.gd` frame data; hero-v3
   (`briefs/hero-v3.md`) authors every melee clip to that data so the drawn blade sweeps through the arc on the
   active frames. Until hero-v3 lands, the current model's Tripo melee clips play (they exist: melee_l1/l2/l3,
   lunge, charge_slash, air_l1/l2, return_cut) — check each one: where the clip's blade sweep and the active
   window disagree by > 3 frames, list it in your status for hero-v3 (do not retime gameplay to bad clips).
3. **Hold for the hit-stop**: `MeleeSystem._advance` must hold for the same span as `HeroModel.hit_pause` (hero-asset
   r3 request 1 — mech-move adds the forward call; coordinate) so the arm and the blade freeze together.
4. Keep everything else (crescent wave, lunge homing, executions, parry/guard) as it is.

## Gates
- A test that samples the drawn blade tip each physics tick through melee_l1→l3, lunge, charge_slash, air_l1/l2 and
  asserts it is within 0.5 m of the `saber_r` socket line (no arc placement anywhere).
- 60 fps filmstrips `captures/melee_r4_strip_<move>.jpg` (front + side) of the string, lunge and charge slash.
- All existing melee tests green.
