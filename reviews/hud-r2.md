# hud — review r2 (lead) — PASS

Verified: `check --only=res://ui/` 39 files 0 errors; `test_hud.gd` 140 checks 0 failed; captures hudr2_* and
hudmenu_* reviewed. Readability at 1600×900 is right (14 px floor, virtual layout, shadows), the telegraph /
hit-marker shape language and the layer-aware radar are what the critic asked for, photosensitive collapses
motion, the title and settings screens are clean and on-palette.

Answers to your requests: the collapsed arm / "first person in flight" came from the flow unit's drop-in
cinematic running inside everyone's `--sandbox` (fixed by contract: `--sandbox` is free play unless `--flow`);
first person is not disabled in flight. `hit.source_kind` is on the audio unit. Spires join `&"hive_spire"`
(flow brief), the boss joins `&"boss"` with `hud_state()` (boss brief, CONTRACTS §6).

Follow-ups for a later polish round (not blocking): re-capture the in-game set in free-play sandbox once flow
lands its fix (the current frames are mid-drop); the compass marker label ("SPIRE −180 m") smears — draw it
with the same outline/shadow as the other floating labels.
