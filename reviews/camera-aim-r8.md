# camera-aim r8 — lead brief: the pad's D-pad ← → does not switch the lock

## Why
The acceptance pass found a dead binding on a core verb. A hard-locked pad player who has read the
Controls page (`锁定 / 切换 Lock-on … R3 / D←→`, `ui/menus/menu_root.gd:56`) presses D-pad → and
nothing happens: no switch and no lock sound. The only pad switch left is the right-stick flick, which
also turns the view. SPEC §3 (row "Lock-on toggle / switch | … | R3 / RS flick, D-pad ← →") and
CONTRACTS §5 ("lock switching = flick or `lock_prev/lock_next`", given to you in
`reviews/camera-aim-r2.md:8`) both promise it. Two probes found it independently, and the verifier
reproduced it on the real `main.tscn` with raw pad events.

**Re-check first.** The findings were made on the frozen copy at b5d26d4, and the tree has moved on
since (your r7 landed). Re-check each claim against HEAD before you change anything, and if one is
already fixed, say so in status with the evidence. At HEAD 79c69d3 a re-grep still finds no consumer,
and `player/aim/` has had no commits since b5d26d4.

## 1. [major] D-pad ← / → never switches the hard lock
This merges `pad-dpad-lock-switch-dead` (verified) and `aim-dpad-lock-switch-unbound` (the same
defect, found by the verb sweep).
- **The defect:** PadInput turns D-pad ← / → into `lock_prev` / `lock_next` and holds the action while
  the button is down (`core/pad_input.gd:22-23`, `:70-79`; PAD_ONLY at `core/input_setup.gd:56`).
  Nothing reads either action: `AimSystem._physics_process` reads only `lock_on`
  (`player/aim/aim_system.gd:42-43`). `switch_target()` (`:142`) is reached only from
  `CameraRig._on_flick` (`player/camera/camera_rig.gd:163-167`), which the look channel fires for a
  mouse or stick flick (`camera_look.gd:72-78`, `:99-107`). No test caught it: `test_aim.gd:116,124`
  call `switch_target()` directly, and no test sends an action or a device event.
- **Repro (live tree, from `~/m/mecha-city`):**
  ```
  grep -rnw --include='*.gd' --exclude-dir=.godot -e lock_next -e lock_prev game
  # only core/input_setup.gd, core/pad_input.gd and ui/hud_glyphs.gd: no consumer
  mkdir -p game/tmp/acc && cp ~/m/mc-accept/game/tmp_accept/verify-pad-dpad-lock-switch-dead/acc_dpad_switch.gd game/tmp/acc/
  tools/godot.sh test res://tmp/acc/acc_dpad_switch.gd -- --sandbox --no-enemies --skip-menu \
    --stub=flow,boss,post --timeout=800
  ```
  The probe loads the real `main.tscn`, hard-locks the centre of three dummies (−18°, 0°, +18°) with a
  raw R3, and sends raw pad events through `Input.parse_input_event`, so PadInput translates them. At
  b5d26d4: `lock_next` just-pressed on 1 tick, `lock_changed` +0, `FAIL D-pad RIGHT switches the hard
  lock to acc_right … got acc_centre`, the same for LEFT and for `Input.action_press(lock_next)`, then
  `DPAD-SWITCH FAIL: 3 defect checks, 3 failed; 0 control failures (run valid)`. Its RS-flick controls
  pass. The probe's third check also covers the verb sweep's `lock_switch` beat. `game/tmp/` is
  git-ignored; delete the copy after the run, because every unit's `check` compiles all of `res://`.
- **Done means:**
  - **Same selection as the flick:** while hard-locked, one → press moves the lock to the target a
    right flick would pick, and one ← press to the one a left flick would pick. Reuse
    `switch_target(±1)`; do not write a second selection.
  - **One switch per press:** a D-pad held for 0.25 s switches once and fires exactly one
    `Events.lock_changed`. Audio plays a lock sound and a voice line for each event
    (`audio/event_router.gd:186`).
  - **No hard lock:** a press changes nothing, and it does not acquire a lock either.
  - **Only when a flick could:** during a cinematic both flick paths are dead. The rig returns at
    `camera_rig.gd:214-224`, before `_update_look`, and `camera_cinematic.gd:56` disables look. A
    D-pad press must not switch then either.
  - **KB+M is unchanged:** switching there stays the mouse flick (SPEC §3). Do not bind the wheel: it
    is weapon swap (CONTRACTS §5); SPEC §5's "mouse wheel" is stale and the lead's to fix. Update
    `switch_target`'s comment (`aim_system.gd:140-141`), which names only the flick.
- **Where it lives is your call, but your test must reach it.** The verifier suggests AimSystem,
  beside the `lock_on` read. The `test_aim` player is a bare `Node3D` with no `aim()`
  (`test_aim.gd:42-45`), so the rig's `_aim()` (`camera_rig.gd:351-355`) finds nothing there. A
  consumer in the rig therefore needs a test on the real PlayerMech (`main.tscn`, `--sandbox`).
- **Test (new):** write it first, run it on HEAD's code and paste the FAIL lines; then fix it and paste
  the PASS lines. Its switch checks must FAIL on the old code and PASS on yours.
  1. Hard-lock the centre dummy.
  2. Send a RAW `InputEventJoypadButton` `JOY_BUTTON_DPAD_RIGHT` through `Input.parse_input_event` and
     `Input.flush_buffered_events`. Hold it 30 ticks, then release.
  3. `hard_target()` must be the nearest dummy on the right (`_nearest_on_side`, `test_aim.gd:238`),
     with exactly one `lock_changed`. `DPAD_LEFT` must bring it back.
  4. A press changes nothing with no lock or inside a `request_cinematic`; the old flick checks pass.
- **Measure and report; do not change (INFO lines, not gates).** Discrete presses will hit two edges
  of the shared selection more often than flicks do. Drive both through the D-pad and record what
  happens, with numbers, in Known issues. The lead picks the rule after this round.
  - **→ at the right end of the row:** the wrap (`aim_system.gd:166-169`, `|dx − 360·dir|`) appears
    to pick the nearest target on the LEFT, so repeated → presses would bounce between the last two.
  - **A target about 40° off the view:** the switch pool (`:150`) has no cone limit, but
    `_update_hard` drops a lock outside ±30° yaw (`:181-184`). The switch may be undone on the next
    tick.
- **Gate:** the new checks PASS, `test_aim` has 0 failures, and the probe prints
  `DPAD-SWITCH PASS: 3 defect checks, 0 failed; 0 control failures (run valid)`. Run the probe
  yourself before you report.

## 2. [minor, contract only] `CameraRig.eye_residual()` goes into the contract
Request 0g is answered: the lead adds your r7 telemetry (`camera_rig.gd:115-118`) to the CameraRig
paragraph of `docs/CONTRACTS.md`. No code change. In your r8 status section, give the lead a line to
paste:
- **Signature:** `func eye_residual() -> float`.
- **Units and meaning:** metres between the rig and the model's raw `cockpit` socket, written inside
  `_follow` in the tick that places the camera (`:276-281`).
- **What it returns in each case**, read from the code:
  - in third person and during the 0.35 s blend: reset at `:262`, written only above `fp_t` 0.99;
  - during a cinematic: the rig returns at `:224` before `_follow`, so it looks like it holds its last
    value;
  - with no player.

Mark 0g answered. If a case should read differently, say so in Requests; do not change it this round.
**Gate:** the lead pastes your line into CONTRACTS, and a missing or vague case comes back to you.

## Gates
The lead re-runs these on HEAD after your commits (copy the probe as in item 1):
```
tools/godot.sh test res://player/aim/tests/test_aim.gd                 # 0 failures, incl. the D-pad checks
#   if your checks live in another suite or on main.tscn, give its exact command in status
tools/godot.sh test res://tmp/acc/acc_dpad_switch.gd -- --sandbox --no-enemies --skip-menu \
  --stub=flow,boss,post --timeout=800                                  # DPAD-SWITCH PASS ... (run valid)
tools/godot.sh test res://player/camera/tests/test_camera.gd           # 0 failures
tools/godot.sh test res://player/camera/tests/test_camera_audit.gd     # 0 failures
tools/godot.sh test res://player/camera/tests/test_camera_feel.gd      # 0 failures
tools/godot.sh test res://player/camera/tests/test_camera_large.gd     # 0 failures
tools/godot.sh test res://player/camera/tests/test_camera_cockpit.gd   # 0 failures
tools/godot.sh test res://player/camera/tests/test_camera_flight.gd    # 0 failures
tools/godot.sh test res://player/camera/tests/test_camera_flow.gd -- --sandbox --flow --spawn=0,1,60
tools/godot.sh check --only=res://player/camera/,res://player/aim/    # 0 errors
```
- **Captures the lead looks at:** a before/after pair in the camera demo. The first frame has the HUD
  lock marker on the centre dummy; the second has it on the next dummy to the right, with the camera
  following:
  `tools/godot.sh shot --scene=res://player/camera/demo/camera_demo.tscn --sandbox --out=camera-aim_dpad_switch --times=3.0,4.5 --lock --pulse=lock_next@3.5`
  Move the times if the lock is not up by 3.0 s. `--pulse` presses the action directly; the probe
  covers the PadInput path. Put both frames in status.
- **House rules:** no file over 600 lines (`aim_system.gd` 326, `test_aim.gd` 278, `camera_rig.gd` 433),
  no dead code, commits with an explicit path list, an r8 section in `status/camera-aim.md` (Done, How
  to verify, Evidence, Known issues), and no "fixed" without the rerun output beside it.

## Coordination
- **No ownership exception.** The fix lives in `player/aim/**` or `player/camera/**`. Leave these alone:
  `core/**` (PadInput and InputSetup already do their half), `ui/**` (the Controls row becomes true
  once the D-pad works) and `docs/**`.
- **lead:** the PadInput half (D-pad ← / → reaching the actions) is the lead's
  `core/tests/test_core_input.gd` (finding `input-pad-bindings-untested`); your test covers the consumer.
- **hud:** `ui/hud_glyphs.gd:32` gives `lock_prev`/`lock_next` the keyboard glyphs "MMB"/"WHEEL". Both
  are wrong (no keyboard binding exists) and not yours; if a capture shows one, name it in Requests.
- **Other briefs from this pass use your API.** flow's respawn fix calls `snap_to_player()` and points
  the look along the checkpoint's facing; skills' Undertow Well fix starts reading the lock target.
  Keep `snap_to_player()`, `set_look()` and `hard_target()` exactly as they are.
- **hero-v3** has uncommitted work in `game/player/model/hero3/**`. Stage only your own paths.
- **Not this round:** a side note in another finding says that while hard-locked, the reticle ray runs
  about 12 m right of the target: `camera_lock.gd` `track()` aims from the Pitch pivot, but the aim ray
  starts at the Arm tip, which `SHOULDER` puts 12 m to the right. The lead routes it separately. Do not
  change `camera_lock.gd`; if your captures show the offset, put the numbers in Known issues.
- **Requests** go in the Requests section of `status/camera-aim.md`.
