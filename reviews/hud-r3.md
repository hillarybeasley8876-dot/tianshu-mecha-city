# hud — review r3 (lead) — PASS

Verified: `check` 40 files 0 errors; `test_hud` 170/0 (prompt API, twelve-id table, canopy forwarding, credits).
The prompt queue follows CONTRACTS §6 and free play shows nothing; the credits page reads the manifest and labels
our synthesis and the AI content honestly; the compass label has a proper outline.
Lead fixes from your requests: the low-armour widget no longer calls `Audio.play(&"heartbeat")` — the audio
unit's `heartbeat_loop` owns that sound, now at the same 35 % threshold (`Audio.LOW_ARMOUR`). The
`hit.source_kind` error is gone from audio's router (r2). Spire/boss groups: flow r2 and boss are on them.
