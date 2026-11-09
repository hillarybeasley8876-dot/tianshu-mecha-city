# skills r4 — lead brief: every skill fires on the first press and reads on screen

## Why
The r15 acceptance pass ran every SPEC §3/§6 verb through real input. It used a frozen copy at `b5d26d4`
(`~/m/mc-accept`, findings in `~/m/mc-lead/accept/findings_all.json`); a verifier reproduced both majors.
A quick Rift Step tap does nothing. The Undertow Well ignores the lock, so pillar 2's prime→COLLAPSE
lands only with the reticle on the ground in front of the target. The Lance needs a second hold and shows
as a flat pink wedge. The hero keeps its blades while the fins fly, and the Skyhook cable leaves the
torso. All of it passed because the suites call `try_*()` directly, on stand-ins. This round every check
drives the real input path.

## First
- `game/combat/skills/**` is unchanged since `b5d26d4` (`git diff b5d26d4 HEAD -- game/combat/skills/` is
  empty), but the hero (hero-v3 r7), camera (r7, r8) and sky (city-art r15) moved. Re-check each item at HEAD
  first. If one is already fixed, say so in status with the run that shows it.
- `reviews/r16-lead-decisions.md` overrides this brief where they differ: read "Shared" and "skills r4".
  It adds item 6, the alive check in `skill_input.gd` (a dead mech's skill inputs do nothing; mech-move r7
  stays out of that file), and moves the Lance's shake top-up (`zenith_lance.gd:23-28`, `:168`) to
  `Feel.shake_floor`. Never `git stash`: copy your file aside, then `git show HEAD:<path> > <path>`.
- The probes exist only in `~/m/mc-accept/game/tmp_accept/` (`spec-coverage/verb_probe*.gd`,
  `verify-skills-*/`). Read them; never copy them in (`check` and `import` scan all of `res://`). Port what
  you need into two files. `tests/suite_input.gd` is headless and runs from `test_skills.gd`: actions held
  N ticks, keys and pad via `Input.parse_input_event` + flush (as `rift_verify.gd:179-194` does).
  `tests/skills_accept.tscn/.gd` is windowed: `main.tscn` in the sandbox with the real mech, rig, aim and
  Hero3, and real `lock_on` presses. Per beat it prints `SKACC <beat> ok=0|1`, saves gameplay-camera
  stills to `captures/skills_r4_<beat>.jpg`, and checks the skill fired. Stage beats off the sandbox origin.
- `SKACC` = `tools/godot.sh drive --scene=res://combat/skills/tests/skills_accept.tscn` +
  `--timeline=res://combat/skills/tests/timeline_accept.json --sandbox --skip-menu --god --nan-watch`
  (the timeline is end-only; `--skacc-beats=a,b` picks beats). `CLIP <c>` = the status file's showcase
  command with `--skills-showcase=<c> --out=skills_<c>_r4`.
- As r3 asked, split `skyhook_anchor.gd` (443 lines) and `corona_fins.gd` (432) first, in their own commit.

## 1. Rift Step eats short taps and answers 75 ms late — major
- **Defect.** `skill_input.gd:42-57` `_rift()` waits `od_chord` (4/60 s, `skill_tuning.gd:126`) after the
  press. It cancels if the key comes up first or `lock_on` is held. That arbitrated the old layout (Rift on
  L3, L3+R3 = Overdrive); since 37e66d6 Rift is C / RB+B and the chord lives in `core/pad_input.gd`. Holds
  ≤ 4 frames (≤ 67 ms) are dropped with no cost, FEEL row or blink, on key, pad and `action_press`.
  Every blink that does fire starts 9 ticks (75 ms) after the press (burst: 1), against SPEC §1's 2
  frames. `h.tap()` (3 ticks) and the autoplay `tap` (3 frames) sit inside the window.
- **Repro.** The `suite_input` rift cases, written first, fail. SKACC `rift_taps` shows `none` to 4 frames.
- **Done.** Rift fires on the press edge, like burst and well. A press `can_act()` refuses waits in SPEC
  §3's 6 f buffer (real clock) and fires on the first allowed tick; one helper serves every press-edge
  skill (rift, anchor, burst, well, lance). Remove the `lock_on` cancel, `_rift_held`, `od_chord` (only
  reader `:54`) and the L3 comments (`:3-5`, `:42-43`).
- **Gate.** In `suite_input`, holds of 1, 2, 3 (`h.tap`) and 4 ticks, KEY_C down/up a frame apart, pad
  RB+B for a frame, and a press with `lock_on` held: each fires `skill_used(rift_step)` ≤ 2 ticks after
  the press and moves the mech. A press 4 f before `can_act()` opens fires ≤ 2 ticks after it opens; one
  8 f before never does. SKACC `rift_taps`: FIRED, lat ≤ 2 ticks, every row (holds 1–20, key, pad, auto).

## 2. The Undertow Well ignores the lock and flies through bodies, so its target is never primed — major
- **Defect.** `undertow_well.gd:91-108` `begin()` lobs the core at `ctx.aim_point()` (`:95`), never at
  `ctx.lock_target()`, which Fins, Skyhook, Rift and Plunge use. `_hit()` (`:151-156`) tests only
  `MASK_SIGHT`, so the core passes through enemies and arms on the ground behind them. A juggernaut
  hard-locked at 42 m: armed 100–103 m out, 0 primed. No lock, reticle on its body: armed 54.5 m from it,
  0 primed. Nothing emits `Events.prime_collapsed` (`core/events.gd:25`, yours), though audio listens.
- **Repro.** Headless: a dummy locked at 42 m, `h.aim.point` 110 m behind it, `try_well()`. The well arms
  ~100 m out (the `well_range` clamp, `:97-98`), far past the dummy, which stays unprimed. SKACC `well`
  ports `well_lock_probe2.gd` beats A2/B2/C2.
- **Done.** With a hard or soft lock, the core lands on the locked actor's ground position. Without one it
  goes to the aim point, and a core that meets an enemy arms there, on the ground under it. `detonate()`
  emits `prime_collapsed(center, n)` once per call when n > 0. It spends primes with `clear_prime()`
  (`enemies/status_component.gd:211`) so the HUD plate hears it; the comment at `:275-276` predates it.
- **Gate.** Headless, failing today: the lock case, the reticle-on-body case, one `prime_collapsed` per
  detonation. SKACC, juggernaut 42 m ahead: (a) `lock_on`, 1 s, tap G → armed ≤ 24 m (flat) from it, primed
  in 1.5 s; (b) no lock, reticle on its body → same; (c) then fire held 1.3 s (rifle stage 2) into it →
  `well.collapsed_count()` +1, one 900 `collapse` hit, one `prime_collapsed`. Stills: the dome, the implosion.

## 3. Zenith Lance: a press fires it, and it reads as a beam from the gameplay camera — minor
- **Defect.** Input: `skill_input.gd:108-126` puts `od_hold` (0.25 s) on the Lance too, so a V tap during
  Overdrive does nothing (SPEC §3: "V hold 0.25 s / V"). Look: from the gameplay camera the beam is a
  white core plus a flat translucent pink wedge fanning from the hand with hard straight edges
  (`~/m/mc-accept/captures/acc_spec-coverage_34_lance_beam.jpg`, `_35_…`); the r3 stills out-turn it
  (`tests/showcase.gd:401-406`). **Prime suspect, verify before tuning:** `fx/fx_beam.gd:21-24` puts the
  quarter-turn that lays the Y-axis `CylinderMesh` along the beam on `_pivot`, and `line()` (`:73`)
  overwrites `_pivot.global_transform` every frame. The tube's axis may then lie across the beam, making
  every `SkillFxBeam` an elliptic slab with flat caps (print `_mesh.global_basis.y` against `to - from`).
  `beam.gdshader:7-10` still describes a unit box, `:28` flows on `local_pos.z`; layers: `zenith_lance.gd:19`.
- **Repro.** Headless: OD active after the ignition, V held 1 tick. `zenith.is_charging()` stays false.
- **Done.** During Overdrive a press edge fires the Lance. The hold only ignites, and audit #8 holds: one
  long hold ignites and never fires. From the gameplay camera the beam reads as a round beam of light with
  depth, concentric white/gold/red, with no flat sheet, hard edge or wedge. Check every other `fx_beam` user.
- **Gate.** Headless, failing today: with OD active, V for 1 tick, `h.tap`, KEY_V and pad L3+R3 each start
  `zenith.is_charging()` ≤ 2 ticks after the press. A 1 s hold from a full meter ignites without firing. A
  press during the ignition does nothing and does not stick. If the suspect holds, the tube's axis lies
  along `to - from`. SKACC `lance` (hold V, release, tap V): stills from the real third-person rig at its
  gameplay arm (42 m; 46–52 m boosting; 40–60 m behind the hero), beam converged, `cam_dist` printed.
  Take them level down the runway, mid-sweep at ≤ 40°/s, pitched ~15° into the r15 sky, and one
  first-person frame (no whiteout); if `fx_beam` changed, fin beams and cable at combat range, before/after.

## 4. Corona Fins: the docked blades stay on the back while the fins fly — minor (hero-v3 API)
- **Defect.** `corona_fins.gd:138-158` `_hide_docked()` hides `MeshInstance3D` children of the wing
  sockets. On Hero3 the seven blades are bones in one skinned mesh (`hero3_rig.gd:7-13`), so nothing hides:
  at +0.3 s and +0.8 s the full fan is on the back while the fins hit a spitter at 60 m
  (`~/m/mc-accept/captures/acc_spec-coverage_10_fins_flight.jpg`, `_11_…`). It also strips every blade on
  any send, but SPEC §6 S4 makes the fins the hero's own blades: 2 fins out means 2 blades gone.
  `fins.docked_blades_hidden` (`suite_fins.gd:56`) passes only on the stand-in's box blades.
- **Repro.** `CLIP fins`. `captures/skills_fins_volley.jpg` still shows the full fan.
- **hero-v3 owns `game/player/model/hero3/**` (its r8 implements the signature you request, so post it
  early): do not edit it.** In Requests, give the exact HeroModel signature (e.g.
  `set_drones_docked(mask: int)`, bit i = `Drone_{i+1}`) plus a read-back. Hiding must cover the blade AND
  the cyan tip `hero3_glow.gd` attaches to it. Include the fin↔drone table (7 drones: `Drone_1-4` =
  `wing_l`, `5-7` = `wing_r`; `fins_max` stays 6, 3 fins per side, so one `wing_l` blade always stays
  docked) and, optionally, drone positions so a fin leaves its own blade (`Hero3Rig.drone_tip()` is not on
  the model API). Call it behind `has_method`.
- **Done.** A fin's blade is hidden from launch until that fin docks (flying, returning, Ward, respawning);
  `reset()` shows all; the stand-in implements the method; no second hiding path unless a live model needs one.
- **Gate.** Headless on the stand-in, failing today: 2- and 6-fin sends hide exactly the mapped drones; the
  Ward hides what it borrows; a shot-down fin stays hidden until it respawns; all show after docking and
  `reset()`. Headless on `res://player/model/hero3/hero3_model.tscn`: a PENDING line in the TEST summary
  while Hero3 lacks the method (never a silent pass); the mapped drones read back hidden once it exists.
  SKACC `fins`: stills 0.3 s after a real Z tap at a target locked ~60 m out, and 0.3 s after the dock.

## 5. The Skyhook asks for a socket the contract does not have — minor
- **Defect.** `skyhook_anchor.gd:85`, `:400` and `:413` ask for `muzzle_l`, which is in neither CONTRACTS
  §5 nor `Hero3Sockets.TABLE`. Each grapple tick logs `Hero3Rig: no socket named muzzle_l` (225 in one
  beat), and `ctx.socket()` falls back to the chest, so the cable leaves the torso (`…_10_anchor_reel.jpg`).
  The stand-in hid this: `rig_model.gd:6-7` lists `muzzle_l`, and its `socket()` (`:44-50`) accepts any name.
- **Repro.** `CLIP anchor 2>&1 | grep -c 'no socket named'` prints more than 0.
- **Done.** The cable leaves a §5 socket on the left arm, `hand_l` (the well throws from it) or `shield_l`;
  say which, and why. The comments at `skyhook_anchor.gd:5` and `cable_visual.gd:4` follow. The stand-in
  offers exactly the §5 names, and a test fails when a skill asks for any other.
- **Gate.** That test fails today and passes on yours. The repro prints 0. The SKACC `anchor` stills show
  the cable leaving the left arm.

## Gates
- `tools/godot.sh check --only=res://combat/skills/`: 0 errors, 0 warnings; full `check`: nothing from skills.
- `tools/godot.sh test res://combat/skills/tests/test_skills.gd`: 0 failed, more checks than r3's 188, and
  the hero3 fins line reads PENDING or PASS.
- Every new check FAILS on today's code and PASSES on yours: write it first, paste both summaries into
  status (not from a worktree: `tools/godot.sh` there imports the live tree); no "fixed" without the rerun.
- SKACC, all beats: every line `ok=1`, 0 engine/script errors, 0 `no socket named`, no NANWATCH from skills.
- Stills (`captures/skills_r4_*.jpg`, contact sheet in status): rift after a 1-tick tap; well locked and
  the collapse; lance ×4; fins out and docked; anchor; beams before/after if `fx_beam` changed.
  `CLIP all` still runs clean.
- No file over 600 lines, splits in their own commit; an r4 status section (evidence per item, both test
  runs, How to verify, Requests). Lead cross-check: the acceptance beats in `~/m/mc-accept` once synced.

## Coordination
- In parallel: hero-v3 r8 (`game/player/model/hero3/**`) and the other units briefed from this pass, with
  uncommitted and staged files in this tree. Commit with the paths on the commit itself (`git add` only your
  new files, then `git commit -m … -- <paths>`), never `git add -A`.
- No ownership exceptions: everything is in `game/combat/skills/**`. Read hero3, camera, aim and core, but
  edit none of them. If a fix seems to need `core/pad_input.gd`, `input_setup.gd` or `events.gd`, ask.
- Requests go in `status/skills.md` Requests. This round tell hero-v3 the item 4 API; trailer that the V tap
  at 3.4 s in `tl_c_od.json` now fires the Lance; audio that `timeline_reel.json` t=46 taps rift_step, which
  now blinks ~44 m (its overdrive taps at t=50/68.8 stay no-ops: ignition is a hold); flow that the
  tutorial's skills step (`tutorial_director.gd:31`) prompts rift_step, so a quick tap now counts.
- The lead's, not yours: when hard-locked, the reticle ray runs ~12 m right of the target (camera-aim). The
  well's lock path must not depend on it. Windowed slots are shared, so run SKACC beats selectively.
