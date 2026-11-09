# hero-asset — numeric-robustness audit (lead, 2026-11-02) — 3 verified findings

A 36-agent audit read every non-test script twice (non-finite math; clocks + integrators) and a skeptic
tried to refute each finding; these survived. Fix them all (the proposed fixes were checked by the
skeptic — where it corrected one, the correction is what is written under *fix*). Add a regression check
for each high one in your suite, keep every suite green, run one scripted fight with `--nan-watch`, commit,
and report per finding: fixed (how) / not reproducible (evidence).

Clock contract reminder (CONTRACTS §3): Feel.real_delta/real_now for input, camera, UI/post and rate
limits; Feel.player_delta for player timers/anims; plain delta for world VFX; NEVER the wall clock
(movie capture renders a frame in ~70 ms of wall time). Feel now divides _process deltas by the
frame's own scale, so Feel.real_delta(delta) is correct in _process too.

## 1. [medium] game/player/mech/player_mech.gd:342 (clock)
**What**: PlayerMech.hit_pause only passes the local hit-stop to MechLocomotion, so live play never calls HeroModel.hit_pause (game/player/model/hero/hero_model.gd:165). The hero AnimationTree keeps advancing at full Feel.player_delta speed through every player-side local hit-stop, with no freeze and no vibration. That breaks CONTRACTS §4 (hit_pause freezes own animation + motion, visual vibration) and FEEL.md (attacker at 5 % speed). hero_gallery.gd:91 assumes this is 'the same path the game uses', but it is not.

**Trigger**: Any landed melee hit: melee_strike.gd:49 calls Feel.local_hit_stop([player, receiver], 4-10 frames). Also a perfect parry (defense_system.gd:264, 8 frames), the attacker creep in enemies/damage.gd:60, and missile_manager.gd:198. Each reaches PlayerMech.hit_pause, which only sets MechLocomotion._pause_t. The body stops and stops calling set_locomotion, but the swing OneShot plays on while the victim is frozen and vibrating. A grep shows that only the hero tests/gallery ever call HeroModel.hit_pause.

**Fix**: Forward in PlayerMech.hit_pause (player_mech.gd belongs to mech-move, not hero-asset): `if _model != null and is_instance_valid(_model) and _model.has_method(&"hit_pause"): _model.call(&"hit_pause", seconds)`. Every current player-side call site makes the player the attacker or parrier, never the victim. So HeroModel's paused branch should creep (tree.advance(0.05 * dt)), and arguably skip the victim's 0.09 m vibration. MeleeSystem._advance must also hold for the same span: the saber is placed from MeleeSystem's own timeline (MeleeStrike.sample/place_swing), so it would otherwise keep sweeping while the arm is frozen.

**Skeptic's check**: player_mech.gd:341-342 forwards hit_pause only to MechLocomotion, which sets _pause_t and skips post_move, so set_locomotion stops. No production code calls HeroModel.hit_pause; only the hero tests and gallery do. Contrast enemy_base.gd:153-158, which forwards to its model. Every landed melee hit reaches this through melee_strike.gd:49, Feel.local_hit_stop([player, receiver], ...), and so do parries (defense_system.gd:264), attacker creep (damage.gd:60) and missile salvos (missile_manager.gd:198). Meanwhile hero_model.gd:95-107 keeps advancing the tree at Feel.player_delta with no freeze, creep or vibration. That contradicts CONTRACTS §4 and FEEL.md, and the comment in hero_gallery.gd:91.

## 2. [medium] game/player/model/hero/hero_rig.gd:268 (other)
**What**: THRUSTERS `dir` is documented as model space but is used unconverted inside the BoneAttachment3D's bone frame, both for the nozzle `Basis.looking_at(dir, Vector3.UP)` and for `ParticleProcessMaterial.direction` (lines 253/289, applied through EMISSION_TRANSFORM). Only the positions go through `_to_bone_space`, so every plume and nozzle cone points 58 to 143 deg away from its intended direction.

**Trigger**: Any thruster state in normal play: flight 0.85, assault 1.0, dash 0.8, slide 0.55, hover, and the carrier drop-in at 1.0. Computed from hero.glb's joint rests (the Armature node is identity, so skeleton space = model space). Both backpack jets (Spine02) fire down-left at model (-0.68,-0.73,-0.01) instead of down-back (58 deg off, asymmetric). The calf jets point UP the legs, L_Calf at (0.61,0.71,-0.35) and R_Calf at (0.28,0.96,0.07), 142 deg off. shoulder_r points forward-down at (0.49,-0.15,-0.87), 143 deg off; shoulder_l is 72 deg off.

**Fix**: The proposed fix is correct: looking_at(dir_b, up_b) * Basis(Vector3.RIGHT, -PI*0.5) maps the cone's +Y onto dir_b, and dir_b/up_b stay 57-149 deg apart. Put the lookup in one helper that guards a missing bone the way _to_bone_space does, because get_bone_global_pose(-1) errors. For example `_bone_basis_inv(bone: String) -> Basis` returns Basis.IDENTITY when find_bone < 0, else get_bone_global_pose(idx).basis.inverse(). Use it for dir_b/up_b here and for the accents in [1].

**Skeptic's check**: Children of the BoneAttachment3D sit in the bone's global-pose frame, but `dir` is passed through raw to pm.direction (hero_rig.gd:254/290; EMISSION_TRANSFORM rotates it by the emitter's basis) and to the nozzle basis (:269). Only the position goes through _to_bone_space (:256), unlike the wing axis at :204, which is converted with rest_global.basis.inverse(). I rebuilt the joint frames from hero.glb (the Armature node has no TRS) and got the auditor's numbers exactly: backpack (-0.68,-0.73,-0.01) is 58 deg off, calf_l/calf_r are 142 deg off, shoulder_l is 72 deg off and shoulder_r 143 deg off. The same frame maps the HeroSockets 'chest' offset back onto CHEST (0,11.6,-1.05), which confirms it is the frame Godot uses. Normal play reaches this every time through MechContact.update_model->set_thrusters (mech_contact.gd:63-78), drop_in.gd:89 and the run's bound_jet pulse on the backpack jets.

## 3. [low] game/player/model/hero/hero_rig.gd:241 (other)
**What**: The ACCENTS glow boxes get a bone-space position from `_to_bone_space` but keep the bone's rotation, so their model-space `size` (width X, height Y, depth Z) is laid along bone axes and the plates are mis-oriented.

**Trigger**: Always visible: the glow is always emissive, at energy 0.7 or more. The Spine02 'core' plate (1.1 x 1.8 x 0.2) gets its 0.2 m thin axis along model -X and its 1.1 m width along model +Z. Seen from the front it is a 0.2 m vertical sliver; from the side it is a 1.1 m-deep slab sticking out of the chest. The Head 'visor' (1.5 x 0.42 x 0.2) has box X along model (-0.66,0.5,0.57), a slab tilted about 50 deg through the head.

**Fix**: The proposed fix is correct: mi.transform = Transform3D(_bone_basis_inv(bone), _to_bone_space(bone, at)), using the guarded helper shared with [0]. orthonormalized() is harmless because the bone scale is 1.

**Skeptic's check**: Same missing conversion at hero_rig.gd:236-242. The box keeps an identity basis inside the Spine02/Head attachment, so its size axes lie along the bone axes: Spine02 X is about model +Z and Z about model -X, and Head X = (-0.66,0.50,0.57). Measured against the HeroBody vertices, the 'core' slab spans z = -2.0 to -0.6 while the chest front along the centre line is at z = -1.47 to -1.68. That leaves a 0.2 m-wide glowing fin sticking 0.3-0.5 m out of the chest. The visor slab reaches z = -1.54, in front of a face at about z = -1.0. Both use the always-emissive _glow material (energy >= 0.7).
