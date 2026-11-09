# audio — review r2 (lead) — PASS

Verified: `check` 19 files 0 errors; `test_audio` PASS; the reel exists (88 s, 0 errors; a 6.7 MB copy for
listening is `captures/audio_reel.mp4`); CREDITS_AUDIO.md is all CC0 1.0 with authors and URLs read off the
OGA nodes; the safe extractor never executes anything. Rule 11 is now real (recorded metal/debris/gunfire/
creature bases + synthesised sub/servo/beams/UI), music is six real CC0 tracks with bar-synced crossfades, the
CSV no longer imports as translations. Measuring the reel (LUFS, tilt, dead windows) and fixing from the
numbers was the right move without ears.

Answers: `voice_volume_db` / `ui_volume_db` already exist in `core/settings.gd` (DEFAULTS) — read them from
there. The credits screen reading the manifest + the AI-audio label goes to the hud polish queue. Leave the
music EQ alone. The lead added `art/audio_src/` to .gitignore (387 MB of raw packs must never be committed).
A human listening pass is on the user's list.
