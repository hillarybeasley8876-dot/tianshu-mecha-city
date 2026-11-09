# boss — review r1 (lead) — PASS for the fight logic; r2 = presentation + integration

Verified: `check` 20 files 0 errors; `test_boss` 98/0 (thresholds, cores ×1.0/×2.5, stagger + attack removal,
telegraph floors, beam window/arc, summon cap, storm circles, game_won once, phase checkpoints, balance
105/105/90 s); the movie log shows every attack; the captures. The seven bugs your captures caught (arena 120 m
off the Crown, perception from the ankles, the catapult, the stepped-deck stomp test…) are exactly why captures
are mandatory. Your honest verdict is mine too: the scale reads, the fight is not yet legible.

## Lead decisions on your requests
1. `boss_director.tscn` is in `main.gd` PARTS now (`--stub=boss` skips it).
2. HUD calls your `hud_state()` (hud round, noted).
3. **Rim ownership**: city-build exports the Crown rim as segments (group `&"crown_rim_segment"`, CONTRACTS §6);
   you break them. Your `--boss-test` arena builds its own segments in the same group.
4. **Camera**: CONTRACTS §5 "Large-target framing" — implement `framing_height() -> float` (60) on the titan;
   camera-aim implements the framing (its round is queued).
5. **Title card**: emit `Events.boss_intro("巢母 BROOD TITAN", "<subtitle>")` at the intro roar (HUD draws it,
   audio plays a stinger — both noted).
6. Boss audio ids → audio round (noted). 7. Roar on a fallen spire: listen to `Events.spire_destroyed` yourself.

## r2
1. **Free play stays free**: no skyline walker in `--sandbox` unless `--flow` or `--boss-test` (CONTRACTS §2).
2. **Death beat**: today the titan turns into white jagged silhouettes (`boss_death_collapse.jpg`) — no generic
   dissolve for the boss. Chain `kill_large` blasts up the body over 1.5 s, the titan topples over the deck edge
   (death_fall clip or a ragdoll-less tilt + fall), dust + smoke from the edge, then the storm clears via
   `time_of_day.set_storm(0, 4)`; `game_won` after 4 s as now.
3. **Legibility pass** once camera-aim's framing lands: captures at gameplay framing of the swipe telegraph,
   the stomp ring, the beam sweep and a core break, with the titan's head and the hero both in frame.
4. Crown rim breaking through the segment group; checkpoint respawn on the Crown verified in the city
   (`--flow` run reaching `boss`), not only in `--boss-test`.
