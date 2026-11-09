# Brief: boss — 巢母 BROOD TITAN: skyline walker + 3-phase crown fight

## Goal
The climax: a 60 m biomechanical titan that the player has watched walking the city's skyline for the whole
demo, now fought on the Spire's crown deck (+224 m, CIRCULAR Ø 300 m: three rim steps, four 24 m fins at 45°, a Ø 80 m
central core the titan can circle and the player can use as cover — MAP §4, layout `B1_crown`) under a violet storm. Huge scale, readable
telegraphs, weak cores to break, adds, three escalating phases, cinematic intro/phase/death beats, and a
finish that feels like the best moment of the demo (slow-mo kill, JACKPOT, lance finale if available).

## Read first
`docs/SPEC.md` §7–8, `docs/MAP.md` §2 (Crown, catapult entry), `docs/FEEL.md` (boss_roar, boss_stagger,
kill_large, jackpot), `ref/research/juice-impact.md` §5 (finishers), §11 (telegraphs ≥ reaction + dodge +
buffer, boss roars), `ref/research/skills-catalog.md` §4.6 (Colossus stability 9,000, stagger 3.4 s,
immunity 6 s, Core Rend on bosses = 12 % max HP, not lethal), `game/enemies/**` (EnemyBase, StatusComponent,
projectiles, shockwaves, attack tokens), `game/enemies/models/titan/` (monster-assets; placeholder until
then), the flow unit's events, `art/concept/keyart/v8_crown-1.png` (the moment we are building).

## You own
`game/enemies/boss/**` (titan boss actor, skyline walker, attacks, phases, cinematics, arena hazards, tests).

## Build
1. **Skyline walker** (before the fight): a non-interactive titan instance walking a closed path on the
   skyline ring (outside ±700 m, scaled 1.0, visible from ≥ 80 % of the map), slow heavy walk, stops to
   roar (`boss_roar` feel, global shake by distance, audio audible across the city) whenever the flow unit
   reports a destroyed spire, turning toward the player; despawns when the boss fight starts.
2. **Boss actor** (`BroodTitan` extends EnemyBase): 150,000 HP (SPEC §7.1 balance model: phase uptime
   P1 90 s, P2 120 s, P3 90 s), stability 9,000 (decay 8 %/s after 2 s,
   stagger 3.4 s, immunity 6 s), 3 weak cores (shoulders L/R + chest, 8,000 HP each; core hits count ×1.0 to the main pool and ×2.5 to
   the core pool; violet Targetables); breaking a core staggers it and removes an attack (L shoulder → swipe,
   R shoulder → summon, chest → beam breath); armour on legs (×0.5).
3. **Attacks** (each with honest telegraph windows and `Events.enemy_telegraph`):
   stomp (0.9 s lift → shockwave ring 0→80 m, jump/dash over it), claw swipe (1.1 s wind-up, 120° arc; parry glint
   onset ≥ 400 ms before contact, perfect window the last 167 ms → big counter window), beam breath (1.4 s inhale + crown glow →
   4 s sweeping beam across the deck, dodge by flying over/under it or by the core-side blind spot;
   unblockable), summon (spreads arms → 6 rippers + 2 harriers from the deck edges), tail sweep (rear only,
   punishes standing behind), phase-3 lightning (storm strikes at telegraphed circles, 1.0 s).
4. **Phases**: P1 (100–65 %): stomp, swipe, summon. P2 (65–30 %): + beam breath, faster swipes, deck edge
   segments break (fall → land on the S4 ring, catapult back in ≤ 12 s). P3 (< 30 %): storm, lightning,
   enraged combos, music boss 1.0. Phase transitions: 2–3 s cinematic roar via `request_cinematic`
   (player invulnerable), `Events.boss_phase`.
5. **Intro**: the player lands on the crown via the catapult → the titan climbs over the deck edge (or
   lands from the storm), roar, title card 「巢母 BROOD TITAN」 (HUD boss bar appears). **Death**: final hit
   → `Feel.slow_mo(0.2, 1.2)`, JACKPOT if eligible, the titan collapses over the deck edge in 3 s with chain
   explosions, storm clears to dusk gold (city-art TimeOfDay hook), `Events.game_won` after 4 s.
6. Phase checkpoints: dying respawns the player on the Crown at 100 % HP with the boss restored to the
   current phase threshold (SPEC §7.1). Clips available from monster-assets: roar, stomp, swipe, beam_breath,
   summon, stagger, death + tail_sweep, climb_over, phase_roar, core_break, death_fall (see
   `reviews/monster-assets-lead.md`); unblockable telegraphs ≥ 800 ms with sound + shape cues.
7. Works in the sandbox (`--boss-test` flag: spawn it on the plateau) before the city crown exists.
8. Summoned Harriers route with `world.sky_path()` (the sky graph rings the Crown at +232…+250); the storm and
   lightning go through the `&"time_of_day"` group (`set_storm`, `lightning_at`) — CONTRACTS §7 environment hooks.

## Done when
- `tools/godot.sh check --only=res://enemies/boss/` → 0 errors; `tools/godot.sh test
  res://enemies/boss/tests/test_boss.gd` (phase thresholds, core breaks → stagger + attack removal,
  telegraph durations ≥ 0.6 s for unblockables, beam sweep timing, summon cap, invulnerable cinematics,
  death sequence emits game_won once).
- Movie of a full scripted fight in the sandbox with `--god` (≤ 5 min, every attack and phase visible) +
  captures `captures/boss_*.jpg` (intro roar, stomp ring, beam sweep, core break stagger, phase-3 storm,
  death collapse). Judge honestly: does it feel epic at 60 m scale?
