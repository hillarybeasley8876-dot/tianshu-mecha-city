# mech-move r6 — lead brief: 飞行 never engages from a real double tap

## The bug
The trailer could not film flight (`status/trailer.md`, Known issues and Request 4).
- **Repro:** `game/trailer/tl_s06_flight.json`. A `jump` tap at 0.50 s and another at 0.72 s: 0.22 s
  apart, inside `flight_double_tap` = 0.30 s. The hero never enters 飞行; the boost that follows is a
  ground or air boost.
- **Run the take the way the trailer does:**
  1. Find the flags in `game/trailer/shots.json` (take `s06_flight`) and in `tools/trailer/render_all.sh`.
  2. Run it with `tools/godot.sh drive` or `movie`.
  3. Read `move_state` and `is_flying()` from the telemetry log.
- **The unit test is not the real path.** `player/mech/tests/test_clocks.gd`
  (`_double_tap_flies(0.26)`) passes. Find what differs from the real path:
  - the autoplay `tap` holds an action for 3 frames through `Input.action_press`, the way a key
    does;
  - the first tap starts a ground jump, and the "hold = hover" logic may consume or relabel the
    second press;
  - an energy or state gate;
  - the `rd` term in `mech_input.gd:56`.

## SPEC (docs/SPEC.md §3, the flight row)
- **Entering:** double-tap jump in the air enters free 3D flight at 50 m/s; boost in flight is
  84 m/s (= assault).
- **Moving:** climb and descend at 20 m/s.
- **Energy:** 80 EN/s and no EN regen while flying; at EN 0 the hero exits into a glide.
- **Ceiling:** +260 m, with a soft push down above it.
- **Combat:** all weapons and skills are usable, and melee becomes the aerial combo.

From the ground, tap–tap must fly: the first tap's jump puts the hero in the air, and the second tap
is the double tap.

## Do
1. **Root-cause it.** Write the cause in your status file with the evidence: a per-frame trace of the
   jump presses, `double_jump`, the state machine and EN around the two taps.
2. **Fix it** so all of these enter flight within 0.1 s of the second press:
   - tap–tap from the ground;
   - a double tap while falling;
   - a double tap while hovering.

   And check the other directions:
   - leaving flight works as SPEC says;
   - a single tap still jumps;
   - holding still hovers.
3. **Test it through the real input path.** Build the test with `Input.parse_input_event` (or the
   autoplay's action presses), as a keyboard would, and cover the cases in item 2. `test_clocks`'
   slow-mo case must still pass.
4. **Make flight read on screen.** Check that the HUD shows the flight state and the EN drain, and that
   the hero model, the thrusters and the camera (`is_flying()` consumers) respond. Film a 10 s strip:
   tap–tap, climb to about +60 m, bank, boost, descend with `descend`, land.
   - If the HUD or the model is missing a cue, name it in Requests with the frame. Do not edit
     `ui/**` or `player/model/**`.

## Gates
- **The timeline:** `tl_s06_flight.json` itself enters flight, shown by the telemetry log.
- **The tests:** the new input-path test passes, and every `player/mech/tests/` suite passes.
- **The checks:** `tools/godot.sh check` is clean, and no file is over 600 lines.
- **The film strip** is in your status file.

When you are done, tell the trailer in your status file which flags film flight. The lead re-records.
