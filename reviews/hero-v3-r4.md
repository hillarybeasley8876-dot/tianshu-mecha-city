# hero-v3 — lead review r4 (action clips 796a602 + 1475889)

## Verdict
**Block A (the gait) is accepted.** The lead's probes on the skinned mesh agree with every number in
your status:
- pelvis 7.70–8.25 m, with one trough per step;
- the deepest foot vertex sits at the rest baseline in walk, strafe and run;
- zero shared leg voxels;
- air ankle-to-hip 5.7 m;
- waist overlap 0.57 m.

The fixed-camera walk and strafe movies read as a heavy machine walking. Good work.

**Request 1 is accepted:** 80° yaw and 0.90 m stance. Your geometry argument is right.

**Requests 0 and 3 (flip `HERO_MODEL`): not yet.** Block B passes your own tests, but those tests
play every clip alone, from frame 0, with blend 0, at idle. The game does none of that.

The lead drove the model the way the game does: the game's blends, its move states, combos chained
at the cancel frames, and standing idle. Eleven items follow, in priority order. Four of them
(items 1–4) would make the mech look WORSE in play than the old hero, and the old hero is what the
user called 鬼畜.

Lead probes are in `tmp/lead/probe/`:
- `probe_release.gd`, `probe_legfreeze.gd`, `probe_states.gd`, `probe_float.gd`;
- `probe_idle_chain.gd`, `probe_idle_pop.gd`, `probe_idle_feet.gd`;
- `probe_aimsign.gd`, `probe_rifle.gd`, `probe_blade.gd`, `probe_clips.gd`.

Run them with `tools/godot.sh test <abs path> --timeout=900`. Promote what you need into
`hero3/tests/` as gates, the way you did with block A.

Your action strips are not valid evidence (item 10). The lead re-shot them with the warm-up fixed:
`tmp/lead/h3act/lead_{melee,dash,death,knock,slide,jumpland,charge}.jpg`. Look at `lead_death.jpg` and
`lead_knock.jpg` before you start.

## 1. A clip never lets go (blocker)
The fault is in `Hero3ClipPlayer.update()`, past the last frame. The weight first goes UP by
`delta / _blend` and is clamped to 1, then goes DOWN by the same amount. So it sits at `1 − delta/_blend`
forever: 0.72 for a 0.06 s blend, 0.79 for 0.08 s.

Only a blend shorter than one tick escapes. That is `play_action(id, 0.0)`, which is what your tests
and strips use. Every game call site uses 0.05–0.08 s. `probe_release.gd`: after 2.5 s, melee_l1 is
still "playing" at weight 0.72 and fire_r at 0.79.

What this does in the game:
- **After any FULL clip, the legs freeze.** Walking at 9 m/s after ram_kick or rift_out, the thigh
  swings 0° and the ankle misses its IK target by 4.65 m (`probe_legfreeze.gd`). The mech glides on
  stiff legs.
- **After any upper clip that names Spine01/Spine02** (fire_r, every melee swing), the clip keeps
  writing the spine from its last key at 72–79 % weight, over the aim chain and the walk's
  counter-sway, for the rest of the session.
- **`stop()` does not stop.** A stopped loop plays on to its last frame, and then sticks at the same
  weight.
- **death's `"hold": true` is ignored.** The player only reads `"loop"`.

The game never calls `stop_action` today: not when the guard ends (`defense_system._end_guard`), not
when the gatling spins down. So guard_up and gatling_spin loop forever once started. The lead adds
those calls at the switch. Your side is to make `stop_action` fade out at once.

Fix:
- Past the end, the weight only falls.
- `stop()` starts the fade now.
- `hold` keeps the last frame at full weight until `stop_action`.

Gate: play every one-shot clip with the game's blends (0.05, 0.06, 0.08). `playing()` must be false
within `length + blend + 1 tick`, and the bones must be back on the gait and posture.

## 2. The game's move states are walked (blocker)
`set_locomotion` receives these states from mech-move (`grep "move_state =" game/player/mech/`):

| state | what it is |
|---|---|
| idle, walk, run | standing and stepping |
| coast | 42 → 9 m/s after a dash |
| slide | the GROUND boost skate, 42 m/s |
| glide | the AIR boost, 42 m/s |
| assault | 84 m/s |
| dash_f/b/l/r | 0.25 s, 150 → 42 m/s |
| lunge | 60 m/s |
| locked | held in place by an attack |
| jump, fall, hover, fly | airborne |
| land_light, land_heavy | landings |

`Hero3Gait` handles the air states and the landings. Every other state is walked at the reported
speed. `probe_states.gd` moves the stage at the real speed:

| state | steps per second | worst ankle miss (IK target vs bone) |
|---|---|---|
| walk 9 m/s (reference) | 1.3 | 0.00 m |
| dash_f, 150 → 42 m/s | 8.0 | **13.75 m** |
| assault, 84 m/s | 4.0 | **11.74 m** |
| lunge, 60 m/s | 4.0 | **5.74 m** |
| slide, 42 m/s on the ground | 4.0 | 1.63 m |
| glide, 42 m/s IN THE AIR | 4.0 | 1.63 m |
| coast, 42 → 9 m/s | 3.3 | 0.87 m |

The legs scramble at 4–8 steps a second with the feet metres from their targets. Dash, boost and
assault are the verbs the player uses most, so this is the user's 鬼畜 complaint every few seconds.

The game never calls `play_action` for dash_\*, slide, land_\*, hover, fly or fall. These arrive ONLY
as `set_locomotion` states, so your dash, slide and air clips are never played in game. The old
`hero_model.gd` mapped states to poses (`LOCO_STATE` / `LOCO_CLIP`).

What each state should look like on a 16 m thruster mech:
- **Skate.** This covers `slide`, plus `coast`/`run`/`walk` whenever the ground speed is above the
  gait's own step limit (measure it; run is 16 m/s).
  - No steps. Both soles stay on the floor, pinned in the PELVIS frame, so they slide with the body.
  - The feet are staggered fore and aft, the knees bent, and the pelvis 1.0–1.5 m low.
  - The lower body leans 8–12° into the travel. Banking into a turn is a bonus.
  - Blend in over about 0.12 s. When the speed falls back under the step limit, replant through
    `_replant()`.
- **dash_\*.** The skate stance plus a burst.
  - The lean snaps to about 20° toward the jet within 3 frames.
  - The trailing leg extends and the arms pull in.
  - Then it eases into the skate, or into a walk as `coast` slows. No steps during the dash.
- **assault.** The flight pose (as `fly`), with the feet trailing low.
- **glide.** Airborne: add it to `Hero3Air.STATES`.
- **lunge.** A committed thruster charge: skate stance, front foot forward, no steps.
- **locked.** The attack roots the mech: plant both feet and hold them while the body brakes.
- **hover / fly.** Play the upper-body air pose from the state, the way the old hero did.
- **Ground or air.** The model cannot see the floor, so a state that happens in both (dash_\*, lunge,
  locked) inherits it from the state before. If the air pose was up, keep it and add the burst lean.

Gate: one test covering every state in the table, at those speeds, driven the way `probe_states.gd`
drives it. It must show:
- no step cycle above the gait's step-speed limit;
- worst ankle miss ≤ 0.15 m;
- on the ground, the lower sole within 0.15 m of the floor.

Skating feet may slide; that is what a skate is.

## 3. Full-body clips float: key the ROOT, let the IK keep the feet down (blocker)
Pelvis displacement is **0.00 m in every clip** (`probe_clips.gd`). The FULL clips fold the thighs
and calves with FK keys while the pelvis stays at standing height, so the feet leave the ground.

`probe_float.gd` gives the lower of the two ankles at its highest point in each clip. Rest is 2.77 m.

| clip | lower ankle | frame |
|---|---|---|
| death | **5.6 m** | f94 |
| slide | 4.5 m | f5 |
| hit_knockdown | 4.2 m | f23 |
| hit_heavy | 3.5 m | f8 |
| dash_f | 3.5 m | f4 |

Both feet are off the floor in all five. `lead_death.jpg` and `lead_knock.jpg`, side row: the mech
folds its legs up behind it and hangs in the air. That is the opposite of impact.

This is a structure problem, so fix the structure.
- A full-body clip keys the **root**: translation `[frame, dx, dy, dz]` plus pelvis pitch and roll.
- It keys the **feet as targets**: stay planted, or step to a new spot.
- `Hero3LegIk` solves the thighs and calves, so the soles stay on the floor by construction.
- FK leg keys are only for airborne poses: jump, air_l\*, plunge_dive, and ram_kick's kicking leg.

What each clip should do:
- **death:** drop to one knee (pelvis down ≥ 4 m), then topple onto the floor. The last pose lies on
  the ground with the pelvis ≤ 3 m, and it holds (item 1).
- **hit_knockdown:** the pelvis drops ≥ 3 m within 8 frames and the torso throws back. It recovers to
  standing by the end.
- **hit_heavy:** the pelvis dips 0.8–1.2 m and the chest snaps back 15–20°.
- **hit_light:** a 0.3–0.5 m dip and 6–8° of chest snap.
- **stagger:** two short stumble steps, as real steps through the planner.
- **slide and dash_\*:** the item 2 stances.
- **land_\* and plunge_land:** keep the gait's landing dip.

Gate:
- In every frame of every ground clip, the mech touches the floor: the lowest skinned vertex is within
  0.15 m of it, and no vertex is more than 0.05 m below it. Every clip is a ground clip except jump,
  fall, hover, fly, plunge_dive, air_l1 and air_l2.
- The pelvis numbers above hold, measured on the skinned mesh.

## 4. A new clip starts from the ready pose, not from where the arm is (blocker)
`play()` resets the weight to 0, and `apply()` lerps between the new clip and `READY_POSE`. So a
chained swing snaps the arm back toward guard and then into the next swing, on the exact frame the
player presses the button.

`probe_idle_chain.gd` compares the R_Hand's one-frame move over the chain's first three frames with
each clip's own fastest frame:

| chain | hand move on the chain | fastest frame of each clip |
|---|---|---|
| melee_l1 → l2 at its cancel frame f14 | **7.55 m** | 5.18 m / 5.33 m |
| melee_l2 → l3 at its cancel frame f13 | **9.19 m** | 5.33 m / 4.46 m |

Fix: on `play()`, snapshot the current pose of every bone the new clip owns, and blend from the
snapshot.

Gate: run every chain the game makes at the earliest cancel frame in `melee_table.gd`:
- L1 → L2 → L3
- air_l1 → air_l2
- guard_up → return_cut (the perfect-parry counter)
- guard_up → catch_hold → catch_release
- charge_r → fire_r

The hand's one-frame move over each chain's first three frames must be no faster than the faster
clip's own fastest frame.

## 5. Standing still, the feet rock and pop
At idle the phase clock keeps running at `TURN_CYCLE`. `Hero3Foot.roll` rolls each planted foot from
heel to toe across its stance, then snaps it flat when its swing window comes and it does not step.

`probe_idle_pop.gd`: in 4 s with no input there are 15 one-tick roll jumps over 4°. The worst is a
26° snap that moves the ankle 1.10 m in one tick. `probe_idle_feet.gd`: the toe bones rise up to 0.7 m
off their rest height while the mech stands still.

Idle is the pose the player sees most: aiming, shooting from cover, the cockpit view. A twitching
foot reads as broken.

Fix: roll only a foot that is actually stepping, or about to, and blend the roll to 0 otherwise.

Gate: 4 s at idle with no clip, then with melee_l1, then with fire_r. In all three:
- no foot or toe bone moves more than 0.05 m;
- no roll changes by more than 1° in a tick.

## 6. Aim: the signs are inverted, and the rifle never comes up
`probe_aimsign.gd` measures in world space, with the model facing −Z and the aim point 200 m out:

| aim | what Spine02 does |
|---|---|
| 20° to the RIGHT | turns 20° to the **LEFT** |
| 25° UP | pitches 16° **DOWN** |

Both signs come from `_aim_angles` and the quaternions in `apply_torso`:
- It returns +yaw for a point on the right, but `Quaternion(Vector3.UP, +a)` turns −Z to the left.
- `-link_pitch` pitches the chest down for an upward target.

Your tests check that the chest moves, not which way.

And the rifle hangs:
- `Hero3Rifle` is skinned to R_Hand, and its long axis points 84° below horizontal.
- Its barrel direction is identical (to six decimals) at aim 0°, right 20° and up 25°
  (`probe_rifle.gd`, `probe_float.gd`). The arms are written as ABSOLUTE bases from `READY_POSE`, so
  they never inherit the aimed spine.
- The brief says "rifle up when aiming".
- Shots leave `muzzle_r` toward the aim point (`WeaponContext.aim_dir_from`), so today the beam would
  come out sideways from a gun pointed at the floor.

Fix:
- Fix both signs, and test them in world space.
- With `aim_weight > 0`, the right arm brings the rifle up onto the aim. Use two-bone IK to a grip
  point on the aim line, or carry the arm chain with the aimed chest. The barrel must lie on the line
  from the muzzle to the aim point.
- `muzzle_r` sits at the barrel tip, with its −Z along the barrel.
- Weapon clips (fire_r, charge_r, gatling_spin, reload, missile_launch) layer ON TOP of the aim, as
  offsets. Spine keys in any upper clip are offsets on top of the aim and the counter-rotation; today
  they replace both.

Gate, at weight 1, for aims within ±25° yaw and ±20° pitch of the chest:
- The barrel axis (the rifle mesh's long axis, toward the muzzle) is within 3° of the muzzle-to-aim
  direction, with no clip and during charge_r and gatling_spin.
- During fire_r it may be up to 8° off at the recoil peak, and is back within 3° by the clip's end.
- The chest turns toward the aim.

The game does not call `set_aim` today. The lead wires it from the aim system at the switch, so it
has to be right before then.

## 7. Melee: the visible blade reaches half the hitbox, and four swings run against it
`probe_blade.gd`, over each clip's active window:
- **Reach.** The steel tip (socket + 12 m) stays 7.0–9.4 m from the mech's vertical axis. With the
  2 m energy extension the visible blade reaches about 9–11 m. The hitbox reaches 16–22 m
  (`melee_table.gd` `reach`), so enemies 11–20 m out are cut by thin air.
- **The arm wraps instead of extending.** The arm swings ACROSS the chest, with the blade at −37° to
  +3°. The tip's path is about half the hitbox arc: L1 19.6 m against 37.7 m, charge_slash 30.6 m
  against 80.6 m.
- **Direction.** `probe_rifle.gd` SWEEPDIR: the hitbox always sweeps right → left
  (`MeleeTable.blade_dir`, progress 0 → 1).
  - L1, L3, charge_slash and air_l1 swing right → left, which matches.
  - **melee_l2, air_l2, return_cut and ram_kick swing left → right**, against the hitbox.
- **ram_kick** puts the saber tip 3.6 m under the floor at frame 2.

Fix on your side:
- In the active window, extend the arm and point the blade OUT along the swing plane
  (`MeleeTable.TILT`).
- Keep the alternating forehand and backhand; it is good for a combo. The lead adds a per-move sweep
  direction to `melee_table.gd` at the switch (not your folder). Have your melee test print the
  measured direction per clip, so that table is generated, not typed.

Gate:
- The visible 14 m tip reaches ≥ 0.8 × `reach` from the pivot at mid-active.
- It stays ≥ 0.6 × `reach` across the whole active window.
- No saber vertex goes below the floor in any clip.

## 8. Amplitude: a 16 m machine needs bigger moves
`probe_clips.gd`, peak R_Hand displacement: fire_r 0.55 m, hit_light 0.91 m. On a 16 m mech seen from
40 m, both are invisible, and the rifle fires every 0.25 s and has to feel like it kicks.
- **fire_r.** Within 2 frames, the hand comes back ≥ 1.5 m along the barrel and the chest pitches back
  4–6°. It recovers by frame 12, on top of the aim (item 6).
- **Hit reactions.** As item 3.
- **Skill casts** (burst, lance_fire, overdrive_ignite, well_throw, fins_send). Check each in a front
  strip. Each needs one clear key pose, held for at least 6 frames.

## 9. The interpenetration gate is still missing
The brief's gate is "no piece intersects another at rest or in the 4 stress poses; sample the mesh,
report the worst penetration; ≤ 5 cm". Your status says it is not automated yet. It is a gate, so
automate it.
- Measure on the skinned mesh. For each pair of adjacent rigid pieces, find the deepest vertex of one
  inside the other's closed surface.
- Poses: rest, the 4 stress poses, and the item 3 poses (death's last frame, knockdown at its
  deepest, the skate).
- Report the worst pairs.

## 10. The action strips are not evidence yet
`hero3_action_strip.gd` `_restart()` plays the clip and then runs 90 warm-up ticks, which consume it.
That is why your dash and jump strips are identical (the clip is already over), and why the melee
strip's frames 0–4 do not move.

Fix: warm the gait up first, moving the stage when `--walk` is set, and only then start the clip at
frame 0.

Then re-shoot every strip, and add:
- the item 2 states (dash_f, dash_l, the slide skate, assault, coast after a dash). Shoot them from the
  side with the fixed world camera, so the feet can be judged against the floor;
- death, hit_knockdown and hit_heavy;
- a 4 s idle movie from the fixed camera, for item 5;
- the melee combo chained at the cancel frames, not back to back at clip end;
- a front strip of fire_r aimed 20° right and 15° up.

## 11. (Small) Footsteps
`mech_contact.gd` emits `Events.footstep` on a timer, so the thud does not land when a foot does.
Emit a signal from `Hero3Gait` on every touchdown, carrying the side, the world position and the
speed. The lead rewires the footstep to it at the switch.

## Work order and commits
1. Items 1, 4 and 5 first: the clip player and idle. Each is small.
2. Item 2, then item 3: the structure.
3. Then items 6, 7, 8, 9 and 10.

Commit per item, so the lead can review as you go. After each one, re-run every block A gate: none of
this may break the gait.

## Not your job (the lead does these at the switch)
- Flip `PlayerMech.HERO_MODEL`.
- Wire `set_aim` from the aim system.
- Add `stop_action` at guard end and at gatling spin-down.
- Wire hit reactions and death into `PlayerMech._apply_damage`. Today the player's model is never told
  it was hit.
- Add the per-move sweep direction to `melee_table.gd`.
- Play `parry` on a perfect parry (`defense_system.gd` never does today).
- Rewire footsteps to your plant signal.
- Low-pass the first-person eye height.
