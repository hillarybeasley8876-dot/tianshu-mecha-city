# skills — numeric-robustness audit (lead, 2026-11-02) — 12 verified findings

A 36-agent audit read every non-test script twice (non-finite math; clocks + integrators) and a skeptic
tried to refute each finding; these survived. Fix them all (the proposed fixes were checked by the
skeptic — where it corrected one, the correction is what is written under *fix*). Add a regression check
for each high one in your suite, keep every suite green, run one scripted fight with `--nan-watch`, commit,
and report per finding: fixed (how) / not reproducible (evidence).

Clock contract reminder (CONTRACTS §3): Feel.real_delta/real_now for input, camera, UI/post and rate
limits; Feel.player_delta for player timers/anims; plain delta for world VFX; NEVER the wall clock
(movie capture renders a frame in ~70 ms of wall time). Feel now divides _process deltas by the
frame's own scale, so Feel.real_delta(delta) is correct in _process too.

## 1. [high] game/combat/skills/rift_step.gd:56 (other)
**What**: The behind and flank destinations (lines 56 and 61) are built from target.global_position, which is an enemy's feet (body_builder.gd:17 lifts enemy shapes by half their height), but they are used as the mech's body origin, which is its capsule centre (CONTRACTS section 5), so the blink puts the mech's capsule centre at floor level, 7.5 m into the ground.

**Trigger**: Any locked Rift Step with a neutral, forward or sideways stick at a grounded enemy (the default blink). resolve_free_space cannot recover: every probe at that height and at the +/-6 m lifts still overlaps the floor with a 7.5 m half-height capsule, so it returns the sunk point. _tick_transit lerps the body 7.5 m down through the floor with collision_mask = 0 over the 9 f transit, and _arrive restores collision inside the floor, leaving move_and_slide depenetration to pop the mech out. suite_mobility.gd:28-41 only asserts horizontal distances, so the tests don't catch it.

**Fix**: Lifting the base to target feet + capsule half-height is right, but it must ship together with finding [0]. arrival_facing uses target.global_position - destination(), so with a lifted base the behind/flank facing becomes pitched about 28 deg down (atan(7.5/14)) unless it is flattened or measured from the lifted base. Use the lifted base for the away vector too.

**Skeptic's check**: For behind and flank, destination() returns target.global_position (enemy feet, body_builder.gd:17) plus a horizontal offset (rift_step.gd:56, 61), and that point is used as the PlayerMech origin, which is the capsule centre (player_mech.gd:96-101; placeholder_model.tscn at -7.5). Every probe in resolve_free_space (lifts 0/+6/-6) still overlaps the WORLD floor with a capsule of half-height 7.5 m, so it returns the sunk point (skill_context.gd:134-144). _tick_transit then moves the body there with collision_mask 0, and _arrive turns collision back on inside the floor.

## 2. [high] game/combat/skills/rift_step.gd:218 (nonfinite)
**What**: _face_body writes Basis.looking_at(dir, UP) into the CharacterBody3D using the unflattened back-off arrival facing, so the mech (collision capsule and model) is left pitched toward the target, and nothing re-levels it because locomotion only ever calls body.rotate_y (mech_locomotion.gd:177); an exactly vertical facing also hits looking_at's parallel-vector error.

**Trigger**: Lock a target within 90 m and Rift Step with the stick pulled back. arrival_facing (lines 57-60, 67-69) returns -(origin - target.global_position).normalized(), which is 3D. Even on flat ground the player origin is the capsule centre 7.5 m up and the enemy origin is its feet, so the mech arrives pitched atan(7.5/d) nose-down (about 14 deg at 30 m, 37 deg at 10 m). From the air above the target the pitch approaches 90 deg. The tilt persists, tilting the capsule, and ctx.facing() gains a vertical component (yank stop point, knockbacks, ward escort sides) until a Zenith Lance _sweep or a melee execution (both flatten) re-levels the body.

**Fix**: Flatten in _face_body: var flat := Vector3(dir.x, 0.0, dir.z); if flat.length_squared() < 0.0001: return; body.global_basis = Basis.looking_at(flat.normalized(), Vector3.UP). Also flatten d in arrival_facing.

**Skeptic's check**: The back-off arrival facing is the 3D vector -away (rift_step.gd:57-60, 67-69). away contains the 7.5 m offset between the player's origin (capsule centre, player_mech.gd:96-101, CONTRACTS §5) and the enemy's origin (feet, body_builder.gd:17), and _face_body writes Basis.looking_at of it straight into the CharacterBody3D (rift_step.gd:218). The only per-tick rotation is rotate_y (mech_locomotion.gd:177), which keeps pitch, so the capsule and model stay tilted until a melee lunge or execution (melee_strike.gd:108-114, execution_director.gd:190) or a lance sweep flattens the body. The NaN part is not reachable: looking_at's parallel-vector error needs a horizontal offset below about 1e-5 of the vertical. The real defect is the lasting 14-37 deg pitch (near 90 deg from above the target).

## 3. [high] game/combat/skills/zenith_lance.gd:153 (clock)
**What**: _tick_beam calls Feel.shake(0.15) on every 120 Hz physics tick. Camera trauma is additive with a linear 1.2/s decay and a clamp at 1 (camera_shake.gd), so it climbs by about 16/s and stays pinned at 1.0, the maximum shake (3 deg pitch/yaw, 2 deg roll), for the whole 3 s beam plus about a 0.8 s tail. FEEL.md specifies '0.15 continuous'.

**Trigger**: Every Zenith Lance, which every Overdrive ends with, in normal play and in movie capture. The amount is per physics tick, not per second, so it saturates within about 8 ticks and it keeps adding during hit-stops too.

**Fix**: A 0.15 pulse every 0.25 s gives a sawtooth (it decays to 0 in 0.125 s), not 0.15 continuous. The exact fix is a trauma floor of 0.15 held while the beam is open (a small Feel/camera API, e.g. a timed shake floor). Keep the one-shot shakes at beam open and finish.

**Skeptic's check**: _tick_beam runs on every 120 Hz physics tick (skill_system.gd:210-212 -> zenith_overdrive.gd:73). Each call adds about 0.15 * 0.93 trauma (600 m falloff with the camera about 42 m away, camera_rig.gd:151), while decay is only 1.2 * 1/120 = 0.01 per tick (camera_shake.gd advance()). Trauma therefore clamps at 1.0, the maximum shake (trauma squared), for the whole 3 s beam and about a 0.8 s tail, against FEEL.md's '0.15 continuous'.

## 4. [medium] game/combat/skills/corona_ward.gd:153 (clock)
**What**: CoronaWard runs its own _physics_process on the plain scaled delta, so the 6 s barrier timer, the escort fins' 0.5 s fire rate and the ripple decay run on the world clock. Every other skill timer runs on Feel.player_delta, as the contract requires for player timers and fire rates.

**Trigger**: A perfect dodge while the Ward is up (witch time at 0.3x for 0.35 s real). The ward drains only about 0.17 s instead of 0.35 s, and the escorts fire at 0.3x rate. Any longer witch window scales the error; suite_clocks' 0.25x/0.9 s window would leave the ward losing about 0.25 s of 0.9 s.

**Fix**: Use pdt for _left and _escort_at. _ripple is VFX and can stay on the plain delta. Simplest: drop the node's own _physics_process and tick the Ward from CoronaFins.tick(pdt), which already runs after the player has moved.

**Skeptic's check**: CoronaWard has its own _physics_process on the engine's scaled delta for _left and _escort_at (corona_ward.gd:150-156, 189-193). The contract and every other skill tick on Feel.player_delta (skill_system.gd:205-212). A perfect dodge while the Ward is up is reachable, because take_hit checks dash i-frames before the damage filters. Its witch time, slow_mo(0.3, 0.35, 0.03, 0.15, true) (player_mech.gd:213), drains only about 0.17 s of the Ward, and the escorts fire at 0.3x for that window.

## 5. [medium] game/combat/skills/fx/fx_sheath.gd:91 (nonfinite)
**What**: The Plunge sheath's speed-streak ribbons are built in world space (`var a := global_position + offset`, `b = a - dir * length`) but go into an ImmediateMesh on the `Streaks` MeshInstance3D, which is a normal child that already inherits the piece's translation (only SkillVfx is top_level). Every quad is translated twice and lands at 2x the mech's world position: finite but badly misplaced geometry. This is the same bug combat/melee/saber_visual.gd documents and fixes.

**Trigger**: Any Plunge Breaker dive outside the world origin. velocity = _dive_dir * 190 m/s is at least 8, so _draw_ribbons runs every tick, and follow() first sets the piece's global_position to the mech position P. The six ribbons render at 2P + offset: a mech diving at (300, 150, 200) draws them at about (600, 300, 400), off screen, and they fall at twice the dive speed. The showcase clip dives from 150 m above an enemy, which puts the ribbons 150+ m above the frame, so the captures never revealed it. Net effect: the 'reads as speed in a single frame' streaks are missing near the mech and appear as stray streaks somewhere else.

**Fix**: The proposed fix is correct. Either set `_ribbons.top_level = true; _ribbons.global_transform = Transform3D.IDENTITY` in _ready(), or build the ribbons in local space (`var a := offset`). The local version is valid because the piece's basis is always identity and it already sits at the target.

**Skeptic's check**: The finding's 'nonfinite' label is wrong because every value stays finite, but the misplacement is real. SkillVfx is top_level at identity (skill_vfx.gd:23-24). follow() sets the sheath piece's global_position to the mech position P and never rotates it (fx_sheath.gd:64). `Streaks` is a plain, non-top_level child (fx_sheath.gd:35-42) whose material is a StandardMaterial3D from SkillFx.glow (skill_fx.gd:90), and that material does not use world vertex coordinates, so the vertices are in local space. The ribbons are built as `global_position + offset` (fx_sheath.gd:91), so they render at 2P + offset. PlungeBreaker._tick_dive calls follow(body.velocity) every tick with plunge_speed 190 (plunge_breaker.gd:159-161, skill_tuning.gd:109), which is over the 8 m/s gate. Plunge also needs at least 16 m of height, so P is never zero and the ribbons are always off the mech. saber_visual.gd:69-73 documents and fixes the same double-transform.

## 6. [medium] game/combat/skills/fx/skill_vfx.gd:65 (other)
**What**: When a pool is dry, take() recycles pool[cursor] even if it is a long-lived piece opened with OPEN_LIFE (Zenith Lance layers, Skyhook cable core/glow). The original holder keeps its reference and keeps driving it, so the cable or lance layer gets hijacked by fin trails, then vanishes or freezes, and the holder's later stop() kills whichever unrelated beam now owns that slot.

**Trigger**: Corona Ward up (4 tetra + 2 escort fins visible, re-placed around the chest every tick) while the hero moves faster than about 9 m/s, or a 4-6 fin send (1-2 marks) in flight. corona_fins._tick_trail drops a 0.24 s beam every 0.045 s per fin, about 32 concurrent with 6 fins, against the 20-slot beam pool. Every take() then steals, and the round-robin cursor sweeps all slots in about 0.15 s. Grapple during this and CableVisual.is_shown() follows the stolen piece: the cable draws in fin colour and fades for 0.24 s, then the core expires, draw() returns early, and the glow tube and latch freeze in mid-air until detach. Firing the lance while fins fly flickers its 800 m layers the same way, and _finish()/hide_cable() then stop other skills' beams.

**Fix**: The proposed fix is right but its pool-size estimate is too small. In take(), when no piece is free, steal the busy piece with the smallest life_left(), or never steal open-ended pieces at all. Long-lived holders (CableVisual, ZenithLance._layers) should also check that they still own their piece, for example through a generation counter returned by take(), so they never re-line or stop a recycled piece. If you resize the pool instead, budget for 6 fins x 5-6 trails, plus about 6 reel streaks, plus 2 volley beams per fin, plus the 5 open owners. Giving fin trails their own pool kind is cleaner.

**Skeptic's check**: When the pool is dry, take() returns pool[cursor] with no check on life or owner (skill_vfx.gd:65-68). The cable holds its core and glow, opened with OPEN_LIFE 3600 s (cable_visual.gd:47-52, fx_beam.gd:9/46-52). It only checks `not _core.free_to_use()` (cable_visual.gd:67-68) and re-lines the piece every tick (skyhook_anchor.gd:412-417). The lance does the same with its 3 open layers (zenith_lance.gd:131-139/178-183) and stops them in _finish (zenith_lance.gd:251). Ward fins are WARD-state, visible and re-placed on the chest every tick (corona_ward.gd:163-178, corona_fins.gd:340-347). _tick_trail spawns a 0.24 s beam every 6 ticks (0.05 s) whenever a fin moved more than 0.4 m, i.e. above 8 m/s (corona_fins.gd:185-194, corona_fin_fx.gd:55-58). That is about 30 concurrent trails, plus the reel streaks (skyhook_anchor.gd:251-268), against 20 slots. Nothing stops the anchor or lance from running alongside the ward or fins (skill_system.gd:279-300). A simulation of take() and the piece life code shows the cable core and glow stolen within 0.10-0.15 s with the ward up and the hero moving, and the lance layers stolen within 0.1-0.2 s with 4-6 fins in flight. With 2 fins nothing is stolen.

## 7. [medium] game/combat/skills/skill_context.gd:57 (other)
**What**: chest() adds CHEST_HEIGHT (11.5 m, the chest measured from the feet) to origin(), which is the capsule centre 7.5 m above the feet, so every skill's 'chest' point is 19 m above the feet, 3 m above the 16 m crest.

**Trigger**: Always, whenever ctx.chest() is used directly instead of a model socket. The Skyhook aims its cable from it (aim_dir_from(ctx.chest()), skyhook_anchor.gd:77) but launches the tip from muzzle_l, so the cable runs parallel to the crosshair line and latches several metres below or beside the aimed point. Reel range, ARRIVE distance and swing angle are measured from above the head. The Corona Ward shell and BARRIER volume centre there (bottom at feet+5 m, legs outside), and its 'fired from inside' test measures from there. The same origin mix-up makes the Plunge 16 m gate (plunge_breaker.gd:72) only 8.5 m below the feet, makes its origin.y - ground <= 2 landing test (line 164) unreachable, and puts the yank stop (skyhook_anchor.gd:305) at capsule-centre height.

**Fix**: Add feet() = origin() - UP * capsule_height * 0.5 and set chest() = feet() + UP * CHEST_HEIGHT (= origin + 4.0). Read capsule_height from tuning instead of allocating a CapsuleShape3D on every call. If chest() should prefer the model's chest socket, call socket_node(&"chest"), not socket(): socket() falls back to chest() and would recurse forever when the model is missing.

**Skeptic's check**: origin() is the capsule centre, 7.5 m above the feet (player_mech.gd:96-101; debug_camera.gd:6 puts the 11.5 m chest pivot 4.0 m above the body origin), so chest() = origin + 11.5 lands 19 m above the feet. It is used for the Skyhook aim, miss range, reel and arrive checks (skyhook_anchor.gd:77, 117, 196, 225) while the tip launches from muzzle_l, and for the Ward centre and its 'fired from inside' test (corona_ward.gd:136, 164). The plunge gate and the <= 2 m landing test compare the capsule centre to the ground (plunge_breaker.gd:72, 164; the 2 m test is unreachable with a 7.5 m half-height), and the yank stop is at capsule-centre height (skyhook_anchor.gd:305).

## 8. [medium] game/combat/skills/skill_input.gd:116 (other)
**What**: The Overdrive hold timer re-arms while the key is still held: it resets _od_held to 0.0 and keeps accumulating. A single continuous hold of about 1 s therefore ignites the Overdrive and then, as soon as the ignition ends, also fires the Zenith Lance, which cuts the 12 s Overdrive window down to one beam. input_setup.gd says 'press again = lance'.

**Trigger**: Hold V (or L3+R3) for 1.0 s or more with a full OD meter. At t=0.25 s try_overdrive() runs. At t=0.5 and 0.75 s the re-checks return because is_igniting() is true. The ignition ends at about 0.82 s real under its own slow-mo, so at t=1.0 s can_fire_lance() is true and begin_lance() runs.

**Fix**: Latch the gesture the way _rift_held and _fins_held work: after it fires, set _od_held = -1.0 and return while it is negative, and only reset it to 0.0 when 'overdrive' is released. A new press is then required for the lance.

**Skeptic's check**: _overdrive resets _od_held to 0 after each 0.25 s and keeps counting while the key is held (skill_input.gd:110-121). After try_overdrive at 0.25 s, the checks at 0.5 and 0.75 s are swallowed because the ignition is still running (about 0.57 s real under its slow-mo). At 1.0 s, can_fire_lance() is true (zenith_overdrive.gd:86-89) and begin_lance() fires. On the pad, PadInput keeps 'overdrive' pressed for as long as L3+R3 are held (pad_input.gd:88-97), so pad players hit it too.

## 9. [medium] game/combat/skills/skyhook_anchor.gd:234 (other)
**What**: The surface reel only ends when the chest point is within ARRIVE (8 m) of the anchor, which is unreachable for an anchor on the floor or on any surface lower than about chest height minus 8 m, because the body stops on the floor first and the SURFACE state never ends.

**Trigger**: Fly up and fire the anchor at the street or a low surface below (kerb, car, low ledge). Every tick sets body.velocity = dir * reel_speed() straight into the floor, posts speedlines and drops streaks, and the mech stays pinned until the player presses jump, boost, guard, fire or anchor, or looks more than 90 deg off the cable. The floor case stays stuck even with a correct chest height (11.5 m > 8 m).

**Fix**: End the reel when the body is blocked along the cable (e.g. body.is_on_floor() and dir.y < -0.7, or a slide collision whose normal opposes dir) or when dist stops decreasing for a few ticks, and measure arrival against the capsule's extent along dir rather than from a fixed chest point.

**Skeptic's check**: The surface reel only ends when |anchor - chest()| <= ARRIVE = 8 (skyhook_anchor.gd:234). For a floor anchor, chest() is at least 19 m above it (11.5 m even after fixing [2]) once the feet are on the floor, so the reel never arrives. Each tick still sets velocity = dir * reel_speed() and posts speed lines and streaks (lines 240-242). Nothing detaches on landing: the only external detach is the anchor toggle (skill_input.gd:65), plus the jump/boost/guard/fire presses and the 90 deg swing detach.

## 10. [medium] game/combat/skills/zenith_lance.gd:109 (clock)
**What**: The 0.8 s charge timer runs on the player clock (pdt), but begin() also requests its own non-witch Feel.slow_mo(0.3, lance_charge) at line 92, which is measured in real seconds. That slow-mo slows the player clock to 0.3x, so the charge takes about 1.3 s of real time and the world is back to 1.0x about 0.5 s before the beam fires. FEEL.md specifies 'enemies 0.3x during the 0.8 s charge'.

**Trigger**: Every lance, whether pressed or auto-fired with 1 s of Overdrive left. With the 0.05/0.1 s eases, the 0.8 s real-time slow-mo advances the player clock by only about 0.29 s, leaving about 0.51 s of charge at full world speed. The same pattern stretches the 0.45 s ignition in zenith_overdrive.gd:56/70 to about 0.57 s, under a 0.25 s slow-mo.

**Fix**: If the CHARGE phase moves to Feel.real_delta, also re-time what begin() issues on the player clock. lock_movement(lance_charge + lance_beam) (mech_locomotion.gd:123) and invulnerable_for (player_mech.gd:172) would otherwise outlast the beam by about 0.5 s; issue the beam's lock at beam open instead. The world-clock brackets need the matching length (about 0.29 s), or should be driven from the charge's u. The witch=true alternative is not free of side effects: it fires witch_time_changed, which drives the perfect-dodge screen tint (screen_fx.gd:72) and the audio witch filter (audio.gd:120).

**Skeptic's check**: _tick_charge counts pdt, and in a non-witch slow-mo that is the scaled delta (feel.gd player_time_comp returns 1 unless _witch). Feel.slow_mo(0.3, 0.8, 0.05, 0.1) lasts 0.8 s of real time and advances the player clock by only about 0.29 s, so the charge ends about 1.31 s real after it starts, with the last ~0.5 s at 1.0x. The ignition has the same pattern: 0.45 s on pdt under a 0.25 s slow-mo comes to about 0.57 s real.

## 11. [low] game/combat/skills/corona_fins.gd:269 (nonfinite)
**What**: With no lock-on, _fire_beam aims at f.station, which is exactly where _tick_out just placed the fin, so every beam is zero length (SkillFxBeam.line hides it) and the spark and sound play on the fin itself.

**Trigger**: Tap Fins without a lock (the documented 'fly to the crosshair point' path). Two fins reach stations on the 18 m sphere around the aim point and each fires 4 invisible zero-length beams, each holding two pooled beam pieces for 0.22 s with nothing drawn.

**Fix**: Store the launch aim point on the Fin in _launch (f.aim_at = aim) and fire at it when there is no live target (var aim := f.aim_at) instead of f.station.

**Skeptic's check**: With no lock, f.target is null, so on station _tick_out sets mesh.global_position = f.station (corona_fins.gd:213) and _fire_beam aims at f.station (line 247): from == to. SkillFxBeam.line hides beams shorter than 0.01 m (fx_beam.gd), so all 4 beams per fin are invisible while each holds its pooled pieces, and the spark and sound play at the fin itself. Cosmetic, low severity.

## 12. [low] game/combat/skills/shockcore_burst.gd:154 (nonfinite)
**What**: ctx.ground_point() snaps up to 1,200 m down with no distance cap, so an airborne Shockcore stamps its scorch_ring decal, dust ring, shock ring, arcs and inflow onto the deck far below the mech, while the shell and the damage stay at the mech.

**Trigger**: Burst while flying, e.g. 150 m up under the 260 m ceiling: the ground ring and decal appear 150 m below. The same uncapped pattern is in undertow_well.gd:170 (a well that arms in mid-air after 1.2 s) and zenith_overdrive.gd:62 (the ignition deck ring). zenith_lance.gd:197-198 caps at 400 m, so it still scorches the deck under a beam far above it.

**Fix**: Skip the ground-layer pieces when _centre.y - ground.y > t.burst_radius (the shock can't reach the deck); use the field or ring radius for the well and the ignition, and tighten the lance's 400 m cap to about lance_width.

**Skeptic's check**: This is a cosmetic misplacement, not a non-finite value: ground_point returns `at` when the ray misses. ground_y casts 1,200 m down (skill_context.gd:152-153), and _draw_burst puts the ring, arcs, inflow, dust ring and scorch_ring decal at the hit point whatever the height (shockcore_burst.gd:154-164). can_act() allows the burst in AIR/FLIGHT, since can_cancel only blocks LOCKED, LUNGE and the land lock. The same uncapped pattern is in undertow_well.gd:170-171 (a well that arms mid-air) and zenith_overdrive.gd:62; the lance caps at 400 m (zenith_lance.gd:197-199).
