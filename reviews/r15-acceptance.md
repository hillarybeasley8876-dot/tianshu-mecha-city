# r15 — lead acceptance log

One entry per unit delivery: what the lead re-ran, what it looked at, the verdict, and where each
request was routed.

## mech-move r6 (flight double tap) — ACCEPTED 11-05 04:20
**Root cause.** `input.double_jump` was only honoured in `MechAir.air()`. Every other state that answers
a jump press threw the flag away: the ground knee-dip, the slide, the assault, the dash and the landing.
So holding boost made flight unreachable. The fix is `MechLocomotion.try_flight()`, asked first by every
state, with an Outage gate (567027e).

**The original trailer repro was a camera problem, not an input one.** The mech was flying from 0.746 s;
the rig had whipped off it.

**Re-run by the lead, live tree:**

| suite | result |
|---|---|
| `test_flight_input` | 16/16 |
| `test_clocks` | 9/9 |
| `test_locomotion` | 56/56 |

**Looked at** `captures/mech-move_flight_t*.jpg` (sheet `~/m/mc-lead/accept/mm_flight.jpg`): the mech is
airborne, with its shadow far below, and the thruster flames are lit. In t4.9 and t5.9 the camera loses
it behind pillars: that is the camera request below.

**Routed:**
- **camera-aim:** the rig loses a flying mech. Nudged into r7 as item 3.
- **hud:** no flight cue reads `hud_state()["state"]`. Queued for hud r6.
- **trailer:** the flight flags are in `status/mech-move.md`.
- **hero-v3 (lead's own note):** the flight pose is a standing hover. It needs a lean and a bank with
  velocity. Queued for the round after r7.

## camera-aim r7 (first person black, the camera park, flight framing) — ACCEPTED 11-05 06:04

**1. First person went black.** The cause: the FP lens sits inside the hero's own head, and the aim
solve swings the gatling across it. The fix culls the hero by layer (bit 18) from the FP camera,
which `camera_hero_cull.gd` does, and caps the eye-correction offset at 0.18 m. Over 30 s in the city,
day and dusk:
- 0 of about 3,550 frames are under 0.02 luma;
- the eye stays within 0.180 m of the socket;
- the cockpit covers 17.2 % of the screen (the limit is 18 %).

**2. The camera park: not reproducible on the current tree.** The worker shipped
`test_camera_flow.gd`, which drives the real flow over the real rig and fails against the pre-fix
`end_cinematic()`. The lead re-ran it with the documented flags (`-- --sandbox --flow --spawn=0,1,60`):
10/10. Without the flags the flow stays in "title": that was the lead's invocation, not a defect.

**3. Flight framing.** The hero stays at ≥ 25 % of the frame height and is never occluded (sandbox and
city).

**Re-run by the lead, live tree:**
- `test_camera_flow` 10/10;
- `test_camera_cockpit`, `test_camera_flight` and `test_camera`: 0 failures.

**Looked at** `tmp/camera-aim/fp_final_sheet.jpg` (cockpit frame, HUD on the glass, no black frames)
and `flight_city_sheet.jpg` (the hero stays framed through the climb; the r15 sky is already visible).

**Open requests:**
- 0f: hero-v3 may prefer a lowered-weapon cockpit pose. Later.
- 0g: `CameraRig.eye_residual()` goes into CONTRACTS §3. Lead docs, batched.

## trailer r2 part A — ACCEPTED 11-05 06:04
**The stage:** A6 Sky Garden. The hero reads at 0.34–0.39 of the frame, with 0.71–0.87 of the frame
open behind it. **The cut:** eleven combat cuts on eight setups, each ≤ 2.79 s; every take passes the
framing gate. **The boss:** the crane replaces the black under-deck intro.

**Looked at** `captures/trailer/sheets/TIANSHU_trailer_v2a_shots.jpg`:
- the hero is centred;
- enemies are visible, and their glow reads;
- the skills (the Undertow Well dome, PERFECT witch time) read;
- s01–s07 are still the r14 look.

**Notes sent by nudge:**
- hold part B's final re-records until the lead says "re-record";
- identify the pale beige "ghost" enemy in c_missiles, c_dodge, c_fins and c_od.

## hero-v3 r7 — interim art note (nudge, 06:04)
On `look_r14_vs_r15.jpg` the cyan seams are right. Three problems:
- the visor and the chest vent are flat orange rectangles: they must follow the concept's gold grille;
- the armour lost its black-gold identity and reads blue-grey;
- re-shoot the gates after city-art r15 lands.

## trailer r2 part A — final (done 06:22)
- **Re-records are held.** The 5 test takes are parked in `shots_r15_test/`. `shots.json` is already
  the part-B list.
- **The ghost enemy is the Mantis hit flash.** `monster_body.gdshader:78` adds
  `hit_flash × flash_energy` to emission. `flash_energy` defaults to 4.0, no `<type>_rig.json` sets it,
  and every missile impact re-arms it. Frames: `captures/trailer/sheets/ghost_mantis_hitflash.jpg`,
  `ghost_archetype_ab.jpg`. Routed to monster-assets.
- **Requests routed:**
  - weapons: the gatling muzzle flash is a ~10 m sprite that fills 1/4 of the frame in FP;
  - the map owner: the Crown deck is roofed (open = 0.00 from 8 bearings), so the boss films as an
    interior;
  - lead: `game/override.cfg` goes into .gitignore (done);
  - flow: the spire collapse needs a filmable camera.

## city-art r15 (colour, sky, wet ground) — ACCEPTED as a step, 11-05 06:31
**Measured:** a third, sun-off probe frame gives an exact sun mask, and a colour table in CIE Lab is
read against the key art.

**The causes:**
- The flat brown sky was 100 % cloud: a hard `mass` clamp at cover 0.77. Now a smoothstep mass, cover
  0.40–0.80, a violet-grey cloud body, and `fog_sky_affect` 0.22 → 0.08.
- The crushed shadows were the grade's toe, which clipped every luma under 0.094 to 0. `sky_ambient`
  went 0.33 → 1.60.

**Results:**
- hero shaded-side luma at the s04 cameras 0.003 → 0.085;
- 0 clip regressions against r14;
- SSR costs +4 to +29 ms, so it stays off; an analytic reflection of the sky ramp ships instead.

**Looked at** `captures/sheets/art_r15_{V1,V8,S02city,S04fight}.jpg`. The sky is blue-violet with
cloud bands and a gold horizon, and the shadows are cool and readable: a clear step up from r14.

**Not met** (it is in the worker's own table):
- golden-hour warmth: `skylo_hue` 43–66 against a target of 65–85, and `lit_hue` — V1 now reads cool
  and overcast;
- a diagonal hatch pattern across the whole r15 frames;
- the HDRI plates ship at blend 0, which is dead weight;
- the `--tod=1.0` emissive budget.

All four are in city-art r16, together with the acceptance findings (the settle-cache mtime
fingerprint, the material_library split, the stale tests, the antenna).

**Request:** hero-v3 — the ambient is 4.8× brighter, so the rim and the emissives need a re-tune. That
is item 3 of the hero-v3 nudge.

# r16 wave

## melee-defense r6 (hud_state before the first physics tick) — ACCEPTED 11-05 07:46
**The fix:** every public MeleeSystem method is safe from the moment the node enters the tree (7cf4abe).
The new `test_hud_first_frame.gd` (42 checks) fails on the old code (2 SCRIPT ERRORs) and passes on the
new.

**Re-run by the lead:**
- `test_hud_first_frame`: 42/0;
- `test_main_spawn --enemies=ripper:6`: 6/0, PASS, `SCRIPT ERROR` count 0.

**Worker note:** one integration drive caught camera-aim r8's `aim_system.gd` mid-write (a parse
error) and passed once the write landed. That is shared-tree noise, not a defect.

## audio r6 (the credits match what ships) — ACCEPTED 11-05 08:05
**What changed:**
- the dead `oga_monster2` pack and role are removed;
- the firearm library is now credited to its four recordists: the fetcher read the "Submitted by"
  link instead of the author;
- seven packs got dated CC0 records;
- the music rows name their tracks;
- no audio file changed.

**Re-run by the lead:**
- `credits_check.py`: files 300, rows 300, sources 17, 0 unmatched either way, 0 bad authors;
- `test_audio`: PASS.

**Lead hygiene:** each pack's `oga_sources.json` licence record is now tracked, so the check runs on a
clean checkout (efd31eb).

**Routed:**
- Request 8 (the final credit strings) goes to hud r6;
- Request 9 (sound rows for `rift_step`, `last_stand` and `boss_kill`) waits for an audio r7 once
  those ids land.

## hero-v3 r7 (the hero must read) — ACCEPTED 11-05 08:14
**What changed:**
- an atlas-derived emission mask (R seams 1.78 %, G vents 0.15 %, B gold 3.84 %);
- `hero3_shell.gdshader`: emission, a linear floor, metal trim, a plate sheen, a rim and a hemisphere
  fill;
- modelled glows: the portcullis grille, the visor slit and 7 drone tips.

**Readability at the trailer cameras:**

| camera | dark pixels, before → after | hero/ring, before → after |
|---|---|---|
| s01 | 49.1 → 7.9 % | 0.19 → 0.54 |
| s03 | 29.8 → 6.0 % | — |
| s04 | 31.1 → 5.3 % | — |

Black-and-gold: the plates are darker than the trim in 16/16 frames.

**Re-run by the lead:** `check hero3` 66/0, `test_hero3_shade` PASS.

**Looked at** the before/after, look-vs-concept and glow-vs-concept sheets. At gameplay distance it
reads as the concept: cyan seams, gold, a lit grille.

**Close-up defects → hero-v3 r8:**
- white blotches inside the grille;
- the visor streak sticks out of the helmet;
- the flight pose is a standing hover;
- the drone hide API (for skills r4);
- re-run the gates on city-art r16 light.

**Ruling:** `GOLD_GLOW` stays. The trim follows the environment, so the 3/16 orange-lit front-on misses
are accepted.

## camera-aim r8 (pad lock switch) — ACCEPTED 11-05 08:18
**The fix:** `aim_system.gd` now consumes `lock_next` and `lock_prev` (they were pressed by PadInput,
but nothing read them) and routes them through the existing `switch_target`. `SWITCH_GRACE` = 0.35 s
keeps a deliberate switch from being dropped by the keep cone on the next tick.

**Re-run by the lead:** `test_aim`: 0 failures. The worker's run went 36 PASS, against 3 FAIL on the old
code.

**Rulings:**
- 5a: `SWITCH_GRACE` stays, flick path included; a deliberate switch should stick.
- 5b: the wrap bounce at the end of a row goes to a later camera-aim round (minor).
- 6: the capture-tool clocks go to tooling.
- 7: the lock glyphs go to hud r6.
- 0g: the `eye_residual()` line is now in CONTRACTS §3.

## city-kit r10 (the props that decimation shredded) — ACCEPTED 11-05 08:43
**The root cause went beyond the brief:**
- 27 of the 30 Tripo prop sources are not watertight.
- Blender's collapse decimator constrains boundary edges, so a tear survives every budget and grows
  (ac_cluster 0.27 → 1.09 m).
- The fix caps the loops before and after the decimate, and reprocesses all 30 props.
- The crane moved to the statue tier (40k).
- `normalise()` now measures mesh data, not the stale bounding box, which had sunk the crane 24.9 m.

**Re-run by the lead:**
- `rebase_glb --check --set props`: PASS;
- `git status game/world/props`: 0 uncommitted.

**Looked at:**
- `captures/kit/r10_crane_after.jpg`: a clean gantry crane in clay and textured views;
- `r10_ingame_{before,after}.jpg`: at H0 the gold shards are now a readable lattice crane.

**Cost:** +0.44 ms at the H0 harbour camera, flat at A1.

**Rulings and routing:**
- ac_cluster's 0.26 m "open boundary" is a one-sided fin, not a hole, so it is accepted.
- The settle stamp should cover the prop meshes: already in city-art r16's decisions.
- perf_probe and `godot.sh run` arguments go to tooling (nudged).

## weapons r5 (the FP muzzle flash, the vent feel id) — ACCEPTED with a follow-up, 11-05 08:51
**What changed:** the muzzle VFX are sized by camera mode, so in FP the gatling flash goes from 2.2 m
to 0.59 m, and the rifle and hailstorm VFX are trimmed too. The duplicate vent chime is gone.

**The worker's numbers:** `test_weapons` 148/0, with an A/B per fix.

**Looked at** `captures/weapons_r5_fp_sheet.jpg`. Before, a cream disc covered the right third of the FP
frame. After, a small flash, and the mantis target reads.

**Follow-up (weapons r6):** large flat ORANGE slabs, probably the casings or the sparks, still fly
across the right of the FP frame in every frame of that sheet, before and after.

**Routing:**
- the three vent FEEL rows go to feel r5, which is granted FEEL.md;
- the `OVERRIDES` entry goes to audio r7;
- `test_feel_rows` stays on the tooling KNOWN list until feel r5 lands.

**Note:** the integration drive's 2,907 errors at the time were hero-v3's mid-edit `hero3_glow.gd`
parse error, not weapons'.

## mech-move r7 (a dead mech is dead) — NOT ACCEPTED → r7b, 11-05 10:15
This was the acceptance workflow's first run: 4 reviewers (gates, old-code proof, adversary, visual).
**What holds:**
- the gate is right: `test_death` goes 34/71 on old code and 71/71 on new;
- the windowed and `--stub=hud` probes show 0 failed;
- the wreck stays down under the page.

**Major defects:**
- a death inside Overdrive leaves it on and gives a free OD after RETRY (`SkillSystem.reset()`, a test
  hook);
- the gate refills ammo, heat and cooldowns (carry-over was ruled out);
- the revive latch eats fresh presses while any key is held;
- the tests never hold a key through the kill, and the revive phase never kills;
- `test_last_stand` is 10/12 now that feel's row has landed.

**Routed in the same pass:**
- flow: a clean checkout is broken, because `flow_debug.gd:479` calls an uncommitted
  `BossTuning.phase_fraction()`. Nudged as URGENT.
- hero-v3: its uncommitted `hero3_rig.gd:411` calls `Basis.scaled(float)`, which throws SCRIPT ERRORs
  on every flight; also the dead-lock emissives. Nudged.

The brief is `reviews/mech-move-r7b.md`.

## city-layout r8 (3D routes) — accepted as a step → r8b, 11-05 10:45
- **What exists now:** the 3D solids model (`route3d.py`) and the route sub-checks a–d.
- **Re-run by the lead:** the connectors went from 1/40 to 18/40 passing a–d. `validate_layout` still
  FAILs (56), honestly reported. `validate_graph` passes, and the md5 is deterministic.
- **Accepted:** the hive moves (A2 125 m, A6 27 m), posted to flow and trailer.
- **Not done** (city-layout r8b):
  - the Knot;
  - the shaft tops;
  - the headroom failures;
  - the C14 crate regression and the cover.
- **Next:** city-build r11 starts now on r8, and rebuilds once more on r8b.

## hero-v3 r9 (the user's defects: the hero floats, the thrusters float, the walk looks wrong) — ACCEPTED 11-05 16:20
Only one worker ran this round (the user's load rule).

**The float.** The model hung 7.4 m above the ground everywhere. There were four causes:
1. the model was never hung half a capsule below the body origin;
2. the feet are asymmetric about the mesh origin;
3. `mech_contact` negated the stick's z, so the gait ran mirrored: plants behind the hip, legs
   over-reached, the pelvis pinned at MAX_DROP;
4. a roll residual, and planting on the body's plane instead of each foot's floor.

**The thrusters.** A skeleton-space point was written into a bone-space position, the cone's centre
sat at the mouth, and the shader's `along` was inverted. The nozzles are now measured off the mesh;
there are two back plumes, and the calf flames are gone.

**The gait.** The lean was a constant −1.8° (leaning back) and now grows with speed. The arm swing was
0 and is now a 5° counter-swing. The strafe pelvis travel was 2.17 m and is now 0.62 m. Foot slip is 0.

**Re-run by the lead:**
- `test_hero3_thruster`: PASS, 0 errors.
- `probe_float`: 100 % near on flat, ramp, turn, slide, hop and heavy landing. The 2 m kerb walk is
  75 %: the capsule rides up the step (a mech-move request), as the worker reported.

**Looked at** `hero3_r9_gait_before_after.jpg`: a stride instead of a duck-walk. `hero3_r9_thruster_states.jpg`:
the plumes sit on the back.

**Polish, later:** the plumes read as flat white slabs and need a hot core with a coloured falloff.

**Routed:**
- the kerb capsule goes to mech-move;
- `ArtSurfaces` creates DYNAMIC bodies (`settle/surface_query.gd:167,175`), so the settle pass measured
  falling surfaces. This goes to city-art NOW, because it is a likely cause of floating or buried
  dressing;
- skate sparks and dust go to feel.

## city-art r16a (the settle index, floating dressing) — ACCEPTED 11-05 17:00
- **The fix:** static-mode bodies in `surface_query.gd`. `test_surface_static` fails on the old code
  (−4.78 m of drift in 1 s) and passes on the new.
- **Honest finding:** the dynamic-body bug did NO damage. The index is built and queried inside one
  frame, so it was latent. The lead's earlier guess that it caused the floating was wrong.
- **The real last two floaters** (an antenna at 0.80 m, a vent at 0.77 m) came from the verify
  tolerance: `VERIFY_M` went 1.0 → 0.5.
- **The headless float gate was blind:** `RoofGreebles.emitted` was never assigned, so all 1,315
  greebles measured as zero instances. Fixed.
- **The re-bake** (stamp 3cada3af) keeps the same survivors. The content stamp now covers the prop
  meshes, which closes the packaging findings.
- **Re-run by the lead:**
  - `test_surface_static` PASS;
  - `test_float` PASS, 0 floating;
  - `test_settle_cache` PASS.
- **Looked at** `r16a_{before,after}`: the antenna is settled, and A1 is unchanged.
- **Noted for later:** 741 buried instances (pylons meeting viaduct undersides, roof units against
  parapets) are reported but not gated; the street-only categories are 0/0. The A1 foreground shows
  pale, crumpled white figures (props). That is an art item for a later round.

## mech-move r7b (the death gate stops only what is running) — ACCEPTED 11-06 00:50
**What changed:**
- `mech_teardown.gd` stops only the running actions. Ammo, heat, cooldowns and the selected weapon are
  kept.
- Overdrive now ends through `end_overdrive()`.
- The revive latch works per action: RMB held through RETRY no longer mutes fire, melee, guard or
  skills.
- `boost_ended(assault)` fires at the latch, a shoved corpse revives on the floor, and one death
  announces once.

**Test fixes:** the tests now hold keys through an unblockable kill. The mutation score is 8/10
mutations flipping 32 rows; M7b's post-release OR is a correctness fix the suite cannot falsify, and
that is stated honestly.

**Re-run by the lead, headless:**
- `test_death` 108/108;
- `test_damage` 33/33 (last stand folded in);
- `test_locomotion` 56/56;
- `test_flight_input` 16/16;
- `check player/` 155/0.

**Open:**
- Captures needed (windowed): pending the user's OK.
- Requests 16–20: skills (fold the OD teardown in), weapons (`stop_volley`), flow (`die` announces
  twice), tooling (the suite row for `test_death`).

## flow r5b (the hive collapse films; the WIP; die) — ACCEPTED 11-06 16:30, windowed proofs pending
**The collapse camera had two causes:**
1. the offset was built in world axes but read in the duel frame, whose −Z follows the hero's facing,
   so at A5 the eye sat 68 m away, 90° round and inside a building;
2. nothing checked the placement against the city.

`flow_collapse_shot.gd` now solves the stand: clear air, both ends of the spire on a clear ray, and
the framing in the frustum, at all three hives.

**The WIP** is re-applied. The bot stood 5.5 m inside the floor, because the mech origin is the
capsule centre.

**`die`:** only the mech announces now.

**Re-run by the lead, headless:**
- `test_collapse_camera` 62/0 (it fails 11 on HEAD);
- `test_die_once` 9/0;
- `test_flow` 252/0.

**Pending:** 4 windowed captures under "Captures needed" in `status/flow.md`: the collapse film and
movie, the city E2E, the bot assault.

**Routed:** the A2 hive sits in a slot (42/1,344 stands see it), so the bot cannot finish A2. That is
city-layout's Request 8, for its r8b.

## melee-defense r7 (the Mirror Guard as an energy shield) — ACCEPTED headless 11-06 17:00, pixels pending
**What changed:**
- `mirror_shield.gdshader`, additive, with no depth write, so nothing behind it is hidden;
- a hex wash plus a fresnel/radial rim in the hero's cyan;
- a curved 9.2 m cap instead of a 13 m flat hex;
- 0.08/0.15 s fades, a ripple from the hit point, a parry flash with 18 pooled shards;
- the catch-field dome, which had no surface before.

**Numbers:** interior alpha ≤ 0.156, rim 0.95. Seven mutations each fail a named check.

**Finding:** `tools/godot.sh check` does not catch a broken shader. Compiling through
`get_shader_uniform_list()` inside an error window does, so this is a tooling item.

**Re-run by the lead:** see the line below.

**Pending:** the captures under "Captures needed (r7)" in `status/melee-defense.md`.
- Re-run: `test_defense` 144/0 and `test_guard_capture` 27/0, both with TEST ERRORS 0.

## weapons r6 (the FP orange slabs) — ACCEPTED headless 11-06 17:45, pixels pending
**Identified, not guessed:** `FpNearScan` lists every drawn primitive within 15 m of the FP lens, every
tick. It found:
- the spent casings: 1.25 × 0.42 m orange boxes, 5 m from the lens;
- the missile flares: 3.5 m quads covering 58° of the frame.

**The fix, by camera mode** (third person is byte-identical):
- casings at ×0.27, thrown along the lens→port ray and hidden inside 4 m;
- missile visuals ramped by distance.

**Proof:** reverting only the `FP_SCALE` constants gives 6 failures, which name the casing.

**Re-run by the lead:** see the line below.

**Pending:** the captures under Captures needed in `status/weapons.md`.

**Open note:** the missile smoke is still a 3.4 m grey disc at the canopy; it can come down further if
it reads badly.
- Re-run: `test_weapons -- --audio-trace` 172/0 and `test_feel_rows` 13/0 (feel landed the vent rows).

## skills r4 and monster-assets r5 — ACCEPTED headless 11-06 18:05
Both acceptance workflows were stopped on 11-05 (the user's load rule), so these are inline headless
re-runs.

**skills r4:**
- `test_skills` 275/0, TEST ERRORS 0;
- the showcase reel films every skill (s1–s7), and each reads.

**monster-assets r5:**
- `test_models` 722/0;
- `probe_floor`: 0 hovering frames for the ripper and the mantis, which floated before;
- the 40 m sheet and the showcase m1–m7 show no torn green sheets.

**Open, from monster-assets' report:** the spitter and harrier bridges (fused bind geometry, a Tripo
re-rig candidate) and the juggernaut `charge_run`, which sinks 0.70 m.

**Covered by hero-v3 r9's acceptance:** hero-v3 r8 (grille, visor, flight pose, drone API, dead
power-down).

## hud r6 (credits, licences, menus, the flight cue, the first prompt) — ACCEPTED headless 11-06 18:50, pixels pending
**What changed:**
- the first tutorial prompt survives the title: its life counts from the front of the queue;
- an honest AI disclosure per family, Tripo included;
- the licence composer feeds both the LICENCES page and the headless writer;
- credits wrap and scroll;
- the flight cue, measured from the falling EN gauge;
- the seven routed menu items: PAUSE RETRY; GAME_OVER holds its page until the respawn; pad B/ESC;
  `abort_to_title`; the tree pause; the footer; the glyphs. Plus four CONTROLS rows.

**Re-run by the lead:**
- `test_hud` 371/0;
- `test_title_tutorial` 6/0, through the real `main.tscn` and a real ENTER; it failed 2 on the old
  widget.

**Lead follow-ups in the same pass:**
- `tools/godot.sh package` now writes `THIRD_PARTY_LICENSES.txt` beside the .app (104,775 characters;
  `build/` verified);
- the fixed allow-list entries `hud-r6-item6-typedarray-freed` and `gatling-vent-good-unknown-feel-id`
  are removed, and both suites stay green under the strict host.

**Pending:** 4 capture commands under Captures needed in `status/hud.md`.

## enemies r11 (spawn safety, near miss, the balance gate) — ACCEPTED headless 11-06 19:45
**What changed:**
- `spawner.gd` sets the monster's transform before `add_child`. The old code flung the player at
  16–20 km/s and teleported monsters 7–10 m.
- `EnemyNearMiss`: an enemy round that passes within 6 m of the hurtbox without hitting plays
  `Feel.play(near_miss)`.
- `test_ai` measures SPEC §7.1's "full tokens" (the pool at capacity) and holds 25.5–32.0 s over 5 runs.

**Re-run by the lead:**
- `test_spawn_safety` 10/0;
- `test_near_miss` 17/0;
- `test_ai` (see below).

**Routed:**
- Request 21: a monster that loses sight of the player parks blind forever. It goes to the next
  enemies round.
- Request 19: `platform_floor_layers` goes to mech-move.
- Request 20: the HP row of a median run goes to flow.

**Pending:** the captures listed in `status/enemies.md`.
- Re-run: `test_ai` over 5 runs gave 4 × 14/0 and 1 × 13/1. The failing run was under a load of about
  22; its failing line was not captured. The flake is minor and goes to the next enemies round, together
  with Request 21 (the blind park), which is a plausible cause of an "engaged / stuck" check failing.

## feel r5b (the r5 remainder, skate sparks) — ACCEPTED headless 11-06 20:10, pixels pending
**What changed:**
- the gallery stills run on the game clock (the saved WIP is committed);
- `FxSkateTrail`: sparks and dust off the boots on the ground skate and slide, and off in the air;
- `test_boss_kill`: the boss death plays `boss_kill` once.

**No edit needed:** the `enemy_base.gd` victim stop (in aeb8234) is intact after enemies r11.

**Re-run by the lead:** `test_skate`, `test_boss_kill`, `test_swarm` (28/0), `test_clocks` and
`test_feel` all PASS with 0 errors.

**Routed:**
- the suite rows go to tooling;
- the `VfxLibrary.skate` / `FxSkateTrail` lines go to CONTRACTS (lead, batched);
- a FEEL row for the skate rumble is deferred.

## tooling r1b (one regression table) — ACCEPTED 11-06 21:15
- **The table:** 92 rows, 0 UNLISTED, a `SUITES` verdict line, and one Godot at a time. Four full passes
  ran at about 11 min each.
- **The worker's result:** 90 green, 1 known (`test-occlusion-stale-premise`), 1 red
  (`art_design_copy`), and an audio clocks flake (1 of 4 passes).
- **The input quad's check-time engine ERROR is fixed:** it polled F3 before the actions were
  registered.

**Lead decision: the MAP IS FROZEN at the built r7 layout for the demo.** city-layout r8 (437e0b9)
removed 40 buildings and 1 deck for its 3D routes, and city-build never rebuilt on it. The game, the
trailer, the showcase and the app all run on the r7 city. Rebuilding the whole city now would
invalidate the settle bake, the kit assignment, the trailer stages and flow's stands, late in the demo.
`art_design_copy` is therefore allow-listed as `map-r8-unbuilt`. The layout → build → traversal chain
(city-layout r8b, city-build r11, traversal r1) waits until after the demo, or until the user asks
for it.

**Lead fix:** `tools/suites.sh` counts a suite's own FAIL lines when its summary prints no total, so
that a known red can match.

**Routed:** the audio clocks flake (`test_audio_clocks.gd:171`, 110 vs 145.6 BPM) goes to audio r7.

## audio r7 (sounds for the new feel rows, the clock flake) — ACCEPTED 11-06 22:10
**What changed:**
- `last_stand` and `boss_kill` are new bank rows. `boss_kill` layers with `kill_large`, and FEEL's
  world −6 dB duck is implemented.
- The vent rows are mapped, and `near_miss` already reached a sound.

**The flake:** it was not clock drift; drift measured 0.000 s. Two causes, both fixed:
- an order-dependent clip switch;
- combat heat overriding an explicit `music_intensity` request.

`test_audio_clocks` passed 20/20 back to back.

**Re-run by the lead:** the FULL table, `tools/suites.sh --jobs=1`, gives
**`SUITES 92 rows, 90 green, 2 known, 0 red`**. The 2 known are `map-r8-unbuilt` and
`test-occlusion-stale-premise`.

**Pending:** the boss-death mix (the loudest moment) has not been heard in a mix yet; it is under
Captures needed.

## enemies r12 (the blind park) — ACCEPTED 11-06 23:05
**What changed:**
- `EnemyBrainSearch`: a monster walks to the last known position, sweeps the horizon, searches in rings
  (45/90/150 m) and gives up after 8 s, then returns to its arena.
- Perception keeps a memory age, and a gunshot refreshes where an already-hunting monster thinks the
  player is.
- The leash puts a blind monster back on a ring point it can see the player from.

**Proof:** `test_los_loss` fails 37 checks on the old brain and passes 0/54 on the new.

**The `test_ai` flake** had two attack-gate defects:
- the spitter's 0-damage chaff took a RANGED token;
- the attack pick could choose an attack the monster could not see.

`test_ai` now passes 10/10 sequential runs, dying in 26.6–28.1 s.

**Re-run by the lead:** `test_los_loss` 54/0, and the FULL table **`SUITES 93 rows, 91 green, 2 known,
0 red`**.

## mech-move r8 (the kerb float, monsters as floor) — ACCEPTED 11-07 03:10
**The kerb.** Measured first: `try_step` moved the capsule 2.01 m up and 4.24 m forward in ONE tick.
`MechCoast` now walks that displacement out at the mech's own speed, and `step_lag` holds the model on
the trailing foot's plane. `MechGround` and `MechCoast` were split out first, in their own commit
(b1f1579). The result: `walk_kerb` went 75 % → 100 % near, from +0.91 above to +0.02.

**Monsters.** `platform_floor_layers` excludes ENEMY (732d8d9), with `test_platform` 5/5.

**Re-run by the lead:**
- `probe_float`: all 11 cases PASS (walk_kerb 100 %, +0.02);
- `test_step_coast` 36/36.

**Lead follow-up:** the two new suite rows (`mech_step_coast`, `mech_platform`) are added, so `--list`
shows 0 UNLISTED.

**Still open:** skills Request 16 (the OD teardown fold) and weapons Request 17 (`stop_volley`). Both are
minor, because mech-move's teardown already covers them from its side.

## monster-assets r6 (no monster sinks or floats) — ACCEPTED 11-07 05:55
**Four causes behind `charge_run`:**
1. Blender's round-trip measured an unposed rig: 41 of 54 bones were left in the previous clip's pose.
2. The exporter's forced sampling broke the ground lock.
3. A knuckle claw sat 0.64 m below the feet; the elbow was refolded.
4. Godot re-sampled every clip at 30 fps against 24 fps authoring; clips are now baked on the engine's
   grid.

**Also found:** the juggernaut stood 2.3–3.5 m up on its knuckles for its whole idle. It was invisible to
the old probe, which reported only the lowest point. `probe_floor` now walks every grounded clip and
reports both hover and sink.

**Re-run by the lead:** `probe_floor` reads 46 clips, 44 in band. `charge_run` is −0.00 m, the idle is
0/460 hovering, and the slam, roar and swipe are within 0.03 m.

**The 2 out of band:** `titan_skyline` idle (−0.19 m) and walk (−0.21 m). That is the titan's −0.14 m
times the skyline model's ×1.5 scale. It is a background walker on the city ring, seen from hundreds of
metres, so it is accepted.

**Pending:** the captures under Captures needed.

## hero-v3 r10 (the plumes as jets) — ACCEPTED headless 11-07 06:35, in-game pixels pending
**Four causes behind the "white slab":**
1. there was no radial term;
2. the accent clipped to white over the first third;
3. the bottom cap's normal made the rear view a hard white disc;
4. the shock diamonds lived in ALPHA and clipped flat.

The new shader goes from a hot core to the seam cyan, then to transparent, with a soft radial edge and
throttle-scaled length.

**Looked at** `tmp/hero-v3/plume.png`, the offline render of the shader's own maths: a white-hot nozzle
falling to cyan, visible banding, a soft rear disc. It reads as a jet.

**Re-run by the lead:** `test_hero3_thruster`, below. **Pending:** the captures under Captures needed.
- Re-run: `test_hero3_thruster` passes with TEST ERRORS 0.

## weapons r7 (`stop_volley`) — ACCEPTED 11-07 07:20
**What changed:**
- `WeaponSystem.stop_volley()` cancels the rifle charge, the gatling spin and the hailstorm paint
  (through a public `HailstormLauncher.cancel()`), and drops ADS and strafe;
- it never refills or swaps;
- `suite_teardown` adds 17 checks;
- the worker proved `MechTeardown` takes the `stop_volley` path with a scratch stub.

**Re-run by the lead:** `test_weapons` 189/0, `test_death` 108/108.

**Routed:** mech-move deletes the now-dead private-field writes in `MechTeardown._weapons()`. That is
small, and goes into mech-move's next round.

## skills r5 (the Overdrive ends inside on_player_died) — ACCEPTED 11-07 07:40
**What changed:**
- `on_player_died()` is now the one skills teardown: the anchor, the ward, a lance mid-fire, and the
  Overdrive through `end_on_death()`, with NO aftermath (lead correction);
- `overdrive_state.gd` was split out (`skill_system.gd` 479 → 376).

**Proof:** the new `suite_death` fails 8 of 14 checks on the r4 hook.

**Re-run by the lead:** `test_skills` 289/0, `test_death` 108/108.

**Routed:** mech-move removes the now-dead OD block and the weapons fallback writes from `MechTeardown`.
This is a tiny cleanup, queued.

## mech-move r9 (the teardown calls the owners' hooks only) — ACCEPTED 11-07 08:00
`mech_teardown.gd` went from 76 to 27 lines. The redundant OD block and the weapons fallback writes are
gone, and the worker checked that they really were redundant.

**Re-run by the lead:** `test_death` 108/108; `check player/` 162/0.

**The headless queue is now empty of demo-relevant work.** Everything left needs a window and the
user's OK:
- the Captures needed batches;
- city-art r16b;
- a re-cut of the trailer and the showcase.

## trailer r5 (re-record both reels on today's build) — ACCEPTED 11-09 03:20
- **Showcase:** 248.7 s, 26 cuts plus 3 cards. It now includes the hive collapse (m6b, 19.9 s), the
  cyan Mirror Guard dome, and the jump segment against clear sky.
- **Trailer v2:** 64.5 s.
- **Both:** every take `errors=0`, framing 0 failed, −14.0 LUFS, 0 black, 0 frozen.
- **Pipeline fix:** the audio mix deadlock (26 videos demuxed by one ffmpeg) is gone; the mix now
  extracts per-clip WAVs and uses the concat demuxer, with a 120 s stall watchdog.
- **The lead looked at** the segment sheet and the 5 s and 2.5 s sheets of both reels. Both are on the
  Desktop.
- **Still reads badly:**
  - showcase: the acid cloud over the spitter segment, a pale fins disc, the mech nearly out of frame
    at 190 s in flight;
  - v2: a flat orange wall at 9–15 s (drop and impact), and the dark cockpit.

## trailer r4 (the captures batch) — ACCEPTED 11-09 05:00, with one blocker found
- **The run:** 44 commands across 10 units, all in windows the user OK'd, one at a time. 42 exited 0;
  2 hit the slot timeout after writing their frames.
- **The lead looked at** the hero-v3, melee-defense, hud, weapons, mech-move, enemies and flow sheets.
  All match what the units claim:
  - the plumes on the back nozzles;
  - the Mirror Guard as a translucent cyan dome with a parry ring;
  - every menu (licences, credits, game over, controls) and the tutorial prompt after the title;
  - no orange slabs in FP;
  - the wreck kneels under the page;
  - the search behaviour, the dodge afterimage and the telegraphs;
  - the collapse filmed at A5 and A6. A2's lens is far: polish.
- **BLOCKER found:** with the menus live, GAME_OVER paused the tree in the death frame, so the slump
  froze standing and the city E2E stalled at the death beat. Routed as hud r7.
- **Harness-only mismatches** (not game bugs): the mech-move kerb exists only in the test scene; the
  monster charge is out of frame; the feel skate timeline has no boost; the hero assault taps never
  take.

## hud r7 (the death plays out before GAME_OVER pauses) — ACCEPTED 11-09 06:40
- **The fix:** `death_hold.gd` pauses only when flow is in `game_over` AND the death clip is at full
  weight AND the wreck is on the floor, between 1.5 s and 8 s on the real clock. Inputs are dead
  meanwhile (0.00 m moved with W held).
- **Proof:** `test_death_pause` fails 4 of 24 checks on HEAD and passes 24 after.
- **Windowed gates, run by the worker under the user's OK:**
  - `1_death` (menus live): SUMMARY 0 failed, slumped at weight 1.00;
  - `3_city`: passes the death beat, 17/17 captures and the report (was 6/17).
- **Re-run by the lead:** the FULL table gives `SUITES 96 rows, 94 green, 2 known, 0 red`.
- **Open, not this unit's:** the E2E bot cannot finish the titan (`won=false`, identical with
  `--stub=hud`). That goes to flow/boss, Request 14. A human player is unaffected.

## city-art r16b (golden hour, the hatch, the HDRI, tod 1.0, post, occlusion) — ACCEPTED as a step 11-09 09:25
**Item 1 had four measured causes:**
- the dusk ramp aged with `progress`, not with the storm;
- `cloud_cover` rode that ramp;
- the dome's gold band ended 5° above the horizon;
- the palette (`SKY_HORIZON`, `SUN_COLOR`) was re-picked with the tonemap probe.

**The others:**
- **Item 2:** the "hatch" was the film grain's sine hash losing its argument to fp32.
- **Item 3:** the HDRI plates now ship at blend 0.5, because they win the golden-hour band. That gives
  real clouds.
- **Item 4:** the tod 1.0 clip was the cyan "up" accent; the lit windows came down 1.5 → 1.15.
- **Item 8:** an occluder core reached to infinity; the gate now has a live premise.

**Looked at** the r15 | r16b | key art sheets:
- V1 and S02 now have cloud structure, a warm peach and gold horizon and sunlit cloud edges;
- the violet cast is gone, and so is the hatch;
- S04 is warmer.

**Still less saturated than the key art's orange sky,** and the midground stays dark and boxy. It is
accepted as a step.

**Re-run by the lead:** the art and post rows give `SUITES 12 rows, 11 green, 1 known, 0 red`. The
known one is `map-r8-unbuilt`.

**Next:** re-record both reels on this look (trailer r6).

## trailer r6 (both reels on golden hour) — ACCEPTED 11-09 11:55
- **Showcase:** 248.7 s, recorded on city-art r16b's golden-hour sky. The crown boss keeps its storm.
- **Trailer v2:** 64.5 s. The drop now opens on the A1 yard and its cranes instead of an orange wall.
- **Both:** −14.0 LUFS, 0 black, 0 frozen; the gates PASS per the worker's report.
- **The lead looked at** both sheets: warm gold light throughout, every gameplay fix on camera.
- **Delivered:** both are on the Desktop.
- **Note:** the worker took about 1 h on the time-of-day A/B before recording, after a nudge.
