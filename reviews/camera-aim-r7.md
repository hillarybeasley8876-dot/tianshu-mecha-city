# camera-aim r7 — lead brief: first person goes black; the camera parks after the flow's cinematic

Both bugs came from the trailer job (`status/trailer.md`, Known issues and Requests 2–3). Both block
shots the user asked for, so they are gameplay bugs, not trailer issues.

## 1. First person goes black about a second after `camera_toggle`
- **Repro:** `game/trailer/tl_s05_fp.json` (the flags are in `game/trailer/shots.json`, take `s05_fp`).
  The clip `captures/trailer/shots/s05_fp.avi` shows a clean cockpit view for about 1 s (canopy frame,
  HUD on the glass, P2 THUNDER SPINDLE), and then the frame goes black.
- **What the trailer measured:** `probe_eye.gd` puts the model's `cockpit` socket at 12.2–12.8 m and
  its head bone at 13.0–13.5 m. SPEC §5 says the eye is at 11.5–13.5 m. So either
  `set_first_person` is not using that socket at the END of the 0.35 s blend, or something else covers
  the lens.
- **Suspects to rule in or out with evidence:**
  - the blend's end state;
  - the arm or shoulder in FP;
  - the near plane;
  - the hero's own meshes (and the hero3 armour pieces, the drones, the saber) not hidden from the FP
    camera: cull mask / layers;
  - `cockpit_build` geometry;
  - the weapon switch at 0.5 s.
- **Fix it**, then prove it:
  - **a 30 s first-person run in the city:** walk, boost, dash, jump, melee combo, fire, guard, and
    flight once mech-move r6 lands. Log the eye position against the `cockpit` socket every frame
    (gate ≤ 0.2 m), and log the frame's mean luma. No frame under 0.02 mean luma, unless the eye is
    legitimately looking into a wall: show that frame if it happens.
  - **ACCEPTANCE §3:** the cockpit frame covers ≤ 18 % of the screen, and the glass HUD is readable.
    Contact sheets in the city at `--tod` 0 and at night.
  - **SPEC §5:** the 1st↔3rd blend is 0.35 s and holds the aim point; the crosshair never jumps.

## 2. The camera parks after the flow's opening cinematic
- **Repro:** `--skip-menu --spawn=…` without `--sandbox` and without `--stub=flow`. The flow goes
  straight to the tutorial and calls `CameraRig.end_cinematic()`, but the rig never resumes following.
  The hero walks out of frame while the camera holds a fixed vista. The trailer had to stub the flow on
  every gameplay take.
- **Find why** `end_cinematic()` (`player/camera/camera_rig.gd:380`) does not hand the view back. For
  example:
  - a second shot list started after it;
  - a look-at or hold that `_cine.cancel()` leaves behind;
  - `is_cinematic()` still true;
  - the flow calling the API in an order the rig does not expect.

  Use the REAL flow, not `flow/tests/flow_fake_rig.gd`.
- **Fix it** where the fault is.
  - If the fault is on the flow's side (`game/flow/**`), make the minimal fix there and record it in
    both status files. Flow is idle this round, so there is no conflict.
- **Gate:** in the real game path (`--skip-menu`, the real flow, no stubs), 1 s after
  `end_cinematic()`:
  - the camera is within 1 m of its follow position;
  - the hero is on screen.

  A regression test drives the real intro to that point.

## Gates (both)
- Your tests, the flow tests and `tools/godot.sh check` pass. No file is over 600 lines.
- Contact sheets for both fixes are in your status file.
- Tell the trailer, in your status file, which flags now film first person and the un-stubbed flow.
