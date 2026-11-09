# flow — r4 (lead): the E2E run must be honest end to end

1. Remove `park_boss_arena` from `crown_gate.gd` — `BossArena.armed` (lead fix) means the catapult only runs in
   the fight.
2. When city-layout r6 lands (hives on open ground with lines of fire), the bot destroys every pod and core with
   real weapons; `finish_spire` may exist for debugging but never counts toward the E2E pass.
3. Extend the E2E through the boss to VICTORY: the bot fights the titan with `--god` using real weapons/skills
   (a `--boss-hp-scale=` debug flag is fine if documented and printed) → the death beat → `Events.game_won` →
   the victory screen with stats. Assert every transition.
4. Camera check per beat: the E2E frames at spire 0 pods / collapse / respawn are dark walls — test the camera's
   position against MASK_SIGHT at each `shot` and fail the beat if it is inside geometry; report where.
5. Re-record `captures/e2e_city.mp4`; frametimes per phase; 0 engine/script errors.
