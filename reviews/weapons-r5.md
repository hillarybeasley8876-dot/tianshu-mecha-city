# weapons r5 — lead brief: the cockpit gatling flash, and vent results that play nothing

## Why
The acceptance pass found that a **good vent** is silent, and that is the 12-frame window most players
will hit. `gatling.gd:122` plays `gatling_vent_good`, which has no FEEL.md row, no `fx/events/` resource
and no sound: the press lands, the heat clears 0.8 s later, and nothing tells the player it worked. On a
re-read of the gun, **overheat** (`:193`) and **jam** (`:134`) have the same defect: no row and no `.tres`.
They only make a noise because the sound bank happens to share their names. In the game the FeelDirector
logs `no FeelEvent for id 'gatling_overheat'` (`~/m/mc-accept/tmp/acc/spec-coverage/verbs_r2.log:1626`)
and plays no shake, steam or rumble. The vent is the gatling's skill beat, so perfect, good and miss must
each read and sound different.
The lead adds a second item, from the trailer (`status/trailer.md`, Known issues and Request 2). In first
person the gatling's muzzle flash is a flat yellow disc about 30 % of the frame tall, under the glass
HUD's weapon readout (`captures/trailer_fp2_t4_4.jpg`). It is the one thing that makes the cockpit gatling
shot unusable, and any player who presses B mid-fight sees it.

**Re-check first.** The finding was made on the frozen copy at b5d26d4. At HEAD 79c69d3, `game/combat/**`,
`game/fx/**`, `game/audio/**`, `game/core/**` and `docs/FEEL.md` are byte-identical to it (`git diff --stat`
is empty); only the first-person camera changed (camera-aim r7's chassis cull). Run each repro on HEAD
first. If one no longer reproduces, say so in status and paste the output.

## 1. [major] In first person the gatling's muzzle flash covers a third of the frame
- **Defect.** Every round calls `ctx.sparks.impact(muzzle, dir, Color(1.0, 0.8, 0.4), 2.2, 0.07)`
  (`gatling.gd:186`). That draws SparkPool's sphere: a 0.5 m-radius 10×6 SphereMesh with
  `BeamPool.additive_material` (unshaded, additive), built at `spark_pool.gd:38-45`, which grows to 2.2 m
  in 0.07 s (`:127-143`, `:191`). `impact()` draws that sphere itself, with no FxBridge route, so it is the
  gun's flash in the game too, not the fallback the pool's header suggests (`:3-5`). It is sized for the
  42 m third-person arm (≈ 5 % of the frame) and drawn unchanged in the cockpit. camera-aim r7 measured
  `muzzle_r` 6.0 m from the lens while firing (`status/camera-aim.md:28`), and 2.2 m at 6 m under the 62°
  first-person FOV is ≈ 30 % of the frame height. Nothing under `combat/` reads the camera mode:
  `grep -rn "first_person\|camera_mode" game/combat` finds only the stand-in `tests/rig_aim.gd:47`.
  FEEL.md:9's first-person rule ("VFX opacity −40 %") never reaches the weapons' StandardMaterial3D pools,
  because fx applies it through the `fx_opacity` shader global (`vfx_library.gd:67-68`).
- **Repro on HEAD.** Run the trailer's take `c_fp` (flags from `game/trailer/shots.json`; `camera_toggle`
  at 1.8 s, `fire` from 2.8 s):
  `tools/godot.sh drive --scene=res://trailer/shot.tscn --timeline=res://trailer/tl_c_fp.json --skip-menu --god --tod=0.6 --stub=flow --spawn=-540,10,570,45 --trailer-pack=30,ripper:4,mantis:1 --trailer-hud=1 --out=weapons_r5_fp_before --shots=3.4,3.8,4.4,5.0,5.6`
  Then prove which draw call makes the disc. Run camera-aim's `player/camera/demo/rig_probe.tscn` on the
  same timeline and flags, without the `--trailer-*` flags and with `--fp-hide=Sparks`: the disc must
  vanish. `--probe-dump-at=4.4 --probe-dump-radius=10` lists what sits near the lens. If the disc stays,
  report that before you change any code.
- **Done means.**
  - **Scale it by camera mode (the lead's call).** In first person the flash is ≤ 8 % of the frame height
    at the 62° FOV (≈ 0.6 m at 6 m), drawn at FEEL.md:9's ×0.6 opacity. It reads as a flash at the gun,
    not as a disc. In third person it stays exactly today's 2.2 m.
  - **The mode comes only from camera-aim's public API:** `Events.camera_mode_changed`
    (`core/events.gd:36`, emitted at `camera_rig.gd:112`) and/or `AimSystem.is_first_person()` through
    `ctx.aim` (`aim_system.gd:103`, `weapon_context.gd:15`). The size is right from the first round after
    a toggle, in both directions, and for a mech that is already in first person when WeaponSystem readies.
    Do not cull the pools in first person: tracers, casings and impacts stay visible.
  - **The rest of the kit in first person: check it, fix only what fails.** A new
    `tests/timeline_fp_kit.json` on the `c_fp` flags films a rifle tap; a stage-2 release (the
    3.2 m × (1 + stage) muzzle ring, 12 m shock ring and 7 m glow, `rifle_tuning.gd:38-47`); a gatling
    burst with `aim` held (ADS is 45°, so the flash reads about 1.5× larger); and a Hailstorm salvo (the
    launch puffs and the 4.2 → 12.6 m smoke at the rails). Anything that whites out the cockpit or covers
    the crosshair goes through the same camera-mode path; for anything that passes, show its frame.
- **Test (new; it must FAIL on HEAD).** Drive the real WeaponSystem with input actions, as
  `suite_gatling.gd` does. Set first person the way your code reads it (the signal, or a settable
  `RigAim.is_first_person()`), then hold `fire` for 1 s. Record the largest muzzle flash the pool draws,
  not counting the impact sparks the same pool draws at the target. Add a read-only accessor if you need
  one, as `MissileVisuals.live_samples()` does. Expect ≤ 0.6 m in first person, 2.2 m in third, and
  2.2 m again after toggling back. On HEAD the first-person value is 2.2 m.
- **Gate.** The test; the `c_fp` drive re-shot as `weapons_r5_fp`, next to `_before`; a third-person
  before/after pair at the same spot that looks the same (`tl_c_gatling.json` on the `c_fp` flags,
  `--shots=2.2,2.6,3.0,3.4`); and the kit stills.

## 2. [minor] The good vent, the overheat and the jam are not FEEL rows
- **Defect.** Of the 13 ids the weapons unit passes to `Feel.play`, three have no FEEL.md row and no
  `fx/events/<id>.tres`: `gatling_overheat` (`gatling.gd:193`), `gatling_vent_good` (`:122`) and
  `gatling_jam` (`:134`). For each one the FeelDirector warns once and plays nothing
  (`feel_director.gd:60-67`). The audio router maps the id to a bank sound (`event_router.gd:56-60`,
  `event_map.gd:19-23`). The bank has `gatling_overheat` and `gatling_jam`
  (`audio/tables/table_weapons.gd:30-34`), so those two sound. It has no `gatling_vent_good`, so the good
  vent is silent and logs `Audio: unknown or empty sound id 'gatling_vent_good'`.
- **Repro on HEAD.** This prints that warning, with a backtrace to `gatling.gd:122`:
  `tools/godot.sh test res://combat/weapons/tests/test_weapons.gd 2>&1 | grep -A3 gatling_vent_good`
  From `game/`, this prints `NO ROW` for `gatling_jam`, `gatling_overheat` and `gatling_vent_good`:
  `for id in $(grep -rhoE 'Feel\.play\(&"[a-z0-9_]+"' combat/weapons combat/projectiles | sed -E 's/.*&"//; s/"$//' | sort -u); do [ -f fx/events/$id.tres ] || echo "NO ROW $id"; done`
- **Decision (FEEL.md): three new rows, not a borrowed one.** FEEL.md has one row per `Feel.play` event,
  and gameplay code never hand-rolls juice (FEEL.md:1, :5). The only candidate is `gatling_vent_perfect`
  (FEEL.md:20), and it is the reward cue: hiss + chime, white ring, +3°. At a low strength the director
  still plays the chime (−6 dB under 0.5, `feel_director.gd:203-206`) and the router still plays
  `gatling_vent_perfect`, so a good vent would sound like a quiet perfect. The bank already has the three
  sounds. Good is the hiss alone, `gatling_vent` (the perfect row layers it as `gatling_vent_hiss`); jam
  is `gatling_jam`; overheat is `gatling_overheat`.
- **Who lands what.** The rows are the lead's (FEEL.md). The `.tres` files are feel's. The sound mapping
  is audio's (`event_map.gd`): add the ids to `FEEL_IDS` and add the `OVERRIDES` entry
  `gatling_vent_good → gatling_vent`, without which the router keeps warning. File the Request, with the
  three rows' content, at once. Your new checks go in when the rows land. Until then keep the suite
  green: keep the checks local, put their FAIL output in status, and do item 1.
- **Done means.** Each result plays its own row, and the good vent requests a sound. The suite log has no
  `gatling_vent_good`, `no FeelEvent` or `unknown or empty sound id` line. Each vent result gets its sound
  from one place only. A perfect vent also calls `Audio.play(&"gatling_vent_perfect")` directly
  (`gatling.gd:118`), on top of the row's chime and the router. If `--audio-trace` shows the row covers
  it, delete the line. The good vent gets no direct `Audio.play`.
- **Test (new).** Instance the real `res://fx/feel_director.tscn` for these checks only, so the perf suite
  still measures what it did. An overheat and the perfect, good and miss results each fire `event_played`
  (`feel_director.gd:15`) for their id, `warned_unknown()` (`:127`) stays 0, and the good vent requests a
  sound (`Audio.request_counts()`, `audio.gd:216`, counts under `--audio-trace`). Add a call-site check on
  the pattern of `audio/tests/test_audio_call_sites.gd`: every literal `Feel.play(&"…")` id under
  `combat/weapons` and `combat/projectiles` is in `FeelTable.ids()` and has its `.tres`. Show both FAIL
  with the three new `.tres` moved aside (uncommitted), and PASS with them back.

## Gates
The lead re-runs these on HEAD after your commits:
```
tools/godot.sh test res://combat/weapons/tests/test_weapons.gd -- --audio-trace   # TEST <n> checks, 0 failed (121 at HEAD + yours)
tools/godot.sh test res://combat/weapons/tests/test_weapons.gd 2>&1 | grep -E "gatling_vent_good|no FeelEvent|unknown or empty sound id"   # nothing
tools/godot.sh test res://fx/tests/test_feel.gd                 # PASS with the new rows
tools/godot.sh test res://audio/tests/test_audio.gd             # PASS: FEEL ids and call sites resolve
tools/godot.sh check --only=res://combat/weapons/,res://combat/projectiles/   # 0 failed, 0 warnings
tools/godot.sh drive --scene=res://combat/weapons/tests/integration.tscn \
  --timeline=res://combat/weapons/tests/timeline_integration.json --sandbox --nan-watch \
  --out=weapons_r5_int --shots=1.75,3.85,6.0,9.15,9.6         # DRIVE done ... errors=0, no warning from combat/
```
Item 2's one-liner must print nothing. If a check needs another flag, give its exact command in status.
- **Captures the lead looks at.** One sheet each, with the paths in status: first person before/after
  (`weapons_r5_fp_before_t*`, `weapons_r5_fp_t*`), third person before/after, the first-person kit stills,
  and the `--fp-hide=Sparks` frame that identified the disc.
- **House rules.** A file over 600 lines is split first, in its own commit; none is close (`gatling.gd`
  257, `spark_pool.gd` 210, `weapon_system.gd` 198). No dead code. Commit with an explicit path list.
  Tests drive the real path. Never write "fixed" without the rerun beside it. `status/weapons.md` gets an
  r5 section: the causes, the FAIL→PASS lines and the capture paths. How to verify still says 114 checks,
  but the suite prints 121: update it with the new count.

## Coordination
- **Ownership.** Item 1 is all yours (`combat/weapons/**`, `combat/projectiles/**`). Item 2's rows are not:
  `docs/FEEL.md` is the lead's, `fx/events/*.tres` feel's, `audio/event_map.gd` audio's. There is no
  ownership exception this round. You may run, but not edit, camera-aim's `rig_probe.tscn` and the
  trailer's `shot.tscn`, timelines and `tools/trailer/sheet.py`. Never write into `captures/trailer/`.
- **mech-move r7** may add ONE guard line at the top of the input read in `weapon_system.gd`
  `_physics_process` (its dead-mech exception), and will file a Request. Keep your edits out of
  `:105-124`, and if the line lands, keep it.
- **feel r5** is in `game/fx/**`. The lead gives `Feel.play` an optional `actors` argument through a new
  4-argument signal. The 3-argument `event_requested` stays, so your calls, and any test that listens to
  it, keep working.
- **camera-aim r8** (pad lock switching) is running. Take the camera mode from its public API only. If you
  need more (the eye position, the blend), ask in Requests.
- **hero-v3** has uncommitted work under `game/player/model/hero3/**`: stage only your own paths.
  **trailer** re-records `c_fp` after this lands: write the commit in your status for it.
- **Requests** go in the Requests section of `status/weapons.md`.
