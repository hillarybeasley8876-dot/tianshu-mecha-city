# audio r7 — lead brief: sounds for the new feel rows, and the beat clock flake

## Why
Since r6, feel r5 and r5b, weapons r5, mech-move r7 and enemies r11 added FEEL rows and events. Some of
them play no sound yet, or only through a warning:
- `last_stand` (`mech_damage.gd` `_last_stand()`), the 0.5× slow-mo when HP first crosses 15 %;
- `boss_kill`: the brood titan's death. `brood_titan.gd:285` still calls `Audio.play(&"kill_large")`
  beside the new row. Decide whether the row's sound replaces it or layers with it, and make the death
  sound like a climax;
- the three gatling vent rows: `gatling_vent_good`, `gatling_overheat`, `gatling_jam` (weapons r5,
  rows in `docs/FEEL.md`). Map `gatling_vent_good → gatling_vent` in `event_map.gd`, as decided in
  `reviews/r16-lead-decisions.md`;
- `near_miss` (enemies r11, `EnemyNearMiss`): a doppler flyby. FEEL.md has the row; check that it
  reaches a sound;
- the skate trail (feel r5b, `FxSkateTrail`): a grinding scrape loop while the boots spark on the
  ground skate. Optional: add it only if it fits the mix budget.

tooling r1b also found a flake in your suite: `test_audio_clocks.gd:171`, `FAIL the beat clock reaches
the requested clip (110.0 BPM)`, where green runs print 145.6 BPM (`clip_bpm(&"boss")`). It failed in 1
of 4 full passes and passed 4 of 4 when run alone. It looks order-dependent: state left over from the
previous suite in the same pass.

## House rules (the user's machine)
- You are the ONLY worker. Headless only; one Godot process at a time.
- Your listening is the job: `tools/sfx/` renders to files, and you can inspect waveforms and loudness
  without a window.
- Never use git stash. Commit with explicit paths. No audio file is committed without its manifest row
  (`credits_check.py` stays clean).

## Do
1. Wire every id above to a sound: an existing bank sound or a new layered composite from your CC0
   sources. Add the `FEEL_IDS` / `OVERRIDES` / `event_map` entries. No unknown-id warning may remain;
   run `--audio-trace`.
2. Root-cause the beat clock flake (shared state between suites, a static, a timer) and fix it. Gate:
   20 back-to-back runs, plus a pass of the full `tools/suites.sh --only=audio,audio_clocks,...` table
   in the same order as the full run.
3. `credits_check.py` stays at 0 unmatched. hud's credits page reads the manifest.

## Gates
- `test_audio`, `test_audio_clocks` (20× green), `audio_call_sites` and `audio_enemies` pass.
- `test_feel_rows -- --audio-trace` passes with no unknown-id line.
- `credits_check.py` is clean, and `check --only=res://audio/` is clean.
- `status/audio.md` gets an r7 section. List a short listening reel (rendered to a file, no window) of
  each new sound under Evidence.
